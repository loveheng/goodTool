// P2-④ 步骤 B：ICS 源真实链路测试（本地 HttpServer + subscribe Actor + query + refresh）。
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:good_template/action/command_gateway.dart';
import 'package:good_template/mcp/calendar_provider.dart';
import 'package:good_template/mcp/category_tool_face.dart';
import 'package:good_template/mcp/settings_kv.dart';
import 'package:good_template/ports.dart';
import 'package:good_template/service/calendar_actors.dart';
import 'package:good_template/service/ics_feed_provider.dart';
import 'package:good_template/service/marker_store.dart';
import 'package:good_template/tools/system_pim_tool.dart';

void main() {
  late HttpServer server;
  late SettingsKv kv;
  late CommandGateway gateway;
  late CategoryTool tool;
  late IcsFeedProvider feeds;

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((HttpRequest req) {
      req.response
        ..statusCode = 200
        ..write(_sampleIcs)
        ..close();
    });
    kv = InMemoryKv();
    gateway = CommandGateway();
    feeds = IcsFeedProvider(
      kv,
      host: server.address.host,
      port: server.port,
      scheme: 'http',
    );
    registerCalendarActors(
      gateway,
      kv: kv,
      markers: InMemoryMarkerStore(),
      feeds: feeds,
    );
    tool = buildSystemPimTool(
        gateway, markers: InMemoryMarkerStore(), feeds: feeds);
  });

  tearDown(() async {
    await server.close(force: true);
  });

  Map<String, Object?> envelope(SubActionResult r) =>
      jsonDecode((r.content.first)['text']! as String) as Map<String, Object?>;

  Map<String, Object?> errOf(SubActionResult r) =>
      envelope(r)['error']! as Map<String, Object?>;

  Future<Map<String, Object?>> query(Map<String, Object?> params) async =>
      envelope(await tool.call('calendar_query', params));

  group('端到端：subscribe → refresh → query', () {
    test('订阅后 query 返回 ICS 事件（含 RRULE 展开与全天事件）', () async {
      final sub = envelope(await tool.call('calendar_subscribe', {
        'url': 'https://example.com/holiday.ics',
        'name': '节假日',
      }));
      expect(sub['success'], isTrue);
      final feedId = sub['feedId'] as String;

      final j = await query({
        'rangeStart': '2026-10-01',
        'rangeEnd': '2026-10-31',
      });
      final events = j['events'] as List;
      expect(events.length, 4); // 全天 1 + RRULE 3 个每日站会

      final allday = events.firstWhere((e) => e['isAllDay'] == true);
      expect(allday['start'], '2026-10-01'); // 全天输出纯日期
      expect(allday['title'], '团建');
      expect(allday['uid'], '$feedId:trip@x'); // G4 复合键
      expect(allday['source'], 'feed');

      final standups = events.where((e) => e['title'] == '每日站会').toList();
      expect(standups.length, 3);
      expect(standups.first['start'], '2026-10-05T01:30:00Z');
      // D1 固定排序
      final starts = events.map((e) => e['start'] as String).toList();
      expect(starts, [...starts]..sort());
      expect(j['hasMore'], isFalse);
    });

    test('第二次 query 命中缓存并标 isCached（不再打网络）', () async {
      await tool
          .call('calendar_subscribe', {'url': 'https://example.com/holiday.ics'});
      await query({'rangeStart': '2026-10-01', 'rangeEnd': '2026-10-31'});
      // 关闭 server：若还打网络，第二次查询必失败
      await server.close(force: true);
      final j =
          await query({'rangeStart': '2026-10-01', 'rangeEnd': '2026-10-31'});
      expect((j['events'] as List).length, 4);
      expect((j['events'] as List).first['isCached'], isTrue);
    });

    test('limit 截断 + hasMore 语义', () async {
      await tool
          .call('calendar_subscribe', {'url': 'https://example.com/holiday.ics'});
      final j = await query({
        'rangeStart': '2026-10-01',
        'rangeEnd': '2026-10-31',
        'limit': 2,
      });
      expect((j['events'] as List).length, 2);
      expect(j['hasMore'], isTrue);
    });

    test('limit=0 / 非正整数 → INVALID_ARGUMENT（不静默返全量）', () async {
      for (final bad in <Object>['0', 0, -1, 'abc']) {
        final r = await tool.call('calendar_query', {
          'rangeStart': '2026-10-01',
          'rangeEnd': '2026-10-31',
          'limit': bad,
        });
        expect(r.isError, isTrue, reason: '$bad');
        expect(errOf(r)['code'], contains('INVALID_ARGUMENT'), reason: '$bad');
      }
    });

    test('C1：跨度 > 90 天 → ERR_RANGE_TOO_WIDE', () async {
      await tool
          .call('calendar_subscribe', {'url': 'https://example.com/holiday.ics'});
      final r = await tool.call('calendar_query', {
        'rangeStart': '2026-01-01',
        'rangeEnd': '2026-12-31',
      });
      expect(r.isError, isTrue);
      expect(errOf(r)['code'], contains('ERR_RANGE_TOO_WIDE'));
    });
  });

  group('脱敏（E 拍板：默认 PII_MASK_PHONE_EMAIL）', () {
    test('手机号 / 邮箱被替换为 [已隐藏]', () async {
      await tool
          .call('calendar_subscribe', {'url': 'https://example.com/holiday.ics'});
      final j = await query({
        'rangeStart': '2026-10-01',
        'rangeEnd': '2026-10-31',
      });
      final e = (j['events'] as List).firstWhere((e) => e['title'] == '团建');
      expect(e['location'], contains('[已隐藏]'));
      expect(e['location'], isNot(contains('1381234')));
      expect(e['description'], contains('[已隐藏]'));
    });
  });

  group('refresh 与 G2 频控 / G3 缓存清理', () {
    test('refresh 成功刷新并写 lastSyncTime', () async {
      await tool
          .call('calendar_subscribe', {'url': 'https://example.com/holiday.ics'});
      final r = envelope(await tool.call('calendar_refresh', {}));
      expect(r['success'], isTrue);
      expect(r['updatedCount'], 1);

      final feedsNow = envelope(await tool.call('calendar_feeds', {}));
      final list = feedsNow['feeds'] as List;
      expect(list.single['lastSyncTime'], isNotNull);
      expect(list.single['status'], 'ok');
    });

    test('G2：30 秒内重复 refresh → ERR_RATE_LIMITED', () async {
      await tool
          .call('calendar_subscribe', {'url': 'https://example.com/holiday.ics'});
      await tool.call('calendar_refresh', {});
      final again = await tool.call('calendar_refresh', {});
      expect(again.isError, isTrue);
      expect(errOf(again)['code'], contains('ERR_RATE_LIMITED'));
    });

    test('G2：指定不存在的 feedId → ERR_FEED_NOT_FOUND', () async {
      final r = await tool.call('calendar_refresh', {'feedId': 'feed_nope'});
      expect(r.isError, isTrue);
      expect(errOf(r)['code'], contains('ERR_FEED_NOT_FOUND'));
    });

    test('G3：退订清缓存（ICS 原文与同步时间均清空）', () async {
      final sub = envelope(await tool.call('calendar_subscribe', {
        'url': 'https://example.com/holiday.ics',
      }));
      final feedId = sub['feedId'] as String;
      await tool.call('calendar_refresh', {});
      expect(await kv.settingsGet('$kIcsBodyPrefix$feedId'), isNotNull);

      await tool.call('calendar_unsubscribe', {'feedId': feedId});
      expect(await kv.settingsGet('$kIcsBodyPrefix$feedId'), '');
      expect(await kv.settingsGet('$kIcsSyncPrefix$feedId'), '');
    });
  });

  group('拉取失败', () {
    test('无缓存且拉取失败 → 结构化错误（ERR_NETWORK）', () async {
      await server.close(force: true);
      await tool
          .call('calendar_subscribe', {'url': 'https://example.com/holiday.ics'});
      final r = await tool.call('calendar_query', {
        'rangeStart': '2026-10-01',
        'rangeEnd': '2026-10-31',
      });
      expect(r.isError, isTrue);
      expect(errOf(r)['code'], contains('ERR_NETWORK'));
    });
  });
}

const String _sampleIcs = '''
BEGIN:VCALENDAR
VERSION:2.0
BEGIN:VEVENT
UID:trip@x
SUMMARY:团建
DTSTART;VALUE=DATE:20261001
DTEND;VALUE=DATE:20261002
LOCATION:北京市朝阳区某路 13812345678 号
DESCRIPTION:值班表见邮件，联系 ops@example.com
END:VEVENT
BEGIN:VEVENT
UID:standup@x
SUMMARY:每日站会
DTSTART:20261005T013000Z
DTEND:20261005T014000Z
RRULE:FREQ=DAILY;COUNT=3
END:VEVENT
END:VCALENDAR
''';
