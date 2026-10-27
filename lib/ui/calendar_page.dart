library;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter/services.dart';

import '../mcp/calendar_provider.dart';
import '../ui_ports/calendar_port.dart';
import 'components/app_components.dart';
import 'components/calendar_grid.dart';
import 'home_shell.dart';
import 'tokens/app_tokens.dart';

/// 日历子页面（极简 + 手势）：**月视图无限滚动**为唯一形态，
/// 点选日 → **底部面板同屏**展开当天只读快照（不切独立模式）。
///
/// 定位红线（ui-console.md §1）：**不做日程管理**——本页不提供事件/标记增删改，
/// 写归系统日历本身与 Agent 侧 W 档命令；UI 只读。
/// 手势（§6 双通道：每条手势均有等价可见控件——可点标题 / 今天按钮 / 把手）：
///   纵滑 = 无限**自由**滚动（跟手 + 惯性滑行，可停在任意位置——上月尾 +
///   本月头同屏的中间态是合法停留态，不强吸附月边界；跨过半页松手即落定新月）；
///   「今天」按钮 = 归位；点日格（任意可见月）/ 上滑面板把手 = 展开当日快照
///   （FAB = 当日快照全屏切换，挤压月网格腾高占满可视区；悬浮位与面板
///   把手/上滑分属不同热区、互不抢手势）。
/// 离线兜底：农历 / 节气 / 法定节假日来自纯内核，不依赖系统日历权限，未授权页也不空。
///
/// 滚动实现（v2 整页重写）：跟手 / 惯性 / 页复用 / 光栅缓存全部交给**框架内置
/// 滚动**（ScrollController + ListView.builder + 自定义滑行 physics），替代 v1
/// 手工 Stack+Transform+三套缓存管线（真机「不跟手后跳一下」的病灶层）。
/// 索引空间固定 ±100 年（kCenter 居中今天月），**无需重锚**——落定只做
/// 数据预载与跨月触感；惯性手感沿用原口径（滑行目标 = 位置 + 末速度 × 0.3，
/// 临界阻尼弹簧速度连续收敛，自由落点不吸附月边界）。

/// 视图模式：月条带（自由滚动）/ 年条带（12 迷你月）/ 年份块条带（12 年 4×3 数字），
/// 三级同构无限滚动——逐级放大：月(最细)→年→年份块(最粗)，甩出放大、点按缩进。
enum _CalMode { month, year, yearGrid }

class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key, required this.port});

  final CalendarPort port;

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

/// 滑行 physics：松手惯性目标 = 当前位置 + 末速度 × 系数——**自由落点**，
/// 不吸附月边界（可停在任意位置）；临界阻尼弹簧从当前速度连续收敛到目标，
/// 无松手顿挫。速度极小（零速慢放松手）不产生仿真——条带停在松手位置。
/// 目标钳进滚动边界（索引空间 ±100 年，实际触界可忽略）。
class _GlidePhysics extends ScrollPhysics {
  const _GlidePhysics({super.parent, this.zoomOut, this.thresholdPx});

  /// 惯性投影系数（逻辑像素）：调大滑得更远，调小更快停住。
  static const double _kMomentumFactor = 0.3;

  /// 临界阻尼弹簧（无过冲、起始速度连续）。公开给程序化滑行
  /// （[_CalendarPageState._glideTo] 等）共用——全页一个运动模型。
  static final SpringDescription kSpring = SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: 220,
    ratio: 1,
  );

  /// 收敛容差：放宽到 0.5px / 50px·s⁻¹，避免渐近长尾拖住落定回调。
  /// 公开给程序化滑行（BallisticScrollActivity）共用。
  static const Tolerance kTolerance = Tolerance(distance: 0.5, velocity: 50);

  /// 「甩出」意图触发回调（切到更粗的缩放层）；null = 该条带无甩出（最粗层）。
  final VoidCallback? zoomOut;

  /// 「甩出」动量阈值（px），**惰性求值**——每次 fling 时调用取当前值，绕开
  /// applyTo 拷贝导致的页高陈旧。null = 关闭甩出（既有滚动行为逐字节不变，
  /// 既有条带 / 滚动稳定性测试零影响）。
  final double Function()? thresholdPx;

  @override
  _GlidePhysics applyTo(ScrollPhysics? ancestor) => _GlidePhysics(
    parent: buildParent(ancestor),
    zoomOut: zoomOut,
    thresholdPx: thresholdPx,
  );

  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) {
    if (velocity.abs() < kTolerance.velocity) return null;
    // 甩出意图：动量投影（|v|×系数）越阈值 → 取消惯性滑行、触发逐级放大。
    // 回调延迟到本帧滚动管线结束后（post-frame），避免在 createBallistic
    // 同步路径里 setState/触发动画的再入风险；低速 fling（投影不足）走原路径。
    final thr = thresholdPx?.call();
    if (thr != null && thr > 0 && velocity.abs() * _kMomentumFactor >= thr) {
      final cb = zoomOut;
      WidgetsBinding.instance.addPostFrameCallback((_) => cb?.call());
      return null;
    }
    final target = (position.pixels + velocity * _kMomentumFactor)
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
    return SpringSimulation(kSpring, position.pixels, target, velocity)
      ..tolerance = kTolerance;
  }
}

class _CalendarPageState extends State<CalendarPage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  /// 星期表头与数据条带的间距（固定表头下缘 ↔ 页内容上缘）。
  static const double _kHeaderGap = 4;

  /// 视图模式：月（无限自由滚动条）/ 年（12 迷你月同构滚动条）。
  _CalMode _mode = _CalMode.month;

  /// 索引空间半径（年）：±100 年，月页索引 = delta + 1200。位移幅度在
  /// double 精度安全区内，锚点恒为今天月、无需重锚换算。
  static const int _kYears = 100;
  static const int _kCenter = _kYears * 12;

  /// 年条带索引空间半径：±100 年，年页索引 = yearDelta + 100。
  static const int _kYearCenter = 100;

  /// 权限申请反馈（人话；透出机器码）。
  String? _permissionHint;

  /// 基准月（initState 时的今天；索引空间原点，恒定不变）。
  int _baseYear = 1970;
  int _baseMonth = 1;

  /// 选中日（用于月格高亮；默认今天）。
  String _selectedDate = '';

  /// 标题月（相对基准月的 delta）：由滚动位移实时推导（跨过半页边界即
  /// 换字过渡）；ValueNotifier 只重建 AppBar 标题，不逐帧整页 setState。
  final ValueNotifier<int> _titleDelta = ValueNotifier<int>(0);

  /// 标题过渡方向（+1 = 翻向下一月：旧上出/新下入；-1 = 反向；
  /// 归位跳转用 0 = 无位移淡入淡出）。与内容条带运动同向。
  int _titleDirection = 0;

  /// 最近落定月 delta：ScrollEnd 时更新，驱动数据预载与跨月触感。
  int _settledDelta = 0;

  /// 月视图数据（当前落定区间；用于权限/源告警引导，不参与网格密度）。
  CalendarRangeOverviewView? _overview;
  bool _overviewLoading = false;

  /// 逐月密度缓存：`YYYY-MM` → 该月逐日密度。落定预载 ±2 槽位，
  /// 供相邻月页预览使用；增量口径（已缓存旁路槽位跳过不拉）。
  final Map<String, Map<String, CalendarDayDensity>> _densityCache =
      <String, Map<String, CalendarDayDensity>>{};

  /// 月离线事实缓存（`YYYY-MM` → 事实映射），避免滚动逐帧重算农历/节假日。
  final Map<String, Map<String, CalendarDayFacts>> _monthFactsCache =
      <String, Map<String, CalendarDayFacts>>{};

  /// 月页 widget 实例缓存（槽位+选中态为键）：滚动帧间同一实例直接跳过
  /// 整页 rebuild；超上限整表清空。
  final Map<String, Widget> _monthPageCache = <String, Widget>{};

  /// 内置滚动控制器：页高度量后带 initialScrollOffset 创建（锚定今天月），
  /// 惯性/跟手/边界全由框架 + [_GlidePhysics] 接管。
  ScrollController? _scroll;

  /// 年条带滚动控制器（懒创建：首次进年视图按页高锚定基准年）。
  ScrollController? _yearScroll;

  /// 年标题 delta（相对基准年）：由年条带位移实时推导（跨过半页即换字）。
  final ValueNotifier<int> _yearDelta = ValueNotifier<int>(0);

  /// 年标题过渡方向（语义同 [_titleDirection]）。
  int _yearDirection = 0;

  /// 最近落定年 delta：ScrollEnd 守卫——同年内小幅滑动落定不重复触感/预载
  /// （口径同月视图 [_settledDelta]）。
  int _settledYearDelta = 0;

  /// 整年密度缓存：`YYYY` → 逐日密度（年页一次拉整年区间）。
  final Map<int, Map<String, CalendarDayDensity>> _yearDensityCache =
      <int, Map<String, CalendarDayDensity>>{};

  /// 年页 widget 实例缓存（年+选中态为键）。
  final Map<String, Widget> _yearPageCache = <String, Widget>{};

  /// 双指捏合检测（Listener 原始指针，**不进手势竞技场**——单指拖拽/滚动
  /// 零干扰）：两指触点间距收缩 ≥25% 进年视图，张开 ≥25% 回月视图。
  final Map<int, Offset> _pinchPointers = <int, Offset>{};
  double? _pinchBaseSpan;
  bool _pinchFired = false;

  /// 单页高度（LayoutBuilder 量得；= 月条带视口高）。
  double _pageHeight = 0;

  /// 年条带单页高度（年视口自身量得；与月页高无关——两视口高度不同）。
  double _yearPageHeight = 0;

  // ---- L3 年份块条带（三级缩放最粗层：12 年/块，4×3 年份数字阵） ----

  /// L3 索引空间半径（块）：±20 块 = ±240 年；块页绝对索引 = blockDelta + 20。
  static const int _kL3Center = 20;

  /// 每块年份数（4×3 = 12）。
  static const int _kL3YearsPerPage = 12;

  /// L3 条带滚动控制器（懒创建：首次进年份块视图按块页高锚定基准块）。
  ScrollController? _yearGridScroll;

  /// L3 标题：当前块**首年** delta（相对基准年，恒为 12 的倍数），由条带位移
  /// 实时推导（跨块即换字）；ValueNotifier 只重建 AppBar 标题。
  final ValueNotifier<int> _yearGridDelta = ValueNotifier<int>(0);

  /// L3 标题过渡方向（语义同 [_yearDirection]）。
  int _yearGridDirection = 0;

  /// 最近落定块（首年 delta）：ScrollEnd 守卫——同块小幅滑动不重复触感。
  int _settledYearGridDelta = 0;

  /// L3 块页 widget 实例缓存（块首年+选中态为键）。
  final Map<String, Widget> _yearGridPageCache = <String, Widget>{};

  /// L3 条带单页高度（年份块视口自身量得）。
  double _yearGridPageHeight = 0;

  /// 选中日事件（月视图底部下拉面板用；只取事件标题/时间，不含地点等敏感字段）。
  List<EventView>? _events;
  String? _eventsDate;
  bool _eventsLoading = false;
  bool _showEvents = false;

  /// 面板全屏态（[_EventPanelState._isFull] 经 onFullscreenChanged 回报）：
  /// FAB 图标/tooltip 跟随；FAB 点击经 [_panelKey] 触发面板私有切换。
  bool _panelIsFull = false;
  final GlobalKey<_EventPanelState> _panelKey = GlobalKey<_EventPanelState>();

  /// 键盘焦点（方向键切月/切年：手势之外的可选通道，桌面端/外接键盘可达）。
  final FocusNode _focusNode = FocusNode();

  /// 模式切换过渡（scale 0.97→1.0 + fade 0→1，200ms）：三级缩放切换
  /// 原为 Offstage 瞬切（Stack 常驻不重挂载的约束不动——AnimatedSwitcher
  /// 会重挂载丢条带位置），此处只给**入场一次性过渡**消掉「啪一下换页」
  /// 的硬切感；条带结构零改动。时长固定、**禁在初始化器读 MediaQuery**
  /// （late final 在 initState 首触时读 inherited widget 即断言崩溃）——
  /// reduced motion 判断只在 [_kickZoom]（build 期）做，命中直接置完成态。
  late final AnimationController _zoomAnim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
  );
  late final Animation<double> _zoomScale = Tween<double>(
    begin: 0.97,
    end: 1.0,
  ).animate(CurvedAnimation(parent: _zoomAnim, curve: Curves.easeOutCubic));
  late final Animation<double> _zoomFade = Tween<double>(begin: 0.0, end: 1.0)
      .animate(CurvedAnimation(parent: _zoomAnim, curve: Curves.easeOut));

  /// 模式切换入场过渡触发（每次切 _mode 后调用一次）。
  void _kickZoom() {
    if (MediaQuery.disableAnimationsOf(context)) {
      _zoomAnim.value = 1.0;
      return;
    }
    _zoomAnim.forward(from: 0);
  }

  // ---- 甩出触发（三级缩放手势通道：决绝快甩 = 「想走远」→ 逐级放大） ----

  /// 甩出动量阈值（以"页"计）：动量投影 ÷ 页高 超过此页数即判定甩出。
  /// 取 2.5——高于既有 fling 测试的 ~1 页投影（速度 3000px/s，不误触），
  /// 低于决绝快甩（速度 ~7000px/s+）可触发；月/年条带共用，L3 最粗无甩出。
  static const double _kZoomOutPages = 2.5;

  /// 月条带物理：甩出 → 年视图（阈值惰性取 _pageHeight）。
  late final _GlidePhysics _monthPhysics;

  /// 年条带物理：甩出 → 年份块视图（阈值惰性取 _yearPageHeight）。
  late final _GlidePhysics _yearPhysics;

  /// L3 年份块条带物理：最粗层，无甩出（zoomOut/thresholdPx=null，行为同原物理）。
  late final _GlidePhysics _yearGridPhysics;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _baseYear = now.year;
    _baseMonth = now.month;
    _selectedDate = _today;
    // 甩出阈值惰性闭包：fling 时现取当前页高换算 px 阈值（量得前为 0 = 关闭，
    // 安全退化到普通滚动）。月甩→年、年甩→年份块，L3 最粗不甩。
    _monthPhysics = _GlidePhysics(
      parent: const ClampingScrollPhysics(),
      zoomOut: _goYear,
      thresholdPx: () => _kZoomOutPages * _pageHeight,
    );
    _yearPhysics = _GlidePhysics(
      parent: const ClampingScrollPhysics(),
      zoomOut: _goYearGrid,
      thresholdPx: () => _kZoomOutPages * _yearPageHeight,
    );
    _yearGridPhysics = _GlidePhysics(parent: const ClampingScrollPhysics());
    // 过渡动画初始即完成态：控制器默认 value=0（_zoomFade 起点为全透明），
    // 不置 1 的话进页面首帧整个日历 Stack 以透明度 0 渲染 → 空白屏。
    // _kickZoom 只在模式切换时才从 0 重播过渡。
    _zoomAnim.value = 1.0;
    _loadOverview();
    WidgetsBinding.instance.addObserver(this); // 授权回前台自动重读（#12）。
  }

  /// 生命周期：从系统设置授权返回（resumed）时提示仍挂着——自动 force 重读，
  /// 读取成功即清提示（[_loadOverview] 口径）；数据口径变化同步失效缓存，
  /// 与 [_requestPermission] 的失效面一致。仍在后台/无提示则不动作。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    if (_permissionHint == null) return;
    _loadOverview(force: true);
    _yearDensityCache.clear(); // 授权状态可能已变，年页密度一并重拉。
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scroll?.dispose();
    _yearScroll?.dispose();
    _yearGridScroll?.dispose();
    _titleDelta.dispose();
    _yearDelta.dispose();
    _yearGridDelta.dispose();
    _focusNode.dispose();
    _zoomAnim.dispose();
    super.dispose();
  }

  String get _today {
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${now.year}-${two(now.month)}-${two(now.day)}';
  }

  String _two(int v) => v.toString().padLeft(2, '0');

  /// 系统开启「减少动态效果」时直接落位，不做滑行/过渡动画。
  bool get _reducedMotion => MediaQuery.disableAnimationsOf(context);

  /// 滚动 delta（相对基准月）→ (年, 月)。
  (int, int) _monthFromDelta(int delta) {
    final m = DateTime(_baseYear, _baseMonth + delta);
    return (m.year, m.month);
  }

  /// 向下取整除法（Dart `~/` 向零截断，负数会偏；L3 取块需真 floor）。
  static int _floorDiv(int a, int b) =>
      (a / b) >= 0 ? a ~/ b : (a % b == 0 ? a ~/ b : a ~/ b - 1);

  /// 加载月视图数据：落定月 ±2 槽位密度预载进 [_densityCache]（视口
  /// cacheExtent 同挂 ±2 页）；落定槽位总览（告警/错误）存 [_overview]。
  ///
  /// 增量口径（[force] 默认关）：已缓存的旁路槽位跳过不拉——快甩连翻时
  /// 每次落定只补缺口；主槽位恒拉（告警/错误码以本次读取为准）。
  /// 授权刷新等数据口径变化走 force 全量。
  Future<void> _loadOverview({bool force = false}) async {
    final settled = _settledDelta; // 竞态守卫基准：发起时的落定月。
    setState(() => _overviewLoading = true);
    final months = <(int, int)>[
      for (var d = -2; d <= 2; d++) _monthFromDelta(_settledDelta + d),
    ];
    final tasks = <(String, String, String)>[]; // (slot, start, end)
    for (final m in months) {
      final lastDay = DateTime(m.$1, m.$2 + 1, 0).day;
      tasks.add((
        '${m.$1}-${_two(m.$2)}',
        '${m.$1}-${_two(m.$2)}-01',
        '${m.$1}-${_two(m.$2)}-$lastDay',
      ));
      // 预热农历/节假日事实缓存：滚动中相邻页首次挂载不再同步重算整月。
      _monthFactsFor(m.$1, m.$2);
    }
    final primarySlot = tasks[2].$1; // 落定月槽位。
    final pending = force
        ? tasks
        : tasks
              .where(
                (t) => t.$1 == primarySlot || !_densityCache.containsKey(t.$1),
              )
              .toList(growable: false);
    List<CalendarRangeOverviewView> views;
    try {
      views = await Future.wait(
        pending.map(
          (t) => widget.port.rangeOverview(rangeStart: t.$2, rangeEnd: t.$3),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      // DEGRADE: [calendar_overview] 月总览读取失败——解除 loading 留空态，
      // 不编造数据；下次落定重拉。
      debugPrint('[DEGRADE][calendar_overview] 月总览读取失败: $e');
      setState(() => _overviewLoading = false);
      return;
    }
    if (!mounted) return;
    // 竞态守卫：慢的旧月响应晚到时落定月已变，丢弃本次结果（不覆盖新月
    // 总览/密度）；新月自身发起的加载会补齐数据。
    if (settled != _settledDelta) return;
    // 逐槽位入库并侦测数据版本变化：月页实例缓存键不含数据版本，密度
    // 变化的槽位必须精准摘除重建，否则格上事件点滞留旧值。
    final changedSlots = <String>{};
    for (var i = 0; i < pending.length; i++) {
      final slot = pending[i].$1;
      final fresh = _densitiesOf(views[i]);
      final old = _densityCache[slot];
      if (old != null) {
        if (!_densityMapsEqual(old, fresh)) changedSlots.add(slot);
      } else if (fresh.isNotEmpty) {
        changedSlots.add(slot); // 新槽位首次有数据（此前按空密度渲染）。
      }
      _densityCache[slot] = fresh;
    }
    if (changedSlots.isNotEmpty) {
      _monthPageCache.removeWhere(
        (key, _) => changedSlots.any((s) => key.startsWith('$s|')),
      );
      setState(() {}); // 密度/事件点变化：重建落位后月页取最新点。
    }
    final primaryIndex = pending.indexWhere((t) => t.$1 == primarySlot);
    if (primaryIndex < 0) {
      // 防御：主槽位恒拉不应缺席；缺席时只解除 loading，不动既有总览。
      setState(() => _overviewLoading = false);
      return;
    }
    final primary = views[primaryIndex]; // 落定月槽位。
    setState(() {
      _overview = primary;
      _overviewLoading = false;
      // 读取成功即权限提示已过时——不清会一直挂着「重新读取即可」误导用户。
      if (primary.errorCode == null) _permissionHint = null;
    });
  }

  /// 解析区间总览 → 逐日密度映射（`YYYY-MM-DD` → 密度）。
  Map<String, CalendarDayDensity> _densitiesOf(CalendarRangeOverviewView view) {
    return <String, CalendarDayDensity>{
      for (final d in view.days)
        d.date: CalendarDayDensity(
          eventCount: d.eventCount,
          markerCount: d.markerCount,
        ),
    };
  }

  /// 密度映射内容相等（月页实例缓存按数据版本失效的比较基准）。
  static bool _densityMapsEqual(
    Map<String, CalendarDayDensity> a,
    Map<String, CalendarDayDensity> b,
  ) {
    if (a.length != b.length) return false;
    for (final e in a.entries) {
      final o = b[e.key];
      if (o == null ||
          o.eventCount != e.value.eventCount ||
          o.markerCount != e.value.markerCount) {
        return false;
      }
    }
    return true;
  }

  // ---------------- 内置滚动（跟手/惯性/落定全框架接管） ----------------

  /// 首次量得页高：带 initialScrollOffset（锚定今天月）创建控制器——
  /// 同一次 build 即可挂上 ListView，无错位首帧、无 postFrame 跳变。
  void _anchorIfNeeded(BoxConstraints constraints) {
    final h = constraints.maxHeight;
    if (h <= 0) return;
    if (_scroll == null) {
      _pageHeight = h;
      _scroll = ScrollController(initialScrollOffset: _kCenter * h);
      return;
    }
    if ((h - _pageHeight).abs() <= 0.5) return;
    // 尺寸变化（旋转/分屏/折叠屏）：itemExtent 与视口必须同高，否则条带
    // 错位、两页同屏。按当前落定页换算新 offset，post-frame 落位
    // （build/layout 期禁 jumpTo）。
    final delta = (_scroll!.offset / _pageHeight).round() - _kCenter;
    _pageHeight = h;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final c = _scroll;
      if (c == null || !c.hasClients) return;
      c.jumpTo((_kCenter + delta) * h);
    });
  }

  /// 滚动通知：标题月实时推导（跨过半页边界即换字，只改 notifier 不
  /// setState）；ScrollEnd 落定最近整月——跨月触感 + 数据预载。
  /// **无重锚**：索引空间恒定，视觉位置本就逐像素连续。
  bool _onScroll(ScrollNotification n) {
    if (_pageHeight <= 0) return false;
    final d = (n.metrics.pixels / _pageHeight).round() - _kCenter;
    if (d != _titleDelta.value) {
      _titleDirection = d > _titleDelta.value ? 1 : -1;
      _titleDelta.value = d;
    }
    if (n is ScrollEndNotification && d != _settledDelta) {
      _settledDelta = d;
      HapticFeedback.selectionClick(); // 跨月落定触感：确认新月。
      _loadOverview();
    }
    return false;
  }

  /// 整页滑行（键盘/归位等手势外通道；reduced motion 直落）。
  /// 统一走 [_GlidePhysics] 同款临界阻尼弹簧（速度连续收敛）——与手势惯性
  /// 共用同一运动模型，观感一致；easeOutCubic 定时缓动起步即峰值速度，
  /// 「猛冲急停」与弹簧的优雅减速不符，弃用。
  void _glideTo(double target) {
    final c = _scroll;
    if (c == null || !c.hasClients || _pageHeight <= 0) return;
    if (_reducedMotion) {
      c.jumpTo(target);
      return;
    }
    final pos = c.position;
    // 仿真驱动入口：ScrollPosition 无公开 animateWith，官方手势惯性走的
    // BallisticScrollActivity 构造公开、直接吃 Simulation——弹簧收敛后经
    // goBallistic(≈0 速度) 走 physics 判 idle，终止干净。
    // delegate 参数收口到 ScrollActivityDelegate（具体位置类
    // ScrollPositionWithSingleContext 实现了它，标准 ListView 恒成立）。
    pos.beginActivity(
      BallisticScrollActivity(
        pos as ScrollActivityDelegate,
        SpringSimulation(
          _GlidePhysics.kSpring,
          pos.pixels,
          target,
          0,
        )..tolerance = _GlidePhysics.kTolerance,
        pos.context.vsync,
        true,
      ),
    );
  }

  /// 方向键翻页：↓/PageDown = 上一月（条带语义 = 视口向列表头走）；
  /// ↑/PageUp 无绑定（原「↑ = 下一月」与通用日历惯例相反，已按用户口径移除）；
  /// Esc 关闭事件面板。手势之外的可选通道。
  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape && _showEvents) {
      setState(() => _showEvents = false);
      return KeyEventResult.handled;
    }
    final prev =
        event.logicalKey == LogicalKeyboardKey.arrowDown ||
        event.logicalKey == LogicalKeyboardKey.pageDown;
    if (!prev) return KeyEventResult.ignored;
    if (_mode == _CalMode.year) {
      // 年条带：↓/PageDown = 上一年。
      final c = _yearScroll;
      if (c == null || !c.hasClients) return KeyEventResult.handled;
      _glideYearTo(c.offset - _yearPageHeight);
      return KeyEventResult.handled;
    }
    if (_mode == _CalMode.yearGrid) {
      // 年份块条带：↓/PageDown = 上一块（−12 年）。
      final c = _yearGridScroll;
      if (c == null || !c.hasClients) return KeyEventResult.handled;
      _glideYearGridTo(c.offset - _yearGridPageHeight);
      return KeyEventResult.handled;
    }
    final c = _scroll;
    if (c == null || !c.hasClients) return KeyEventResult.handled;
    _glideTo(c.offset - _pageHeight);
    return KeyEventResult.handled;
  }

  /// 「今天」归位：精确落位基准月（位移归零），选中今天。**不强制展开**
  /// 事件面板——面板本就开着才刷新为今天的事件，关着保持关着（归位 ≠ 查看日程）。
  /// 年视图下先切回月视图（「今天」语义 = 回到当月）。
  void _goToday() {
    setState(() {
      _mode = _CalMode.month;
      _selectedDate = _today;
    });
    _kickZoom();
    if (_showEvents) _loadEvents(_today);
    _glideTo(_kCenter * _pageHeight);
  }

  /// 跳转到指定日期（§6 双通道：三级缩放手势之外的等价可见控件）——远日期
  /// 直达，不必甩出→年份块→点年→点月四级导航。系统日期选择器选取后走
  /// [_onDaySelected]（选中 + 展开当日快照面板），月条带滑行落到该月。
  Future<void> _jumpToDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.tryParse(_selectedDate) ?? now,
      firstDate: DateTime(now.year - _kYears),
      lastDate: DateTime(now.year + _kYears),
    );
    if (picked == null || !mounted) return;
    _onDaySelected(
      '${picked.year}-${_two(picked.month)}-${_two(picked.day)}',
    );
    _glideTo(
      (_kCenter + _monthDeltaOf(picked.year, picked.month)) * _pageHeight,
    );
  }

  // ---------------- 年视图 ----------------

  /// 进年视图：条带切年模式，年条带同步到当前标题年（从哪个月进来就看
  /// 哪一年），并预载该年密度。
  void _goYear() {
    final (y, _) = _monthFromDelta(_titleDelta.value);
    // 标题年先行同步：年条带首帧即按标题年锚定，_yearDelta 不随锚点更新的话
    // 标题停在旧基准年，首次滚动落定才「追」过来——观感即年份乱跳。
    _yearDirection = 0;
    _yearDelta.value = y - _baseYear;
    _settledYearDelta = y - _baseYear;
    setState(() => _mode = _CalMode.year);
    _kickZoom();
    final c = _yearScroll;
    if (c != null && c.hasClients && _yearPageHeight > 0) {
      final target = (_kYearCenter + (y - _baseYear)) * _yearPageHeight;
      if ((c.offset - target).abs() > 0.5) {
        _glideYearTo(target);
      }
    }
    _loadYearDensities(y);
  }

  /// 回月视图：条带切月模式（月条带滚动位置原样保留，无重锚）。
  void _goMonth() {
    setState(() => _mode = _CalMode.month);
    _kickZoom();
  }

  /// (年, 月) 相对基准月的月数差（年视图点迷你月 → 月条带目标索引）。
  int _monthDeltaOf(int year, int month) {
    final base = DateTime(_baseYear, _baseMonth);
    return (year - base.year) * 12 + month - base.month;
  }

  /// 年视图点迷你月 → 落月视图并滑行到该月（月份条带原样保留语义）。
  void _onMonthSelected(int month) {
    final year = _baseYear + _yearDelta.value;
    setState(() => _mode = _CalMode.month);
    _kickZoom();
    _glideTo((_kCenter + _monthDeltaOf(year, month)) * _pageHeight);
  }

  /// 首次进年条带：按**年视口自身高度**创建控制器（锚定当前标题年）——
  /// 年/月视口高不同（月模式上方有固定表头占位），禁共用月页高，否则
  /// itemExtent 与视口失配 → 年页错位、两页同屏。
  void _yearAnchorIfNeeded(BoxConstraints constraints) {
    final h = constraints.maxHeight;
    if (h <= 0) return;
    if (_yearScroll != null) {
      if ((h - _yearPageHeight).abs() <= 0.5) return;
      // 尺寸变化：同月条带口径——按落定年换算新 offset，post-frame 落位。
      final delta =
          (_yearScroll!.offset / _yearPageHeight).round() - _kYearCenter;
      _yearPageHeight = h;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final c = _yearScroll;
        if (c == null || !c.hasClients) return;
        c.jumpTo((_kYearCenter + delta) * h);
      });
      return;
    }
    // 首次量得：按**年视口自身高度**创建控制器（锚定当前标题年——由标题
    // 月 delta 换算整年，禁 `~/ 12` 截断：如 delta=5（今年 3 月后）截断为 0
    // 会锚错一年，且负 delta 向零取整同样错）。年/月视口高不同（月模式上方
    // 有固定表头占位），禁共用月页高，否则 itemExtent 与视口失配。
    _yearPageHeight = h;
    final (anchorYear, _) = _monthFromDelta(_titleDelta.value);
    _yearScroll = ScrollController(
      initialScrollOffset:
          (_kYearCenter + (anchorYear - _baseYear)) * _yearPageHeight,
    );
  }

  /// 年条带滚动通知：标题年实时推导；落定触感 + 整年密度预载。
  bool _onYearScroll(ScrollNotification n) {
    if (_yearPageHeight <= 0) return false;
    final d = (n.metrics.pixels / _yearPageHeight).round() - _kYearCenter;
    if (d != _yearDelta.value) {
      _yearDirection = d > _yearDelta.value ? 1 : -1;
      _yearDelta.value = d;
    }
    if (n is ScrollEndNotification && d != _settledYearDelta) {
      _settledYearDelta = d;
      HapticFeedback.selectionClick(); // 跨年落定触感。
      _loadYearDensities(_baseYear + d);
    }
    return false;
  }

  /// 拉取整年逐日密度（年页渲染；已缓存年份旁路——授权刷新走 force 清缓存）。
  Future<void> _loadYearDensities(int year, {bool force = false}) async {
    if (!force && _yearDensityCache.containsKey(year)) return;
    CalendarRangeOverviewView view;
    try {
      view = await widget.port.rangeOverview(
        rangeStart: '$year-01-01',
        rangeEnd: '$year-12-31',
      );
    } catch (e) {
      if (!mounted) return;
      // DEGRADE: [calendar_year_density] 整年密度读取失败——不入缓存（保留
      // 空密度渲染），回年视图重拉时重试。
      debugPrint('[DEGRADE][calendar_year_density] $year 年密度读取失败: $e');
      return;
    }
    if (!mounted) return;
    setState(() {
      _yearDensityCache[year] = _densitiesOf(view);
      // 年页实例缓存键不含数据版本：密度入库后摘除该年页缓存，落位重建
      // 才能取到最新密度点（口径同月页 changedSlots 摘除）。
      _yearPageCache.removeWhere((key, _) => key.startsWith('$year|'));
    });
  }

  /// 年条带滑行（键盘/归位等手势外通道）。统一弹簧口径同 [_glideTo]。
  void _glideYearTo(double target) {
    final c = _yearScroll;
    if (c == null || !c.hasClients || _yearPageHeight <= 0) return;
    if (_reducedMotion) {
      c.jumpTo(target);
      return;
    }
    final pos = c.position;
    // 仿真驱动入口：ScrollPosition 无公开 animateWith，官方手势惯性走的
    // BallisticScrollActivity 构造公开、直接吃 Simulation——弹簧收敛后经
    // goBallistic(≈0 速度) 走 physics 判 idle，终止干净。
    // delegate 参数收口到 ScrollActivityDelegate（具体位置类
    // ScrollPositionWithSingleContext 实现了它，标准 ListView 恒成立）。
    pos.beginActivity(
      BallisticScrollActivity(
        pos as ScrollActivityDelegate,
        SpringSimulation(
          _GlidePhysics.kSpring,
          pos.pixels,
          target,
          0,
        )..tolerance = _GlidePhysics.kTolerance,
        pos.context.vsync,
        true,
      ),
    );
  }

  /// 相对年 delta → 年页（缓存键含选中态，选中变化自然失效）。
  Widget _yearPageFor(int delta) {
    final y = _baseYear + delta;
    _pruneYearPageCache();
    return _yearPageCache['$y|sel:$_selectedDate'] ??= _yearPage(y);
  }

  /// 年页缓存定向摘除：超上限只摘标题年 ±2 年窗口外的年份（口径同
  /// [_pruneMonthPageCache]，覆盖 ±2 预挂载）。
  void _pruneYearPageCache() {
    if (_yearPageCache.length <= 16) return;
    final anchor = _baseYear + _yearDelta.value;
    _yearPageCache.removeWhere((key, _) {
      final y = int.tryParse(key.split('|').first) ?? 0;
      return (y - anchor).abs() > 2;
    });
  }

  Widget _yearPage(int year) {
    final now = DateTime.now();
    final selMonth = _selectedDate.length >= 10
        ? int.tryParse(_selectedDate.substring(5, 7)) ?? 0
        : 0;
    final selDay = _selectedDate.length >= 10
        ? int.tryParse(_selectedDate.substring(8, 10)) ?? 0
        : 0;
    // 选中日年份：迷你月高亮须限定在选中年份内——否则自由滚动下多年同屏时，
    // 同一 (月,日) 会在每一年的迷你月重复点亮（2026-10-27 年视图恢复时引入）。
    final selYear = _selectedDate.length >= 10
        ? int.tryParse(_selectedDate.substring(0, 4)) ?? 0
        : 0;
    return YearGrid(
      year: year,
      densities:
          _yearDensityCache[year] ?? const <String, CalendarDayDensity>{},
      currentMonth: year == now.year ? now.month : 0,
      today: now,
      selectedMonth: selMonth,
      selectedDay: selDay,
      selectedYear: selYear,
      onMonthSelected: _onMonthSelected,
    );
  }

  // ---------------- L3 年份块视图（三级缩放最粗层） ----------------

  /// 进年份块视图：年视图甩出/点标题放大到最粗层；条带同步到当前标题年所在
  /// 块（从哪一年进来就看那 12 年窗口，选中年在块内高亮）。
  void _goYearGrid() {
    final y = _baseYear + _yearDelta.value;
    final block = _floorDiv(y - _baseYear, _kL3YearsPerPage);
    _yearGridDirection = 0;
    _yearGridDelta.value = block * _kL3YearsPerPage;
    _settledYearGridDelta = _yearGridDelta.value;
    setState(() => _mode = _CalMode.yearGrid);
    final c = _yearGridScroll;
    if (c != null && c.hasClients && _yearGridPageHeight > 0) {
      final target = (_kL3Center + block) * _yearGridPageHeight;
      if ((c.offset - target).abs() > 0.5) {
        _glideYearGridTo(target);
      }
    }
  }

  /// 年份块点某年 → 缩进该年视图并滑行落位（年条带位置原样保留语义）。
  void _onYearSelected(int year) {
    final delta = year - _baseYear;
    _yearDirection = 0;
    _yearDelta.value = delta;
    _settledYearDelta = delta;
    setState(() => _mode = _CalMode.year);
    _kickZoom();
    final c = _yearScroll;
    if (c != null && c.hasClients && _yearPageHeight > 0) {
      final target = (_kYearCenter + delta) * _yearPageHeight;
      if ((c.offset - target).abs() > 0.5) {
        _glideYearTo(target);
      }
    }
    _loadYearDensities(year);
  }

  /// 首次进 L3 条带：按**年份块视口自身高度**创建控制器（锚定当前标题年所在
  /// 块）——口径同年条带，禁共用月/年页高，否则 itemExtent 与视口失配。
  void _yearGridAnchorIfNeeded(BoxConstraints constraints) {
    final h = constraints.maxHeight;
    if (h <= 0) return;
    if (_yearGridScroll != null) {
      if ((h - _yearGridPageHeight).abs() <= 0.5) return;
      // 尺寸变化：同年条带口径——按落定块换算新 offset，post-frame 落位。
      final block =
          (_yearGridScroll!.offset / _yearGridPageHeight).round() - _kL3Center;
      _yearGridPageHeight = h;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final c = _yearGridScroll;
        if (c == null || !c.hasClients) return;
        c.jumpTo((_kL3Center + block) * h);
      });
      return;
    }
    _yearGridPageHeight = h;
    // 首次量得：锚定当前标题年所在块（由标题月 delta 换算年份再 floor 取块，
    // 禁 `~/` 截断——负 delta 向零取整会锚错块）。
    final (anchorYear, _) = _monthFromDelta(_titleDelta.value);
    final block = _floorDiv(anchorYear - _baseYear, _kL3YearsPerPage);
    _yearGridScroll = ScrollController(
      initialScrollOffset: (_kL3Center + block) * _yearGridPageHeight,
    );
  }

  /// L3 条带滚动通知：标题块首年实时推导（跨块换字）；落定触感。
  bool _onYearGridScroll(ScrollNotification n) {
    if (_yearGridPageHeight <= 0) return false;
    final block = (n.metrics.pixels / _yearGridPageHeight).round() - _kL3Center;
    final d = block * _kL3YearsPerPage; // 块首年 delta（恒为 12 的倍数）。
    if (d != _yearGridDelta.value) {
      _yearGridDirection = d > _yearGridDelta.value ? 1 : -1;
      _yearGridDelta.value = d;
    }
    if (n is ScrollEndNotification && d != _settledYearGridDelta) {
      _settledYearGridDelta = d;
      HapticFeedback.selectionClick(); // 跨块落定触感。
    }
    return false;
  }

  /// L3 条带滑行（键盘翻页等手势外通道）。统一弹簧口径同 [_glideTo]。
  void _glideYearGridTo(double target) {
    final c = _yearGridScroll;
    if (c == null || !c.hasClients || _yearGridPageHeight <= 0) return;
    if (_reducedMotion) {
      c.jumpTo(target);
      return;
    }
    final pos = c.position;
    // 仿真驱动入口：ScrollPosition 无公开 animateWith，官方手势惯性走的
    // BallisticScrollActivity 构造公开、直接吃 Simulation——弹簧收敛后经
    // goBallistic(≈0 速度) 走 physics 判 idle，终止干净。
    // delegate 参数收口到 ScrollActivityDelegate（具体位置类
    // ScrollPositionWithSingleContext 实现了它，标准 ListView 恒成立）。
    pos.beginActivity(
      BallisticScrollActivity(
        pos as ScrollActivityDelegate,
        SpringSimulation(
          _GlidePhysics.kSpring,
          pos.pixels,
          target,
          0,
        )..tolerance = _GlidePhysics.kTolerance,
        pos.context.vsync,
        true,
      ),
    );
  }

  /// 相对块 delta → L3 块页（缓存键含选中态，选中变化自然失效）。
  Widget _yearGridPageFor(int blockDelta) {
    final firstYear = _baseYear + blockDelta * _kL3YearsPerPage;
    _pruneYearGridPageCache();
    return _yearGridPageCache['$firstYear|sel:$_selectedDate'] ??=
        _yearGridPage(firstYear);
  }

  /// 块页缓存定向摘除：超上限只摘标题块 ±1 块窗口外的块（口径同
  /// [_pruneMonthPageCache]；块粒度粗，±1 即覆盖 ±2 预挂载）。
  void _pruneYearGridPageCache() {
    if (_yearGridPageCache.length <= 16) return;
    final anchor = _floorDiv(
      _baseYear + _yearDelta.value,
      _kL3YearsPerPage,
    );
    _yearGridPageCache.removeWhere((key, _) {
      final first = int.tryParse(key.split('|').first) ?? 0;
      return (_floorDiv(first, _kL3YearsPerPage) - anchor).abs() > 1;
    });
  }

  /// L3 单块页：4×3 年份数字阵，点某年缩进该年视图。
  Widget _yearGridPage(int blockFirstYear) {
    final nowYear = DateTime.now().year;
    final selYear = _selectedDate.length >= 4
        ? int.tryParse(_selectedDate.substring(0, 4)) ?? 0
        : 0;
    return YearNumberGrid(
      startYear: blockFirstYear,
      currentYear: nowYear,
      selectedYear: selYear,
      onYearSelected: _onYearSelected,
    );
  }

  // ---------------- 双指捏合（三级缩放通道，Listener 原始指针） ----------------

  void _onPinchDown(PointerDownEvent e) {
    _pinchPointers[e.pointer] = e.localPosition;
    if (_pinchPointers.length == 2) {
      _pinchBaseSpan = _pinchSpan();
      _pinchFired = false;
    }
  }

  void _onPinchMove(PointerMoveEvent e) {
    if (!_pinchPointers.containsKey(e.pointer)) return;
    _pinchPointers[e.pointer] = e.localPosition;
    final base = _pinchBaseSpan;
    if (_pinchPointers.length < 2 || base == null || base <= 0 || _pinchFired) {
      return;
    }
    final span = _pinchSpan();
    // 三级同向：收缩 = 逐级放大（月→年→年份块），张开 = 逐级缩进（年份块→年→月）。
    if (_mode == _CalMode.month) {
      if (span < base * 0.75) {
        _pinchFired = true;
        _goYear(); // 收缩 → 年视图。
      }
    } else if (_mode == _CalMode.year) {
      if (span < base * 0.75) {
        _pinchFired = true;
        _goYearGrid(); // 收缩 → 年份块视图。
      } else if (span > base * 1.25) {
        _pinchFired = true;
        _goMonth(); // 张开 → 月视图。
      }
    } else if (_mode == _CalMode.yearGrid) {
      if (span > base * 1.25) {
        _pinchFired = true;
        _goYear(); // 张开 → 年视图。
      }
    }
  }

  void _onPinchEnd(PointerEvent e) {
    _pinchPointers.remove(e.pointer);
    if (_pinchPointers.length < 2) _pinchBaseSpan = null;
  }

  double _pinchSpan() {
    final it = _pinchPointers.values.iterator..moveNext();
    final a = it.current;
    it.moveNext();
    return (a - it.current).distance;
  }

  /// 捏合检测包装：包住条带（月/年同构），只旁听原始指针不抢手势。
  Widget _pinchSensor({required Widget child}) {
    return Listener(
      onPointerDown: _onPinchDown,
      onPointerMove: _onPinchMove,
      onPointerUp: _onPinchEnd,
      onPointerCancel: _onPinchEnd,
      child: child,
    );
  }

  /// 加载选中日事件（底部下拉面板；只取事件标题/时间，不含地点等敏感字段）。
  Future<void> _loadEvents(String date) async {
    setState(() {
      _eventsLoading = true;
      _eventsDate = date;
    });
    CalendarSnapshotView view;
    try {
      view = await widget.port.snapshot(date: date);
    } catch (e) {
      if (!mounted || date != _eventsDate) return;
      // DEGRADE: [calendar_events] 日快照读取失败——解除 loading 并清空旧
      // 日期事件残留，呈真「无日程」空态，不编造事件；重选该日重拉。
      debugPrint('[DEGRADE][calendar_events] 日快照读取失败: $e');
      setState(() {
        _events = null;
        _eventsLoading = false;
      });
      return;
    }
    // 竞态守卫：慢的旧日响应晚到不得覆盖新选中日的事件。
    if (!mounted || date != _eventsDate) return;
    setState(() {
      _events = view.events;
      _eventsLoading = false;
    });
  }

  // ---------------- 月页构建（实例缓存 + 框架滚动复用） ----------------

  /// 相对页 delta → 月页（全部可见页均可点选：自由滚动下相邻月同屏是
  /// 合法停留态，跨月点选是一等交互；缓存键含选中态，选中变化自然失效）。
  Widget _monthPageFor(int delta) {
    final (y, m) = _monthFromDelta(delta);
    _pruneMonthPageCache();
    return _monthPageCache['$y-${_two(m)}|sel:$_selectedDate'] ??= _monthPage(
      y,
      m,
    );
  }

  /// 月页缓存定向摘除：超上限时只摘标题月 ±4 个月窗口外的槽位，落定页
  /// 附近全保留——原整表清空会让快甩远途回跳时可见页全量重建（可感知
  /// 卡顿）；窗口取 ±4（覆盖 ±2 预挂载 + 回跳一屏余量）。
  void _pruneMonthPageCache() {
    if (_monthPageCache.length <= 64) return;
    final keep = <String>{
      for (var d = -4; d <= 4; d++)
        () {
          final (y, m) = _monthFromDelta(_titleDelta.value + d);
          return '$y-${_two(m)}';
        }(),
    };
    _monthPageCache.removeWhere(
      (key, _) => !keep.contains(key.split('|').first),
    );
  }

  /// 月视图单页：星期表头全局仅一条（钉在滚动区上方，不随数据滚动），
  /// 相邻月内容直接从其下滚入；7 列等宽保证任意页的周列恒对齐。
  Widget _monthPage(int year, int month) {
    return MonthGrid(
      year: year,
      month: month,
      densities:
          _densityCache['$year-${_two(month)}'] ??
          const <String, CalendarDayDensity>{},
      selectedDate: _selectedDate,
      todayDate: _today,
      dayFacts: _monthFactsFor(year, month),
      onDaySelected: _onDaySelected,
      showHeader: false,
    );
  }

  /// 逐月离线事实映射（农历 / 节假日 / 休班），纯本地、零权限依赖。
  /// 结果按 `YYYY-MM` 槽位缓存，滚动时稳定引用，避免逐帧重算与相邻页重建。
  Map<String, CalendarDayFacts> _monthFactsFor(int year, int month) {
    final slot = '$year-${_two(month)}';
    final cached = _monthFactsCache[slot];
    if (cached != null) return cached;
    final list = widget.port.monthFacts(year, month);
    final map = <String, CalendarDayFacts>{};
    for (var d = 0; d < list.length; d++) {
      final date = '$year-${_two(month)}-${_two(d + 1)}';
      final f = list[d];
      map[date] = CalendarDayFacts(
        lunarLabel: f.lunarLabel,
        holidayName: f.holidayName,
        isHoliday: f.isHoliday,
        isWorkday: f.isWorkday,
        description: f.description,
      );
    }
    _monthFactsCache[slot] = map;
    return map;
  }

  /// 月格点选 → 更新选中高亮，并展开底部当日快照面板。
  void _onDaySelected(String date) {
    final slotChanged = _selectedDate != date;
    setState(() {
      _selectedDate = date;
      _showEvents = true;
    });
    if (slotChanged) _monthPageCache.clear(); // 选中态即缓存键，变化即失效。
    _loadEvents(date);
  }

  /// U12b：未授权 → 引导卡按钮 → 平台通道申请（跳转系统设置）。
  Future<void> _requestPermission() async {
    final view = await widget.port.requestPermission();
    if (!mounted) return;
    setState(() {
      if (!view.ok) {
        _permissionHint = '${view.errorCode}：${view.message ?? ''}';
      } else if (view.granted) {
        _permissionHint = '日历权限已授予，重新读取即可';
      } else {
        _permissionHint = '已打开系统设置，授予日历权限后返回';
      }
    });
    if (view.ok && view.granted) {
      _loadOverview(force: true); // 权限授予后数据口径变了，旁路缓存须重拉。
      _yearDensityCache.clear(); // 年页密度同样失效，回年视图时重拉。
    }
  }

  /// 总览是否因权限/源不可用而需要引导（日视图已并入底部面板，仅查 overview）。
  bool get _needsGuidance {
    final code = _overview?.errorCode;
    if (code == CalendarErr.permissionDenied ||
        code == CalendarErr.sourceUnavailable) {
      return true;
    }
    final warnings = _overview?.warnings ?? const <String>[];
    return warnings.any((w) => w.startsWith(CalendarErr.permissionDenied));
  }

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final shell = ShellNav.maybeOf(context);
    final p = t.palette;
    return Scaffold(
      backgroundColor: p.surface,
      appBar: AppBar(
        backgroundColor: p.surface,
        elevation: 0,
        automaticallyImplyLeading: false,
        // ☰ 导航抽屉入口（§6 双通道：左缘滑动手势 + 可见控件）。
        leading: shell == null
            ? null
            : IconButton(
                onPressed: shell.openDrawer,
                icon: const Icon(Icons.menu),
                tooltip: '导航',
              ),
        centerTitle: true,
        // 标题区：‹ 当前年/月 ›。标题月由滚动位移实时推导（跨过半页边界
        // 即换字过渡）——自由滚动下没有「落月才换字」的时刻，标题始终
        // 指向最近整月。点标题 = 月↔年切换的可见通道（§6 双通道：手势
        // 捏合 + 可见控件）。
        // 标题点按 = 逐级放大（月→年→年份块→回月循环，§6 可见控件通道）：
        // 与甩出/捏合同语义，是缩放的可靠兜底。
        title: _mode == _CalMode.month
            ? ValueListenableBuilder<int>(
                valueListenable: _titleDelta,
                builder: (context, delta, _) {
                  final (y, m) = _monthFromDelta(delta);
                  return _RangeNav(
                    label: '$y 年 $m 月',
                    direction: _titleDirection,
                    onTap: _goYear,
                  );
                },
              )
            : _mode == _CalMode.year
            ? ValueListenableBuilder<int>(
                valueListenable: _yearDelta,
                builder: (context, delta, _) {
                  return _RangeNav(
                    label: '${_baseYear + delta} 年',
                    direction: _yearDirection,
                    onTap: _goYearGrid,
                  );
                },
              )
            : ValueListenableBuilder<int>(
                valueListenable: _yearGridDelta,
                builder: (context, delta, _) {
                  return _RangeNav(
                    label: '${_baseYear + delta} 年起',
                    direction: _yearGridDirection,
                    onTap: _goMonth,
                  );
                },
              ),
        actions: <Widget>[
          IconButton(
            onPressed: _jumpToDate,
            tooltip: '跳转到指定日期',
            icon: const Icon(Icons.event),
          ),
          TextButton(
            onPressed: _goToday,
            child: Text(
              '今天',
              style: t.typeScale.compact.copyWith(color: p.l1Info),
            ),
          ),
          if (shell != null)
            TextButton(
              onPressed: shell.onOpenSettings,
              child: Text(
                '设置',
                style: t.typeScale.compact.copyWith(color: p.textMuted),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: Focus(
          focusNode: _focusNode,
          autofocus: true,
          onKeyEvent: _handleKeyEvent,
          child: Column(
            children: <Widget>[
              if (_needsGuidance)
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    t.metrics.space16,
                    t.metrics.space8,
                    t.metrics.space16,
                    0,
                  ),
                  child: GuidanceCard(
                    message: '无法读取系统日历：未授予日历权限',
                    detail:
                        '日历视图需要系统日历读取权限；授予后即可查看日程'
                        '（农历/节假日仍离线可见）',
                    actionLabel: '去授权',
                    onAction: _requestPermission,
                  ),
                ),
              if (_permissionHint != null)
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: t.metrics.space16),
                  child: Text(
                    _permissionHint!,
                    style: t.typeScale.micro.copyWith(color: p.textMuted),
                  ),
                ),
              // 月↔年模式切换：Stack + Offstage 双模式**常驻**——切走不
              // unmount，各自条带滚动位置天然保留（AnimatedSwitcher 会重挂
              // 载子树：条带 offset 丢失 + glide 撞未挂载 controller 被丢弃，
              // 故弃用）；模式切换观感 = 标题 AnimatedSwitcher 换字 + 入场
              // scale/fade 过渡（[_kickZoom]，条带结构不动）。
              Expanded(
                child: ScaleTransition(
                  scale: _zoomScale,
                  child: FadeTransition(
                    opacity: _zoomFade,
                    child: Stack(
                      fit: StackFit.expand,
                      children: <Widget>[
                        Offstage(
                          offstage: _mode != _CalMode.month,
                          child: _buildMonthMode(t),
                        ),
                        Offstage(
                          offstage: _mode != _CalMode.year,
                          child: _buildYearMode(t),
                        ),
                        Offstage(
                          offstage: _mode != _CalMode.yearGrid,
                          child: _buildYearGridMode(t),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      // FAB（原「向上滚动一屏」改挂**全屏切换**）：面板把手行右上角的全屏
      // 按钮移此——面板全屏占满可视区时右上角不再有按钮位，FAB 悬浮位与
      // 面板互不抢手势；图标/tooltip 跟随全屏态（_panelIsFull 回报）。
      // **仅月视图显示**：面板随月视图 Offstage 收起，年/年份块下 FAB 点了
      // 操作的是看不见的面板（无任何反馈）——泄露按钮即「回不去月视图」
      // 的观感病灶；回月通道 = 捏合张开 / 点标题，不靠 FAB。
      floatingActionButton: _showEvents && _mode == _CalMode.month
          ? FloatingActionButton(
              mini: true,
              key: const ValueKey('panel-fullscreen-fab'),
              tooltip: _panelIsFull ? '退出全屏' : '日程全屏',
              onPressed: () => _panelKey.currentState?._toggleFullscreen(),
              child: Icon(
                _panelIsFull ? Icons.fullscreen_exit : Icons.fullscreen,
              ),
            )
          : null,
    );
  }

  // ---------------- 月视图 ----------------

  Widget _buildMonthMode(AppTokens t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(height: t.metrics.space8),
        Expanded(
          child: _overviewLoading && _overview == null
              ? Padding(
                  padding: EdgeInsets.all(t.metrics.space16),
                  child: Text('读取中…', style: t.typeScale.body),
                )
              : _overview?.errorCode != null
              ? Padding(
                  padding: EdgeInsets.all(t.metrics.space16),
                  child: ErrorLine(
                    code: _overview!.errorCode,
                    message: _overview!.message,
                  ),
                )
              : _overview != null
              ? LayoutBuilder(
                  // 极端挤压（面板全屏把条带挤到 ~0 高）：告警行/星期表头等
                  // 固定件装不下即让位消失（0 高度下本就不可见），防
                  // RenderFlex overflow（复现：FAB 全屏后 9.4px 溢出满屏格）。
                  builder: (context, constraints) {
                    final tight = constraints.maxHeight < 120;
                    return Column(
                      children: <Widget>[
                        // 告警行恒占位：翻月后 _overview 异步更新，告警行
                        // 出现/消失会改滚动区高度 → 网格重排即「落月跳一下」；
                        // 隐藏不塌，滚动区高度恒定。极端挤压（tight）下让位。
                        if (!tight)
                          Visibility(
                            maintainSize: true,
                            maintainAnimation: true,
                            maintainState: true,
                            visible: _overview!.warnings.isNotEmpty,
                            child: Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: t.metrics.space16,
                              ),
                              child: Text(
                                _overview!.warnings.toSet().join('；'),
                                style: t.typeScale.micro.copyWith(
                                  color: t.palette.l2Warn,
                                ),
                              ),
                            ),
                          ),
                        // 全局固定星期表头：数据页无限滚动时不动——页内
                        // 对齐表头滚到其正下方即重合，周列全程对齐。极端
                        // 挤压（tight）下让位。
                        if (!tight) const WeekdayHeader(),
                        if (!tight) const SizedBox(height: _kHeaderGap),
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: t.metrics.space8,
                        ),
                        // 内置滚动条：跟手 + 惯性滑行由框架与
                        // [_GlidePhysics] 接管（每页 RepaintBoundary
                        // 隔离光栅），可停在任意位置（两月同屏中间态
                        // 合法停留态），落定预载数据（无重锚换算）。
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            _anchorIfNeeded(constraints);
                            final c = _scroll;
                            return _pinchSensor(
                              child: NotificationListener<ScrollNotification>(
                                onNotification: _onScroll,
                                child: c == null
                                    ? const SizedBox.expand()
                                    : ListView.builder(
                                        controller: c,
                                        physics: _monthPhysics,
                                        itemExtent: _pageHeight,
                                        // ±2 页预挂载：快甩跨界时新页
                                        // 已在视口外就绪，无构建掉帧尖峰。
                                        scrollCacheExtent:
                                            ScrollCacheExtent.pixels(
                                              _pageHeight * 2,
                                            ),
                                        itemCount: _kCenter * 2 + 1,
                                        itemBuilder: (context, i) =>
                                            _monthPageFor(i - _kCenter),
                                      ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                      ],
                    ); // 内容 Column
                  }, // LayoutBuilder builder
                )
              : Padding(
                  padding: EdgeInsets.all(t.metrics.space16),
                  child: const EmptyState(message: '读取当月日程密度'),
                ),
        ),
        // 出现/收起走 AnimatedSize 高度过渡（对齐底边），不再瞬间闪现/消失。
        AnimatedSize(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          alignment: Alignment.bottomCenter,
          child: _showEvents
              ? _EventPanel(
                  key: _panelKey,
                  date: _selectedDate,
                  events: _events,
                  loading: _eventsLoading && _eventsDate == _selectedDate,
                  onClose: () => setState(() => _showEvents = false),
                  onRetry: () => _loadEvents(_selectedDate),
                  onFullscreenChanged: (full) {
                    if (full != _panelIsFull) {
                      setState(() => _panelIsFull = full);
                    }
                  },
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }

  // ---------------- 年视图（月条带同构无限滚动条） ----------------

  Widget _buildYearMode(AppTokens t) {
    return Column(
      children: <Widget>[
        SizedBox(height: t.metrics.space8),
        Expanded(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: t.metrics.space8),
            child: LayoutBuilder(
              builder: (context, constraints) {
                _yearAnchorIfNeeded(constraints);
                final c = _yearScroll;
                return c == null
                    ? const SizedBox.expand()
                    : _pinchSensor(
                        child: NotificationListener<ScrollNotification>(
                          onNotification: _onYearScroll,
                          child: ListView.builder(
                            controller: c,
                            physics: _yearPhysics,
                            itemExtent: _yearPageHeight,
                            // ±2 页预挂载：跨年快甩同月条带口径。
                            scrollCacheExtent: ScrollCacheExtent.pixels(
                              _yearPageHeight * 2,
                            ),
                            itemCount: _kYearCenter * 2 + 1,
                            itemBuilder: (context, i) =>
                                _yearPageFor(i - _kYearCenter),
                          ),
                        ),
                      );
              },
            ),
          ),
        ),
      ],
    );
  }

  // ---------------- L3 年份块视图（月/年条带同构无限滚动条） ----------------

  Widget _buildYearGridMode(AppTokens t) {
    return Column(
      children: <Widget>[
        SizedBox(height: t.metrics.space8),
        Expanded(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: t.metrics.space8),
            child: LayoutBuilder(
              builder: (context, constraints) {
                _yearGridAnchorIfNeeded(constraints);
                final c = _yearGridScroll;
                return c == null
                    ? const SizedBox.expand()
                    : _pinchSensor(
                        child: NotificationListener<ScrollNotification>(
                          onNotification: _onYearGridScroll,
                          child: ListView.builder(
                            controller: c,
                            physics: _yearGridPhysics,
                            itemExtent: _yearGridPageHeight,
                            // ±2 块预挂载：跨块快甩同月/年条带口径。
                            scrollCacheExtent: ScrollCacheExtent.pixels(
                              _yearGridPageHeight * 2,
                            ),
                            itemCount: _kL3Center * 2 + 1,
                            itemBuilder: (context, i) =>
                                _yearGridPageFor(i - _kL3Center),
                          ),
                        ),
                      );
              },
            ),
          ),
        ),
      ],
    );
  }
}

/// 选中日事件面板（月视图底部）：点选某天后向下滑动滚动查看该日从日历获取的事件。
/// 只展示事件标题/时间，不含地点等敏感字段。
///
/// 关闭双通道（§6）：① 点抓手/标题区（可见控件）直接关闭；② 在抓手/标题区**向下拖拽**
/// 关闭（下拉收起，对齐文件头设计意图）。拖拽限缩在抓手热区，避免吞掉事件列表的滚动；
/// 拖拽时面板跟手下移，松手未过阈值则弹性回弹，过位移/速度阈值则触感反馈后关闭。
class _EventPanel extends StatefulWidget {
  const _EventPanel({
    super.key, // 父级挂 GlobalKey 以从 FAB 触发 [_EventPanelState] 全屏切换。
    required this.date,
    required this.events,
    required this.loading,
    required this.onClose,
    required this.onRetry,
    required this.onFullscreenChanged,
  });

  final String date;
  final List<EventView>? events;
  final bool loading;
  final VoidCallback onClose;

  /// 空态重试：空态与「读取失败呈空态」不可辨，给一条主动重拉通道。
  final VoidCallback onRetry;

  /// 全屏态变化回报：全屏切换按钮移到 Scaffold FAB 位（原把手行右上角
  /// 按钮撤除），FAB 图标/tooltip 需跟随 [_EventPanelState._isFull]。
  final ValueChanged<bool> onFullscreenChanged;

  @override
  State<_EventPanel> createState() => _EventPanelState();
}

class _EventPanelState extends State<_EventPanel>
    with SingleTickerProviderStateMixin {
  /// 当前面板高度（px）。**半屏起步**（默认档位，事件列表首屏可读——peek
  /// 200px 太矮看不全，下意识上推的起点就该给足内容）；上拖长高至 max
  /// （三档吸附），下拖降到 peek 以下触发关闭滑出。单一状态驱动高度与
  /// 下拉位移，口径统一。初始值经 [_initPanelHOnce] 在
  /// didChangeDependencies 置位（_halfH 依赖 MediaQuery，禁在 initState 读）。
  double _panelH = 0;

  /// 默认档位是否已初始化（首帧前一次性，防重复置位回跳）。
  bool _panelHInitialized = false;

  /// 默认档位置位：半屏（仅首次，后续拖拽/吸附结果不被覆盖）。
  void _initPanelHOnce() {
    if (_panelHInitialized) return;
    _panelHInitialized = true;
    _panelH = _halfH;
  }

  /// 拖拽起始高度（跟手换算基准：_panelH = base − dy）。
  double? _dragBaseH;

  /// 吸附/滑出动画（复用同一控制器）。**速度连续**：用与 [_GlidePhysics]
  /// 同款临界阻尼弹簧 animateWith 驱动——把手拖拽/列表接力的松手末速直接
  /// 喂入仿真，松手瞬间速度不归零、无「顿一下再走」；原 Tween+定时缓动
  /// 起步零速（速度不连续）是滚动动画不够优雅的主要病灶。
  /// **必须 unbounded**：面板高度是 px 量级（数百），默认控制器的
  /// 0.0–1.0 值域会把弹簧值钳到 1——点全屏后面板塌成 1px（真机复现）。
  late final AnimationController _spring = AnimationController.unbounded(
    vsync: this,
  );

  /// 点按展开完整描述的条目索引（null = 全收起）；换日期/收起面板时重置。
  int? _expandedIndex;

  /// 滚动接力进行中（列表 overscroll 正驱动面板高度）：ScrollEnd 时据此
  /// 走吸附/关闭判定，防止把普通列表滚动的 ScrollEnd 误判为链式拖拽结束。
  bool _chainActive = false;

  /// peek 档高度（px）：抓手 + 日期 + 首屏事件（列表约 168，含抓手约 200）。
  static const double _kPeekH = 200;

  /// 半屏 / 近全屏档：按视口高比例（半屏 0.5 / 近全屏 0.85）。
  static const double _kHalfFraction = 0.5;
  static const double _kMaxFraction = 0.85;

  /// 下甩关闭速度阈值（px/s）：快速下甩即便位移不足也关闭。
  static const double _kDismissVelocity = 300;

  /// 下拉关闭位移阈值（px）：拉到 peek 以下超过此值即关闭。
  static const double _kDismissDistance = 80;

  /// 关闭滑出行程（px）：大于 peek 保证完全滑出屏幕。
  static const double _kSlideOutDistance = 320;

  double get _screenH => MediaQuery.of(context).size.height;
  double get _halfH => _screenH * _kHalfFraction;
  double get _maxH => _screenH * _kMaxFraction;

  /// 真全屏档：面板是月视图列的兄弟、靠**挤压列表**腾高（非覆盖层），故上界取
  /// 「视口高 − 标准 AppBar − 安全区 − 顶部留白」，而非 1.0，避免 RenderFlex 溢出；
  /// 效果上占满日历可视区。**顶部留 48px 呼吸条**（原 8px）：挤到 0 高的退化
  /// 布局下固定件与面板高度的小数尾差互打（复现 0.358px 溢出）；呼吸条让
  /// 条带恒有非退化布局空间，视觉上仍是全屏日程。
  double get _fullH {
    final pad = MediaQuery.of(context).padding;
    return _screenH - kToolbarHeight - pad.top - pad.bottom - 48;
  }

  /// 视觉高度：不小于 peek（关闭时高度保持 peek、用位移滑出，不塌成一条）。
  double get _renderH => _panelH > _kPeekH ? _panelH : _kPeekH;

  /// 下拉关闭位移：peek 以下部分（上拖展开时为 0）。
  double get _translateY => _panelH < _kPeekH ? _kPeekH - _panelH : 0;

  void _onDragStart(DragStartDetails _) {
    _dragBaseH = _panelH;
  }

  void _onDragUpdate(DragUpdateDetails d) {
    // 上拖（dy<0）长高、下拖（dy>0）缩矮/下拉关闭；限缩在抓手热区。
    final h = (_dragBaseH! - d.delta.dy).clamp(0.0, _fullH);
    setState(() => _panelH = h);
    _notifyFull();
  }

  /// 全屏态回报（FAB 图标/tooltip 依据）：拖拽与吸附动画的每个高度变化
  /// 后调用，跨过 _fullH 边界即通知（bool 变化才 setState，稳态零开销）。
  void _notifyFull() {
    widget.onFullscreenChanged(_isFull);
  }

  void _onDragEnd(DragEndDetails d) {
    final v = d.primaryVelocity ?? 0;
    // 关闭：下甩过速度阈值，或拉到 peek 以下过位移阈值（跟手延续滑出，不瞬隐）。
    if (v > _kDismissVelocity || _panelH < _kPeekH - _kDismissDistance) {
      _dismiss(velocity: v); // 松手末速喂入弹簧，滑出顺势加速。
    } else {
      _snapTo(_nearestSnap(), velocity: v); // 末速连续，吸附无顿挫。
    }
  }

  /// 最近的吸附档（peek / 半屏 / 近全屏 / 全屏）。
  double _nearestSnap() {
    var best = _kPeekH;
    for (final s in <double>[_halfH, _maxH, _fullH]) {
      if ((s - _panelH).abs() < (best - _panelH).abs()) best = s;
    }
    return best;
  }

  /// 是否处于全屏档（面板盖满下方可视区）。
  bool get _isFull => _panelH >= _fullH - 1;

  /// 全屏双通道：FAB（Scaffold 悬浮位）点按在半屏 / 全屏间切换，让当天日程
  /// 占满可视区；父级经 [_EventPanel.fullscreenKey 对应的 widget key] 调用本方法，
  /// 全屏态经 onFullscreenChanged 回报驱动 FAB 图标。
  void _toggleFullscreen() => _snapTo(_isFull ? _halfH : _fullH);

  /// 点把手 = 一次直接关闭（用户拍板：默认半屏后降档中转啰嗦——半屏→
  /// peek→关要点两次；热区已加大 + 下拉/滚动接力链都在，误触代价可控）。
  /// 降档语义保留在拖拽/列表顶部下拉链路里。
  void _onHandleTap() {
    widget.onClose();
  }

  /// 滚动接力链（内容优先、面板兜底）：
  /// - 列表能滚 → 上滑滚内容（本方法不拦截，正常滚动）；
  /// - 列表**已在顶部**继续**下拉**（overscroll < 0）→ 面板跟手降档，
  ///   松手过位移阈值即关闭、否则吸附最近档——「把面板拉回来」；
  /// - 列表**滚不动**（内容不足一屏，maxScrollExtent==0 且在顶）继续
  ///   **上推**（overscroll > 0）→ 面板跟手升档直至全屏——手势无处可去
  ///   时才交给面板，不与内容滚动抢。
  /// 仅吃最内层滚动（depth 0），把手拖拽进行中不接力（[_dragBaseH] 非空）。
  bool _onListChainScroll(ScrollNotification n) {
    if (_dragBaseH != null) return false;
    if (n.depth != 0) return false;
    if (n is ScrollUpdateNotification) {
      final m = n.metrics;
      final delta = n.scrollDelta ?? 0;
      if (delta == 0) return false;
      // 顶部下拉（delta<0 吸收为 overscroll）→ 面板降档；顶部上推且列表
      // 无可滚内容（delta>0 被吸收）→ 面板升档。两者都以 pixels 在顶为前提。
      if (m.pixels <= 0 && (delta < 0 || m.maxScrollExtent <= 0)) {
        setState(() => _panelH = (_panelH + delta).clamp(0.0, _fullH));
        _chainActive = true;
        _notifyFull();
      }
    } else if (n is ScrollEndNotification && _chainActive) {
      _chainActive = false;
      // 判定口径与把手拖拽一致：拉到 peek 以下过阈值即关闭，否则吸附最近档。
      if (_panelH < _kPeekH - _kDismissDistance) {
        _dismiss();
      } else {
        _snapTo(_nearestSnap());
      }
    }
    return false;
  }

  /// 吸附到目标高度（速度连续弹簧；reduced motion 直落）。
  /// [velocity] = 松手末速（px/s，向下为正），从把手拖拽/接力链末速喂入。
  void _snapTo(double target, {double velocity = 0}) {
    if (MediaQuery.disableAnimationsOf(context)) {
      setState(() => _panelH = target);
      _notifyFull();
      return;
    }
    _spring.stop();
    _spring.animateWith(
      SpringSimulation(_GlidePhysics.kSpring, _panelH, target, velocity),
    );
  }

  /// 关闭：从当前位移继续滑出屏幕（跟手延续，末速喂入弹簧顺势加速），
  /// 落定后摘除面板。
  void _dismiss({double velocity = 0}) {
    HapticFeedback.lightImpact();
    if (MediaQuery.disableAnimationsOf(context)) {
      widget.onClose();
      return;
    }
    _spring.stop();
    _spring
        .animateWith(
          // 目标越过 peek 使 _translateY 达 _kSlideOutDistance（完全滑出）。
          SpringSimulation(
            _GlidePhysics.kSpring,
            _panelH,
            _kPeekH - _kSlideOutDistance,
            velocity,
          ),
        )
        .then((_) {
          if (!mounted) return;
          widget.onClose();
        });
  }

  void _onTick() {
    if (mounted) {
      setState(() => _panelH = _spring.value);
      _notifyFull();
    }
  }

  @override
  void didUpdateWidget(covariant _EventPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    _initPanelHOnce(); // 默认档位半屏：一次性置位（依赖 MediaQuery，禁在 initState 读）。
    // 换日期：展开态索引随旧列表作废，收起防错位展开。
    if (oldWidget.date != widget.date && _expandedIndex != null) {
      _expandedIndex = null;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _initPanelHOnce(); // 首帧 build 前一次性置位，防首帧 peek → 半屏跳变。
  }

  @override
  void initState() {
    super.initState();
    _spring.addListener(_onTick); // 弹簧值 → _panelH 统一出口。
  }

  @override
  void dispose() {
    _spring.removeListener(_onTick);
    _spring.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final p = t.palette;
    final dt = DateTime.parse(widget.date);
    final weekday = const <String>[
      '一',
      '二',
      '三',
      '四',
      '五',
      '六',
      '日',
    ][dt.weekday - 1];
    return Transform.translate(
      offset: Offset(0, _translateY),
      child: Container(
        decoration: BoxDecoration(
          color: p.surface,
          border: Border(
            top: BorderSide(
              color: p.hairline,
              width: t.metrics.borderWidthThin,
            ),
          ),
        ),
        child: SizedBox(
          height: _renderH,
          child: Column(
            children: <Widget>[
              // 把手行：仅剩抓手 + 日期（点按关闭 + 下拉拖拽热区）。全屏切换
              // 按钮已移到 Scaffold FAB 位（onFullscreenChanged 回报全屏态）。
              GestureDetector(
                // 点抓手 = 一次直接关闭（可见控件）；上拖 = 跟手长高、下拖 =
                // 下拉收起/关闭（限缩在把手热区，不吞事件列表滚动）。降档
                // 走拖拽/列表顶部下拉（滚动接力链），点按不中转。
                onTap: _onHandleTap,
                onVerticalDragStart: _onDragStart,
                onVerticalDragUpdate: _onDragUpdate,
                onVerticalDragEnd: _onDragEnd,
                behavior: HitTestBehavior.opaque,
                child: Column(
                  children: <Widget>[
                    // 热区大幅加高（fat-finger 实测反馈：热区太小手指太粗，
                    // 触摸串到日历格 → 操作混乱）：上下留白 16px + 日期行
                    // 下 16px，把手可点/可拖区约 100px 高——足够粗手指稳定
                    // 落点，peek 200px 下仍给事件列表留足首屏。
                    SizedBox(height: t.metrics.space16),
                    Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: p.hairline,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    SizedBox(height: t.metrics.space16),
                    // 方向 chevron（HCI 可供性）：未全屏朝上 = 提示「上推/
                    // 上拖展开」（滚动接力链 + 把手拖拽共用语义）；全屏翻转
                    // 向下 = 「下拉收回」。旋转 180° 过渡，方向即隐喻。
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          '${dt.month}月${dt.day}日 周$weekday',
                          style: t.typeScale.compact.copyWith(
                            color: p.textMuted,
                          ),
                        ),
                        SizedBox(width: t.metrics.space4),
                        AnimatedRotation(
                          turns: _isFull ? 0.5 : 0,
                          duration: MediaQuery.disableAnimationsOf(context)
                              ? Duration.zero
                              : const Duration(milliseconds: 200),
                          child: Icon(
                            Icons.expand_less,
                            size: 16,
                            color: p.textMuted,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: t.metrics.space16),
                  ],
                ),
              ),
              // 滚动接力链（内容优先、面板兜底）：列表能滚 → 上滑滚内容；
              // 列表已在顶部继续下拉 → 面板跟手降档/关闭；内容少到滚不动
              // （maxScrollExtent==0）时上推 → 面板跟手升档直至全屏。规则
              // 见 [_EventPanelState._onListChainScroll]。
              Expanded(
                child: NotificationListener<ScrollNotification>(
                  onNotification: _onListChainScroll,
                  child: widget.loading
                    ? Center(
                        child: Text(
                          '读取中…',
                          style: t.typeScale.micro.copyWith(color: p.textMuted),
                        ),
                      )
                    : (widget.events == null || widget.events!.isEmpty)
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Text(
                              '无日程',
                              style: t.typeScale.micro.copyWith(
                                color: p.textMuted,
                              ),
                            ),
                            SizedBox(height: t.metrics.space8),
                            // 空态与「读取失败呈空态」不可辨——重试补一条
                            // 主动重拉通道（读取成功再点也只是幂等重查）。
                            TextButton.icon(
                              onPressed: widget.onRetry,
                              icon: const Icon(Icons.refresh, size: 18),
                              label: const Text('重新读取'),
                              style: TextButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: EdgeInsets.symmetric(
                          horizontal: t.metrics.space16,
                          vertical: t.metrics.space4,
                        ),
                        itemCount: widget.events!.length,
                        itemBuilder: (context, i) {
                          final e = widget.events![i];
                          final expanded = _expandedIndex == i;
                          final desc = e.description;
                          return InkWell(
                            // 点按展开/收起完整描述（只读信息出口；描述截断
                            // 2 行时点开看全文，无描述的条目不可点）。
                            onTap: (desc?.isNotEmpty == true)
                                ? () => setState(() {
                                    _expandedIndex = expanded ? null : i;
                                  })
                                : null,
                            child: Padding(
                              padding: EdgeInsets.symmetric(
                                vertical: t.metrics.space4,
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  SizedBox(
                                    width: 52,
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: <Widget>[
                                        Text(
                                          e.timeText,
                                          style: t.typeScale.micro.copyWith(
                                            color: p.textMuted,
                                          ),
                                        ),
                                        if (e.feedName != null &&
                                            e.feedName!.isNotEmpty)
                                          Text(
                                            e.feedName!,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: t.typeScale.micro.copyWith(
                                              color: p.textMuted,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  SizedBox(width: t.metrics.space8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: <Widget>[
                                        Text(
                                          e.title,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: t.typeScale.listItem,
                                        ),
                                        if (desc != null && desc.isNotEmpty)
                                          Text(
                                            desc,
                                            maxLines: expanded ? null : 2,
                                            overflow: expanded
                                                ? TextOverflow.visible
                                                : TextOverflow.ellipsis,
                                            style: t.typeScale.micro.copyWith(
                                              color: p.textMuted,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 区间导航条：当前年月标题（翻月落定时随内容方向滚动换字）。
/// [onTap] = 点标题切换视图模式（月↔年，§6 双通道的可见控件通道）。
class _RangeNav extends StatelessWidget {
  const _RangeNav({required this.label, this.direction = 0, this.onTap});

  final String label;

  final VoidCallback? onTap;

  /// 过渡方向：+1 翻向下一页（旧上出/新下入，与条带同向）、-1 反向、
  /// 0 无方向语义（点标题/今天归位）——纯淡入淡出。
  final int direction;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    // 翻月换字：新标题从条带运动方向**轻推入**（小幅滑移 + 淡入），旧标题
    // 同向淡出——与内容滚动同向、幅度克制，看起来是「月份在走」而非穿帮跳变；
    // 无方向跳转（今天/重锚）则为纯淡入淡出。减少动效时直切。
    final title = AnimatedSwitcher(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 200),
      transitionBuilder: (child, anim) {
        final slide = Tween<Offset>(
          begin: Offset(0, 0.4 * direction),
          end: Offset.zero,
        ).animate(anim);
        return FadeTransition(
          opacity: anim,
          child: SlideTransition(position: slide, child: child),
        );
      },
      child: Text(label, key: ValueKey(label), style: t.typeScale.titleSmall),
    );
    return Row(
      children: <Widget>[
        Expanded(
          child: Center(
            // GestureDetector 而非 InkWell：AppBar 标题槽位真机上 InkWell
            // tap 竞技场不稳（同 AppBar 的 TextButton 可点、InkWell 不响应，
            // 真机取证 2026-10-27）；手势语义只需 onTap，无需水纹。
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onTap,
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: t.metrics.space8,
                  vertical: t.metrics.space4,
                ),
                child: title,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
