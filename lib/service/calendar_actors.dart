// 日历 W 档命令执行体（P2-⑤）：service 层，由**装配件**登记进 CommandGateway。
//
// 纪律（G3 / arch-guard R7 / standards §2.3）：本文件是唯一持有写端口
// （[CalendarMarkerWriter] / feed 列表）的一侧；鉴权由 `CategoryTool` 网关层在
// 派发前执行，本文件不再做鉴权，只做**业务规则 + 存储**。
//
// 输出约定（「Actor 信封」）：首条 text 统一为 JSON 信封
// `{'success': bool, ...}`；`success: false` 时附 `error: {code, message, suggestion?}`
// （D3 结构化错误，禁散文）。`CategoryTool` 据此信封的 `success` 派生 MCP `isError`
// （见 category_tool_face.dart 的 fromActor），保证「业务失败 = isError:true」。
library;

import 'dart:convert';
import 'dart:math';

import '../action/command_gateway.dart';
import '../mcp/calendar_provider.dart';
import '../mcp/settings_kv.dart';

/// feed 列表持久化键与刷新周期常量已上移内核
/// （`kCalendarFeedsKey` / `calendarMinRefreshMin` 等，见 calendar_provider.dart）。

/// 在 [gateway] 登记日历 5 个 W 档命令（命令名 = action 名）。
///
/// 供装配件在 P2-⑧ 调用；[markers] 为标记写端口，[kv] 供 feed 列表与频控时间戳读写，
/// [feeds] 为事件源（`refresh` 的真实同步入口；缺省 null ⇒ fail-closed）。
void registerCalendarActors(
  CommandGateway gateway, {
  required SettingsKv kv,
  required CalendarMarkerWriter markers,
  CalendarFeedProvider? feeds,
}) {
  gateway.register('calendar_subscribe',
      (cmd) => _subscribe(kv, cmd.payload));
  gateway.register('calendar_unsubscribe',
      (cmd) => _unsubscribe(kv, cmd.payload));
  gateway.register('calendar_refresh',
      (cmd) => _refresh(feeds, cmd.payload));
  gateway.register('calendar_marker_add',
      (cmd) => _markerAdd(markers, cmd.payload));
  gateway.register('calendar_marker_delete',
      (cmd) => _markerDelete(markers, cmd.payload));
}

// ---------------------------------------------------------------------------
// 订阅源
// ---------------------------------------------------------------------------

Future<List<Map<String, Object?>>> _subscribe(
  SettingsKv kv,
  Map<String, Object?> payload,
) async {
  // 防御性复检：装配路径若绕过子操作 validate，此处仍须拦（SSRF 是安全关键，
  // 宁可双查也不漏）。
  final guard = guardCalendarUrl(payload['url']);
  if (!guard.ok) {
    return _fail(guard.code!, guard.message!);
  }
  final uri = guard.uri!;

  final refresh = payload['refreshMin'];
  if (refresh != null) {
    final n = refresh is int ? refresh : int.tryParse(refresh.toString());
    if (n == null ||
        n < calendarMinRefreshMin ||
        n > calendarMaxRefreshMin) {
      return _fail(
          'INVALID_ARGUMENT',
          'refreshMin 须为 $calendarMinRefreshMin~$calendarMaxRefreshMin 分钟：$refresh',
          suggestion: '默认 $calendarDefaultRefreshMin（12 小时）；填 0 表示仅手动刷新');
    }
  }

  final feeds = await _loadFeeds(kv);
  final url = uri.toString();
  // G1 幂等：同 url 不建重复源，返回已有 feedId。
  for (final f in feeds) {
    if (f.url == url) {
      return _ok(<String, Object?>{
        'feedId': f.id,
        'idempotent': true,
        'url': f.url,
        'name': f.name,
        'refreshMin': f.refreshMin,
      });
    }
  }

  final rawName = payload['name'];
  final name = rawName is String && rawName.trim().isNotEmpty
      ? rawName.trim()
      : uri.host;
  final refreshMin = refresh is int
      ? refresh
      : (refresh == null ? calendarDefaultRefreshMin : int.parse('$refresh'));
  final feed = CalendarFeed(
    id: _newFeedId(),
    name: name,
    url: url,
    refreshMin: refreshMin,
  );
  await _saveFeeds(kv, <CalendarFeed>[...feeds, feed]);
  return _ok(<String, Object?>{
    'feedId': feed.id,
    'url': feed.url,
    'name': feed.name,
    'refreshMin': feed.refreshMin,
  });
}

Future<List<Map<String, Object?>>> _unsubscribe(
  SettingsKv kv,
  Map<String, Object?> payload,
) async {
  final feedId = payload['feedId'];
  if (feedId is! String || feedId.trim().isEmpty) {
    return _fail('MISSING_ARGUMENT', '缺少必填参数 feedId');
  }
  final feeds = await _loadFeeds(kv);
  final before = feeds.length;
  feeds.removeWhere((f) => f.id == feedId);
  if (feeds.length == before) {
    // G1：对不存在的 feedId 明确错误（Agent 无权凭空操作）
    return _fail(CalendarErr.feedNotFound, 'feedId 不存在：$feedId',
        suggestion: '先用 calendar_feeds 列出可用源');
  }
  await _saveFeeds(kv, feeds);
  // G3 缓存生命周期：退订必须清该 feedId 的 ICS 缓存与同步时间。
  await kv.settingsSet(<String, String>{
    '$kIcsBodyPrefix$feedId': '',
    '$kIcsSyncPrefix$feedId': '',
  });
  return _ok(<String, Object?>{'feedId': feedId});
}

Future<List<Map<String, Object?>>> _refresh(
  CalendarFeedProvider? feeds,
  Map<String, Object?> payload,
) async {
  final provider = feeds;
  if (provider == null) {
    // fail-closed：没有真实源时不假装同步成功（success:true 会让 Agent 以为数据已更新）。
    return _fail(
        CalendarErr.sourceUnavailable,
        '订阅源同步（ICS 拉取与解析）尚未接入',
        suggestion: '装配 IcsFeedProvider 后本命令生效；查询请用 calendar_query');
  }
  try {
    final feedId = payload['feedId'] is String ? payload['feedId'] as String : null;
    final updated = await provider.refresh(feedId: feedId);
    return _ok(<String, Object?>{'updatedCount': updated});
  } on CalendarFeedException catch (e) {
    return _fail(e.code, e.message, suggestion: e.suggestion);
  }
}

// ---------------------------------------------------------------------------
// 重要事件标记
// ---------------------------------------------------------------------------

Future<List<Map<String, Object?>>> _markerAdd(
  CalendarMarkerWriter markers,
  Map<String, Object?> payload,
) async {
  final originalDate = payload['originalDate'];
  final title = payload['title'];
  final category = payload['category'];
  if (originalDate is! String || originalDate.trim().isEmpty) {
    return _fail('MISSING_ARGUMENT', '缺少必填参数 originalDate');
  }
  if (title is! String || title.trim().isEmpty) {
    return _fail('MISSING_ARGUMENT', '缺少必填参数 title');
  }
  if (category is! String ||
      !const {'birthday', 'anniversary', 'milestone'}.contains(category)) {
    return _fail('INVALID_ARGUMENT',
        'category 须为 birthday | anniversary | milestone：$category');
  }
  final leapPolicy = payload['leapPolicy'] ?? 'ignoreLeap';
  if (leapPolicy is! String ||
      !const {'ignoreLeap', 'strictLeap', 'followRegular'}
          .contains(leapPolicy)) {
    return _fail('INVALID_ARGUMENT',
        'leapPolicy 须为 ignoreLeap | strictLeap | followRegular：$leapPolicy');
  }

  final baseYear = payload['baseYear'] == null
      ? null
      : (payload['baseYear'] is int
          ? payload['baseYear'] as int
          : int.tryParse(payload['baseYear'].toString()));
  if (payload['baseYear'] != null && baseYear == null) {
    return _fail('INVALID_ARGUMENT', 'baseYear 不是合法整数');
  }
  // originalDate 无年份（MM-DD）时必须显式 baseYear（「年份单一真相源」）。
  final fullDate = RegExp(r'^\d{4}-\d{2}-\d{2}$')
      .hasMatch(originalDate.trim());
  if (!fullDate && baseYear == null) {
    return _fail(
        'MISSING_ARGUMENT',
        'originalDate 为无年份格式（$originalDate），必须显式传 baseYear');
  }

  final id = await markers.addMarker(
    originalDate: originalDate,
    title: title.trim(),
    category: category,
    baseYear: baseYear,
    isAnnual: payload['isAnnual'] == null
        ? true
        : payload['isAnnual'] == true ||
            payload['isAnnual'].toString().toLowerCase() == 'true',
    isLunar: payload['isLunar'] == true ||
        payload['isLunar'].toString().toLowerCase() == 'true',
    leapPolicy: leapPolicy,
  );
  return _ok(<String, Object?>{
    'markerId': id,
    'title': title.trim(),
    'category': category,
  });
}

Future<List<Map<String, Object?>>> _markerDelete(
  CalendarMarkerWriter markers,
  Map<String, Object?> payload,
) async {
  final markerId = payload['markerId'];
  if (markerId is! String || markerId.trim().isEmpty) {
    return _fail('MISSING_ARGUMENT', '缺少必填参数 markerId');
  }
  final deleted = await markers.deleteMarker(markerId);
  if (!deleted) {
    return _fail('ERR_MARKER_NOT_FOUND', 'markerId 不存在：$markerId',
        suggestion: '先用 calendar_marker_list 查询区间内标记');
  }
  return _ok(<String, Object?>{'markerId': markerId});
}

// ---------------------------------------------------------------------------
// feed 列表持久化（SettingsKv，JSON 数组）
// ---------------------------------------------------------------------------

Future<List<CalendarFeed>> _loadFeeds(SettingsKv kv) async {
  final raw = await kv.settingsGet(kCalendarFeedsKey);
  if (raw == null || raw.trim().isEmpty) return <CalendarFeed>[];
  final Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } on FormatException {
    return <CalendarFeed>[]; // 损坏数据按空处理（下一次写入即覆盖修复）
  }
  if (decoded is! List) return <CalendarFeed>[];
  return decoded.whereType<Map<String, Object?>>().map((m) {
    return CalendarFeed(
      id: (m['id'] as String?) ?? '',
      name: (m['name'] as String?) ?? '',
      url: (m['url'] as String?) ?? '',
      refreshMin: (m['refreshMin'] as num?)?.toInt() ?? calendarDefaultRefreshMin,
      lastSyncTime: m['lastSyncTime'] as String?,
      status: (m['status'] as String?) ?? 'ok',
    );
  }).toList();
}

Future<void> _saveFeeds(SettingsKv kv, List<CalendarFeed> feeds) async {
  final raw = jsonEncode(feeds.map((f) => f.toJson()).toList());
  await kv.settingsSet(<String, String>{kCalendarFeedsKey: raw});
}

String _newFeedId() =>
    'feed_${Random.secure().nextInt(1 << 32).toRadixString(16).padLeft(8, '0')}';

// ---------------------------------------------------------------------------
// Actor 信封
// ---------------------------------------------------------------------------

List<Map<String, Object?>> _ok(Map<String, Object?> body) => <Map<String, Object?>>[
      {
        'type': 'text',
        'text': jsonEncode(<String, Object?>{'success': true, ...body}),
      }
    ];

List<Map<String, Object?>> _fail(String code, String message,
        {String? suggestion}) =>
    <Map<String, Object?>>[
      {
        'type': 'text',
        'text': jsonEncode(<String, Object?>{
          'success': false,
          'error': <String, Object?>{
            'code': code,
            'message': message,
            'suggestion': ?suggestion,
          },
        }),
      }
    ];
