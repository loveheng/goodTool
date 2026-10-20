// system_pim 领域网关适配层（P1d）：注册 product/calendar.md 定义的 **14 个原子动作**，
// action 名原样沿用能力文档，不改名、不自造（G1）——「文档表格第一列」与本文件
// `register` 列表可机械对账（单测已钉死）。
//
// 档位：5 个 W 档（subscribe / unsubscribe / refresh / marker_add / marker_delete，
// **只 buildCommand**，鉴权与派发由 `CategoryTool` 网关层统一执行——G3 / arch-guard R7）
// + 9 个 R 档。
//
// **落地进度（P1）**：3 个纯函数 R 档（`date_calc` / `date_diff` / `workdays_between`）
// 已真实实现（零外部依赖、确定性可测）；其余 6 个 R 档依赖 ICS 解析 / 农历引擎 /
// 时区库（P2），**源未注入时按 standards §1.2 fail-closed**，返回
// `ERR_CALENDAR_SOURCE_UNAVAILABLE`——不返回空列表假装「查到了但没有」。
library;

import 'dart:convert';

import '../action/calendar_commands.dart';
import '../action/command_gateway.dart';
import '../mcp/calendar_provider.dart';
import '../mcp/category_tool_face.dart';
import 'calendar/date_math.dart';
import 'calendar/holiday_table.dart';
import 'calendar/marker_math.dart';

/// **C1 防御**：查询跨度硬上限 90 天；超限报 `ERR_RANGE_TOO_WIDE`，
/// 不静默截断（避免 Agent 误以为拿到全量）。
const int calendarMaxRangeDays = 90;

/// 公开入口：构建 `system_pim` 领域网关（日历 + 标记 + 时间推演）。
///
/// [gateway] 为写门禁端口（W 档必经）；[feeds] / [markers] 为 P2 真实源，
/// 缺省 null ⇒ 相关 R 档 fail-closed；[holidays] 默认内置 **2026 年法定节假日表**
/// （数据逐字照录国务院办公厅通知，见 `calendar/holiday_table.dart`）。
CategoryTool buildSystemPimTool(
  CommandGateway gateway, {
  CalendarFeedProvider? feeds,
  CalendarMarkerStore? markers,
  HolidayProvider holidays = cnHolidayBundled,
}) {
  final cat = CategoryTool(
    'system_pim',
    '日历基准 + 重要事件标记 + 时间推演：区间事件查询（展开 RRULE）、订阅源管理、'
    '整月网格（恒定 42 格）、相对日期消歧、工作日与节假日推演、时区投影。'
    '定位是「看」与「算」，**不做独立会议 / 日程管理**（参会人、会议链接由独立日程 App 承接）。'
    '写操作（订阅 / 退订 / 刷新 / 增删标记）属用户委托写，须会话已鉴权。',
    gateway,
  );
  // R 档 · 已实现（纯函数）
  cat.register(_CalendarDateCalcSub(holidays));
  cat.register(_CalendarDateDiffSub(holidays));
  cat.register(_CalendarWorkdaysBetweenSub(holidays));
  // R 档 · 待 P2 真实源
  cat.register(_CalendarQuerySub(feeds));
  cat.register(_CalendarFeedsSub(feeds));
  cat.register(_CalendarMonthGridSub(markers, holidays));
  cat.register(_CalendarResolveDateSub());
  cat.register(_CalendarMarkerListSub(markers, holidays));
  cat.register(_CalendarTzConvertSub());
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

    final List<CalendarEvent> events;
    try {
      events = await provider.query(
        rangeStart: DateMath.fmt(start),
        rangeEnd: DateMath.fmt(end),
        timezone: params['timezone'] is String ? params['timezone'] as String : null,
        feedIds: _stringList(params['feedIds']),
      );
    } on CalendarFeedException catch (e) {
      // 源层机器码透出（区间超限 / 拉取失败 / 解析失败），不静默返空。
      return _err(e.code, e.message, suggestion: e.suggestion);
    }

    final take = cap == 0 ? events.length : cap;
    return _jsonSuccess(<String, Object?>{
      'success': true,
      'events': events.take(take).map((e) => e.toJson()).toList(),
      'hasMore': events.length > take,
      'timezone': 'UTC',
      'note': '系统日历源（source: system）尚未实现（P2-⑦）；当前仅返回已订阅的在线 ICS 源',
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
      '整月网格（恒定 42 格 = 6 行 × 7 列）：每格含是否工作日、'
      '节假日 / 调休补班 badge 与当日标记数，供 UI 绘制与整月自省。'
      'firstDayOfWeek 决定列起始（默认 1 = 周一），避免中 / 欧首日习惯差异导致整列错位；'
      '农历 / 节气角标待 P2-③ 农历引擎落地后补（该字段直接不出，不出 null 占位）。';

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
      'note': 'lunar / solar_term 角标待 P2-③ 农历引擎；badge 已覆盖节假日与调休补班',
    });
  }
}

class _CalendarResolveDateSub extends SubAction {
  @override
  String get name => 'calendar_resolve_date';

  @override
  String get description =>
      '相对日期消歧（纯函数）：把 "next_friday" / "today+3" / "q4_start" / '
      '"lunar:2026-08-15" / "mid_autumn" 等自然语言解析为确定日期，'
      '杜绝 LLM 自算幻觉。实现内不调用 DateTime.now()，基准日由入参注入。';

  @override
  String get paramSignature =>
      'calendar_resolve_date(expression: string, baseDate?: string, timezone?: string) '
      '[必填: expression]';

  @override
  Future<SubActionResult> execute(Map<String, Object?> params) async {
    if (params['expression'] is! String ||
        (params['expression'] as String).trim().isEmpty) {
      return _err('MISSING_ARGUMENT', '缺少必填参数 expression（日期表达式）');
    }
    return _unavailable('农历引擎与节日别名表（日期消歧）');
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
      '并给出倒计时天数与周年数；农历标记先对齐到对应公历日再算。'
      'daysRemaining 以 rangeStart 为基准日（不用系统当天，保证可重放）；'
      '平年 02-29 对齐 02-28 并标 approximate；农历标记暂标 lunarPending 不展开。';

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
      'note': 'lunarPending=true 的标记为农历标记，周年对齐待 P2-③ 农历引擎落地',
    });
  }
}

class _CalendarTzConvertSub extends SubAction {
  @override
  String get name => 'calendar_tz_convert';

  @override
  String get description =>
      '时区投影 / 世界时钟：把某时刻从 fromTz 投影到 toTz，返回目标时间、'
      'offset 与 DST 是否生效，避免 Agent 自算夏令时。';

  @override
  String get paramSignature =>
      'calendar_tz_convert(datetime: string, fromTz: string, toTz: string) '
      '[必填: datetime, fromTz, toTz]';

  @override
  Future<SubActionResult> execute(Map<String, Object?> params) async {
    if (params['fromTz'] is! String || params['toTz'] is! String) {
      return _err('MISSING_ARGUMENT', '缺少必填参数 fromTz / toTz（IANA 时区名）');
    }
    return _unavailable('时区库（package:timezone 待引入）');
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