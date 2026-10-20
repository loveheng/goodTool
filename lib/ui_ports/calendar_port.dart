library;

import '../mcp/calendar_provider.dart';
import '../repository/marker_repository.dart';

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

/// 日历 UI 适配层：事件与标记的**类型化**读取。
///
/// 与 MCP 工具面**并列共享同一内核**：读的是同一批端口（`CalendarFeedProvider` /
/// `CalendarMarkerStore`），但出口不同——这里给类型化对象，那里给 LLM 文本信封。
class CalendarPort {
  const CalendarPort({
    required this.feeds,
    required this.markers,
  });

  final CalendarFeedProvider? feeds;
  final MarkerRepository markers;

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
