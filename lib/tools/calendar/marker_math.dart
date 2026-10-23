// 重要事件标记周年推演（P2-⑥ 公历 + P2-③ 农历）：对齐 + 区间展开 + 月网格。
//
// 纯 Dart（农历经 lib/tools/calendar/lunar_math.dart 包装 package:lunar，
// 1900–2100 确定性换算）。**禁 `DateTime.now()`**（F1）：
// `daysRemaining` 的基准日由调用方（工具层 rangeStart）显式注入。
library;

import '../../mcp/calendar_provider.dart';
import 'date_math.dart';
import 'lunar_math.dart';

/// 单次日展开上限（防一年 365 个「每日纪念日」把出参撑爆）。
const int markerExpansionCap = 64;

class MarkerMath {
  const MarkerMath._();

  /// 公历周年对齐：把标记的月日落到 [year] 年。
  ///
  /// **02-29 平年统一对齐 02-28 并标 `approximate`**（calendar.md 明示；
  /// 不静默按 3-01 算，那会把纪念日推到 3 月）。
  static ({DateTime date, bool approximate}) resolveInYear(
    CalendarMarker marker,
    int year,
  ) {
    final src = DateMath.parseDate(marker.originalDate)!;
    var month = src.month;
    var day = src.day;
    var approximate = false;
    if (month == 2 && day == 29) {
      final last = DateTime.utc(year, 3, 0).day;
      if (last < 29) {
        day = last;
        approximate = true;
      }
    }
    return (date: DateTime.utc(year, month, day), approximate: approximate);
  }

  /// 区间展开：返回 `[from, to]`（含）内的周年实例列表。
  ///
  /// - 公历标记（`isLunar: false`）：见 [resolveInYear]（02-29 对齐 02-28）。
  /// - 农历标记（`isLunar: true`）：经农历引擎对齐到对应公历日再展开，
  ///   闰月按标记的 [CalendarMarker.leapPolicy] 三策略处理（见 [_expandLunar]）。
  /// - 非年度标记（`isAnnual: false`）只在起始年当天出现一次。
  /// - `daysRemaining` 以 [from] 为基准日（工具层注入 rangeStart，非系统今天）。
  static List<Map<String, Object?>> expand(
    List<CalendarMarker> markers,
    DateTime from,
    DateTime to,
  ) {
    final out = <Map<String, Object?>>[];
    for (final m in markers) {
      if (m.isLunar) {
        final lp = parseLunarDate(m.originalDate);
        if (lp == null) {
          // 解析失败的农历标记 fail-visible：不静默按公历算（会把日子错算约一个月），
          // 也不静默丢弃（那会「假装没有这个标记」）。
          out.add(<String, Object?>{
            'id': m.id,
            'title': m.title,
            'originalDate': m.originalDate,
            'category': m.category,
            'lunarParseError': true,
            'note': '农历日期无法解析（支持 1900–2100，格式 YYYY-MM-DD / YYYY-闰M-DD）',
          });
          continue;
        }
        _expandLunar(m, lp, from, to, out);
        continue;
      }
      if (!m.isAnnual) {
        final d = DateMath.parseDate(m.originalDate)!;
        if (!d.isBefore(from) && !d.isAfter(to)) {
          out.add(_instance(m, d, d.year, false, from));
        }
        continue;
      }
      // 年度标记：从「能落在区间内的最早年份」到 to.year。
      final firstYear = m.baseYear;
      final lastYear = to.year;
      var emitted = 0;
      for (var y = firstYear; y <= lastYear; y++) {
        if (emitted >= markerExpansionCap) break;
        final r = resolveInYear(m, y);
        if (r.date.isBefore(from)) continue;
        if (r.date.isAfter(to)) break; // 后续年份只会更晚
        emitted++;
        // 生日场景：ordinalCount = targetYear − baseYear + 1（第 N 个生日）
        final ordinal = m.category == 'birthday' ? y - m.baseYear + 1 : null;
        out.add(_instance(m, r.date, y, r.approximate, from,
            ordinalCount: ordinal));
      }
    }
    out.sort((a, b) {
      final da = a['date'];
      final db = b['date'];
      if (da is! String || db is! String) {
        // 农历解析失败条目无 date：排到尾部，不打断正常实例的日期序。
        return da is String ? -1 : 1;
      }
      final c = da.compareTo(db);
      return c != 0 ? c : (a['id']! as String).compareTo(b['id']! as String);
    });
    return List.unmodifiable(out);
  }

  /// 农历日期串解析：`YYYY-MM-DD`（平月）或 `YYYY-闰M-DD`（闰月）。
  ///
  /// 注：marker_add 入参面当前只放行纯数字格式（无闰月位），「闰」前缀为
  /// 数据模型向前兼容位——strictLeap / followRegular 的闰月语义以直接构造
  /// [CalendarMarker] 的单测钉死。
  static ({int y, int m, int d, bool leap})? parseLunarDate(String raw) {
    final m = RegExp(r'^(\d{4})-(闰?)(\d{1,2})-(\d{1,2})$').firstMatch(raw.trim());
    if (m == null) return null;
    return (
      y: int.parse(m.group(1)!),
      m: int.parse(m.group(3)!),
      d: int.parse(m.group(4)!),
      leap: m.group(2) == '闰',
    );
  }

  /// 农历标记周年展开（calendar.md「农历与纪念日引擎」leapPolicy 三策略）：
  ///
  /// - `ignoreLeap`（默认）：一律按**平月**对齐，无论当年有无同号闰月；
  /// - `strictLeap`：标记本身创建于闰月时，仅在有该闰月的年份触发（平年不触发，
  ///   **不自动落到平月**）；标记为平月时与平月标记一致；
  /// - `followRegular`：闰月标记在无该闰月的年份自动对齐平月并标
  ///   `approximate: true`（显式提示而非静默错算）。
  ///
  /// 不用「公历年 break」提前终止：农历年实例对应的公历日期随年份**不严格单调**
  /// （闰月可回跳近一个月），逐农历年换算后按区间过滤。
  static void _expandLunar(
    CalendarMarker m,
    ({int y, int m, int d, bool leap}) src,
    DateTime from,
    DateTime to,
    List<Map<String, Object?>> out,
  ) {
    var emitted = 0;
    final lastLunarYear = to.year + 1; // 农历年尾实例可能落在公历 to+1 年初
    for (var ly = src.y; ly <= lastLunarYear && emitted < markerExpansionCap; ly++) {
      // 闰月策略分派：strictLeap/followRegular 只对「创建于闰月」的标记生效；
      // 平月源与 ignoreLeap 一律平月实例（calendar.md L181-183 语义）。
      final bool isLeapInst;
      var approximate = false;
      switch (m.leapPolicy) {
        case 'strictLeap' when src.leap:
          if (LunarMath.leapMonthOf(ly) != src.m) continue; // 平年不触发
          isLeapInst = true;
        case 'followRegular' when src.leap:
          final hasLeap = LunarMath.leapMonthOf(ly) == src.m;
          isLeapInst = hasLeap;
          approximate = !hasLeap; // 平年回落平月，显式标 approximate
        default:
          isLeapInst = false; // ignoreLeap 与一切平月源：取平月
      }
      DateTime solar;
      try {
        solar = LunarMath.lunarToSolar(ly, src.m, src.d, isLeapMonth: isLeapInst);
      } on LunarMathException {
        // 该农历年此日不存在：跳过该年，不 clamp 伪造日期
        //（与 ICS「无 31 日不触发」同一纪律）。
        continue;
      }
      if (solar.isBefore(from)) continue;
      if (solar.isAfter(to)) continue;
      emitted++;
      final anniversary = ly - m.baseYear; // 按农历年计满周年
      final ordinal =
          m.category == 'birthday' ? ly - m.baseYear + 1 : null;
      out.add(<String, Object?>{
        'id': m.id,
        'title': m.title,
        'date': DateMath.fmt(solar),
        'category': m.category,
        'isLunar': true,
        'anniversaryCount': anniversary,
        'ordinalCount': ?ordinal,
        'daysRemaining': solar.difference(from).inDays,
        'approximate': ?(approximate ? true : null),
      });
    }
  }

  static Map<String, Object?> _instance(
    CalendarMarker m,
    DateTime date,
    int year,
    bool? approximate,
    DateTime baseDate, {
    int? ordinalCount,
  }) {
    final anniversary = year - m.baseYear;
    // approximate 仅在「平年 02-29 对齐」为 true 时出参；false 时整字段省略
    //（null-aware 值对 false 仍会出，故先归 null）。
    final isApprox = approximate == true ? true : null;
    return <String, Object?>{
      'id': m.id,
      'title': m.title,
      'date': DateMath.fmt(date),
      'category': m.category,
      'anniversaryCount': anniversary,
      'ordinalCount': ?ordinalCount, // 生日场景：第 N 个生日
      'daysRemaining': date.difference(baseDate).inDays,
      'approximate': ?isApprox,
    };
  }

  /// 整月网格（恒定 42 格）。
  ///
  /// - 每格 `date` / `lunar`（农历角标：初一显月名 '八月'，其余显日 '十五'）/
  ///   `solarTerm`（仅节气日出，如 '霜降'）/ `isWorkday` / `badge`
  ///   （holiday | adjusted_workday | solar_term | none）/ `markerCount` /
  ///   `isCurrentMonth`（P2-③：lunar 字段从「不出」转真实出参）。
  /// - badge 优先级：**调休补班 > 法定节假日 > 节气**（节假日对放假判断更关键，
  ///   节气信息由 `solarTerm` 字段无损单列，不因 badge 单值丢失）。
  /// - [firstDayOfWeek] 取 1（周一）~7（周日），决定矩阵列起始。
  static List<Map<String, Object?>> monthGrid(
    int year,
    int month,
    int firstDayOfWeek,
    HolidayProvider holidays,
    List<Map<String, Object?>> expanded,
  ) {
    final first = DateTime.utc(year, month, 1);
    // ISO 周几→以 firstDayOfWeek 为列 0 的偏移。
    final offset = (first.weekday - firstDayOfWeek + 7) % 7;
    final start = first.subtract(Duration(days: offset));

    final markerCounts = <String, int>{};
    for (final e in expanded) {
      final d = e['date'];
      if (d is String) markerCounts[d] = (markerCounts[d] ?? 0) + 1;
    }

    final cells = <Map<String, Object?>>[];
    for (var i = 0; i < 42; i++) {
      final d = start.add(Duration(days: i));
      final key = DateMath.fmt(d);
      final badgeSet = <String>{};
      for (final e in holidays.between(key, key)) {
        if (e.date != key) continue;
        badgeSet.add(e.type == 'workday' ? 'adjusted_workday' : 'holiday');
      }
      final lunar = LunarMath.describe(d);
      final term = lunar.solarTerm.isEmpty ? null : lunar.solarTerm;
      cells.add(<String, Object?>{
        'date': key,
        'lunar': lunar.label,
        'solarTerm': ?term,
        'isWorkday': DateMath.isWorkday(d, holidays),
        'badge': badgeSet.contains('adjusted_workday')
            ? 'adjusted_workday'
            : badgeSet.contains('holiday')
                ? 'holiday'
                : (term != null ? 'solar_term' : 'none'),
        'markerCount': markerCounts[key] ?? 0,
        'isCurrentMonth': d.month == month && d.year == year,
      });
    }
    return List.unmodifiable(cells);
  }

  /// 默认节假日来源（工具层装配用）：空表，不编造官方放假 / 补班判断。
  /// 实际由装配注入 ICS 驱动的 [IcsHolidayProvider]；内置 2026 表仍可作可注入选项。
  static const HolidayProvider defaultHolidays = EmptyHolidayProvider();
}
