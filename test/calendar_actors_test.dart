// P2-⑤ W 档 Actor + 前置校验测试：网关装配 CommandGateway（登记 Acters）后，
// 走通「admits → validate(SSRF/必填/枚举) → Actor 派发 → 信封派生 isError」全链路。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:good_template/action/command_gateway.dart';
import 'package:good_template/mcp/category_tool_face.dart';
import 'package:good_template/mcp/settings_kv.dart';
import 'package:good_template/ports.dart';
import 'package:good_template/service/calendar_actors.dart';
import 'package:good_template/service/marker_store.dart';
import 'package:good_template/tools/system_pim_tool.dart';

void main() {
  late CommandGateway gateway;
  late SettingsKv kv;
  late InMemoryMarkerStore markers;
  late CategoryTool tool;

  setUp(() {
    gateway = CommandGateway();
    kv = InMemoryKv();
    markers = InMemoryMarkerStore();
    registerCalendarActors(gateway, kv: kv, markers: markers);
    tool = buildSystemPimTool(gateway, markers: markers);
  });

  Map<String, Object?> envelope(SubActionResult result) =>
      jsonDecode((result.content.first)['text']! as String)
          as Map<String, Object?>;

  Map<String, Object?> errorOf(SubActionResult result) =>
      envelope(result)['error']! as Map<String, Object?>;

  group('G6 前置校验（在派发前拦截，buildCommand 无法表达失败）', () {
    test('subscribe 缺 url / 私网地址 / http 明文 / refreshMin 越界', () async {
      const cases = <(Map<String, Object?>, String)>[
        ({}, 'MISSING_ARGUMENT'),
        ({'url': 'https://127.0.0.1/a.ics'}, 'ERR_INVALID_URL'),
        ({'url': 'http://example.com/a.ics'}, 'ERR_INVALID_URL'),
        ({'url': 'https://example.com/a.ics', 'refreshMin': 1},
            'INVALID_ARGUMENT'),
        ({'url': 'https://example.com/a.ics', 'refreshMin': 99999},
            'INVALID_ARGUMENT'),
      ];
      for (final (payload, expected) in cases) {
        final r = await tool.call('calendar_subscribe', payload);
        expect(r.isError, isTrue, reason: '$payload');
        expect(errorOf(r)['code'], contains(expected), reason: '$payload');
      }
    });

    test('webcal 被规整为 https 后放行', () async {
      final r = await tool.call('calendar_subscribe', {
        'url': 'webcal://example.com/holiday.ics',
      });
      expect(r.isError, isFalse);
      expect(envelope(r)['url'], 'https://example.com/holiday.ics');
    });

    test('marker_add：category 非法 / 无年份且无 baseYear / leapPolicy 非法',
        () async {
      expect(
        errorOf(await tool.call('calendar_marker_add', {
          'originalDate': '2018-10-19',
          'title': 'x',
          'category': 'party',
        }))['code'],
        contains('INVALID_ARGUMENT'),
      );
      expect(
        errorOf(await tool.call('calendar_marker_add', {
          'originalDate': '10-19',
          'title': 'x',
          'category': 'birthday',
        }))['code'],
        contains('MISSING_ARGUMENT'),
      );
      expect(
        errorOf(await tool.call('calendar_marker_add', {
          'originalDate': '2018-10-19',
          'title': 'x',
          'category': 'birthday',
          'leapPolicy': 'whatever',
        }))['code'],
        contains('INVALID_ARGUMENT'),
      );
    });
  });

  group('Actor 派发与信封（G6：success=false ⇒ isError=true）', () {
    test('marker_add 成功并落库（baseYear 自动派生）', () async {
      final r = await tool.call('calendar_marker_add', {
        'originalDate': '2018-10-19',
        'title': '妈妈的生日',
        'category': 'birthday',
      });
      expect(r.isError, isFalse);
      final markerId = envelope(r)['markerId'] as String;
      final stored = await markers.list(
          rangeStart: '2018-01-01', rangeEnd: '2026-12-31');
      expect(stored.single.id, markerId);
      expect(stored.single.baseYear, 2018); // 从完整日期派生
      expect(stored.single.category, 'birthday');
      expect(stored.single.isAnnual, isTrue);
      expect(stored.single.leapPolicy, 'ignoreLeap');
    });

    test('marker_add 无年份格式 + 显式 baseYear', () async {
      final r = await tool.call('calendar_marker_add', {
        'originalDate': '10-19',
        'title': '纪念日',
        'category': 'anniversary',
        'baseYear': 2018,
      });
      expect(r.isError, isFalse);
      final stored = await markers.list(
          rangeStart: '2000-01-01', rangeEnd: '2099-12-31');
      expect(stored.single.baseYear, 2018);
    });

    test('marker_delete 成功 / 不存在 → ERR_MARKER_NOT_FOUND', () async {
      final add = envelope(await tool.call('calendar_marker_add', {
        'originalDate': '2018-10-19',
        'title': 't',
        'category': 'birthday',
      }));
      final id = add['markerId'] as String;
      final ok = await tool.call('calendar_marker_delete', {'markerId': id});
      expect(ok.isError, isFalse);
      final again = await tool.call('calendar_marker_delete', {'markerId': id});
      expect(again.isError, isTrue);
      expect(errorOf(again)['code'], contains('ERR_MARKER_NOT_FOUND'));
    });

    test('subscribe 幂等：同 url 不建重复源，返回已有 feedId', () async {
      final first = envelope(await tool.call('calendar_subscribe', {
        'url': 'https://example.com/a.ics',
        'name': '节假日',
      }));
      final second = envelope(await tool.call('calendar_subscribe', {
        'url': 'https://example.com/a.ics',
      }));
      expect(first['feedId'], second['feedId']);
      expect(second['idempotent'], isTrue);
      final feeds = await (() async {
        final raw = await kv.settingsGet(kCalendarFeedsKey);
        return (jsonDecode(raw!) as List).cast<Map<String, Object?>>();
      })();
      expect(feeds.length, 1);
    });

    test('unsubscribe 成功 / 不存在 → ERR_FEED_NOT_FOUND', () async {
      final add = envelope(await tool.call('calendar_subscribe', {
        'url': 'https://example.com/a.ics',
      }));
      final id = add['feedId'] as String;
      final ok = await tool.call('calendar_unsubscribe', {'feedId': id});
      expect(ok.isError, isFalse);
      final again = await tool.call('calendar_unsubscribe', {'feedId': id});
      expect(again.isError, isTrue);
      expect(errorOf(again)['code'], contains('ERR_FEED_NOT_FOUND'));
    });

    test('refresh fail-closed：ICS 未实现不假装同步成功', () async {
      final r = await tool.call('calendar_refresh', {});
      expect(r.isError, isTrue);
      expect(errorOf(r)['code'], contains('ERR_CALENDAR_SOURCE_UNAVAILABLE'));
    });
  });

  group('门禁与 Actor 未登记时的行为', () {
    test('未登记 Actor 的网关 → PERMISSION_DENIED 且 validate 不执行', () async {
      final bare = buildSystemPimTool(CommandGateway());
      // 若 validate 先于 admits 执行，缺 url 会返回 MISSING_ARGUMENT；
      // 顺序必须是 admits → validate，故此处应为 PERMISSION_DENIED。
      final r = await bare.call('calendar_subscribe', {});
      expect(r.isError, isTrue);
      expect(r.content.first['text'], contains('PERMISSION_DENIED'));
    });

    test('R 档不受门禁影响', () async {
      final r = await tool.call('calendar_workdays_between', {
        'startDate': '2026-10-01',
        'endDate': '2026-10-11',
      });
      expect(r.isError, isFalse);
    });
  });

  group('标记 store 编解码往返', () {
    test('encode / decode 保真（含默认值）', () async {
      final id = await markers.addMarker(
        originalDate: '2018-10-19',
        title: 't',
        category: 'milestone',
        isAnnual: false,
        isLunar: true,
        leapPolicy: 'strictLeap',
      );
      final all = await markers.list(
          rangeStart: '2018-01-01', rangeEnd: '2018-12-31');
      final m = all.single;
      expect(m.id, id);
      expect(m.isAnnual, isFalse);
      expect(m.isLunar, isTrue);
      expect(m.leapPolicy, 'strictLeap');
      final round = decodeMarker(encodeMarker(m));
      expect(round.id, m.id);
      expect(round.leapPolicy, m.leapPolicy);
    });
  });
}
