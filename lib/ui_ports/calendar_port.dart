library;

import 'dart:collection';

import '../mcp/calendar_provider.dart';
import '../repository/marker_repository.dart';
import '../service/calendar_permission_port.dart';
import '../tools/calendar/lunar_math.dart';

/// 日历单日「离线事实」（不依赖系统日历权限）：农历 / 节气 / 法定节假日。
///
/// 农历/节气来自纯内核 [LunarMath]（离线）；法定节假日来自注入的 [HolidayProvider]
/// ——默认空表，由装配注入 ICS 驱动的 [IcsHolidayProvider]（订阅名称含『节假日』
/// 的 ICS 源）。未订阅节假日源时 [holidayName] 为 null、[kind] 回落 normal——前端
/// 须按此降级，不可把"无节假日"误判为"异常"。
enum DayKind { normal, holiday, workday }

class DayFacts {
  const DayFacts({
    this.lunarLabel = '',
    this.solarTerm = '',
    this.holidayName,
    this.kind = DayKind.normal,
  });

  /// 农历角标（'八月' / '十五'）；逢节气日则为节气名（更值得看）。
  final String lunarLabel;

  /// 当天节气名（非空时 [lunarLabel] 已被其覆盖）。
  final String solarTerm;

  /// 法定节假日 / 调休补班名称（'元旦' / '春节调休' 等）；普通日为 null。
  final String? holidayName;

  /// 日性质：法定假 / 调休补班 / 普通。
  final DayKind kind;

  bool get isHoliday => kind == DayKind.holiday;
  bool get isWorkday => kind == DayKind.workday;
}

/// 日历事件视图（类型化）。
class EventView {
  const EventView({
    required this.title,
    required this.start,
    required this.end,
    required this.isAllDay,
    required this.source,
    this.location,
  });

  final String title;
  final String start;
  final String end;
  final bool isAllDay;

  /// 来源（`system` / `feed`）。
  final String source;

  final String? location;

  /// 展示用时间串（全天 → 「全天」；否则取 start 的时刻部分）。
  String get timeText {
    if (isAllDay) return '全天';
    final t = start.split('T').last;
    return t.length >= 5 ? t.substring(0, 5) : t;
  }
}

/// 重要标记视图（类型化）。
class MarkerView {
  const MarkerView({
    required this.id,
    required this.title,
    required this.originalDate,
    required this.category,
    required this.isAnnual,
    required this.isLunar,
  });

  final String id;
  final String title;

  /// 真实起始日期（`YYYY-MM-DD`；农历标记同格式）。
  final String originalDate;

  final String category;
  final bool isAnnual;
  final bool isLunar;
}

/// 日历快照视图（某一天的事件 + 区间内的重要标记 + 子源告警）。
class CalendarSnapshotView {
  const CalendarSnapshotView({
    required this.date,
    this.events = const <EventView>[],
    this.markers = const <MarkerView>[],
    this.warnings = const <String>[],
    this.errorCode,
    this.message,
  });

  /// 快照日期（`YYYY-MM-DD`）。
  final String date;

  final List<EventView> events;
  final List<MarkerView> markers;

  /// 子源告警（机器码 + 文案；显式透出，不静默）。
  final List<String> warnings;

  final String? errorCode;
  final String? message;
}

/// 日历权限申请结果视图（U12b；类型化，UI 不碰平台语义）。
class CalendarPermissionView {
  const CalendarPermissionView({
    required this.ok,
    this.granted = false,
    this.settingsOpened = false,
    this.errorCode,
    this.message,
    this.suggestion,
  });

  final bool ok;

  /// 已授权（可直接重试读取）。
  final bool granted;

  /// 已跳转系统设置页（提示用户去授予后返回重试）。
  final bool settingsOpened;

  final String? errorCode;
  final String? message;
  final String? suggestion;
}

/// 单日密度视图（月/年网格的格子数据：只计数，不携带事件详情）。
class DayDensityView {
  const DayDensityView({
    required this.date,
    this.eventCount = 0,
    this.markerCount = 0,
  });

  /// `YYYY-MM-DD`。
  final String date;

  final int eventCount;

  final int markerCount;

  bool get isEmpty => eventCount == 0 && markerCount == 0;
}

/// 区间总览视图（月/年视图数据源）：逐日密度 + 子源告警归并。
class CalendarRangeOverviewView {
  const CalendarRangeOverviewView({
    required this.rangeStart,
    required this.rangeEnd,
    required this.days,
    this.warnings = const <String>[],
    this.errorCode,
    this.message,
  });

  /// `YYYY-MM-DD`（含首尾）。
  final String rangeStart;
  final String rangeEnd;

  /// 区间内每一天一格（缺失事件源时为全 0 格——以 [errorCode] 区分真失败）。
  final List<DayDensityView> days;

  /// 子源告警（机器码 + 文案；显式透出，不静默）。
  final List<String> warnings;

  final String? errorCode;
  final String? message;
}

/// 日历 UI 适配层：事件与标记的**类型化**读取 + 运行时权限申请（U12b）。
///
/// 与 MCP 工具面**并列共享同一内核**：读的是同一批端口（`CalendarFeedProvider` /
/// `CalendarMarkerStore`），但出口不同——这里给类型化对象，那里给 LLM 文本信封。
class CalendarPort {
  const CalendarPort({
    required this.feeds,
    required this.markers,
    this.holidays = const EmptyHolidayProvider(),
    this.permission = const MethodChannelCalendarPermissionPort(),
  });

  final CalendarFeedProvider? feeds;
  final MarkerRepository markers;

  /// 法定节假日来源：默认空表，由装配注入 ICS 驱动的 [IcsHolidayProvider]
  /// （订阅名称含『节假日』的 ICS 源）；未订阅时回落空表（不编造放假/补班）。
  final HolidayProvider holidays;

  /// 运行时权限申请端口（平台细节收敛处，守 R3）。
  final CalendarPermissionPort permission;

  /// 单日离线事实（农历 / 节气 / 法定节假日）；纯本地，无需权限与源注入。
  ///
  /// 即便系统日历未授权、源未注入，本方法仍返回有效结果（农历/节假日属离线数据），
  /// 是日历只读页"未授权也不空"的兜底内容来源。
  DayFacts dayFacts(String date) {
    final parts = date.split('-');
    if (parts.length != 3) {
      return const DayFacts();
    }
    final y = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final d = int.tryParse(parts[2]);
    if (y == null || m == null || d == null) {
      return const DayFacts();
    }
    final dt = DateTime.utc(y, m, d);
    final lunar = LunarMath.describe(dt);
    final lunarLabel =
        lunar.solarTerm.isNotEmpty ? lunar.solarTerm : lunar.label;
    final entry = _holidayEntryOn(date);
    if (entry == null) {
      return DayFacts(lunarLabel: lunarLabel, solarTerm: lunar.solarTerm);
    }
    final kind =
        entry.type == 'workday' ? DayKind.workday : DayKind.holiday;
    return DayFacts(
      lunarLabel: lunarLabel,
      solarTerm: lunar.solarTerm,
      holidayName: entry.name,
      kind: kind,
    );
  }

  /// 整月离线事实（1..daysInMonth），供月网格一次性取，避免逐格调用。
  List<DayFacts> monthFacts(int year, int month) {
    final days = _daysInMonth(year, month);
    final out = <DayFacts>[];
    for (var d = 1; d <= days; d++) {
      out.add(dayFacts(_fmtDate(DateTime.utc(year, month, d))));
    }
    return out;
  }

  HolidayEntry? _holidayEntryOn(String date) {
    final hits = holidays.between(date, date);
    return hits.isEmpty ? null : hits.first;
  }

  static int _daysInMonth(int year, int month) {
    final next = month == 12
        ? DateTime.utc(year + 1, 1, 1)
        : DateTime.utc(year, month + 1, 1);
    return next.subtract(const Duration(days: 1)).day;
  }

  /// 取某天的日历快照（事件 + 重要标记）。
  Future<CalendarSnapshotView> snapshot({required String date}) async {
    final provider = feeds;
    if (provider == null) {
      return CalendarSnapshotView(
        date: date,
        errorCode: CalendarErr.sourceUnavailable,
        message: '未注入日历源',
      );
    }
    try {
      final result = await provider.query(
        rangeStart: date,
        rangeEnd: date,
        includeSystem: true,
      );
      final markerList = await markers.list(
        rangeStart: date,
        rangeEnd: date,
      );
      return CalendarSnapshotView(
        date: date,
        events: result.events.map(_toEventView).toList(growable: false),
        markers: markerList.map(_toMarkerView).toList(growable: false),
        warnings: result.warnings
            .map((w) => '${w['code']}：${w['message']}')
            .toList(growable: false),
      );
    } on CalendarFeedException catch (e) {
      return CalendarSnapshotView(
        date: date,
        errorCode: e.code,
        message: e.message,
      );
    }
  }

  /// 区间总览（月/年视图数据源）：逐日事件与标记密度。
  ///
  /// 事件查询受 C1 硬上限（`calendarMaxRangeDays` 90 天）约束，内部按上限
  /// 分片逐段查询并归并 warnings；标记为本地存储，整区间一次查。
  /// 事件按其 `start` 落日计数——跨多日的全天事件只计入起始日（v1 密度口径）。
  Future<CalendarRangeOverviewView> rangeOverview({
    required String rangeStart,
    required String rangeEnd,
  }) async {
    final provider = feeds;
    if (provider == null) {
      return CalendarRangeOverviewView(
        rangeStart: rangeStart,
        rangeEnd: rangeEnd,
        days: const <DayDensityView>[],
        errorCode: CalendarErr.sourceUnavailable,
        message: '未注入日历源',
      );
    }
    final DateTime start;
    final DateTime end;
    try {
      start = DateTime.parse(rangeStart);
      end = DateTime.parse(rangeEnd);
    } on FormatException {
      return CalendarRangeOverviewView(
        rangeStart: rangeStart,
        rangeEnd: rangeEnd,
        days: const <DayDensityView>[],
        errorCode: CalendarErr.parseFailed,
        message: '日期格式需为 YYYY-MM-DD',
      );
    }
    if (end.isBefore(start)) {
      return CalendarRangeOverviewView(
        rangeStart: rangeStart,
        rangeEnd: rangeEnd,
        days: const <DayDensityView>[],
        errorCode: CalendarErr.parseFailed,
        message: '区间终点早于起点',
      );
    }
    try {
      final counts = SplayTreeMap<String, List<int>>();
      final warnings = <String>[];
      var cursor = start;
      while (!cursor.isAfter(end)) {
        final chunkEndRaw = cursor.add(
          const Duration(days: calendarMaxRangeDays - 1),
        );
        final chunkEnd = chunkEndRaw.isAfter(end) ? end : chunkEndRaw;
        final fmtStart = _fmtDate(cursor);
        final fmtEnd = _fmtDate(chunkEnd);
        final result = await provider.query(
          rangeStart: fmtStart,
          rangeEnd: fmtEnd,
          includeSystem: true,
        );
        for (final e in result.events) {
          if (e.start.length < 10) continue;
          final day = e.start.substring(0, 10);
          if (day.compareTo(fmtStart) < 0 || day.compareTo(fmtEnd) > 0) {
            continue;
          }
          final bucket =
              counts.putIfAbsent(day, () => <int>[0, 0]);
          bucket[0] += 1;
        }
        for (final w in result.warnings) {
          warnings.add('${w['code']}：${w['message']}');
        }
        if (cursor.isAtSameMomentAs(chunkEnd)) break;
        cursor = chunkEnd.add(const Duration(days: 1));
      }
      final markerList = await markers.list(
        rangeStart: _fmtDate(start),
        rangeEnd: _fmtDate(end),
      );
      for (final m in markerList) {
        if (m.originalDate.length < 10) continue;
        counts
            .putIfAbsent(m.originalDate, () => <int>[0, 0])[1] += 1;
      }
      // 逐日补齐：区间内每一天一格（无事件的日 = 全 0 格）。
      final days = <DayDensityView>[];
      for (var d = start; !d.isAfter(end); d = d.add(const Duration(days: 1))) {
        final key = _fmtDate(d);
        final bucket = counts[key];
        days.add(
          DayDensityView(
            date: key,
            eventCount: bucket?[0] ?? 0,
            markerCount: bucket?[1] ?? 0,
          ),
        );
      }
      return CalendarRangeOverviewView(
        rangeStart: _fmtDate(start),
        rangeEnd: _fmtDate(end),
        days: days,
        warnings: List<String>.unmodifiable(warnings),
      );
    } on CalendarFeedException catch (e) {
      return CalendarRangeOverviewView(
        rangeStart: rangeStart,
        rangeEnd: rangeEnd,
        days: const <DayDensityView>[],
        errorCode: e.code,
        message: e.message,
      );
    }
  }

  static String _fmtDate(DateTime d) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)}';
  }

  /// 申请日历运行时权限（U12b）。
  ///
  /// fail-closed：平台故障转 [CalendarPermissionView] 失败态（带机器码），
  /// UI 展示可操作引导，不假装已授权。
  Future<CalendarPermissionView> requestPermission() async {
    try {
      final outcome = await permission.request();
      return CalendarPermissionView(
        ok: true,
        granted: outcome == CalendarPermissionOutcome.granted,
        settingsOpened: outcome == CalendarPermissionOutcome.settingsOpened,
      );
    } on CalendarFeedException catch (e) {
      return CalendarPermissionView(
        ok: false,
        errorCode: e.code,
        message: e.message,
        suggestion: e.suggestion,
      );
    }
  }

  static EventView _toEventView(CalendarEvent e) => EventView(
        title: e.title,
        start: e.start,
        end: e.end,
        isAllDay: e.isAllDay,
        source: e.source,
        location: e.location,
      );

  static MarkerView _toMarkerView(CalendarMarker m) => MarkerView(
        id: m.id,
        title: m.title,
        originalDate: m.originalDate,
        category: m.category,
        isAnnual: m.isAnnual,
        isLunar: m.isLunar,
      );
}
