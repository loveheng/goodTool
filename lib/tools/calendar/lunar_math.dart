// 农历引擎封装（P2-③）：包装 package:lunar（6tail，纯 Dart 无第三方依赖，
// 1900–2100 公农历双向确定性换算 + 二十四节气），落实 calendar.md「农历与节气
// 内核」与「农历与纪念日引擎（Lunar Engine）」节契约。
//
// 纯 Dart（R4 延伸）；**F1 纯函数纪律**：无 DateTime.now()，全部输入显式注入。
//
// 关键库约定（读包源码钉死，勿凭记忆改）：
// - 闰月用**负月份数**表达（`Lunar.fromYmd(y, -6, d)` = 闰六月初六）；
// - `getMonthInChinese()` 返回 '正'/'二'/'八'（闰月带 '闰' 前缀，如 '闰六'），
//   **不带 '月' 字**；`getDayInChinese()` 返回 '初一'/'十五'；
// - `getJieQi()` 仅当天恰为节气日才返回节气名，否则空串；
// - `Lunar.fromYmd` 对非法农历日**抛 String**（非 Exception），必须 `on Object` 接。
library;

import 'package:lunar/lunar.dart';

/// 农历换算失败信号（由工具层转 INVALID_ARGUMENT，不把库异常漏给 Agent）。
class LunarMathException implements Exception {
  const LunarMathException(this.message);
  final String message;
  @override
  String toString() => 'LunarMathException: $message';
}

/// 农历描述信息（角标 / 回显用）。
class LunarInfo {
  const LunarInfo({
    required this.lunarYear,
    required this.lunarMonth,
    required this.lunarDay,
    required this.isLeapMonth,
    required this.monthText,
    required this.dayText,
    required this.label,
    required this.solarTerm,
  });

  final int lunarYear;

  /// 正数 = 平月，负数 = 闰月（库约定）。
  final int lunarMonth;
  final int lunarDay;
  final bool isLeapMonth;

  /// '正' / '二' / '闰六'（不带 '月' 字）。
  final String monthText;

  /// '初一' / '十五'。
  final String dayText;

  /// 角标惯例：初一显示月名（'八月'），其余显示日（'十五'）。
  final String label;

  /// 当天节气名（非节气日为空串）。
  final String solarTerm;

  /// 全称，如 '2026年八月十五'（闰月 '2025年闰六月初五'）。
  String get fullText =>
      '$lunarYear年${isLeapMonth ? '闰' : ''}$monthText月$dayText';
}

/// 农历推演工具集。
class LunarMath {
  const LunarMath._();

  /// 公历日 → 农历描述（含当天节气）。
  ///
  /// [solar] 传 UTC 成分即可（本库按年月日成分换算，与时区无关）。
  static LunarInfo describe(DateTime solar) {
    final lunar = Solar.fromDate(solar).getLunar();
    final m = lunar.getMonth();
    final isLeap = m < 0;
    final monthText = lunar.getMonthInChinese(); // '八' / '闰六'
    final dayText = lunar.getDayInChinese(); // '十五'
    final solarTerm = lunar.getJieQi(); // 非节气日为 ''
    final label = lunar.getDay() == 1 ? '$monthText月' : dayText;
    return LunarInfo(
      lunarYear: lunar.getYear(),
      lunarMonth: m,
      lunarDay: lunar.getDay(),
      isLeapMonth: isLeap,
      monthText: monthText,
      dayText: dayText,
      label: label,
      solarTerm: solarTerm,
    );
  }

  /// 当天节气名（非节气日返回空串）。
  static String solarTermOf(DateTime solar) => describe(solar).solarTerm;

  /// 指定公历年的农历月份是否存在闰月；返回闰月号（无闰月返回 0）。
  static int leapMonthOf(int lunarYear) {
    try {
      return LunarYear.fromYear(lunarYear).getLeapMonth();
    } on Object {
      throw LunarMathException('农历年 $lunarYear 超出可换算范围（1900–2100）');
    }
  }

  /// 农历 → 公历。月日为农历成分；[isLeapMonth] 指定闰月。
  ///
  /// 非法农历日（如该年无闰五月、腊月只有 29 天却传 30）抛
  /// [LunarMathException]——**不 clamp 不伪造**（与 ICS「无 31 日不触发」同一纪律）。
  static DateTime lunarToSolar(
    int lunarYear,
    int lunarMonth,
    int lunarDay, {
    bool isLeapMonth = false,
  }) {
    if (lunarMonth < 1 || lunarMonth > 12) {
      throw LunarMathException('农历月须为 1~12：$lunarMonth');
    }
    if (lunarDay < 1 || lunarDay > 30) {
      throw LunarMathException('农历日须为 1~30：$lunarDay');
    }
    try {
      final solar = Lunar.fromYmd(
        lunarYear,
        isLeapMonth ? -lunarMonth : lunarMonth,
        lunarDay,
      ).getSolar();
      return DateTime.utc(solar.getYear(), solar.getMonth(), solar.getDay());
    } on Object {
      throw LunarMathException(
        '农历 $lunarYear 年${isLeapMonth ? '闰' : ''}$lunarMonth 月 $lunarDay 日'
        '不存在或超出可换算范围（1900–2100）',
      );
    }
  }

  /// 公历 → 农历（完整往返用；[describe] 已覆盖角标场景）。
  static ({int year, int month, int day, bool isLeapMonth}) toLunar(
    DateTime solar,
  ) {
    final lunar = Solar.fromDate(solar).getLunar();
    final m = lunar.getMonth();
    return (
      year: lunar.getYear(),
      month: m.abs(),
      day: lunar.getDay(),
      isLeapMonth: m < 0,
    );
  }

  /// 指定年份（按农历年取表）的二十四节气表：节气名 → 公历日（UTC 成分）。
  ///
  /// 指定农历年的二十四节气表：节气名 → 公历日（UTC 成分）。
  static Map<String, DateTime> jieQiTableOfYear(int year) {
    try {
      final table = Lunar.fromYmd(year, 1, 1).getJieQiTable();
      return <String, DateTime>{
        for (final e in table.entries)
          _normalizeJieQiKey(e.key):
              DateTime.utc(e.value.getYear(), e.value.getMonth(), e.value.getDay()),
      };
    } on Object {
      throw LunarMathException('年份 $year 超出节气表范围（1900–2100）');
    }
  }

  /// 库的跨农历年表头 key 为拼音（JIE_QI_IN_USE 首尾 7 项，源码钉死），
  /// 统一归一为中文，调用方按中文名查。
  static String _normalizeJieQiKey(String k) => switch (k) {
        'DA_XUE' => '大雪',
        'DONG_ZHI' => '冬至',
        'XIAO_HAN' => '小寒',
        'DA_HAN' => '大寒',
        'LI_CHUN' => '立春',
        'YU_SHUI' => '雨水',
        'JING_ZHE' => '惊蛰',
        _ => k,
      };
}
