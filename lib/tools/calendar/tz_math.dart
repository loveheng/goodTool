// 时区投影内核（P2-②）：包装 package:timezone，落实 calendar.md 时区治理
// B3（ISO 8601 带显式 offset）/ B4（DST 由 tz 库判定）/ B5（bundled latest.tzf）。
//
// 纯 Dart：package:timezone 内核不沾 dart:io（R4 延伸）。
// **F1 纯函数纪律**：无 DateTime.now()，全部输入显式注入，同输入恒同输出。
//
// 踩坑先例（P2-④ devlog）：ICS 时间解析禁用 `DateTime(...).toUtc()`——本文件
// 仅在**输入串自带 Z / offset** 时才 `toUtc()`（此时 Dart 已按声明偏移解析，
// toUtc 只是换表示，不引入本机时区）；无时区信息的墙钟一律按 fromTz 显式构造
// `TZDateTime`，绝不落进本机时区。
library;

import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// 时区解析失败信号（由工具层转 INVALID_ARGUMENT，不把库异常漏给 Agent）。
class TzMathException implements Exception {
  const TzMathException(this.message);
  final String message;
  @override
  String toString() => 'TzMathException: $message';
}

/// 时区推演工具集。
class TzMath {
  const TzMath._();

  static bool _initialized = false;

  /// 初始化内嵌 tz 数据库（B5：bundled `latest.tzf`，纯 Dart 可测）。
  /// 幂等：数据库只装载一次，重复调用是空操作。
  static void ensureInitialized() {
    if (_initialized) return;
    tzdata.initializeTimeZones();
    _initialized = true;
  }

  /// IANA 时区名 → Location；非法名抛 [TzMathException]（不静默回退 UTC）。
  static tz.Location resolveLocation(String name) {
    ensureInitialized();
    try {
      return tz.getLocation(name);
    } on Object {
      throw TzMathException('非合法 IANA 时区名：$name');
    }
  }

  /// 解析 `datetime` 入参为确定时刻：
  ///
  /// - 串尾带 `Z` / `±HH[:MM]` → 已声明时区信息，`DateTime.tryParse` 后取
  ///   UTC 时刻（不引入本机时区，见文件头踩坑说明）；
  /// - 纯墙钟（无时区信息）→ 按 [fromLoc] 的墙钟构造 `TZDateTime`（B2/B3：
  ///   浮动时间按生效时区解释）；
  /// - 纯日期 `YYYY-MM-DD` → fromTz 当日 00:00。
  ///
  /// 非法串抛 [TzMathException]。
  static DateTime parseInput(Object? raw, tz.Location fromLoc) {
    if (raw is! String || raw.trim().isEmpty) {
      throw const TzMathException('缺少 datetime（ISO 8601，如 2026-10-20T14:30:00）');
    }
    final s = raw.trim();
    final dt = DateTime.tryParse(s);
    if (dt == null) {
      throw TzMathException('datetime 无法解析为 ISO 8601：$s');
    }
    final hasExplicitTz =
        RegExp(r'(?:Z|[+-]\d{2}:?\d{2})$', caseSensitive: false).hasMatch(s);
    if (hasExplicitTz) return dt.toUtc();
    return tz.TZDateTime(
      fromLoc,
      dt.year,
      dt.month,
      dt.day,
      dt.hour,
      dt.minute,
      dt.second,
      dt.millisecond,
      dt.microsecond,
    );
  }

  /// 把时刻投影到 [toLoc]，产出 B3/B4/B5 出参（`calendar_tz_convert` 契约）。
  ///
  /// - `target`：ISO 8601 带显式 offset（自格式化——`TZDateTime.toString()`
  ///   是空格分隔的非标格式，不能直接用）；
  /// - `dstActive`：由 tz 库在该瞬间的真实时区段判定（B4）；
  /// - `abbreviation`：如 `CST` / `UTC`。
  static Map<String, Object?> project(DateTime instant, tz.Location toLoc) {
    final projected = tz.TZDateTime.from(instant, toLoc);
    final zone = toLoc.timeZone(projected.millisecondsSinceEpoch);
    return <String, Object?>{
      'target': fmtIso(projected),
      'offset': fmtOffset(projected.timeZoneOffset),
      'offsetMinutes': projected.timeZoneOffset.inMinutes,
      'abbreviation': zone.abbreviation,
      'dstActive': zone.isDst,
      'timezone': toLoc.name,
    };
  }

  /// `Duration` → `±HH:MM`。
  static String fmtOffset(Duration d) {
    final sign = d.isNegative ? '-' : '+';
    final a = d.abs();
    return '$sign${a.inHours.toString().padLeft(2, '0')}:'
        '${(a.inMinutes % 60).toString().padLeft(2, '0')}';
  }

  /// `TZDateTime` → `YYYY-MM-DDTHH:mm:ss±HH:MM`（B3 显式 offset，秒级精度）。
  /// 公开口径：`project().target` 与 `time_now().now` 同一格式化器。
  static String fmtIso(tz.TZDateTime d) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${d.year.toString().padLeft(4, '0')}-${two(d.month)}-${two(d.day)}'
        'T${two(d.hour)}:${two(d.minute)}:${two(d.second)}'
        '${fmtOffset(d.timeZoneOffset)}';
  }
}
