library;

import 'package:flutter/material.dart';

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

class _CalendarPageState extends State<CalendarPage> {
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

  /// 月/年视图数据（按当前定位区间查询的逐日密度）。
  CalendarRangeOverviewView? _overview;

  /// 月/年视图数据装配完成后的格子映射（`YYYY-MM-DD` → 密度）。
  Map<String, CalendarDayDensity> _densities = const <String, CalendarDayDensity>{};
  bool _overviewLoading = false;

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

  /// 加载月/年视图数据：month 查当月区间，year 查整年（端口内部分片）。
  Future<void> _loadOverview() async {
    setState(() => _overviewLoading = true);
    final String start;
    final String end;
    String two(int v) => v.toString().padLeft(2, '0');
    if (_mode == _CalMode.month) {
      start = '$_viewYear-${two(_viewMonth)}-01';
      final lastDay = DateTime(_viewYear, _viewMonth + 1, 0).day;
      end = '$_viewYear-${two(_viewMonth)}-$lastDay';
    } else {
      start = '$_viewYear-01-01';
      end = '$_viewYear-12-31';
    }
    final view = await widget.port.rangeOverview(rangeStart: start, rangeEnd: end);
    if (!mounted) return;
    final densities = <String, CalendarDayDensity>{
      for (final d in view.days)
        d.date: CalendarDayDensity(
          eventCount: d.eventCount,
          markerCount: d.markerCount,
        ),
    };
    setState(() {
      _overview = view;
      _densities = densities;
      _overviewLoading = false;
      // 读取成功即权限提示已过时——不清会一直挂着「重新读取即可」误导用户。
      if (view.errorCode == null) _permissionHint = null;
    });
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
    });
    _loadOverview();
  }

  void _goYear() {
    setState(() {
      _mode = _CalMode.year;
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
    });
    _loadOverview();
    _loadEvents(_today);
  }

  /// 横滑判定（年视图用）：右滑 = 上一项，左滑 = 下一项。
  void _swipeShift(DragEndDetails details, VoidCallback prev, VoidCallback next) {
    final v = details.primaryVelocity ?? 0;
    if (v > _kSwipeVelocity) {
      prev();
    } else if (v < -_kSwipeVelocity) {
      next();
    }
  }

  /// 月格点选 → 更新选中高亮，并展开底部当日快照面板。
  void _onDaySelected(String date) {
    setState(() {
      _selectedDate = date;
      _showEvents = true;
    });
    _loadEvents(date);
  }

  /// 年视图点迷你月 → 落月视图并定位该月。
  void _onMonthSelected(int month) {
    setState(() {
      _mode = _CalMode.month;
      _viewMonth = month;
    });
    _loadOverview();
  }

  void _shiftMonth(int delta) {
    setState(() {
      var y = _viewYear;
      var m = _viewMonth + delta;
      if (m < 1) {
        m = 12;
        y -= 1;
      } else if (m > 12) {
        m = 1;
        y += 1;
      }
      _viewYear = y;
      _viewMonth = m;
    });
    _loadOverview();
  }

  void _shiftYear(int delta) {
    setState(() {
      _viewYear += delta;
    });
    _loadOverview();
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
                                // 单一 scale 识别器同时承载「单指横滑切月」与
                                // 「双指捏合收缩 → 年视图」（§6 双通道：手势 + 可见箭头/标题）。
                                child: GestureDetector(
                                  onScaleStart: (d) {
                                    _gestureDx = 0;
                                    _gestureScale = 1.0;
                                    _gesturePointers = d.pointerCount;
                                  },
                                  onScaleUpdate: (d) {
                                    _gestureDx += d.focalPointDelta.dx;
                                    _gestureScale = d.scale;
                                  },
                                  onScaleEnd: (d) {
                                    // 进年视图须明确双指捏合（pointerCount>=2），
                                    // 单指横滑绝不误触——避免「滑一下闪到年视图」的闪屏。
                                    if (_gesturePointers >= 2 &&
                                        _gestureScale < 0.9) {
                                      _goYear();
                                    } else if (_gestureDx.abs() > 60) {
                                      _gestureDx > 0
                                          ? _shiftMonth(-1)
                                          : _shiftMonth(1);
                                    }
                                  },
                                  child: MonthGrid(
                                    year: _viewYear,
                                    month: _viewMonth,
                                    densities: _densities,
                                    selectedDate: _selectedDate,
                                    todayDate: _today,
                                    dayFacts: _monthFacts(),
                                    onDaySelected: _onDaySelected,
                                  ),
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
              child: GestureDetector(
                // 左右横滑切年（与月视图同手势语义）。
                onHorizontalDragEnd: (details) => _swipeShift(
                  details,
                  () => _shiftYear(-1),
                  () => _shiftYear(1),
                ),
                child: () {
                  final sel = _selectedDate.split('-');
                  final selYear = int.parse(sel[0]);
                  final selMonth = int.parse(sel[1]);
                  final selDay = int.parse(sel[2]);
                  return YearGrid(
                    year: _viewYear,
                    densities: _densities,
                    currentMonth: DateTime.now().year == _viewYear
                        ? DateTime.now().month
                        : 0,
                    today: DateTime.now(),
                    selectedMonth: selYear == _viewYear ? selMonth : 0,
                    selectedDay: selYear == _viewYear ? selDay : -1,
                    onMonthSelected: _onMonthSelected,
                  );
                }(),
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

  /// 月视图离线事实映射（农历 / 节假日 / 休班），纯本地、零权限依赖。
  Map<String, CalendarDayFacts> _monthFacts() {
    final list = widget.port.monthFacts(_viewYear, _viewMonth);
    final map = <String, CalendarDayFacts>{};
    String two(int v) => v.toString().padLeft(2, '0');
    for (var d = 0; d < list.length; d++) {
      final date = '$_viewYear-${two(_viewMonth)}-${two(d + 1)}';
      final f = list[d];
      map[date] = CalendarDayFacts(
        lunarLabel: f.lunarLabel,
        holidayName: f.holidayName,
        isHoliday: f.isHoliday,
        isWorkday: f.isWorkday,
      );
    }
    return map;
  }
}

/// 选中日事件面板（月视图底部）：点选某天后向下滑动滚动查看该日从日历获取的事件。
/// 只展示事件标题/时间，不含地点等敏感字段。
class _EventPanel extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final p = t.palette;
    final parts = date.split('-');
    final dt = DateTime(
      int.parse(parts[0]),
      int.parse(parts[1]),
      int.parse(parts[2]),
    );
    final weekday = const <String>['一', '二', '三', '四', '五', '六', '日']
        [dt.weekday - 1];
    return Container(
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
            onTap: onClose,
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
            child: loading
                ? Center(
                    child: Text(
                      '读取中…',
                      style: t.typeScale.micro.copyWith(color: p.textMuted),
                    ),
                  )
                : (events == null || events!.isEmpty)
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
                        itemCount: events!.length,
                        itemBuilder: (context, i) {
                          final e = events![i];
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
                                  child: Text(
                                    e.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: t.typeScale.listItem,
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


