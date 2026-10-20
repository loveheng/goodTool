// 时间推演纯函数内核（calendar.md F 拍板）。
//
// **F1 纯函数纪律**：本文件**禁止 `DateTime.now()`**——所有基准日期由调用方
// 显式注入，保证同输入恒同输出（确定性单测纪律）。
// 内核纯 Dart、零 Flutter / dart:io 依赖（arch-guard R4 延伸）。
library;

import '../../mcp/calendar_provider.dart';

/// 日期解析与推演工具集。
class DateMath {
  const DateMath._();

  static final RegExp _dateRe = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');

  /// 严格解析 `YYYY-MM-DD`；格式非法或**日期溢出**（如 `2026-02-31`）返回 null
  /// ——`DateTime` 会把溢出日滚动到下月，必须显式回判（否则静默算错一天）。
  static DateTime? parseDate(Object? raw) {
    if (raw is! String) return null;
    final m = _dateRe.firstMatch(raw.trim());
    if (m == null) return null;
    final y = int.parse(m.group(1)!);
    final mo = int.parse(m.group(2)!);
    final d = int.parse(m.group(3)!);
    final dt = DateTime.utc(y, mo, d);
    if (dt.year != y || dt.month != mo || dt.day != d) return null;
    return dt;
  }

  /// 格式化为 `YYYY-MM-DD`。
  static String fmt(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  /// 日历天数差（`end − start`，两端按 UTC 日界取整）。
  static int totalDays(DateTime start, DateTime end) =>
      _day(end).difference(_day(start)).inDays;

  static DateTime _day(DateTime d) => DateTime.utc(d.year, d.month, d.day);

  /// **F4 成分跨度**：严格按日期成分（年/月/日）计算，不用毫秒相除——
  /// 大小月与闰年由 [addMonths] 的月末 clamp 承担，避免「31 天 = 1 个月」这类近似误差。
  ///
  /// 做法：从 start 逐**整月**推进（先年、后月）直到再进一月就超过 end，
  /// 剩余部分即天数。比「月份相减 + 借位」稳——借位法在 `1/31 → 3/1` 上会算错。
  static Map<String, int> span(DateTime start, DateTime end) {
    final forward = !end.isBefore(start);
    final from = forward ? start : end;
    final to = forward ? end : start;

    var years = 0;
    var cursor = from;
    while (!addMonths(cursor, 12).isAfter(to)) {
      cursor = addMonths(cursor, 12);
      years++;
    }
    var months = 0;
    while (!addMonths(cursor, 1).isAfter(to)) {
      cursor = addMonths(cursor, 1);
      months++;
    }
    final days = _day(to).difference(_day(cursor)).inDays;
    final hours = to.hour - cursor.hour;
    return <String, int>{
      'years': forward ? years : -years,
      'months': forward ? months : -months,
      'days': forward ? days : -days,
      'hours': forward ? hours : -hours,
    };
  }

  /// 是否工作日。优先级：**调休补班 > 法定节假日 > 周末**
  /// （国务院调休会把某个周末变成工作日，故 adjustments 最先判定）。
  static bool isWorkday(DateTime d, HolidayProvider holidays) {
    final ds = fmt(d);
    for (final e in holidays.between(ds, ds)) {
      if (e.date != ds) continue;
      if (e.type == 'workday') return true;
      if (e.type == 'holiday') return false;
    }
    return d.weekday != DateTime.saturday && d.weekday != DateTime.sunday;
  }

  /// 区间工作日数（含首尾；周末与法定假不计，调休补班计入）。
  static int workdays(DateTime start, DateTime end, HolidayProvider holidays) {
    var count = 0;
    var cur = _day(start);
    final last = _day(end);
    while (!cur.isAfter(last)) {
      if (isWorkday(cur, holidays)) count++;
      cur = cur.add(const Duration(days: 1));
    }
    return count;
  }

  /// **F2 组合顺序**：`days → months → workdays → hours`。
  ///
  /// 文档规定 `months` 不得与 `workdays`/`hours` 混合；若调用方同时传入，
  /// 按上述顺序**依次应用**（而非拒绝或静默择一）。
  static DateTime addDelta(
    DateTime base, {
    int days = 0,
    int months = 0,
    int workdays = 0,
    int hours = 0,
    HolidayProvider? holidays,
  }) {
    final h = holidays ?? const EmptyHolidayProvider();
    var cur = base.add(Duration(days: days));
    if (months != 0) cur = addMonths(cur, months);
    if (workdays != 0) cur = addWorkdays(cur, workdays, h);
    if (hours != 0) cur = cur.add(Duration(hours: hours));
    return cur;
  }

  /// 加 N 月：**月末 clamp**（1/31 + 1 月 = 2/28 平年，不滚到 3/3）。
  static DateTime addMonths(DateTime d, int n) {
    final total = d.month - 1 + n;
    final y = d.year + (total ~/ 12);
    final mo = (total % 12) + 1;
    final lastDay = DateTime.utc(y, mo + 1, 0).day;
    return DateTime(
      y,
      mo,
      d.day > lastDay ? lastDay : d.day,
      d.hour,
      d.minute,
      d.second,
      d.millisecond,
      d.microsecond,
    );
  }

  /// 加 N 个工作日（负数为回溯）：逐日步进并仅在工作日计数。
  static DateTime addWorkdays(DateTime d, int n, HolidayProvider holidays) {
    final step = n >= 0 ? 1 : -1;
    var remain = n.abs();
    var cur = d;
    while (remain > 0) {
      cur = cur.add(Duration(days: step));
      if (isWorkday(cur, holidays)) remain--;
    }
    return cur;
  }

  /// 区间内法定节假日明细（供 `workdays_between` 的 `holidays` 字段）。
  static List<Map<String, Object?>> holidaysIn(
    DateTime start,
    DateTime end,
    HolidayProvider holidays,
  ) =>
      holidays
          .between(fmt(start), fmt(end))
          .where((e) => e.type == 'holiday')
          .map((e) => <String, Object?>{'date': e.date, 'name': e.name})
          .toList();

  /// 区间内调休补班明细（供 `workdays_between` 的 `adjustments` 字段）。
  static List<Map<String, Object?>> adjustmentsIn(
    DateTime start,
    DateTime end,
    HolidayProvider holidays,
  ) =>
      holidays
          .between(fmt(start), fmt(end))
          .where((e) => e.type == 'workday')
          .map((e) => <String, Object?>{
                'date': e.date,
                'name': e.name,
                'type': 'workday',
              })
          .toList();
}
