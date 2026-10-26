library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../mcp/calendar_provider.dart';
import '../ui_ports/calendar_port.dart';
import 'components/app_components.dart';
import 'components/calendar_grid.dart';
import 'home_shell.dart';
import 'tokens/app_tokens.dart';

/// 日历子页面（极简 + 手势）：默认**月视图**为绝对主角，年视图为缩放层，
/// 点选日 → **底部面板同屏**展开当天只读快照（不切独立模式）。
///
/// 定位红线（ui-console.md §1）：**不做日程管理**——本页不提供事件/标记增删改，
/// 写归系统日历本身与 Agent 侧 W 档命令；UI 只读。
/// 手势（§6 双通道：每条手势均有等价可见控件——箭头 / 可点标题 / 今天按钮 / 把手）：
///   横滑 = 切月/年；双指捏合收缩 = 月→年（缩放层）；点月份标题 = 跳年/回月；
///   「今天」按钮 = 归位；点日格 / 上滑面板把手 = 展开当日快照（下拉收起）。
/// 离线兜底：农历 / 节气 / 法定节假日来自纯内核，不依赖系统日历权限，未授权页也不空。
enum _CalMode { month, year }

/// 横滑切页速度阈值（px/s）：低于此值的拖动不算翻页意图。
/// token 阶梯无数值档，显式命名常量收口，禁散落字面量。
const double _kSwipeVelocity = 120;

class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key, required this.port});

  final CalendarPort port;

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage>
    with SingleTickerProviderStateMixin {
  /// 权限申请反馈（人话；透出机器码）。
  String? _permissionHint;

  /// 当前视图模式（默认月视图，挂历/极简形态的前提）。
  _CalMode _mode = _CalMode.month;

  /// 月/年视图的定位（切月/切年由导航与手势驱动）。
  int _viewYear = 1970;
  int _viewMonth = 1;

  /// 选中日（用于月格/年格高亮；默认今天）。
  String _selectedDate = '';

  /// 月视图手势临时累积（横滑位移 + 捏合缩放，单一 scale 识别器复用）。
  double _gestureDx = 0;
  double _gestureScale = 1;
  int _gesturePointers = 1;

  /// 月/年视图数据（当前定位区间；用于权限/源告警引导，不参与网格密度）。
  CalendarRangeOverviewView? _overview;

  /// 逐月/逐年密度缓存：`YYYY-MM`（月）或 `YYYY`（年）槽位 → 该区间逐日密度。
  /// 切页时预载当前 ±1 槽位，供「跟手 + 相邻页预览」的滑动条使用。
  final Map<String, Map<String, CalendarDayDensity>> _densityCache =
      <String, Map<String, CalendarDayDensity>>{};

  /// 月离线事实缓存（`YYYY-MM` → 事实映射），避免滑动逐帧重算农历/节假日
  /// （稳定引用也使相邻月 MonthGrid 在拖拽时不被重建）。
  final Map<String, Map<String, CalendarDayFacts>> _monthFactsCache =
      <String, Map<String, CalendarDayFacts>>{};

  /// 滑动条单页宽度（由 LayoutBuilder 量得；用于实时平移与吸附阈值）。
  double _pageWidth = 0;

  /// 松手吸附动画（把实时拖拽位移补完到目标页或回弹到 0）。
  late final AnimationController _swipe = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
  )..addListener(_onSwipeTick);

  double _releaseFrom = 0;
  double _releaseTo = 0;
  int _animToken = 0;

  bool _overviewLoading = false;

  /// 两指捏合进年视图的速度阈值（scale<1 即收缩，无需速度）。
  static const double _kPinchInScale = 0.9;

  /// 拖拽吸附阈值（占单页宽度比例）：超过即判定翻页意图。
  static const double _kSwipeRatio = 0.3;

  /// 选中日事件（月视图底部下拉面板用；只取事件标题/时间，不含地点等敏感字段）。
  List<EventView>? _events;
  String? _eventsDate;
  bool _eventsLoading = false;
  bool _showEvents = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _viewYear = now.year;
    _viewMonth = now.month;
    _selectedDate = _today;
    _loadOverview();
  }

  String get _today {
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${now.year}-${two(now.month)}-${two(now.day)}';
  }

  String _two(int v) => v.toString().padLeft(2, '0');

  /// 加载月/年视图数据：预载「当前 ±1」槽位密度进 [_densityCache]，供滑动条做
  /// 相邻页预览；当前槽位的总览（告警/错误）存 [_overview] 供引导展示。
  Future<void> _loadOverview() async {
    setState(() => _overviewLoading = true);
    final tasks = <(String, String, String)>[]; // (slot, start, end)
    if (_mode == _CalMode.month) {
      for (final m in <(int, int)>[
        _adjacentMonth(-1),
        (_viewYear, _viewMonth),
        _adjacentMonth(1),
      ]) {
        final lastDay = DateTime(m.$1, m.$2 + 1, 0).day;
        tasks.add((
          '${m.$1}-${_two(m.$2)}',
          '${m.$1}-${_two(m.$2)}-01',
          '${m.$1}-${_two(m.$2)}-$lastDay',
        ));
      }
    } else {
      for (final y in <int>[_viewYear - 1, _viewYear, _viewYear + 1]) {
        tasks.add(('$y', '$y-01-01', '$y-12-31'));
      }
    }
    final views = await Future.wait(
      tasks.map(
        (t) => widget.port.rangeOverview(rangeStart: t.$2, rangeEnd: t.$3),
      ),
    );
    if (!mounted) return;
    for (var i = 0; i < tasks.length; i++) {
      _storeDensities(tasks[i].$1, views[i]);
    }
    final primary = views[1]; // 中间槽位即当前页。
    setState(() {
      _overview = primary;
      _overviewLoading = false;
      // 读取成功即权限提示已过时——不清会一直挂着「重新读取即可」误导用户。
      if (primary.errorCode == null) _permissionHint = null;
    });
  }

  void _storeDensities(String slot, CalendarRangeOverviewView view) {
    _densityCache[slot] = <String, CalendarDayDensity>{
      for (final d in view.days)
        d.date: CalendarDayDensity(
          eventCount: d.eventCount,
          markerCount: d.markerCount,
        ),
    };
  }

  /// 相邻月（delta = -1 / +1），自动跨年进位/借位。
  (int, int) _adjacentMonth(int delta) {
    var y = _viewYear;
    var m = _viewMonth + delta;
    if (m < 1) {
      m = 12;
      y -= 1;
    } else if (m > 12) {
      m = 1;
      y += 1;
    }
    return (y, m);
  }

  /// 松手吸附动画每帧：把 [_gestureDx] 从起止插值到目标位移。
  void _onSwipeTick() {
    if (!mounted) return;
    setState(
      () => _gestureDx = _releaseFrom + (_releaseTo - _releaseFrom) * _swipe.value,
    );
  }

  /// 把实时拖拽位移补完到目标（±_pageWidth 翻页 或 0 回弹）。
  void _animateRelease(double to, {VoidCallback? onDone}) {
    _releaseFrom = _gestureDx;
    _releaseTo = to;
    final token = ++_animToken; // 令旧的 pending .then 失效，避免过期回调节流。
    _swipe.forward(from: 0).then((_) {
      if (!mounted || token != _animToken) return;
      setState(() => _gestureDx = to);
      onDone?.call();
    });
  }

  /// 提交翻月（吸附动画结束后调用）：视图落到相邻月并预载其 ±1 密度。
  void _commitMonth(int delta) {
    final adj = _adjacentMonth(delta);
    setState(() {
      _viewYear = adj.$1;
      _viewMonth = adj.$2;
      _gestureDx = 0;
    });
    _loadOverview();
  }

  /// 提交翻年（吸附动画结束后调用）。
  void _commitYear(int delta) {
    setState(() {
      _viewYear += delta;
      _gestureDx = 0;
    });
    _loadOverview();
  }

  /// 月视图单页（当前页可点选/高亮；相邻页只读、不响应点选，避免跨月误选）。
  Widget _monthPage(int year, int month, bool isCurrent) {
    return MonthGrid(
      year: year,
      month: month,
      densities:
          _densityCache['$year-${_two(month)}'] ?? const <String, CalendarDayDensity>{},
      selectedDate: isCurrent ? _selectedDate : '',
      todayDate: _today,
      dayFacts: _monthFactsFor(year, month),
      onDaySelected: isCurrent ? _onDaySelected : null,
    );
  }

  /// 年视图单页（同理：仅当前年可点月）。
  Widget _yearPage(int year, bool isCurrent) {
    final sel = _selectedDate.split('-');
    final selYear = sel.isNotEmpty ? int.tryParse(sel[0]) ?? -1 : -1;
    final selMonth = sel.length >= 2 ? int.tryParse(sel[1]) ?? 0 : 0;
    final selDay = sel.length >= 3 ? int.tryParse(sel[2]) ?? -1 : -1;
    return YearGrid(
      year: year,
      densities: _densityCache['$year'] ?? const <String, CalendarDayDensity>{},
      currentMonth: DateTime.now().year == year ? DateTime.now().month : 0,
      today: DateTime.now(),
      selectedMonth: isCurrent && selYear == year ? selMonth : 0,
      selectedDay: isCurrent && selYear == year ? selDay : -1,
      onMonthSelected: isCurrent ? _onMonthSelected : null,
    );
  }

  /// 逐月离线事实映射（农历 / 节假日 / 休班），纯本地、零权限依赖。
  /// 结果按 `YYYY-MM` 槽位缓存，拖拽时稳定引用，避免逐帧重算与相邻页重建。
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

  /// 滑动条单页容器：按 [left] 偏移、固定 [width]、撑满高度，置于 [Stack] 内。
  Widget _stripPage(double left, double width, Widget child) {
    return Positioned(
      left: left,
      top: 0,
      bottom: 0,
      width: width,
      child: child,
    );
  }

  @override
  void dispose() {
    _swipe.dispose();
    super.dispose();
  }

  /// 加载选中日事件（底部下拉面板；只取事件标题/时间，不含地点等敏感字段）。
  Future<void> _loadEvents(String date) async {
    setState(() {
      _eventsLoading = true;
      _eventsDate = date;
    });
    final view = await widget.port.snapshot(date: date);
    if (!mounted) return;
    setState(() {
      _events = view.events;
      _eventsLoading = false;
    });
  }

  void _goMonth() {
    setState(() {
      _mode = _CalMode.month;
      _gestureDx = 0; // 视图模式切换：复位滑动条位移。
    });
    _loadOverview();
  }

  void _goYear() {
    setState(() {
      _mode = _CalMode.year;
      _gestureDx = 0;
    });
    _loadOverview();
  }

  /// 「今天」归位：回到当月、选中今天，并展开当日快照面板。
  void _goToday() {
    final now = DateTime.now();
    setState(() {
      _viewYear = now.year;
      _viewMonth = now.month;
      _selectedDate = _today;
      _mode = _CalMode.month;
      _showEvents = true;
      _gestureDx = 0;
    });
    _loadOverview();
    _loadEvents(_today);
  }

  /// 月格点选 → 更新选中高亮，并展开底部当日快照面板。
  void _onDaySelected(String date) {
    setState(() {
      _selectedDate = date;
      _showEvents = true;
    });
    _loadEvents(date);
  }

  /// 年视图点迷你月 → 落月视图并定位该月（即时切换，无横滑语义）。
  void _onMonthSelected(int month) {
    setState(() {
      _mode = _CalMode.month;
      _viewMonth = month;
      _gestureDx = 0;
    });
    _loadOverview();
  }

  /// 月视图箭头切月：复用与滑动同套的吸附动画（方向对齐 PageView），
  /// 落月后由 [_commitMonth] 预载 ±1 密度。
  void _shiftMonth(int delta) {
    _animateRelease(delta > 0 ? -_pageWidth : _pageWidth,
        onDone: () => _commitMonth(delta));
  }

  /// 年视图箭头切年：同上。
  void _shiftYear(int delta) {
    _animateRelease(delta > 0 ? -_pageWidth : _pageWidth,
        onDone: () => _commitYear(delta));
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
      _loadOverview();
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
        centerTitle: true,
        // 左右切换搬进标题区：‹ 当前年/月 › 可点跳年/回月（手势的可见双通道），
        // body 不再保留独立导航行，腾出显示面积给网格。
        title: _RangeNav(
          label: _mode == _CalMode.month
              ? '$_viewYear 年 $_viewMonth 月'
              : '$_viewYear 年',
          onPrev: _mode == _CalMode.month
              ? () => _shiftMonth(-1)
              : () => _shiftYear(-1),
          onNext: _mode == _CalMode.month
              ? () => _shiftMonth(1)
              : () => _shiftYear(1),
          onLabelTap: _mode == _CalMode.month ? _goYear : _goMonth,
        ),
        actions: <Widget>[
          TextButton(
            onPressed: _goToday,
            child: Text('今天', style: t.typeScale.compact.copyWith(color: p.l1Info)),
          ),
          if (shell != null)
            TextButton(
              onPressed: shell.onOpenSettings,
              child: Text('设置', style: t.typeScale.compact.copyWith(color: p.textMuted)),
            ),
        ],
      ),
      body: SafeArea(
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
                  detail: '日历视图需要系统日历读取权限；授予后即可查看日程'
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
            Expanded(
              child: _mode == _CalMode.month
                  ? _buildMonthMode(t)
                  : _buildYearMode(t),
            ),
          ],
        ),
      ),
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
                      ? Column(
                          children: <Widget>[
                            if (_overview!.warnings.isNotEmpty)
                              Padding(
                                padding: EdgeInsets.symmetric(
                                  horizontal: t.metrics.space16,
                                ),
                                child: Text(
                                  _overview!.warnings.toSet().join('；'),
                                  style: t.typeScale.micro
                                      .copyWith(color: t.palette.l2Warn),
                                ),
                              ),
                            Expanded(
                              child: Padding(
                                padding: EdgeInsets.symmetric(
                                  horizontal: t.metrics.space8,
                                ),
                                // LayoutBuilder 量得单页宽度；3 页（prev/当前/next）
                                // 并排，实时跟随手指平移，松手吸附——「跟手 + 相邻月预览」。
                                child: LayoutBuilder(
                                  builder: (context, constraints) {
                                    _pageWidth = constraints.maxWidth;
                                    final prev = _adjacentMonth(-1);
                                    final next = _adjacentMonth(1);
                                    return GestureDetector(
                                      // 单一 scale 识别器同时承载「单指横滑切月（跟手 +
                                      // 相邻月预览）」与「双指捏合收缩 → 年视图」（§6 双通道）。
                                      onScaleStart: (d) {
                                        _gestureDx = 0;
                                        _gestureScale = 1.0;
                                        _gesturePointers = d.pointerCount;
                                        _animToken++; // 作废进行中的吸附动画
                                        _swipe.stop();
                                      },
                                      onScaleUpdate: (d) {
                                        _gestureScale = d.scale;
                                        if (_gesturePointers == 1) {
                                          _gestureDx += d.focalPointDelta.dx;
                                          if (_pageWidth > 0) {
                                            _gestureDx = _gestureDx.clamp(
                                              -_pageWidth,
                                              _pageWidth,
                                            );
                                          }
                                          setState(() {});
                                        }
                                      },
                                      onScaleEnd: (d) {
                                        // 进年视图须明确双指捏合（pointerCount>=2），
                                        // 单指横滑绝不误触——避免「滑一下闪到年视图」。
                                        if (_gesturePointers >= 2 &&
                                            _gestureScale < _kPinchInScale) {
                                          _goYear();
                                          return;
                                        }
                                        final threshold = _pageWidth > 0
                                            ? _pageWidth * _kSwipeRatio
                                            : 60.0;
                                        if (_gestureDx <= -threshold) {
                                          _animateRelease(
                                            -_pageWidth,
                                            onDone: () => _commitMonth(1),
                                          );
                                        } else if (_gestureDx >= threshold) {
                                          _animateRelease(
                                            _pageWidth,
                                            onDone: () => _commitMonth(-1),
                                          );
                                        } else {
                                          _animateRelease(0);
                                        }
                                      },
                                      child: ClipRect(
                                        child: Transform.translate(
                                          offset: Offset(_gestureDx, 0),
                                          child: Stack(
                                            children: <Widget>[
                                              _stripPage(
                                                -_pageWidth,
                                                _pageWidth,
                                                _monthPage(
                                                  prev.$1,
                                                  prev.$2,
                                                  false,
                                                ),
                                              ),
                                              _stripPage(
                                                0,
                                                _pageWidth,
                                                _monthPage(
                                                  _viewYear,
                                                  _viewMonth,
                                                  true,
                                                ),
                                              ),
                                              _stripPage(
                                                _pageWidth,
                                                _pageWidth,
                                                _monthPage(
                                                  next.$1,
                                                  next.$2,
                                                  false,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                          ],
                        )
                      : Padding(
                          padding: EdgeInsets.all(t.metrics.space16),
                          child: const EmptyState(message: '读取当月日程密度'),
                        ),
        ),
        if (_showEvents)
          _EventPanel(
            date: _selectedDate,
            events: _events,
            loading: _eventsLoading && _eventsDate == _selectedDate,
            onClose: () => setState(() => _showEvents = false),
          ),
      ],
    );
  }

  // ---------------- 年视图 ----------------

  Widget _buildYearMode(AppTokens t) {
    return Padding(
      padding: EdgeInsets.all(t.metrics.space16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(height: t.metrics.space8),
          if (_overviewLoading && _overview == null)
            Expanded(
              child: Center(
                child: Text('读取中…', style: t.typeScale.body),
              ),
            )
          else if (_overview?.errorCode != null)
            Expanded(
              child: Center(
                child: ErrorLine(
                  code: _overview!.errorCode,
                  message: _overview!.message,
                ),
              ),
            )
          else if (_overview != null) ...<Widget>[
            if (_overview!.warnings.isNotEmpty)
              Padding(
                padding: EdgeInsets.only(bottom: t.metrics.space4),
                child: Text(
                  _overview!.warnings.toSet().join('；'),
                  style: t.typeScale.micro.copyWith(color: t.palette.l2Warn),
                ),
              ),
            // 年视图撑满：YearGrid 内部 4 行 Expanded，消除底部空白。
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  _pageWidth = constraints.maxWidth;
                  return GestureDetector(
                    // 左右横滑切年（与月视图同手势语义）：拖拽实时跟手 + 相邻年预览，
                    // 松手按位移 / 速度吸附。
                    onHorizontalDragStart: (_) {
                      _gestureDx = 0;
                      _animToken++; // 作废进行中的吸附动画
                      _swipe.stop();
                    },
                    onHorizontalDragUpdate: (d) {
                      _gestureDx += d.delta.dx;
                      if (_pageWidth > 0) {
                        _gestureDx = _gestureDx.clamp(-_pageWidth, _pageWidth);
                      }
                      setState(() {});
                    },
                    onHorizontalDragEnd: (d) {
                      final v = d.primaryVelocity ?? 0;
                      final threshold = _pageWidth > 0
                          ? _pageWidth * _kSwipeRatio
                          : 60.0;
                      if (_gestureDx <= -threshold || v < -_kSwipeVelocity) {
                        _animateRelease(
                          -_pageWidth,
                          onDone: () => _commitYear(1),
                        );
                      } else if (_gestureDx >= threshold ||
                          v > _kSwipeVelocity) {
                        _animateRelease(
                          _pageWidth,
                          onDone: () => _commitYear(-1),
                        );
                      } else {
                        _animateRelease(0);
                      }
                    },
                    child: ClipRect(
                      child: Transform.translate(
                        offset: Offset(_gestureDx, 0),
                        child: Stack(
                          children: <Widget>[
                            _stripPage(
                              -_pageWidth,
                              _pageWidth,
                              _yearPage(_viewYear - 1, false),
                            ),
                            _stripPage(
                              0,
                              _pageWidth,
                              _yearPage(_viewYear, true),
                            ),
                            _stripPage(
                              _pageWidth,
                              _pageWidth,
                              _yearPage(_viewYear + 1, false),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            SizedBox(height: t.metrics.space4),
            Text(
              '左右滑动切换年份 · 点月份标题回到月视图',
              style: t.typeScale.micro.copyWith(color: t.palette.textMuted),
            ),
          ] else
            Expanded(
              child: Center(
                child: const EmptyState(message: '读取全年日程密度'),
              ),
            ),
        ],
      ),
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
    required this.date,
    required this.events,
    required this.loading,
    required this.onClose,
  });

  final String date;
  final List<EventView>? events;
  final bool loading;
  final VoidCallback onClose;

  @override
  State<_EventPanel> createState() => _EventPanelState();
}

class _EventPanelState extends State<_EventPanel>
    with SingleTickerProviderStateMixin {
  /// 抓手下拖的跟手位移（px）；仅向下累积（向上留白不误触）。
  double _dragOffset = 0;

  /// 回弹动画（未达关闭阈值时从当前位移弹回 0）。
  late final AnimationController _spring = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  );

  /// 拖拽关闭位移阈值（px）：超过即判定关闭意图。
  static const double _kDismissDistance = 80;

  /// 下甩关闭速度阈值（px/s）：快速下甩即便位移不足也关闭。
  static const double _kDismissVelocity = 300;

  Animation<double>? _rebound;
  void _onRebound() {
    if (mounted) setState(() => _dragOffset = _rebound!.value);
  }

  void _onDragUpdate(DragUpdateDetails d) {
    if (d.delta.dy <= 0) return; // 仅向下拖才累积。
    setState(() => _dragOffset += d.delta.dy);
  }

  void _onDragEnd(DragEndDetails d) {
    final v = d.primaryVelocity ?? 0;
    if (_dragOffset > _kDismissDistance || v > _kDismissVelocity) {
      HapticFeedback.lightImpact();
      widget.onClose();
      return;
    }
    // 未达阈值：从当前位移弹性回弹到 0（先摘除旧监听，避免叠加多个动画）。
    _rebound?.removeListener(_onRebound);
    _spring.reset();
    _rebound = Tween<double>(begin: _dragOffset, end: 0).animate(
      CurvedAnimation(parent: _spring, curve: Curves.easeOut),
    )..addListener(_onRebound);
    _spring.forward().then((_) {
      if (mounted) setState(() => _dragOffset = 0);
    });
  }

  @override
  void dispose() {
    _rebound?.removeListener(_onRebound);
    _spring.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final p = t.palette;
    final parts = widget.date.split('-');
    final dt = DateTime(
      int.parse(parts[0]),
      int.parse(parts[1]),
      int.parse(parts[2]),
    );
    final weekday = const <String>['一', '二', '三', '四', '五', '六', '日']
        [dt.weekday - 1];
    return Transform.translate(
      offset: Offset(0, _dragOffset),
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            GestureDetector(
              // 双通道关闭：点 = 立即关；向下拖 = 下拉收起（限缩在抓手热区）。
              onTap: widget.onClose,
              onVerticalDragUpdate: _onDragUpdate,
              onVerticalDragEnd: _onDragEnd,
              behavior: HitTestBehavior.opaque,
              child: Column(
                children: <Widget>[
                  SizedBox(height: t.metrics.space4),
                  Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: p.hairline,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  SizedBox(height: t.metrics.space4),
                  Text(
                    '${dt.month}月${dt.day}日 周$weekday',
                    style: t.typeScale.compact.copyWith(color: p.textMuted),
                  ),
                  SizedBox(height: t.metrics.space4),
                ],
              ),
            ),
            SizedBox(
              height: 168,
              child: widget.loading
                  ? Center(
                      child: Text(
                        '读取中…',
                        style: t.typeScale.micro.copyWith(color: p.textMuted),
                      ),
                    )
                  : (widget.events == null || widget.events!.isEmpty)
                      ? Center(
                          child: Text(
                            '无日程',
                            style: t.typeScale.micro.copyWith(color: p.textMuted),
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
                            return Padding(
                              padding: EdgeInsets.symmetric(
                                vertical: t.metrics.space4,
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  SizedBox(
                                    width: 52,
                                    child: Text(
                                      e.timeText,
                                      style: t.typeScale.micro
                                          .copyWith(color: p.textMuted),
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
                                        if (e.description != null &&
                                            e.description!.isNotEmpty)
                                          Text(
                                            e.description!,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: t.typeScale.micro.copyWith(
                                              color: p.textMuted,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 区间导航条：‹ 标题 ›（月/年视图共用；标题可点 → 跳年/回月，作为手势的可见双通道）。
class _RangeNav extends StatelessWidget {
  const _RangeNav({
    required this.label,
    required this.onPrev,
    required this.onNext,
    this.onLabelTap,
  });

  final String label;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback? onLabelTap;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final title = Text(label, style: t.typeScale.titleSmall);
    return Row(
      children: <Widget>[
        IconButton(
          onPressed: onPrev,
          icon: const Icon(Icons.chevron_left),
          tooltip: '上一项',
        ),
        Expanded(
          child: Center(
            child: onLabelTap == null
                ? title
                : GestureDetector(onTap: onLabelTap, child: title),
          ),
        ),
        IconButton(
          onPressed: onNext,
          icon: const Icon(Icons.chevron_right),
          tooltip: '下一项',
        ),
      ],
    );
  }
}


