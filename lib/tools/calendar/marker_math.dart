// 重要事件标记周年推演（P2-⑥）：公历对齐 + 区间展开 + 月网格。
//
// 纯 Dart、零依赖（农历部分待 P2-③ 纯 Dart 农历库批准后补，届时本文件只加
// `isLunar` 分支，公历路径不变）。**禁 `DateTime.now()`**（F1）：
// `daysRemaining` 的基准日由调用方（工具层 rangeStart）显式注入。
library;

import '../../mcp/calendar_provider.dart';
import 'date_math.dart';
import 'holiday_table.dart';

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
  /// - `isLunar: true` 的标记**暂不展开**（农历库待 P2-③），原样回传并标
  ///   `lunarPending: true`——不静默按公历算，那会把「农历八月十五」算错一个月左右。
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
        out.add(<String, Object?>{
          'id': m.id,
          'title': m.title,
          'originalDate': m.originalDate,
          'category': m.category,
          'lunarPending': true,
          'note': '农历周年对齐待农历引擎（P2-③）落地，暂不展开',
        });
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
      final da = DateMath.parseDate(a['date']! as String)!;
      final db = DateMath.parseDate(b['date']! as String)!;
      final c = da.compareTo(db);
      return c != 0 ? c : (a['id']! as String).compareTo(b['id']! as String);
    });
    return List.unmodifiable(out);
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
  /// - 每格 `date` / `isWorkday` / `badge`（holiday | adjusted_workday | none）/
  ///   `markerCount` / `isCurrentMonth`；`lunar` 字段**不出**（农历待 P2-③，
  ///   出 null 会让 UI 误判「无农历」而非「未实现」）。
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
      cells.add(<String, Object?>{
        'date': key,
        'isWorkday': DateMath.isWorkday(d, holidays),
        'badge': badgeSet.isEmpty
            ? 'none'
            : (badgeSet.contains('adjusted_workday')
                ? 'adjusted_workday'
                : 'holiday'),
        'markerCount': markerCounts[key] ?? 0,
        'isCurrentMonth': d.month == month && d.year == year,
      });
    }
    return List.unmodifiable(cells);
  }

  /// 默认内置表引用（工具层装配用）。
  static const HolidayProvider defaultHolidays = cnHolidayBundled;
}
