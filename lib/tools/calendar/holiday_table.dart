// 中国法定节假日与调休补班表（P2-①：F3 版本化表 + OTA 静态 JSON 热更入口）。
//
// **数据来源**：国务院办公厅《关于 2026 年部分节假日安排的通知》（2025-11-04 新华社
// 受权发布，人民网 / 央广网 / 央视网 / 中国新闻网多方转载一致）。原文口径：
//   元旦  1/1(四)–1/3(六) 放假调休 3 天，1/4(日) 上班
//   春节  2/15(日)–2/23(一) 放假调休 9 天，2/14(六)、2/28(六) 上班
//   清明  4/4(六)–4/6(一) 放假 3 天（无调休）
//   劳动  5/1(五)–5/5(二) 放假调休 5 天，5/9(六) 上班
//   端午  6/19(五)–6/21(日) 放假 3 天（无调休）
//   中秋  9/25(五)–9/27(日) 放假 3 天（无调休）
//   国庆  10/1(四)–10/7(三) 放假调休 7 天，9/20(日)、10/10(六) 上班
// **纪律**：天数与日期**逐字照录**，不做估算；2027 年安排待官方发布后追加
// （新增时 bump 版本号，不原地改已发布年份的数据，保证历史判断可重放）。
//
// 节假日与调休补班的语义差别：`holiday` = 法定假日（含被放假吞掉的周末）；
// `workday` = 调休补班——原本是周末但因调休而上班，判定工作日时**优先级最高**
// （见 DateMath.isWorkday：调休补班 > 法定节假日 > 周末）。
//
// 内核纯 Dart、零依赖；测试可覆写（注入自建表）保证确定性（F3）。
library;

import '../../mcp/calendar_provider.dart';

/// 内置表版本号（数据源年份 + 修订号；出参 `holidayTableVersion` 回写该值）。
const String cnHolidayTableVersion = 'cn-2026.1';

/// 内置表（2026 年度）。日期逐字照录官方通知。
const CnHolidayProvider cnHolidayBundled = CnHolidayProvider(
  cnHolidayTableVersion,
  <HolidayEntry>[
    // ---- 元旦（3 天）+ 1/4 补班
    HolidayEntry(date: '2026-01-01', name: '元旦', type: 'holiday'),
    HolidayEntry(date: '2026-01-02', name: '元旦', type: 'holiday'),
    HolidayEntry(date: '2026-01-03', name: '元旦', type: 'holiday'),
    HolidayEntry(date: '2026-01-04', name: '元旦调休', type: 'workday'),
    // ---- 春节（9 天）+ 2/14、2/28 补班
    HolidayEntry(date: '2026-02-14', name: '春节调休', type: 'workday'),
    HolidayEntry(date: '2026-02-15', name: '春节', type: 'holiday'),
    HolidayEntry(date: '2026-02-16', name: '春节', type: 'holiday'),
    HolidayEntry(date: '2026-02-17', name: '春节', type: 'holiday'),
    HolidayEntry(date: '2026-02-18', name: '春节', type: 'holiday'),
    HolidayEntry(date: '2026-02-19', name: '春节', type: 'holiday'),
    HolidayEntry(date: '2026-02-20', name: '春节', type: 'holiday'),
    HolidayEntry(date: '2026-02-21', name: '春节', type: 'holiday'),
    HolidayEntry(date: '2026-02-22', name: '春节', type: 'holiday'),
    HolidayEntry(date: '2026-02-23', name: '春节', type: 'holiday'),
    HolidayEntry(date: '2026-02-28', name: '春节调休', type: 'workday'),
    // ---- 清明（3 天，无调休）
    HolidayEntry(date: '2026-04-04', name: '清明节', type: 'holiday'),
    HolidayEntry(date: '2026-04-05', name: '清明节', type: 'holiday'),
    HolidayEntry(date: '2026-04-06', name: '清明节', type: 'holiday'),
    // ---- 劳动节（5 天）+ 5/9 补班
    HolidayEntry(date: '2026-05-01', name: '劳动节', type: 'holiday'),
    HolidayEntry(date: '2026-05-02', name: '劳动节', type: 'holiday'),
    HolidayEntry(date: '2026-05-03', name: '劳动节', type: 'holiday'),
    HolidayEntry(date: '2026-05-04', name: '劳动节', type: 'holiday'),
    HolidayEntry(date: '2026-05-05', name: '劳动节', type: 'holiday'),
    HolidayEntry(date: '2026-05-09', name: '劳动节调休', type: 'workday'),
    // ---- 端午（3 天，无调休）
    HolidayEntry(date: '2026-06-19', name: '端午节', type: 'holiday'),
    HolidayEntry(date: '2026-06-20', name: '端午节', type: 'holiday'),
    HolidayEntry(date: '2026-06-21', name: '端午节', type: 'holiday'),
    // ---- 中秋（3 天，无调休）
    HolidayEntry(date: '2026-09-25', name: '中秋节', type: 'holiday'),
    HolidayEntry(date: '2026-09-26', name: '中秋节', type: 'holiday'),
    HolidayEntry(date: '2026-09-27', name: '中秋节', type: 'holiday'),
    // ---- 国庆（7 天）+ 9/20、10/10 补班
    HolidayEntry(date: '2026-09-20', name: '国庆调休', type: 'workday'),
    HolidayEntry(date: '2026-10-01', name: '国庆节', type: 'holiday'),
    HolidayEntry(date: '2026-10-02', name: '国庆节', type: 'holiday'),
    HolidayEntry(date: '2026-10-03', name: '国庆节', type: 'holiday'),
    HolidayEntry(date: '2026-10-04', name: '国庆节', type: 'holiday'),
    HolidayEntry(date: '2026-10-05', name: '国庆节', type: 'holiday'),
    HolidayEntry(date: '2026-10-06', name: '国庆节', type: 'holiday'),
    HolidayEntry(date: '2026-10-07', name: '国庆节', type: 'holiday'),
    HolidayEntry(date: '2026-10-10', name: '国庆调休', type: 'workday'),
  ],
);

/// 法定节假日表（内置 + OTA 同构）。
class CnHolidayProvider implements HolidayProvider {
  const CnHolidayProvider(this.version, this._entries);

  /// 表版本号（HolidayProvider 接口成员）。
  @override
  final String version;
  final List<HolidayEntry> _entries;

  @override
  List<HolidayEntry> between(String startDate, String endDate) => _entries
      .where((e) =>
          e.date.compareTo(startDate) >= 0 && e.date.compareTo(endDate) <= 0)
      .toList(growable: false);

  /// OTA 静态 JSON 解析（F3：本地 bundle + 静态 JSON 热更同构）。
  ///
  /// 预期形状：
  /// ```json
  /// {"version":"cn-2026.2","ranges":[{"start":"2026-01-01","days":3,"name":"元旦"}],
  ///  "workdays":[{"date":"2026-01-04","name":"元旦调休"}]}
  /// ```
  /// `ranges` 为「连续放假区间」（含被吞掉的周末），展开为逐日 `holiday` 条目；
  /// `workdays` 为调休补班（`workday` 类型）。格式不符抛 [FormatException]。
  factory CnHolidayProvider.fromJson(Map<String, Object?> json) {
    final version = json['version'];
    if (version is! String || version.trim().isEmpty) {
      throw const FormatException('节假日表缺少 version 字段');
    }
    final rawRanges = json['ranges'];
    if (rawRanges is! List) {
      throw const FormatException('节假日表缺少 ranges 数组');
    }
    final rawWorkdays = json['workdays'] ?? const <Object?>[];
    if (rawWorkdays is! List) {
      throw const FormatException('节假日表 workdays 须为数组');
    }

    final entries = <HolidayEntry>[];
    for (final raw in rawRanges) {
      if (raw is! Map) throw const FormatException('ranges 元素须为对象');
      final start = raw['start'];
      final days = raw['days'];
      final name = raw['name'];
      if (start is! String ||
          days is! int ||
          days <= 0 ||
          days > 16 ||
          name is! String) {
        throw const FormatException('ranges 元素字段非法（须含 start/days/name）');
      }
      final startAt = DateTime.tryParse('${start}T00:00:00Z');
      if (startAt == null) {
        throw FormatException('ranges.start 不是合法日期：$start');
      }
      for (var i = 0; i < days; i++) {
        final d = startAt.add(Duration(days: i));
        entries.add(HolidayEntry(
          date: _iso(d),
          name: name,
          type: 'holiday',
        ));
      }
    }
    for (final raw in rawWorkdays) {
      if (raw is! Map) throw const FormatException('workdays 元素须为对象');
      final date = raw['date'];
      final name = raw['name'];
      if (date is! String || name is! String) {
        throw const FormatException('workdays 元素须含 date/name');
      }
      entries.add(HolidayEntry(date: date, name: name, type: 'workday'));
    }
    entries.sort((a, b) => a.date.compareTo(b.date));
    return CnHolidayProvider(version.trim(), entries);
  }

  static String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
