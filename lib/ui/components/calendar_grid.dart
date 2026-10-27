/// 日历网格组件（MonthGrid / YearGrid）——月视图与年视图的**只读**导航网格。
///
/// 定位（ui-console.md §1 日历页红线）：不做日程管理——网格只呈现密度与
/// 选择态，无输入、无写路径；事件详情归单日快照视图。
///
/// 与 BlockCanvas 的关系：复用区块体系的**设计原则**（Page 级受控单源 /
/// 零魔法值 token / 状态双通道），不复用其 widget——四件套（焦点链 / IME
/// Guard / 粘贴裂变 / 弹性槽位）均服务于单行文本编辑，与只读二维网格无关
/// （见 docs/project/calculator-blocks.md §5.1 抽取边界）。
///
/// 视觉纪律：全部取 `AppTokens`（色彩 / 排印 / 几何 / 动效），禁裸值；
/// 选中 = 实底 + 「选中」形状，今日 = hairline 圈——双通道不单靠颜色。
library;

import 'package:flutter/material.dart';

import 'app_components.dart';

/// 逐日密度（与 `ui_ports/calendar_port.dart` 的 `DayDensityView` 对齐的
/// 组件侧最小面：组件不 import ui_ports，防组件层反向依赖页面适配层）。
class CalendarDayDensity {
  const CalendarDayDensity({this.eventCount = 0, this.markerCount = 0});

  final int eventCount;

  final int markerCount;

  bool get isEmpty => eventCount == 0 && markerCount == 0;
}

/// 日格离线事实（组件侧最小面：与 `lib/ui_ports/calendar_port.dart` 的 [DayFacts]
/// 对齐的形状，但本组件层不 import ui_ports，避免反向依赖页面适配层）。
class CalendarDayFacts {
  const CalendarDayFacts({
    this.lunarLabel = '',
    this.holidayName,
    this.isHoliday = false,
    this.isWorkday = false,
    this.description,
  });

  /// 农历角标（'八月' / '十五' / 节气名）。
  final String lunarLabel;

  /// 法定节假日 / 调休补班名称；普通日为 null。
  final String? holidayName;

  /// 法定假（含被放假吞掉的周末）。
  final bool isHoliday;

  /// 调休补班（原本周末但需上班）。
  final bool isWorkday;

  /// 订阅节假日 ICS 的补充说明（DESCRIPTION）；无则为 null。
  final String? description;
}

/// 星期表头（周一起始，中文单字）。
const List<String> _kWeekdayLabels = <String>[
  '一',
  '二',
  '三',
  '四',
  '五',
  '六',
  '日',
];

/// 固定星期表头：周一起始 7 列等宽 + 底部 hairline 分隔线。
/// 月视图把它钉在滑动条上方——数据页无限滚动时表头不动（周列恒对齐）；
/// MonthGrid 内建表头与之同构（showHeader=false 时由页面挂本件）。
class WeekdayHeader extends StatelessWidget {
  const WeekdayHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    return Container(
      padding: EdgeInsets.only(bottom: t.metrics.space4),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: t.palette.hairline,
            width: t.metrics.borderWidthThin,
          ),
        ),
      ),
      child: Row(
        children: <Widget>[
          for (final label in _kWeekdayLabels)
            Expanded(
              child: Center(
                child: Text(
                  label,
                  style: t.typeScale.micro.copyWith(color: t.palette.textMuted),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 该月 1 号是周几（周一=0 … 周日=6）。
int _firstWeekdayOffset(int year, int month) {
  final wd = DateTime(year, month, 1).weekday; // Monday=1..Sunday=7
  return wd - 1;
}

/// 该月天数。
int _daysInMonth(int year, int month) {
  final next = month == 12 ? DateTime(year + 1, 1, 1) : DateTime(year, month + 1, 1);
  return next.subtract(const Duration(days: 1)).day;
}

String _two(int v) => v.toString().padLeft(2, '0');

/// 日格读屏标签：日期 + 今日/选中 + 休班/节假日 + 农历 + 日程数
/// （与视觉双通道同信息面，读屏不缺位）。
String _semanticsLabel(CalendarDayFacts? f, CalendarDayDensity density) {
  final b = StringBuffer();
  if (f != null) {
    if (f.isWorkday) {
      b.write('调休补班');
      if (f.holidayName?.isNotEmpty == true) b.write('（${f.holidayName}）');
    } else if (f.isHoliday) {
      b.write('法定节假日');
      if (f.holidayName?.isNotEmpty == true) b.write('（${f.holidayName}）');
    } else if (f.lunarLabel.isNotEmpty) {
      b.write('农历${f.lunarLabel}');
    }
  }
  if (density.eventCount > 0) {
    if (b.isNotEmpty) b.write('，');
    b.write('有 ${density.eventCount} 个日程');
  }
  if (density.markerCount > 0) {
    if (b.isNotEmpty) b.write('，');
    b.write('有 ${density.markerCount} 个标记');
  }
  return b.toString();
}

String _dateKey(int year, int month, int day) =>
    '$year-${_two(month)}-${_two(day)}';

/// 迷你月读屏标签：年月 + 当前月态 + 有日程天数（年视图数字阵无逐格语义，
/// 集中在月级交代，口径对齐月格 [_semanticsLabel] 的信息面）。
String _miniMonthSemanticsLabel(int year, int month, bool isCurrent) {
  final b = StringBuffer('$year 年 $month 月');
  if (isCurrent) b.write('，当前月');
  return b.toString();
}

/// 月视图网格：7 列日格 + 星期表头，密度点 + 选中/今日态（只读）。
class MonthGrid extends StatelessWidget {
  const MonthGrid({
    super.key,
    required this.year,
    required this.month,
    required this.densities,
    required this.selectedDate,
    required this.todayDate,
    this.dayFacts,
    this.onDaySelected,
    this.showHeader = true,
  });

  final int year;
  final int month;

  /// `YYYY-MM-DD` → 密度；缺失的日期视为空。
  final Map<String, CalendarDayDensity> densities;

  /// 当前选中日（`YYYY-MM-DD`；空串 = 无选中）。
  final String selectedDate;

  /// 今日（`YYYY-MM-DD`，空串 = 无）。
  final String todayDate;

  /// 日格离线事实（`YYYY-MM-DD` → 事实；缺失视为普通日）。
  final Map<String, CalendarDayFacts>? dayFacts;

  /// 点选某日（null = 只读不可点）。
  final ValueChanged<String>? onDaySelected;

  /// 是否内建星期表头：页面级固定表头模式下关掉（表头钉在滑动条上方，
  /// 数据页滚动时不动），网格只留日格区。
  final bool showHeader;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final header = Container(
      padding: EdgeInsets.only(bottom: t.metrics.space4),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: t.palette.hairline,
            width: t.metrics.borderWidthThin,
          ),
        ),
      ),
      child: Row(
        children: <Widget>[
          for (final label in _kWeekdayLabels)
            Expanded(
              child: Center(
                child: Text(
                  label,
                  style: t.typeScale.micro.copyWith(color: t.palette.textMuted),
                ),
              ),
            ),
        ],
      ),
    );
    final offset = _firstWeekdayOffset(year, month);
    final total = offset + _daysInMonth(year, month);
    final fullRows = (total / 7).ceil();
    // 1 号标注归属月；一月连带年份——跨年同屏（12 月 + 1 月）时日格自身
    // 可辨归属年。
    final monthLabel = month == 1 ? '$year年1月' : '$month月';
    final weekRows = <List<Widget>>[];
    for (var r = 0; r < fullRows; r++) {
      final cells = <Widget>[];
      for (var c = 0; c < 7; c++) {
        final index = r * 7 + c;
        final day = index - offset + 1;
        if (day < 1 || day > _daysInMonth(year, month)) {
          cells.add(const Expanded(child: SizedBox()));
          continue;
        }
        final key = _dateKey(year, month, day);
        cells.add(
          Expanded(
            child: _DayCell(
              date: key,
              day: day,
              monthLabel: monthLabel,
              density: densities[key] ?? const CalendarDayDensity(),
              isSelected: key == selectedDate,
              isToday: key == todayDate,
              facts: dayFacts?[key],
              onTap:
                  onDaySelected == null ? null : () => onDaySelected!(key),
            ),
          ),
        );
      }
      weekRows.add(cells);
    }
    return Column(
      children: <Widget>[
        // showHeader=false：表头由页面级固定表头承担（钉在滑动条上方），
        // 网格只渲染日格区，避免表头随数据页一起滚动。
        if (showHeader) header,
        if (showHeader) SizedBox(height: t.metrics.space4),
        // 周行撑满：充分利用月视图屏幕高度，消除底部空白。
        Expanded(
          child: Column(
            children: <Widget>[
              for (var r = 0; r < fullRows; r++)
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      bottom: r < fullRows - 1 ? t.metrics.space4 : 0,
                    ),
                    child: Row(children: weekRows[r]),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 单日格：日号（等宽遥测轨）+ 最多 3 枚密度点；选中实底、今日细圈。
class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.date,
    required this.day,
    required this.monthLabel,
    required this.density,
    required this.isSelected,
    required this.isToday,
    this.facts,
    this.onTap,
  });

  final String date;
  final int day;

  /// 1 号标注文案（「10月」/「2027年1月」）：自由滚动下多月在屏，日格 1
  /// 需标清归属月/年；非 1 号日格不显示，但等高占位仍生效。
  final String monthLabel;
  final CalendarDayDensity density;
  final bool isSelected;
  final bool isToday;

  /// 离线事实（农历 / 节假日 / 休班）；null = 按普通日渲染。
  final CalendarDayFacts? facts;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final p = t.palette;
    final f = facts;

    // 特殊事件配色法则（美学 + HCI 双评估，详见改动说明）：
    //   假期 → l2Accent（暖橙）：喜庆/放假的正向强调，暖色在该语境读「可休息」；
    //   补班 → l1Info（冷青）：与暖橙形成高色相对比，读「非自由、需上班」反向提醒。
    // 二者均 ≥4.5:1（§6 正文红线），且与事件点（l1Info 通用事件标识）分属不同通道——
    // 颜色非唯一判据，另有「休/班」文字角标双通道兜底（§6）。
    final hasEvents = !density.isEmpty;
    final dayColor = isSelected
        ? p.onStatus
        : f?.isHoliday == true
            ? p.l2Accent
            : f?.isWorkday == true
                ? p.l1Info
                : hasEvents
                    ? p.onSurface
                    : p.textMuted;

    // 副行角标（通道②：仅来自 [facts] 的特殊事件语义，与通道①事件点解耦）：
    // 补班（名称 > 描述 > 班标）> 法定假（名称 > 描述）> 农历/节气。
    // 完整 DESCRIPTION 交给点选后的底部面板，日格只放简短角标。
    final String? subText;
    final Color subColor;
    if (f == null) {
      subText = null;
      subColor = p.textMuted;
    } else if (f.isWorkday) {
      subText = f.holidayName?.isNotEmpty == true
          ? f.holidayName
          : (f.description ?? '班');
      subColor = p.l1Info;
    } else if (f.isHoliday) {
      subText = f.holidayName?.isNotEmpty == true
          ? f.holidayName
          : f.description;
      subColor = p.l2Accent;
    } else {
      subText = f.lunarLabel;
      subColor = p.onSurfaceVariant;
    }

    // 高度撑满后日格变高，圆形按较小边取正圆，避免被拉伸成椭圆；
    // 圆形仅包日号，农历/密度点置于圆下方，整体居中不变形。
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        final dim = (w < h ? w : h) * 0.88;
        final radius = dim / 2;
        return Padding(
          padding: EdgeInsets.all(t.metrics.grid),
          child: Material(
            color: Colors.transparent,
            // 无障碍语义：日期 + 今日/选中 + 休班/农历 + 日程数，让读屏用户
            // 拿到视觉双通道（色彩/角标/密度点）之外的信息。
            child: Semantics(
              label: _semanticsLabel(f, density),
              selected: isSelected,
              button: true,
              child: InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(radius),
                // FittedBox scaleDown：面板全屏等极端约束下（月条带被挤到
                // 极矮），日格内容最小高度超出格约束时**整体缩放**而非
                // RenderFlex overflow（复现：FAB 全屏后每格溢出 11px 满屏
                // 黄黑条纹）；空间充足时按自然尺寸渲染，正常布局零变化。
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                    // 1 号标注所属月份：自由滚动下月与月同屏是常态，日格 1 标清
                    // 归属月（「几月份」），避免上/下月日号连续时看不出分界。
                    // 关键：每个日格都预留「等高标注位」——非 1 号留空占位，否则
                    // 仅 day1 多一行会把其圆点下压，导致「1」比「2」低、不规整。
                    SizedBox(
                      height: MediaQuery.textScalerOf(context)
                          .scale((t.typeScale.micro.fontSize ?? 10.0) * 1.3),
                      child: day == 1
                          ? Center(
                              child: Text(
                                monthLabel,
                                style: t.typeScale.micro
                                    .copyWith(color: p.textMuted),
                              ),
                            )
                          : null,
                    ),
                    Container(
                      width: dim,
                      height: dim,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: isSelected ? p.l1Info : Colors.transparent,
                        shape: BoxShape.circle,
                        border: isToday && !isSelected
                            ? Border.all(
                                color: p.l1Info,
                                width: t.metrics.borderWidth,
                              )
                            : null,
                      ),
                      child: Text(
                        _two(day),
                        style: t.typeScale.dayNumber.copyWith(color: dayColor),
                      ),
                    ),
                    if (subText != null && subText.isNotEmpty) ...<Widget>[
                      SizedBox(height: t.metrics.grid),
                      Text(
                        subText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.typeScale.compact.copyWith(color: subColor),
                      ),
                    ],
                    // 通道①：有事件即点密度点（与个人/系统/节假日事件无关，
                    // 仅表「这天有安排」），1~3 枚按日程+标记总数分级——数量
                    // 可粗辨（3 枚 = 3 及以上封顶）；与通道②的休/班角标独立共存。
                    if (hasEvents) ...<Widget>[
                      SizedBox(height: t.metrics.grid),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          for (
                            var i = 0;
                            i <
                                (density.eventCount + density.markerCount)
                                    .clamp(1, 3);
                            i++
                          )
                            Padding(
                              padding: EdgeInsets.only(
                                right: i < 2 ? t.metrics.grid : 0,
                              ),
                              child: Container(
                                width: t.metrics.grid,
                                height: t.metrics.grid,
                                decoration: BoxDecoration(
                                  color: isSelected ? p.onStatus : p.l1Info,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
                ), // FittedBox
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 年视图网格：当年 12 个迷你月（4 行 × 3 列），点迷你月落月视图。
/// 密度点口径与月视图一致（整年区间一次拉取）；迷你月内不显示事件/标记点，
/// 让年视图更满（今日/选中高亮照常）。
class YearGrid extends StatelessWidget {
  const YearGrid({
    super.key,
    required this.year,
    required this.densities,
    required this.currentMonth,
    this.onMonthSelected,
    required this.today,
    required this.selectedMonth,
    required this.selectedDay,
    required this.selectedYear,
  });

  final int year;

  /// `YYYY-MM-DD` → 密度（整年区间）。
  final Map<String, CalendarDayDensity> densities;

  /// 当前月（1~12，高亮标记；0 = 非今年不高亮）。
  final int currentMonth;

  /// 点选某月（null = 只读不可点）。
  final ValueChanged<int>? onMonthSelected;

  /// 今日（高亮标记）。
  final DateTime today;

  /// 选中的月（1~12，与 [selectedDay] 配合高亮选中日）。
  final int selectedMonth;

  /// 选中的日（高亮标记；<=0 表示无选中）。
  final int selectedDay;

  /// 选中的年份（高亮限定在选中年份内；0 = 无选中）。
  final int selectedYear;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final monthRows = <List<Widget>>[];
    for (var r = 0; r < 4; r++) {
      final cells = <Widget>[];
      for (var c = 0; c < 3; c++) {
        final month = r * 3 + c + 1;
        cells.add(
          Expanded(
            child: _MiniMonth(
              year: year,
              month: month,
              densities: densities,
              isCurrent: month == currentMonth,
              today: today,
              selectedMonth: selectedMonth,
              selectedDay: selectedDay,
              selectedYear: selectedYear,
              onTap: onMonthSelected == null
                  ? null
                  : () => onMonthSelected!(month),
            ),
          ),
        );
      }
      monthRows.add(cells);
    }
    // 4 行月格撑满：充分利用年视图屏幕高度，消除底部空白。
    return Column(
      children: <Widget>[
        for (var r = 0; r < 4; r++)
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(
                top: r > 0 ? t.metrics.space8 : 0,
              ),
              child: Row(children: monthRows[r]),
            ),
          ),
      ],
    );
  }
}

/// 迷你月格：月名 + 纯数字日阵（今日/选中高亮；不显示事件/标记点，让年视图更满）。
class _MiniMonth extends StatelessWidget {
  const _MiniMonth({
    required this.year,
    required this.month,
    required this.densities,
    required this.isCurrent,
    required this.today,
    required this.selectedMonth,
    required this.selectedDay,
    required this.selectedYear,
    this.onTap,
  });

  final int year;
  final int month;
  final Map<String, CalendarDayDensity> densities;
  final bool isCurrent;
  final DateTime today;
  final int selectedMonth;
  final int selectedDay;
  final int selectedYear;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final p = t.palette;
    final first = DateTime(year, month, 1);
    final offset = (first.weekday - DateTime.monday) % 7;
    final days = _daysInMonth(year, month);
    final weekCount = ((offset + days) / 7).ceil();
    final weekRows = <List<Widget>>[];
    for (var w = 0; w < weekCount; w++) {
      final cells = <Widget>[];
      for (var c = 0; c < 7; c++) {
        final day = w * 7 + c - offset + 1;
        if (day < 1 || day > days) {
          cells.add(const Expanded(child: SizedBox.shrink()));
          continue;
        }
        final d = DateTime(year, month, day);
        final isToday =
            d.year == today.year && d.month == today.month && d.day == today.day;
        final isSel = year == selectedYear &&
            month == selectedMonth &&
            day == selectedDay;
        final isWeekend = d.weekday >= 6;
        cells.add(
          Expanded(
            child: Center(
              child: Text(
                '$day',
                maxLines: 1,
                overflow: TextOverflow.visible,
                style: t.typeScale.micro.copyWith(
                  color: isSel || isToday
                      ? p.l1Info
                      : isWeekend
                          ? p.textMuted
                          : p.onSurface,
                  fontSize: 9,
                  fontWeight:
                      isSel || isToday ? FontWeight.w700 : FontWeight.normal,
                ),
              ),
            ),
          ),
        );
      }
      weekRows.add(cells);
    }
    return Padding(
      padding: EdgeInsets.all(t.metrics.grid),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(t.metrics.radiusSm),
          // 读屏补位：月格视觉是纯数字阵，读屏用户拿不到「这是哪个月 /
          // 是不是当前月 / 有多少天有日程」——标签集中交代（口径同月格
          // _semanticsLabel 的信息面）。
          child: Semantics(
            label: _miniMonthSemanticsLabel(year, month, isCurrent),
            button: onTap != null,
            child: Container(
              padding: EdgeInsets.all(t.metrics.space4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    // 1 月标注所属年：年页只有页头标年，1 月迷你月自带年份，
                    // 快甩跨年时页内容自身可辨归属。
                    month == 1 ? '$year年1月' : '${_two(month)}月',
                    style: t.typeScale.micro.copyWith(
                      color: isCurrent ? p.l1Info : p.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: t.metrics.space4),
                  // 周行撑满迷你月高度，数字居中不变形。
                  Expanded(
                    child: Column(
                      children: <Widget>[
                        for (var w = 0; w < weekCount; w++)
                          Expanded(
                            child: Padding(
                              padding: EdgeInsets.only(
                                bottom: w < weekCount - 1 ? t.metrics.grid : 0,
                              ),
                              child: Row(children: weekRows[w]),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 年份块网格（L3 缩放层）：12 个年份数字的 4×3 阵，点某年缩进该年视图。
///
/// 与 [YearGrid]（L2）同构（4×3 网格），粒度更粗（年份数字 vs 迷你月）——三级
/// 缩放里最粗的一层，服务于「跳到远处年份」：月→年→年份块逐级放大，甩 40 个月
/// 变成甩出 + 点年份。年份数字走日历域 `dayNumber` 档（与月格日号同档，不同粒度）。
class YearNumberGrid extends StatelessWidget {
  const YearNumberGrid({
    super.key,
    required this.startYear,
    required this.currentYear,
    required this.selectedYear,
    this.onYearSelected,
  });

  /// 本块首年（4×3 = 12 年：startYear .. startYear+11）。
  final int startYear;

  /// 当前年（高亮；落在本块外则无高亮）。
  final int currentYear;

  /// 选中年份（高亮；0 = 无选中）。
  final int selectedYear;

  /// 点选某年（null = 只读不可点）。
  final ValueChanged<int>? onYearSelected;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final p = t.palette;
    final cells = <Widget>[];
    for (var i = 0; i < 12; i++) {
      final year = startYear + i;
      final isCurrent = year == currentYear;
      final isSel = year == selectedYear;
      cells.add(
        Expanded(
          child: Semantics(
            label: '$year 年',
            selected: isSel,
            button: true,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onYearSelected == null
                    ? null
                    : () => onYearSelected!(year),
                borderRadius: BorderRadius.circular(t.metrics.radiusSm),
                child: Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    // 选中实底 + 今日细圈：双通道不单靠颜色（§6）。
                    color: isSel ? p.l1Info : Colors.transparent,
                    borderRadius: BorderRadius.circular(t.metrics.radiusSm),
                    border: isCurrent && !isSel
                        ? Border.all(
                            color: p.l1Info,
                            width: t.metrics.borderWidth,
                          )
                        : null,
                  ),
                  child: Text(
                    '$year',
                    style: t.typeScale.dayNumber.copyWith(
                      color: isSel
                          ? p.onStatus
                          : isCurrent
                              ? p.l1Info
                              : p.onSurface,
                      fontWeight:
                          isSel || isCurrent ? FontWeight.w700 : FontWeight.normal,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }
    // 4 行 × 3 列：与 YearGrid 同构，数字居中、当前/选中高亮。
    final rows = <List<Widget>>[
      for (var r = 0; r < 4; r++) cells.sublist(r * 3, r * 3 + 3),
    ];
    return Column(
      children: <Widget>[
        for (var r = 0; r < 4; r++)
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(top: r > 0 ? t.metrics.space8 : 0),
              child: Row(children: rows[r]),
            ),
          ),
      ],
    );
  }
}

// 组件层自检提示：EmptyState / tokensOf 复用 app_components 的既有语义，
// 若后续需要「区间告警条」，用 ErrorLine 承载（错误圈定口径与子页面一致）。
