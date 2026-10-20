library;

import '../mcp/calendar_provider.dart';

/// 重要标记**读聚合层**（R5 落点）：UI 经此读标记，不直连 store。
///
/// **写端口（`CalendarMarkerWriter`）不在此暴露**——标记写必经 `CommandGateway`
/// （R1 / G3），写端口只给 service 层 Actor 持有。
class MarkerRepository {
  MarkerRepository({required this.store});

  final CalendarMarkerStore store;

  /// 列区间内的标记（含按分类过滤）。
  Future<List<CalendarMarker>> list({
    required String rangeStart,
    required String rangeEnd,
    String? category,
  }) =>
      store.list(
        rangeStart: rangeStart,
        rangeEnd: rangeEnd,
        category: category,
      );
}
