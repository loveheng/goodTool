// 组合日历源（P2-⑦ source: system）：`CalendarFeedProvider` 的合并实现。
//
// ICS 订阅源（[IcsFeedProvider]）与系统日历（[SystemCalendarPort]）双路合并：
//   - D1 固定排序 `start → uid`（合并后统一排序，跨源可重放）；
//   - G4 复合键：系统源事件 uid 统一加 `system:` 前缀（跨源防碰撞，同 ICS 口径）；
//   - E 拍板脱敏：系统源 location / description 复用 `maskPii`（与 ICS 路同口径）；
//   - **部分失败不静默**：系统源失败（未授权 / 引擎缺位）不拖垮 ICS 结果，
//     以 `warnings`（机器码 + 文案）显式透出——不静默返空，也不假装查到。
//
// 落点依据 standards §1.3：合并编排住 service 层，内核只见端口（R4）。
//
// U12a：脱敏开关（`privacy_mask_pii`）经 [maskPiiEnabled] 注入（读 KV 的闭包）——
// 本类不持 KV（KV 归 ICS 源），用注入保持「合并编排不碰存储」；缺省 null = 开
// （保护性缺省，与 ICS 路 `piiMaskEnabledBy` 同语义）。
library;

import '../mcp/calendar_provider.dart';
import '../mcp/pii_mask.dart';

/// 系统日历源在 feedId 命名空间中的保留 id（calendar_feeds 可见）。
const String kSystemCalendarFeedId = 'system';

class CompositeCalendarProvider implements CalendarFeedProvider {
  CompositeCalendarProvider(
    this._ics, {
    this.system,
    this._maskPiiEnabled,
  });

  final CalendarFeedProvider _ics;

  /// null = 系统源未注入（query 出 ERR_CALENDAR_SOURCE_UNAVAILABLE warning，
  /// fail-closed 不静默降级）。
  final SystemCalendarPort? system;

  /// 脱敏开关解析（U12a；null = 开，保护性缺省）。
  final Future<bool> Function()? _maskPiiEnabled;

  @override
  Future<CalendarQueryResult> query({
    required String rangeStart,
    required String rangeEnd,
    String? timezone,
    List<String>? feedIds,
    bool includeSystem = true,
  }) async {
    final wantedSystem =
        feedIds != null && feedIds.contains(kSystemCalendarFeedId);
    final icsOnlyIds =
        feedIds?.where((f) => f != kSystemCalendarFeedId).toList();
    // feedIds 显式点名（非空且不含 system）= 不要系统源；includeSystem=false 硬开关同效。
    final querySystem = includeSystem &&
        (feedIds == null || feedIds.isEmpty || wantedSystem);

    final warnings = <Map<String, Object?>>[];
    if (includeSystem && system == null) {
      warnings.add(_warn(CalendarErr.sourceUnavailable, '系统日历源未注入'));
    }
    final icsResult = await _ics.query(
      rangeStart: rangeStart,
      rangeEnd: rangeEnd,
      timezone: timezone,
      feedIds: icsOnlyIds,
      includeSystem: false,
    );
    warnings.addAll(icsResult.warnings);
    final out = <CalendarEvent>[...icsResult.events];

    final port = system;
    if (querySystem && port != null) {
      try {
        final raw =
            await port.readEvents(rangeStart: rangeStart, rangeEnd: rangeEnd);
        // U12a：系统路与 ICS 路同一开关语义（每次查询现读；null 解析器 = 开）。
        final mask = _maskPiiEnabled == null
            ? true
            : await _maskPiiEnabled();
        out.addAll(raw.map((r) => _toEvent(r, mask: mask)));
      } on CalendarFeedException catch (e) {
        warnings.add(_warn(e.code, e.message, suggestion: e.suggestion));
      }
    }

    // D1 固定排序 start → uid（合并后统一排序，跨源可重放）。
    out.sort((a, b) {
      final c = a.start.compareTo(b.start);
      return c != 0 ? c : a.uid.compareTo(b.uid);
    });
    return CalendarQueryResult(List.unmodifiable(out),
        warnings: List.unmodifiable(warnings));
  }

  /// 子源失败警告；`suggestion` 为自愈指引（值空感知出键——空则整项省略，见
  /// lessons「空值感知元素修饰的是值不是键」）。
  Map<String, Object?> _warn(String code, String message, {String? suggestion}) =>
      <String, Object?>{
        'source': kSystemCalendarFeedId,
        'code': code,
        'message': message,
        'suggestion': ?suggestion,
      };

  @override
  Future<List<CalendarFeed>> feeds() async {
    final icsFeeds = await _ics.feeds();
    if (system == null) return icsFeeds;
    return List.unmodifiable(<CalendarFeed>[
      ...icsFeeds,
      const CalendarFeed(
        id: kSystemCalendarFeedId,
        name: '系统日历',
        url: 'local://system',
        refreshMin: 0,
        status: 'ok',
      ),
    ]);
  }

  @override
  Future<int> refresh({String? feedId}) async {
    // 系统日历实时读取，无刷新语义：显式点名 'system' → 刷新 0 源（不冒充成功）。
    if (feedId == kSystemCalendarFeedId) return 0;
    return _ics.refresh(feedId: feedId);
  }

  /// 原始事件 → CalendarEvent（脱敏 + G4 复合键 + D2 视图字段）。
  ///
  /// 同一事件跨天 RRULE 在平台层回传多实例，uid 需带 start 消重：`system:<uid>:<start>`。
  CalendarEvent _toEvent(SystemCalendarRawEvent r, {required bool mask}) =>
      CalendarEvent(
        uid: '$kSystemCalendarFeedId:${r.uid}:${r.start}',
        title: r.title,
        start: r.start,
        end: r.end,
        isAllDay: r.isAllDay,
        // U12a：开关关 = 原文透出；开/未设置 = maskPii 默认档。
        location: mask ? maskPii(r.location) : r.location,
        description: mask ? maskPii(r.description) : r.description,
        source: kSystemCalendarFeedId,
        feedId: kSystemCalendarFeedId,
        feedName: r.calendarName,
        isCached: false,
      );
}
