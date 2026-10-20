// ICS 订阅源真实实现（P2-④ 步骤 B）：`CalendarFeedProvider` 端口的 service 层实现。
//
// 落点依据 standards §1.3「新平台能力 → service + Provider 端口」：网络与缓存住本层，
// 解析 / 展开 / 脱敏在**内核**（`lib/mcp/ics_parser.dart` / `pii_mask.dart`），
// tools 层只见端口（arch-guard R4）。
//
// 逐条落实 calendar.md：
//   - C3 传输层：`autoUncompress`（和风那种 gzip 陷阱同理，ICS 站点也常启用）、
//     重定向上限 [icsMaxRedirects] 跳、请求超时 10s、失败**回退上次缓存**并标 `isCached`
//   - C1 区间上限 90 天（防御性复检；工具层已拦）
//   - G1 幂等 / G3 缓存生命周期：`unsubscribe` 清缓存由 Actor 负责；本层负责读写
//   - G2 频控：refresh 最小间隔 30s（KV 记时间戳）+ 单 feed 串行
//   - D1 固定排序 `start → uid`；G4 事件主键 `feedId:uid` 复合键（跨源防碰撞）
//   - E 拍板脱敏：`maskPii` 默认开 PII_MASK_PHONE_EMAIL
// 系统日历源（`source: system`）已随 P2-⑦ 落地：合并见
// `composite_calendar_provider.dart`；本类只负责 ICS 单路。
// TZID / 浮动 ICS 时间按「名义 UTC」不解释 IANA 规则（P2-② 引入 package:timezone 后修正）。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../mcp/calendar_provider.dart';
import '../mcp/ics_parser.dart';
import '../mcp/pii_mask.dart';
import '../mcp/settings_keys.dart';
import '../mcp/settings_kv.dart';

/// 重定向上限（C3）。
const int icsMaxRedirects = 3;

/// 拉取超时（C3：超时回退上次缓存并标 `isCached`）。
const Duration icsRequestTimeout = Duration(seconds: 10);

/// refresh 最小间隔（G2 频控，秒）。
const int icsRefreshMinIntervalSec = 30;

/// 缓存键前缀与键名常量已上移内核
/// （`kIcsBodyPrefix` / `kIcsSyncPrefix` / `kCalendarFeedsKey`，见 calendar_provider.dart）。

class IcsFeedProvider implements CalendarFeedProvider {
  IcsFeedProvider(
    this._kv, {
    this.client,
    this.host,
    this.port,
    this.scheme = 'https',
  });

  final SettingsKv _kv;
  final HttpClient? client;
  final String? host;
  final int? port;
  final String scheme;

  @override
  Future<List<CalendarFeed>> feeds() async {
    final raw = await _kv.settingsGet(kCalendarFeedsKey);
    if (raw == null || raw.trim().isEmpty) return <CalendarFeed>[];
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return <CalendarFeed>[];
    }
    if (decoded is! List) return <CalendarFeed>[];
    final entries = decoded.whereType<Map<String, Object?>>().toList();

    // 同步时间逐源读（map 回调内不能 await）。
    final syncTimes = <String, DateTime?>{};
    for (final m in entries) {
      final id = (m['id'] as String?) ?? '';
      syncTimes[id] = await _syncTime(id);
    }
    return entries.map((m) {
      final id = (m['id'] as String?) ?? '';
      return CalendarFeed(
        id: id,
        name: (m['name'] as String?) ?? '',
        url: (m['url'] as String?) ?? '',
        refreshMin: (m['refreshMin'] as num?)?.toInt() ?? calendarDefaultRefreshMin,
        lastSyncTime: (m['lastSyncTime'] as String?) ??
            syncTimes[id]?.toIso8601String(),
        status: (m['status'] as String?) ?? 'ok',
      );
    }).toList();
  }

  @override
  Future<CalendarQueryResult> query({
    required String rangeStart,
    required String rangeEnd,
    String? timezone,
    List<String>? feedIds,
    bool includeSystem = true,
  }) async {
    final from = _parseDay(rangeStart);
    final to = _parseDay(rangeEnd);
    if (from == null || to == null) {
      throw const CalendarFeedException(
          'MISSING_ARGUMENT', 'rangeStart / rangeEnd 须为合法 YYYY-MM-DD');
    }
    // C1 防御性复检（工具层已拦；源层是最后一道闸）。
    if (to.difference(from).inDays > calendarMaxRangeDays) {
      throw CalendarFeedException(CalendarErr.rangeTooWide,
          '查询跨度超过上限 $calendarMaxRangeDays 天（YYYY-MM-DD）',
          suggestion: '缩小区间后重试');
    }

    final all = await feeds();
    final selected = feedIds == null || feedIds.isEmpty
        ? all
        : all.where((f) => feedIds.contains(f.id)).toList();

    // U12a：脱敏开关态每次查询现读（`'0'` = 用户显式关闭；未设置 = 开，
    // 保护性缺省对齐 E 拍板）。用户改开关即时生效，无需重建源。
    final mask =
        piiMaskEnabledBy(await _kv.settingsGet(SettingsKeys.privacyMaskPii));

    final out = <CalendarEvent>[];
    for (final feed in selected) {
      final body = await _bodyOf(feed.id, feed.url, allowStale: true);
      if (body == null) continue; // 无缓存且拉取失败：该源跳过（上层出参可见缺失）
      final parsed = IcsParser.parse(body.text);
      for (final i in IcsExpander.expand(
        parsed.events,
        from,
        // 区间含末日：ICS 展开按 [from, to+1d) 过滤，避免全天事件丢最后一天。
        to.add(const Duration(days: 1)),
      )) {
        out.add(_toEvent(feed, i, cached: body.cached, mask: mask));
      }
    }

    // D1 固定排序 start → uid（复合键已含 feedId，跨源稳定）。
    out.sort((a, b) {
      final c = a.start.compareTo(b.start);
      return c != 0 ? c : a.uid.compareTo(b.uid);
    });
    return CalendarQueryResult(List.unmodifiable(out));
  }

  @override
  Future<int> refresh({String? feedId}) async {
    final all = await feeds();
    if (feedId != null && feedId.isNotEmpty) {
      if (!all.any((f) => f.id == feedId)) {
        throw CalendarFeedException(
            CalendarErr.feedNotFound, 'feedId 不存在：$feedId',
            suggestion: '先用 calendar_feeds 列出可用源');
      }
    }
    final targets =
        feedId == null || feedId.isEmpty ? all : all.where((f) => f.id == feedId);

    // G2 频控：无缓存 + 距上次刷新 < 最小间隔 → 拒绝（防 Agent 循环调用打爆网络）。
    final now = DateTime.now().toUtc();
    for (final f in targets) {
      final last = await _syncTime(f.id);
      if (last != null &&
          now.difference(last).inSeconds < icsRefreshMinIntervalSec) {
        throw CalendarFeedException(CalendarErr.rateLimited,
            '刷新过于频繁：距上次同步不足 $icsRefreshMinIntervalSec 秒',
            suggestion: '订阅源按 refreshMin 周期自动刷新，无需手动触发');
      }
    }

    var ok = 0;
    for (final f in targets) {
      // 串行刷新（单源并发锁的最简形式：本 isolate 内不并发）。
      final body = await _fetch(f.url);
      await _kv.settingsSet(<String, String>{'$kIcsBodyPrefix${f.id}': body});
      await _kv.settingsSet(<String, String>{
        '$kIcsSyncPrefix${f.id}': now.toIso8601String()
      });
      ok++;
    }
    return ok;
  }

  // ---------------------------------------------------------------------------
  // 缓存与传输
  // ---------------------------------------------------------------------------

  /// 取 ICS 原文：缓存优先（allowStale）；无缓存则网络拉取，失败回退缓存或抛错。
  ///
  /// 返回 `(text, cached)`——`cached=true` 表示命中缓存（含拉取失败时的陈旧回退），
  /// 由调用方写进 CalendarEvent.isCached，**不把陈旧数据混充实时**。
  Future<({String text, bool cached})?> _bodyOf(String feedId, String url,
      {required bool allowStale}) async {
    final cached = await _kv.settingsGet('$kIcsBodyPrefix$feedId');
    if (cached != null && cached.isNotEmpty && allowStale) {
      return (text: cached, cached: true);
    }
    try {
      final body = await _fetch(url);
      await _kv.settingsSet(<String, String>{'$kIcsBodyPrefix$feedId': body});
      return (text: body, cached: false);
    } on CalendarFeedException {
      if (cached != null && cached.isNotEmpty) return (text: cached, cached: true);
      rethrow;
    }
  }

  Future<String> _fetch(String url) async {
    final external = client != null;
    // 局部名 http：避免与同名字段 client 互相遮蔽（Dart 不允许前向引用遮蔽名）。
    final http = client ?? (HttpClient()..autoUncompress = true);
    try {
      var current = _rewriteUrl(url);
      var hops = 0;
      while (true) {
        final req = await http
            .getUrl(current)
            .timeout(icsRequestTimeout);
        final res = await req.close().timeout(icsRequestTimeout);
        if (res.statusCode == HttpStatus.movedPermanently ||
            res.statusCode == HttpStatus.found ||
            res.statusCode == HttpStatus.seeOther ||
            res.statusCode == HttpStatus.temporaryRedirect) {
          final loc = res.headers.value(HttpHeaders.locationHeader);
          await res.drain<void>();
          if (loc == null || hops >= icsMaxRedirects) {
            throw CalendarFeedException(
                CalendarErr.network, '重定向缺失或超过 $icsMaxRedirects 跳上限',
                suggestion: '检查订阅地址稳定性，或换一个直链');
          }
          current = current.resolve(loc);
          hops++;
          continue;
        }
        if (res.statusCode != HttpStatus.ok) {
          await res.drain<void>();
          throw CalendarFeedException(
              CalendarErr.network, 'ICS 拉取失败：HTTP ${res.statusCode}',
              suggestion: '检查地址可达性；超时会自动回退上次缓存');
        }
        final text = await res
            .transform(utf8.decoder)
            .fold<String>('', (a, b) => '$a$b')
            .timeout(icsRequestTimeout);
        return text;
      }
    } on CalendarFeedException {
      rethrow;
    } on SocketException catch (e) {
      throw CalendarFeedException(CalendarErr.network, '网络不可达：${e.message}',
          suggestion: '检查网络连接后重试');
    } on TimeoutException {
      throw const CalendarFeedException(
          CalendarErr.network, 'ICS 拉取超时（10s）',
          suggestion: '已自动回退上次缓存（如有）');
    } on HttpException catch (e) {
      throw CalendarFeedException(
          CalendarErr.network, 'HTTP 层失败：${e.message}',
          suggestion: '检查网络连接后重试');
    } finally {
      if (!external) client?.close(force: true);
    }
  }

  /// 测试注入口：把生产地址改写到本地 server。
  Uri _rewriteUrl(String url) {
    final parsed = Uri.parse(url);
    if (host == null) return parsed;
    return Uri(
      scheme: scheme,
      host: host,
      port: port ?? parsed.port,
      path: parsed.path,
      query: parsed.query,
    );
  }

  Future<DateTime?> _syncTime(String feedId) async {
    final raw = await _kv.settingsGet('$kIcsSyncPrefix$feedId');
    if (raw == null || raw.isEmpty) return null;
    return DateTime.tryParse(raw)?.toUtc();
  }

  // ---------------------------------------------------------------------------
  // 转换：实例 → CalendarEvent（脱敏 + 复合键）
  // ---------------------------------------------------------------------------

  CalendarEvent _toEvent(CalendarFeed feed, IcsInstance inst,
      {required bool cached, required bool mask}) {
    final e = inst.event;
    return CalendarEvent(
      // G4：跨源 UID 可能碰撞，事件主键用 feedId:uid 复合键。
      uid: '${feed.id}:${e.uid}',
      title: e.summary ?? '(无标题)',
      start: _iso(inst.start, e.isAllDay),
      end: _iso(inst.end, e.isAllDay),
      isAllDay: e.isAllDay,
      // U12a：开关关 = 原文透出（用户显式选择）；开/未设置 = maskPii 默认档。
      location: mask ? maskPii(e.location) : e.location,
      description: mask ? maskPii(e.description) : e.description,
      source: 'feed',
      feedId: feed.id,
      feedName: feed.name,
      timezone: null,
      isCached: cached,
    );
  }

  static String _iso(DateTime dt, bool isAllDay) {
    final d = dt.toUtc();
    if (isAllDay) {
      return '${d.year.toString().padLeft(4, '0')}-'
          '${d.month.toString().padLeft(2, '0')}-'
          '${d.day.toString().padLeft(2, '0')}';
    }
    final hh = d.hour.toString().padLeft(2, '0');
    final mm = d.minute.toString().padLeft(2, '0');
    final ss = d.second.toString().padLeft(2, '0');
    return '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}T$hh:$mm:${ss}Z';
  }

  static DateTime? _parseDay(String raw) {
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(raw.trim());
    if (m == null) return null;
    final dt = DateTime.utc(
        int.parse(m.group(1)!), int.parse(m.group(2)!), int.parse(m.group(3)!));
    if (dt.year != int.parse(m.group(1)!)) return null;
    return dt;
  }
}
