// system_pim 领域网关适配层（P1d）：注册 product/calendar.md 定义的 **14 个原子动作**，
// action 名原样沿用能力文档，不改名、不自造（G1）——「文档表格第一列」与本文件
// `register` 列表可机械对账（单测已钉死）。
//
// 档位：5 个 W 档（subscribe / unsubscribe / refresh / marker_add / marker_delete，
// **只 buildCommand**，鉴权与派发由 `CategoryTool` 网关层统一执行——G3 / arch-guard R7）
// + 9 个 R 档。
//
// **落地进度（P2 完毕，14/14 全真实可用）**：
// - 纯函数 3 档（date_calc / date_diff / workdays_between）+ 农历 2 档
//   （resolve_date / month_grid / marker_list 的农历分支，P2-③ package:lunar）
//   + 时区 1 档（tz_convert，P2-② package:timezone，B3/B4/B5）；
// - ICS 3 档（query / feeds / refresh）经 `CalendarFeedProvider` 注入；
// - 标记 2 档经 `CalendarMarkerStore` 注入；缺源时按 standards §1.2
//   **fail-closed** 返 `ERR_CALENDAR_SOURCE_UNAVAILABLE`（不假上线）；
// - `calendar_query` 的 `source: system`（P2-⑦）经 CompositeCalendarProvider
//   双路合并落地：Kotlin `SystemCalendarChannel`（双引擎注册）+
//   `MethodChannelSystemCalendarPort`；READ_CALENDAR 缺权降级为 warnings
//   （`ERR_CALENDAR_PERMISSION`），授权入口在日历页（U12b）。
library;

import 'dart:convert';

import 'package:timezone/timezone.dart' as tz;

import '../action/calendar_commands.dart';
import '../action/command_gateway.dart';
import '../mcp/calendar_provider.dart';
import '../mcp/category_tool_face.dart';
import 'calendar/date_math.dart';
import 'calendar/lunar_math.dart';
import 'calendar/marker_math.dart';
import 'calendar/resolve_expression.dart';
import 'calendar/tz_math.dart';

/// **C1 防御**：查询跨度硬上限 90 天；超限报 `ERR_RANGE_TOO_WIDE`，
/// 不静默截断（避免 Agent 误以为拿到全量）。
const int calendarMaxRangeDays = 90;

/// 公开入口：构建 `system_pim` 领域网关（日历 + 标记 + 时间推演）。
///
/// [gateway] 为写门禁端口（W 档必经）；[feeds] / [markers] 为 P2 真实源，
/// 缺省 null ⇒ 相关 R 档 fail-closed；[holidays] 默认 **空表**
/// （[EmptyHolidayProvider]：workdays 仅跳过周末，不编造官方放假 / 补班判断），
/// 实际由装配注入 ICS 驱动的 [IcsHolidayProvider]（订阅名称含『节假日』的 ICS 源）。
/// 内置 2026 表（[cnHolidayBundled]）仍保留为可注入的确定性表 / OTA 种子。
///
/// [ToolVisibility.shared]：本域属四大聚合工具之一，声明允许宿主收进共享面。
CategoryTool buildSystemPimTool(
  CommandGateway gateway, {
  CalendarFeedProvider? feeds,
  CalendarMarkerStore? markers,
  HolidayProvider holidays = const EmptyHolidayProvider(),
  DeviceTimezoneProvider deviceTz = const UtcTimezoneProvider(),
}) {
  final cat = CategoryTool(
    'system_pim',
    '日历基准 + 重要事件标记 + 时间推演：区间事件查询（展开 RRULE）、订阅源管理、'
    '整月网格（恒定 42 格）、相对日期消歧、工作日与节假日推演、时区投影。'
    '定位是「看」与「算」，**不做独立会议 / 日程管理**（参会人、会议链接由独立日程 App 承接）。'
    '写操作（订阅 / 退订 / 刷新 / 增删标记）属用户委托写，须会话已鉴权。',
    gateway,
    visibility: ToolVisibility.shared,
    // SDK 0.2.0 annotations：含 W 档写子操作（订阅/退订/刷新/标记增删，其中
    // marker delete 为删除类），不作只读声明，声明可能破坏性。
    destructiveHint: true,
  );
  // R 档 · 已实现（纯函数）
  cat.register(_CalendarDateCalcSub(holidays));
  cat.register(_CalendarDateDiffSub(holidays));
  cat.register(_CalendarWorkdaysBetweenSub(holidays));
  // R 档 · 真实源注入（ICS / 标记存储；缺省 null ⇒ fail-closed）
  cat.register(_CalendarQuerySub(feeds));
  cat.register(_CalendarFeedsSub(feeds));
  cat.register(_CalendarMonthGridSub(markers, holidays));
  cat.register(_CalendarResolveDateSub(holidays));
  cat.register(_CalendarMarkerListSub(markers, holidays));
  cat.register(_CalendarTzConvertSub(deviceTz));
  cat.register(_TimeNowSub(holidays, deviceTz));
  // W 档 · 只构造命令
  cat.register(_CalendarSubscribeSub());
  cat.register(_CalendarUnsubscribeSub());
  cat.register(_CalendarRefreshSub());
  cat.register(_CalendarMarkerAddSub());
  cat.register(_CalendarMarkerDeleteSub());
  return cat;
}

// ---------------------------------------------------------------------------
// 出参与错误口径
// ---------------------------------------------------------------------------

SubActionResult _jsonSuccess(Map<String, Object?> payload) =>
    SubActionResult.success([
      {'type': 'text', 'text': jsonEncode(payload)}
    ]);

/// 结构化错误：吐**裸 machine code**，`system_pim.<action>:` 前缀由派发层注入（G1/G5）。
SubActionResult _err(String code, String message, {String? suggestion}) =>
    SubActionResult.structuredError(code, message, <String, Object?>{
      'code': code,
      'message': message,
      'suggestion': ?suggestion,
    });

/// 源未注入的统一定价（fail-closed，standards §1.2）。
SubActionResult _unavailable(String what) => _err(
      CalendarErr.sourceUnavailable,
      '$what 尚未接入真实源（P2 排期：ICS 解析 / 农历引擎 / 时区库）',
      suggestion: '当前可先用 date_calc / date_diff / workdays_between 三个纯函数能力',
    );

// ---------------------------------------------------------------------------
// R 档 · 已实现：时间推演三件套（F1 纯函数，确定性）
// ---------------------------------------------------------------------------

/// calendar_date_calc：自然日 / 工作日推算（F2 组合顺序）。
class _CalendarDateCalcSub extends SubAction {
  _CalendarDateCalcSub(this._holidays);

  final HolidayProvider _holidays;

  @override
  String get name => 'calendar_date_calc';

  @override
  String get description =>
      '自然日 / 工作日推算：给定基准日与增量，算出目标日期与是否工作日。'
      'delta 支持 days / months / workdays / hours；同时传入多个时按 '
      'days → months → workdays → hours 顺序依次应用（months 加法按月末 clamp：'
      '1/31 + 1 月 = 2/28，不滚到 3/3）。工作日跳跃跳过周六日与法定节假日，'
      '调休补班日计入工作日。';

  @override
  String get paramSignature =>
      'calendar_date_calc(baseDate: string, delta: {days?, months?, workdays?, hours?}) '
      '[必填: baseDate, delta]';

  @override
  Future<SubActionResult> execute(Map<String, Object?> params) async {
    final base = DateMath.parseDate(params['baseDate']);
    if (base == null) {
      return _err(
          'MISSING_ARGUMENT',
          "缺少或非法 baseDate：${params['baseDate']}"
          '（须为 YYYY-MM-DD，如 2026-10-20）');
    }
    final raw = params['delta'];
    if (raw is! Map) {
      return _err('MISSING_ARGUMENT', '缺少 delta 对象 {days?, months?, workdays?, hours?}');
    }
    final spec = <String, int>{};
    for (final k in const ['days', 'months', 'workdays', 'hours']) {
      final v = raw[k];
      if (v == null) continue;
      final n = parseInt(v);
      if (n == null) {
        return _err('INVALID_ARGUMENT', 'delta.$k 不是合法整数：$v');
      }
      spec[k] = n;
    }
    if (spec.isEmpty) {
      return _err('MISSING_ARGUMENT', 'delta 至少需要一个字段',
          suggestion: '例：{"days": 3} 或 {"workdays": 5}');
    }

    final target = DateMath.addDelta(
      base,
      days: spec['days'] ?? 0,
      months: spec['months'] ?? 0,
      workdays: spec['workdays'] ?? 0,
      hours: spec['hours'] ?? 0,
      holidays: _holidays,
    );
    final lo = target.isBefore(base) ? target : base;
    final hi = target.isBefore(base) ? base : target;
    return _jsonSuccess(<String, Object?>{
      'success': true,
      'targetDate': DateMath.fmt(target),
      'isWorkday': DateMath.isWorkday(target, _holidays),
      'passedWorkdays': DateMath.workdays(lo, hi, _holidays),
      'passedHolidays': DateMath.holidaysIn(lo, hi, _holidays),
      'timezone': 'UTC',
      'holidayTableVersion': _holidays.version,
    });
  }
}

/// calendar_date_diff：精确跨度与工作日统计（F4）。
class _CalendarDateDiffSub extends SubAction {
  _CalendarDateDiffSub(this._holidays);

  final HolidayProvider _holidays;

  @override
  String get name => 'calendar_date_diff';

  @override
  String get description =>
      '计算两日期之间的总天数、工作日数与**成分跨度**（years/months/days/hours）。'
      '跨度严格按日期成分计算（不用毫秒相除），大小月与闰年天然正确；'
      'excludeWeekends 与 excludeHolidays 两个开关独立生效。';

  @override
  String get paramSignature =>
      'calendar_date_diff(startDate: string, endDate: string, '
      'excludeWeekends?: bool, excludeHolidays?: bool) [必填: startDate, endDate]';

  @override
  Future<SubActionResult> execute(Map<String, Object?> params) async {
    final start = DateMath.parseDate(params['startDate']);
    final end = DateMath.parseDate(params['endDate']);
    if (start == null || end == null) {
      return _err('MISSING_ARGUMENT',
          "startDate / endDate 须为合法 YYYY-MM-DD"
          "（start=${params['startDate']}, end=${params['endDate']}）");
    }
    final excludeWeekends = _flag(params['excludeWeekends']);
    final excludeHolidays = _flag(params['excludeHolidays']);
    if (excludeWeekends == null || excludeHolidays == null) {
      return _err('INVALID_ARGUMENT',
          'excludeWeekends / excludeHolidays 须为布尔或 "true"/"false"');
    }
    return _jsonSuccess(<String, Object?>{
      'success': true,
      'totalDays': DateMath.totalDays(start, end),
      'workdays': _countWorkdays(
        start,
        end,
        excludeWeekends: excludeWeekends,
        excludeHolidays: excludeHolidays,
        holidays: _holidays,
      ),
      'span': DateMath.span(start, end),
      'timezone': 'UTC',
      'holidayTableVersion': _holidays.version,
    });
  }
}

/// calendar_workdays_between：区间节假日 / 调休补班明细透视。
class _CalendarWorkdaysBetweenSub extends SubAction {
  _CalendarWorkdaysBetweenSub(this._holidays);

  final HolidayProvider _holidays;

  @override
  String get name => 'calendar_workdays_between';

  @override
  String get description =>
      '区间工作日明细透视：返回总天数、工作日数，并**展开**区间内的法定节假日与'
      '调休补班（周末上班）明细，供拼假策略 / 工期推演，避免逐日往返查询的 Token 损耗。'
      '工作日 = 调休补班 > 法定节假日 > 周末 的优先级判定。';

  @override
  String get paramSignature =>
      'calendar_workdays_between(startDate: string, endDate: string) [必填: startDate, endDate]';

  @override
  Future<SubActionResult> execute(Map<String, Object?> params) async {
    final start = DateMath.parseDate(params['startDate']);
    final end = DateMath.parseDate(params['endDate']);
    if (start == null || end == null) {
      return _err('MISSING_ARGUMENT',
          "startDate / endDate 须为合法 YYYY-MM-DD"
          "（start=${params['startDate']}, end=${params['endDate']}）");
    }
    final lo = start.isBefore(end) ? start : end;
    final hi = start.isBefore(end) ? end : start;
    return _jsonSuccess(<String, Object?>{
      'success': true,
      'totalDays': DateMath.totalDays(lo, hi),
      'workdays': DateMath.workdays(lo, hi, _holidays),
      'holidays': DateMath.holidaysIn(lo, hi, _holidays),
      'adjustments': DateMath.adjustmentsIn(lo, hi, _holidays),
      'timezone': 'UTC',
      'holidayTableVersion': _holidays.version,
    });
  }
}

/// 工作日计数（F4：两个开关独立）。
int _countWorkdays(
  DateTime start,
  DateTime end, {
  required bool excludeWeekends,
  required bool excludeHolidays,
  required HolidayProvider holidays,
}) {
  var count = 0;
  var cur = DateTime.utc(start.year, start.month, start.day);
  final last = DateTime.utc(end.year, end.month, end.day);
  while (!cur.isAfter(last)) {
    final ds = DateMath.fmt(cur);
    var adjustedWorkday = false;
    var holiday = false;
    for (final e in holidays.between(ds, ds)) {
      if (e.date != ds) continue;
      if (e.type == 'workday') adjustedWorkday = true;
      if (e.type == 'holiday') holiday = true;
    }
    final weekend =
        cur.weekday == DateTime.saturday || cur.weekday == DateTime.sunday;
    // 调休补班优先级最高：即便在周末也计入工作日（国务院把该周末变成了工作日）。
    var isWork = adjustedWorkday || (!weekend && !holiday);
    // excludeWeekends 的语义是「周六日一律不计」——显式要求排除周末时，
    // 落在周末的调休补班同样不计（与 workdays_between 的口径差异已写在描述里）。
    if (excludeWeekends && weekend) isWork = false;
    if (!adjustedWorkday && excludeHolidays && holiday) isWork = false;
    if (isWork) count++;
    cur = cur.add(const Duration(days: 1));
  }
  return count;
}

/// 宽容布尔解析：不可解析返回 null（由调用方转带码错误，**不取默认值兜底**）。
bool? _flag(Object? raw) {
  if (raw == null) return false;
  return parseBool(raw);
}

// ---------------------------------------------------------------------------
// R 档 · 待 P2 真实源（fail-closed）
// ---------------------------------------------------------------------------

class _CalendarQuerySub extends SubAction {
  _CalendarQuerySub(this._feeds);
  final CalendarFeedProvider? _feeds;

  @override
  String get name => 'calendar_query';

  @override
  String get description =>
      '按区间查询日历事件（展开 RRULE，含脱敏）：合并系统日历与已订阅的公共 ICS '
      '（节假日 / 调休 / 节气 / 公共赛事）。跨度硬上限 90 天，超限报 ERR_RANGE_TOO_WIDE；'
      '结果按 startTime → uid 固定排序，保证同输入可重放。';

  @override
  String get paramSignature =>
      'calendar_query(rangeStart: string, rangeEnd: string, timezone?: string, '
      'feedIds?: string[], includeSystem?: bool, limit?: int) [必填: rangeStart, rangeEnd]';

  @override
  Future<SubActionResult> execute(Map<String, Object?> params) async {
    final start = DateMath.parseDate(params['rangeStart']);
    final end = DateMath.parseDate(params['rangeEnd']);
    if (start == null || end == null) {
      return _err('MISSING_ARGUMENT',
          "rangeStart / rangeEnd 须为合法 YYYY-MM-DD"
          "（start=${params['rangeStart']}, end=${params['rangeEnd']}）");
    }
    if (DateMath.totalDays(start, end) > calendarMaxRangeDays) {
      return _err(CalendarErr.rangeTooWide,
          '查询跨度 ${DateMath.totalDays(start, end)} 天超过上限 $calendarMaxRangeDays 天',
          suggestion: '缩小区间后重试（本工具不做静默截断，避免你误以为拿到全量）');
    }
    final provider = _feeds;
    if (provider == null) return _unavailable('日历事件源（ICS / 系统日历）');
    final limit = _capOf(params['limit']);
    if (limit case final String err) {
      return _err('INVALID_ARGUMENT', err);
    }
    final cap = limit as int;
    // includeSystem：缺省 true（合并系统日历与 ICS）；显式传入须可解析（不静默兜底）。
    final bool includeSystem;
    final rawInclude = params['includeSystem'];
    if (rawInclude == null) {
      includeSystem = true;
    } else {
      final parsed = parseBool(rawInclude);
      if (parsed == null) {
        return _err('INVALID_ARGUMENT',
            'includeSystem 须为布尔值：$rawInclude');
      }
      includeSystem = parsed;
    }

    final CalendarQueryResult result;
    try {
      result = await provider.query(
        rangeStart: DateMath.fmt(start),
        rangeEnd: DateMath.fmt(end),
        timezone: params['timezone'] is String ? params['timezone'] as String : null,
        feedIds: _stringList(params['feedIds']),
        includeSystem: includeSystem,
      );
    } on CalendarFeedException catch (e) {
      // 源层机器码透出（区间超限 / 拉取失败 / 解析失败），不静默返空。
      return _err(e.code, e.message, suggestion: e.suggestion);
    }

    final events = result.events;
    final take = cap == 0 ? events.length : cap;
    return _jsonSuccess(<String, Object?>{
      'success': true,
      'events': events.take(take).map((e) => e.toJson()).toList(),
      'hasMore': events.length > take,
      'timezone': 'UTC',
      // 子源部分失败显式透出（如系统日历未授权 ERR_CALENDAR_PERMISSION）：
      // ICS 结果照常返回，但 Agent 必须知道哪些源缺席——不静默降级。
      'warnings': result.warnings,
    });
  }
}

class _CalendarFeedsSub extends SubAction {
  _CalendarFeedsSub(this._feeds);
  final CalendarFeedProvider? _feeds;

  @override
  String get name => 'calendar_feeds';

  @override
  String get description =>
      '列出全部日历源：系统日历与已订阅的在线 ICS，含刷新周期、上次同步时间与状态。';

  @override
  String get paramSignature => 'calendar_feeds()';

  @override
  Future<SubActionResult> execute(Map<String, Object?> params) async {
    final provider = _feeds;
    if (provider == null) return _unavailable('订阅源清单');
    final feeds = await provider.feeds();
    return _jsonSuccess(<String, Object?>{
      'success': true,
      'feeds': feeds.map((f) => f.toJson()).toList(),
    });
  }
}

class _CalendarMonthGridSub extends SubAction {
  _CalendarMonthGridSub(this._markers, this._holidays);

  final CalendarMarkerStore? _markers;
  final HolidayProvider _holidays;

  @override
  String get name => 'calendar_month_grid';

  @override
  String get description =>
      '整月网格（恒定 42 格 = 6 行 × 7 列）：每格含农历角标（初一显月名）、'
      '节气名、是否工作日、节假日 / 调休补班 / 节气 badge 与当日标记数，'
      '供 UI 绘制与整月自省。firstDayOfWeek 决定列起始（默认 1 = 周一），'
      '避免中 / 欧首日习惯差异导致整列错位。';

  @override
  String get paramSignature =>
      'calendar_month_grid(year: int, month: int, firstDayOfWeek?: int, timezone?: string) '
      '[必填: year, month]';

  @override
  Future<SubActionResult> execute(Map<String, Object?> params) async {
    final year = parseInt(params['year']);
    final month = parseInt(params['month']);
    if (year == null || month == null || month < 1 || month > 12) {
      return _err('INVALID_ARGUMENT', 'year / month 非法（month 取 1~12）：$year-$month');
    }
    final firstDayOfWeek = params['firstDayOfWeek'] == null
        ? 1
        : parseInt(params['firstDayOfWeek']);
    if (firstDayOfWeek == null || firstDayOfWeek < 1 || firstDayOfWeek > 7) {
      return _err('INVALID_ARGUMENT',
          'firstDayOfWeek 须为 1（周一）~ 7（周日）：${params['firstDayOfWeek']}');
    }
    final store = _markers;
    if (store == null) return _unavailable('标记存储源（月网格）');

    final monthStart = DateTime.utc(year, month, 1);
    final monthEnd = DateTime.utc(year, month + 1, 0);
    final markers = await store.list(
      rangeStart: DateMath.fmt(monthStart),
      rangeEnd: DateMath.fmt(monthEnd),
    );
    final expanded = MarkerMath.expand(markers, monthStart, monthEnd);
    return _jsonSuccess(<String, Object?>{
      'success': true,
      'days':
          MarkerMath.monthGrid(year, month, firstDayOfWeek, _holidays, expanded),
      'holidayTableVersion': _holidays.version,
    });
  }
}

class _CalendarResolveDateSub extends SubAction {
  _CalendarResolveDateSub(this._holidays);

  final HolidayProvider _holidays;

  @override
  String get name => 'calendar_resolve_date';

  @override
  String get description =>
      '相对日期消歧（纯函数）：把 "next_friday" / "today+3" / "q4_start" / '
      '"lunar:2026-08-15"（闰月 "lunar:2025-闰6-15"）/ "mid_autumn"（节日别名，'
      '可带年份如 mid_autumn:2027）等表达式解析为确定公历日期，杜绝 LLM 自算幻觉。'
      '相对型表达式与不带年份的别名必须传 baseDate（实现内不调用 DateTime.now()，'
      '基准日由入参显式注入，同输入恒同输出）。';

  @override
  String get paramSignature =>
      'calendar_resolve_date(expression: string, baseDate?: string, timezone?: string) '
      '[必填: expression]';

  @override
  Future<SubActionResult> execute(Map<String, Object?> params) async {
    final base = params['baseDate'] == null
        ? null
        : DateMath.parseDate(params['baseDate']);
    if (params['baseDate'] != null && base == null) {
      return _err('INVALID_ARGUMENT',
          "baseDate 须为合法 YYYY-MM-DD：${params['baseDate']}");
    }
    final ResolvedDate resolved;
    try {
      resolved = ResolveExpression.resolve(params['expression'], baseDate: base);
    } on ResolveException catch (e) {
      return _err(e.code, e.message, suggestion: e.suggestion);
    } on LunarMathException catch (e) {
      return _err('INVALID_ARGUMENT', e.message);
    }
    final lunar = LunarMath.describe(resolved.date);
    return _jsonSuccess(<String, Object?>{
      'success': true,
      'resolvedDate': DateFmt.fmt(resolved.date),
      'weekday': '周${'一二三四五六日'[resolved.date.weekday - 1]}',
      'lunar': lunar.fullText,
      'solarTerm': ?(lunar.solarTerm.isEmpty ? null : lunar.solarTerm),
      'isWorkday': DateMath.isWorkday(resolved.date, _holidays),
      'description': resolved.description,
      'holidayTableVersion': _holidays.version,
    });
  }
}

class _CalendarMarkerListSub extends SubAction {
  _CalendarMarkerListSub(this._markers, this._holidays);

  final CalendarMarkerStore? _markers;
  final HolidayProvider _holidays;

  @override
  String get name => 'calendar_marker_list';

  @override
  String get description =>
      '查询区间内的重要事件标记（生日 / 纪念日 / 里程碑），按年自动展开各周年实例，'
      '并给出倒计时天数与周年数；农历标记经农历引擎对齐到对应公历日再展开，'
      '闰月按标记的 leapPolicy 三策略处理。'
      'daysRemaining 以 rangeStart 为基准日（不用系统当天，保证可重放）；'
      '平年 02-29 对齐 02-28 并标 approximate。';

  @override
  String get paramSignature =>
      'calendar_marker_list(rangeStart: string, rangeEnd: string, category?: string) '
      '[必填: rangeStart, rangeEnd]';

  @override
  Future<SubActionResult> execute(Map<String, Object?> params) async {
    final start = DateMath.parseDate(params['rangeStart']);
    final end = DateMath.parseDate(params['rangeEnd']);
    if (start == null || end == null) {
      return _err('MISSING_ARGUMENT',
          "rangeStart / rangeEnd 须为合法 YYYY-MM-DD"
          "（start=${params['rangeStart']}, end=${params['rangeEnd']}）");
    }
    final store = _markers;
    if (store == null) return _unavailable('标记存储源（markers）');
    final raw = await store.list(
      rangeStart: DateMath.fmt(start),
      rangeEnd: DateMath.fmt(end),
      category: _optStr(params['category']),
    );
    return _jsonSuccess(<String, Object?>{
      'success': true,
      'markers': MarkerMath.expand(raw, start, end),
      'holidayTableVersion': _holidays.version,
    });
  }
}

/// calendar_tz_convert：时区投影 / 世界时钟（F5，P2-② package:timezone 落地）。
class _CalendarTzConvertSub extends SubAction {
  _CalendarTzConvertSub(this._deviceTz);

  /// B1 基准链端口（缺省 UTC）：fromTz / toTz 缺省时的回退源。
  final DeviceTimezoneProvider _deviceTz;

  @override
  String get name => 'calendar_tz_convert';

  @override
  String get description =>
      '时区投影 / 世界时钟：把某时刻从 fromTz 投影到 toTz，返回目标时间'
      '（ISO 8601 带显式 offset）、offset 与 DST 是否生效（B3/B4），'
      '避免 Agent 自算夏令时。datetime 无时区信息时按 fromTz 墙钟解释；'
      'fromTz / toTz 缺省走 B1 基准链（设备时区，缺省 UTC）。';

  @override
  String get paramSignature =>
      'calendar_tz_convert(datetime: string, fromTz?: string, toTz?: string) '
      '[必填: datetime]';

  @override
  Future<SubActionResult> execute(Map<String, Object?> params) async {
    final fromName = _optStr(params['fromTz']) ?? _deviceTz.timezone;
    final toName = _optStr(params['toTz']) ?? _deviceTz.timezone;
    final tz.Location fromLoc;
    final tz.Location toLoc;
    try {
      fromLoc = TzMath.resolveLocation(fromName);
      toLoc = TzMath.resolveLocation(toName);
    } on TzMathException catch (e) {
      return _err('INVALID_ARGUMENT', e.message,
          suggestion: 'IANA 时区名如 Asia/Shanghai、America/New_York、UTC');
    }
    final DateTime instant;
    try {
      instant = TzMath.parseInput(params['datetime'], fromLoc);
    } on TzMathException catch (e) {
      return _err('INVALID_ARGUMENT', e.message);
    }
    final out = TzMath.project(instant, toLoc);
    return _jsonSuccess(<String, Object?>{
      'success': true,
      'fromTimezone': fromName,
      ...out,
    });
  }
}

// ---------------------------------------------------------------------------
// time_now：当前时刻锚点（设备时间 + 时区 + 工作日/节假日上下文）
// ---------------------------------------------------------------------------

/// time_now（R 档）：Agent 无时钟——一切「今天 / 现在」类判断必须先取本时刻，
/// 严禁用训练数据里的日期推算（防编造）。与 tz_convert 共用 B1 基准链与
/// holidayTableVersion 口径；工作日判定 = DateMath.isWorkday（调休补班 > 法定
/// 节假日 > 周末），空表时仅跳过周末（不编造放假判断）。
class _TimeNowSub extends SubAction {
  _TimeNowSub(this._holidays, this._deviceTz);

  final HolidayProvider _holidays;
  final DeviceTimezoneProvider _deviceTz;

  @override
  String get name => 'time_now';

  @override
  String get description =>
      '获取当前时刻锚点：设备现时在指定时区的投影（ISO 8601 带显式 offset）、'
      'epoch 毫秒、当天日期与星期、是否工作日及节假日/调休名。'
      '任何涉及「今天 / 现在 / 还剩几天」的计算都应先调用本动作取当前时刻，'
      '不要用你自己记忆中的日期推算（会编造）。timezone 缺省为设备时区（缺省 UTC）。';

  @override
  String get paramSignature => 'time_now(timezone?: string) [全可选]';

  @override
  Future<SubActionResult> execute(Map<String, Object?> params) async {
    final tzName = _optStr(params['timezone']) ?? _deviceTz.timezone;
    final tz.Location loc;
    try {
      loc = TzMath.resolveLocation(tzName);
    } on TzMathException catch (e) {
      return _err('INVALID_ARGUMENT', e.message,
          suggestion: 'IANA 时区名如 Asia/Shanghai、America/New_York、UTC');
    }
    final now = tz.TZDateTime.now(loc);
    final date = DateMath.fmt(now);
    final isWorkday = DateMath.isWorkday(now, _holidays);
    // 节假日/调休名：仅当表内有当日条目时回写（空表 = 只有周末口径，不编造）。
    String? holidayName;
    for (final e in _holidays.between(date, date)) {
      if (e.date != date) continue;
      holidayName = e.type == 'workday' ? '${e.name}（调休补班）' : e.name;
    }
    return _jsonSuccess(<String, Object?>{
      'success': true,
      'now': TzMath.fmtIso(now),
      'epochMs': now.millisecondsSinceEpoch,
      'timezone': loc.name,
      'offset': TzMath.fmtOffset(now.timeZoneOffset),
      'dstActive': loc.timeZone(now.millisecondsSinceEpoch).isDst,
      'date': date,
      'time':
          '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}',
      'weekday': '周${'一二三四五六日'[now.weekday - 1]}',
      'isWorkday': isWorkday,
      'holidayName': ?holidayName,
      'holidayTableVersion': _holidays.version,
    });
  }
}

// ---------------------------------------------------------------------------
// W 档（用户委托写）：只构造命令，派发与鉴权由网关层执行（G3 / R7）
// ---------------------------------------------------------------------------

/// W 档基类：execute 恒抛（R 档入口对 W 档物理不可达），isWrite 恒 true。
abstract class _WriteSub extends SubAction {
  _WriteSub();

  @override
  bool get isWrite => true;

  @override
  Future<SubActionResult> execute(Map<String, Object?> params) =>
      throw UnsupportedError('W 档子操作不得直接 execute');
}

class _CalendarSubscribeSub extends _WriteSub {
  _CalendarSubscribeSub();

  @override
  String get name => 'calendar_subscribe';

  @override
  SubActionResult? validate(Map<String, Object?> params) {
    // SSRF / HTTPS 护栏（安全关键，G6 前置）：Actor 内仍会复检一次。
    final guard = guardCalendarUrl(params['url']);
    if (!guard.ok) return _err(guard.code!, guard.message!);
    final refresh = params['refreshMin'];
    if (refresh != null) {
      final n = refresh is int ? refresh : int.tryParse('$refresh');
      if (n == null ||
          n < calendarMinRefreshMin ||
          n > calendarMaxRefreshMin) {
        return _err(
            'INVALID_ARGUMENT',
            'refreshMin 须为 $calendarMinRefreshMin~$calendarMaxRefreshMin 分钟：$refresh',
            suggestion: '默认 $calendarDefaultRefreshMin（12 小时）');
      }
    }
    return null;
  }

  @override
  String get description =>
      '订阅一个通用 / 公共在线 ICS 源（节假日、调休、节气、公共赛事等只读事件）。'
      '同 url 幂等；URL 须为调用方显式传入，服务端强制 HTTPS 并拒绝回环 / 私网地址（SSRF 护栏）。';

  @override
  String get paramSignature =>
      'calendar_subscribe(url: string, name?: string, refreshMin?: int) [必填: url]';

  @override
  Command buildCommand(Map<String, Object?> params) =>
      CalendarSubscribeCommand(params);
}

class _CalendarUnsubscribeSub extends _WriteSub {
  _CalendarUnsubscribeSub();

  @override
  String get name => 'calendar_unsubscribe';

  @override
  SubActionResult? validate(Map<String, Object?> params) {
    final feedId = params['feedId'];
    if (feedId is! String || feedId.trim().isEmpty) {
      return _err('MISSING_ARGUMENT', '缺少必填参数 feedId');
    }
    return null;
  }

  @override
  String get description =>
      '移除一个已订阅的 ICS 源（仅作用于已存在的 feedId，可幂等返回 success）；'
      '同时清空该源的缓存与上次同步时间。';

  @override
  String get paramSignature => 'calendar_unsubscribe(feedId: string) [必填: feedId]';

  @override
  Command buildCommand(Map<String, Object?> params) =>
      CalendarUnsubscribeCommand(params);
}

class _CalendarRefreshSub extends _WriteSub {
  _CalendarRefreshSub();

  @override
  String get name => 'calendar_refresh';

  @override
  String get description =>
      '强制即时同步指定订阅源（省略 feedId 则同步全部）。有最小刷新间隔与单源并发锁，'
      '防循环调用打爆网络；超时回退上次缓存并标 isCached。';

  @override
  String get paramSignature => 'calendar_refresh(feedId?: string) [全可选]';

  @override
  Command buildCommand(Map<String, Object?> params) =>
      CalendarRefreshCommand(params);
}

class _CalendarMarkerAddSub extends _WriteSub {
  _CalendarMarkerAddSub();

  @override
  String get name => 'calendar_marker_add';

  @override
  SubActionResult? validate(Map<String, Object?> params) {
    final originalDate = params['originalDate'];
    if (originalDate is! String || originalDate.trim().isEmpty) {
      return _err('MISSING_ARGUMENT', '缺少必填参数 originalDate');
    }
    final full = RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(originalDate.trim());
    final partial = RegExp(r'^\d{2}-\d{2}$').hasMatch(originalDate.trim());
    if (!full && !partial) {
      return _err('INVALID_ARGUMENT',
          'originalDate 须为 YYYY-MM-DD 或 MM-DD：$originalDate');
    }
    if (params['title'] is! String ||
        (params['title'] as String).trim().isEmpty) {
      return _err('MISSING_ARGUMENT', '缺少必填参数 title');
    }
    final category = params['category'];
    if (category is! String ||
        !const {'birthday', 'anniversary', 'milestone'}.contains(category)) {
      return _err('INVALID_ARGUMENT',
          'category 须为 birthday | anniversary | milestone：$category');
    }
    final baseYearRaw = params['baseYear'];
    if (baseYearRaw != null) {
      final n = baseYearRaw is int ? baseYearRaw : int.tryParse('$baseYearRaw');
      if (n == null) return _err('INVALID_ARGUMENT', 'baseYear 不是合法整数');
    }
    if (!full && baseYearRaw == null) {
      // 「originalDate 是年份单一真相源」：无年份格式必须显式补 baseYear。
      return _err('MISSING_ARGUMENT',
          'originalDate 为无年份格式（$originalDate），必须显式传 baseYear');
    }
    final leap = params['leapPolicy'];
    if (leap != null &&
        (leap is! String ||
            !const {'ignoreLeap', 'strictLeap', 'followRegular'}
                .contains(leap))) {
      return _err('INVALID_ARGUMENT',
          'leapPolicy 须为 ignoreLeap | strictLeap | followRegular：$leap');
    }
    return null;
  }

  @override
  String get description =>
      '添加重要事件标记（生日 / 纪念日 / 里程碑）。originalDate 为年份单一真相源：'
      '传完整 YYYY-MM-DD 时自动派生 baseYear；传无年份格式（如 "10-19"）须显式补 baseYear。'
      'isLunar 按农历对齐，闰月策略默认 ignoreLeap。';

  @override
  String get paramSignature =>
      'calendar_marker_add(originalDate: string, title: string, category: '
      '"birthday"|"anniversary"|"milestone", baseYear?: int, isAnnual?: bool, '
      'isLunar?: bool, leapPolicy?: "ignoreLeap"|"strictLeap"|"followRegular") '
      '[必填: originalDate, title, category]';

  @override
  Command buildCommand(Map<String, Object?> params) =>
      CalendarMarkerAddCommand(params);
}

class _CalendarMarkerDeleteSub extends _WriteSub {
  _CalendarMarkerDeleteSub();

  @override
  String get name => 'calendar_marker_delete';

  @override
  SubActionResult? validate(Map<String, Object?> params) {
    final markerId = params['markerId'];
    if (markerId is! String || markerId.trim().isEmpty) {
      return _err('MISSING_ARGUMENT', '缺少必填参数 markerId');
    }
    return null;
  }

  @override
  String get description =>
      '删除一条重要事件标记（仅作用于用户自有标记，Agent 无权越权删他人数据）。';

  @override
  String get paramSignature => 'calendar_marker_delete(markerId: string) [必填: markerId]';

  @override
  Command buildCommand(Map<String, Object?> params) =>
      CalendarMarkerDeleteCommand(params);
}

List<String>? _stringList(Object? raw) {
  if (raw is! List) return null;
  return raw.whereType<String>().toList();
}

/// `limit` 解析：缺省返回 0（= 不限）；非正整数返回错误文案（**不静默兜底为全量**）。
Object _capOf(Object? raw) {
  if (raw == null) return 0;
  final n = parseInt(raw);
  if (n == null || n < 1) return 'limit 须为正整数（缺省不限）';
  return n;
}

/// 可选字符串入参：空白串按缺失处理（不把 `''` 当有效城市 / 分类）。
String? _optStr(Object? raw) =>
    raw is String && raw.trim().isNotEmpty ? raw.trim() : null;