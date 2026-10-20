// P1e system_pim 适配层测试：14 action 与能力文档 1:1 对账、**W 档写门禁真验**
// （未授权 → PERMISSION_DENIED 且执行体未触达；登记后 → 走 CommandGateway 派发）、
// 时间推演纯函数确定性、C1 区间红线、源缺位 fail-closed、订阅 URL 的 SSRF 护栏。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:good_template/action/command_gateway.dart';
import 'package:good_template/mcp/calendar_provider.dart';
import 'package:good_template/mcp/category_tool_face.dart';
import 'package:good_template/tools/system_pim_tool.dart';

void main() {
  Map<String, Object?> jsonOf(SubActionResult r) =>
      jsonDecode(r.content.first['text']! as String) as Map<String, Object?>;

  Map<String, Object?> errOf(SubActionResult r) =>
      jsonOf(r)['error']! as Map<String, Object?>;

  /// 非结构化错误（网关层拒绝）走 `[前缀:code] message` 文本，非 JSON。
  String textOf(SubActionResult r) => r.content.first['text']! as String;

  CategoryTool tool({
    CalendarFeedProvider? feeds,
    HolidayProvider? holidays,
  }) =>
      buildSystemPimTool(
        CommandGateway(),
        feeds: feeds,
        holidays: holidays ?? const EmptyHolidayProvider(),
      );

  group('能力矩阵 1:1 对账（G1，防改名 / 自造）', () {
    test('恰好 14 个 action，名称与 product/calendar.md 第一列一致', () {
      final props =
          (tool().toSchema()['inputSchema'] as Map)['properties'] as Map;
      final enums = ((props['action'] as Map)['enum'] as List).cast<String>()
        ..sort();
      expect(enums, [
        'calendar_date_calc',
        'calendar_date_diff',
        'calendar_feeds',
        'calendar_marker_add',
        'calendar_marker_delete',
        'calendar_marker_list',
        'calendar_month_grid',
        'calendar_query',
        'calendar_refresh',
        'calendar_resolve_date',
        'calendar_subscribe',
        'calendar_tz_convert',
        'calendar_unsubscribe',
        'calendar_workdays_between',
      ]);
    });

    test('每个 action 描述带紧凑参数签名（消参数盲盒）', () {
      final desc = tool().toSchema()['description'] as String;
      for (final sig in const [
        'calendar_query(',
        'calendar_subscribe(',
        'calendar_marker_add(',
        'calendar_date_calc(',
      ]) {
        expect(desc, contains(sig));
      }
    });
  });

  group('W 档写门禁（G3 / arch-guard R7 首次真验）', () {
    test('未登记 Actor → PERMISSION_DENIED，**执行体未被触达**', () async {
      final t = tool();
      for (final action in const [
        'calendar_subscribe',
        'calendar_unsubscribe',
        'calendar_refresh',
        'calendar_marker_add',
        'calendar_marker_delete',
      ]) {
        // 执行体被触达会抛 UnsupportedError，故「正常返回 + PERMISSION_DENIED」
        // 即证明网关层在执行体之前拦下了（物理级）。
        final r = await t.call(action, {'url': 'https://example.com/a.ics'});
        expect(r.isError, isTrue, reason: action);
        // 网关层拒绝是非结构化文本错误，前缀由派发层注入（G1）
        expect(
          textOf(r),
          startsWith('[system_pim.$action: PERMISSION_DENIED]'),
          reason: action,
        );
      }
    });

    test('登记 Actor 后 → 经 CommandGateway 派发，命令名 = action 名', () async {
      final gw = CommandGateway();
      final seen = <Command>[];
      gw.register('calendar_subscribe', (cmd) async {
        seen.add(cmd);
        return const [
          {'type': 'text', 'text': 'subscribed'}
        ];
      });
      final t = buildSystemPimTool(gw);
      final r = await t.call('calendar_subscribe', {
        'url': 'https://example.com/holiday.ics',
        'name': '节假日',
      });
      expect(r.isError, isFalse);
      expect(seen.single.name, 'calendar_subscribe');
      expect(seen.single.payload['url'], 'https://example.com/holiday.ics');
      // Actor 返回的 content 被网关层包成 success 结果原样透出
      expect(r.content.first['text'], 'subscribed');
    });

    test('越权键命中 → 同样被拦（CommandGateway.forbiddenKeys）', () async {
      final gw = CommandGateway()..forbiddenKeys = {'name'};
      gw.register('calendar_subscribe', (_) async => const [
            {'type': 'text', 'text': 'should not happen'}
          ]);
      final t = buildSystemPimTool(gw);
      final r = await t.call('calendar_subscribe', {
        'url': 'https://example.com/a.ics',
        'name': '越权',
      });
      expect(r.isError, isTrue);
      expect(textOf(r), contains('PERMISSION_DENIED'));
    });

    test('R 档不受写门禁影响（无需登记即可执行）', () async {
      final r = await tool().call('calendar_date_diff', {
        'startDate': '2026-01-01',
        'endDate': '2026-01-10',
      });
      expect(r.isError, isFalse);
    });
  });

  group('时间推演纯函数（F1 确定性，无 DateTime.now）', () {
    test('date_diff：总天数 + 成分跨度（大小月 / 闰年严格）', () async {
      final j = jsonOf(await tool().call('calendar_date_diff', {
        'startDate': '2026-01-31',
        'endDate': '2026-03-01',
      }));
      expect(j['totalDays'], 29);
      // 成分跨度：1/31 → 3/1 = 1 个月零 1 天（不是「29 天 ≈ 1 个月」的近似）
      expect(j['span'], {'years': 0, 'months': 1, 'days': 1, 'hours': 0});
    });

    test('date_diff：闰年 2024-02-28 → 2024-03-01 = 2 天', () async {
      final j = jsonOf(await tool().call('calendar_date_diff', {
        'startDate': '2024-02-28',
        'endDate': '2024-03-01',
      }));
      expect(j['totalDays'], 2);
    });

    test('date_calc：days 增量', () async {
      final j = jsonOf(await tool().call('calendar_date_calc', {
        'baseDate': '2026-10-20',
        'delta': {'days': 3},
      }));
      expect(j['targetDate'], '2026-10-23');
      expect(j['isWorkday'], isTrue); // 2026-10-23 周五
    });

    test('date_calc：months 月末 clamp（1/31 + 1 月 = 2/28，不滚到 3/3）',
        () async {
      final j = jsonOf(await tool().call('calendar_date_calc', {
        'baseDate': '2026-01-31',
        'delta': {'months': 1},
      }));
      expect(j['targetDate'], '2026-02-28');
    });

    test('date_calc：workdays 跳过周末', () async {
      final j = jsonOf(await tool().call('calendar_date_calc', {
        'baseDate': '2026-10-16', // 周五
        'delta': {'workdays': 1},
      }));
      expect(j['targetDate'], '2026-10-19'); // 跳过周六日到周一
    });

    test('workdays_between：节假日与调休补班明细（HolidayProvider 可覆写）',
        () async {
      final j = jsonOf(await buildSystemPimTool(
        CommandGateway(),
        holidays: _FakeHolidays(),
      ).call('calendar_workdays_between', {
        'startDate': '2026-10-01',
        'endDate': '2026-10-11',
      }));
      expect(j['totalDays'], 10);
      expect(j['holidays'], [
        {'date': '2026-10-01', 'name': '国庆节'},
      ]);
      expect(j['adjustments'], [
        {
          'date': '2026-10-10',
          'name': '国庆调休补班',
          'type': 'workday',
        }
      ]);
      // 调休补班优先级最高：10-10 是周六但仍计入工作日
      expect(j['workdays'], _FakeHolidays().expectedWorkdays);
      expect(j['holidayTableVersion'], 'fake-1');
    });

    test('date_diff：excludeWeekends 与 excludeHolidays 独立生效', () async {
      final t = buildSystemPimTool(CommandGateway(), holidays: _FakeHolidays());
      final both = jsonOf(await t.call('calendar_date_diff', {
        'startDate': '2026-10-01',
        'endDate': '2026-10-11',
        'excludeWeekends': true,
        'excludeHolidays': true,
      }));
      final none = jsonOf(await t.call('calendar_date_diff', {
        'startDate': '2026-10-01',
        'endDate': '2026-10-11',
      }));
      expect(both['workdays'], lessThan(none['workdays'] as int));
      expect(both['holidayTableVersion'], 'fake-1');
    });
  });

  group('入参校验（不静默兜底）', () {
    test('日期溢出（2026-02-31）→ MISSING_ARGUMENT，不滚到下月', () async {
      final r = await tool().call('calendar_date_diff', {
        'startDate': '2026-02-31',
        'endDate': '2026-03-01',
      });
      expect(r.isError, isTrue);
      expect(errOf(r)['code'], contains('MISSING_ARGUMENT'));
    });

    test('delta 非整数 → INVALID_ARGUMENT', () async {
      final r = await tool().call('calendar_date_calc', {
        'baseDate': '2026-10-20',
        'delta': {'days': '三天'},
      });
      expect(errOf(r)['code'], contains('INVALID_ARGUMENT'));
    });

    test('delta 空对象 → MISSING_ARGUMENT', () async {
      final r = await tool().call('calendar_date_calc', {
        'baseDate': '2026-10-20',
        'delta': {},
      });
      expect(errOf(r)['code'], contains('MISSING_ARGUMENT'));
    });

    test('C1 查询跨度 > 90 天 → ERR_RANGE_TOO_WIDE（不静默截断）', () async {
      final r = await tool().call('calendar_query', {
        'rangeStart': '2026-01-01',
        'rangeEnd': '2026-06-30',
      });
      expect(errOf(r)['code'], contains('ERR_RANGE_TOO_WIDE'));
      expect(errOf(r)['suggestion'], contains('缩小区间'));
    });

    test('枚举外 action → UNKNOWN_ACTION（不幻觉执行）', () async {
      final r = await tool().call('calendar_create_meeting', {});
      expect(r.isError, isTrue);
      expect(r.content.first['text'], contains('UNKNOWN_ACTION'));
    });
  });

  group('源缺位 fail-closed（standards §1.2，不返回空列表假装查到）', () {
    // 各 action 的**合法**入参（先过入参校验，才能验证「源缺位」而非「参数缺失」）。
    // resolve_date（纯函数 + 农历引擎）与 tz_convert（bundled tz 库 + B1 缺省）
    // 自 P2-②/③ 起不再依赖可空源，移出本组（真实行为见「日期消歧 / 时区投影」组）。
    const sourceArgs = <String, Map<String, Object?>>{
      'calendar_query': {'rangeStart': '2026-10-01', 'rangeEnd': '2026-10-07'},
      'calendar_feeds': <String, Object?>{},
      'calendar_month_grid': {'year': 2026, 'month': 10},
      'calendar_marker_list': {
        'rangeStart': '2026-10-01',
        'rangeEnd': '2026-10-07',
      },
    };
    for (final entry in sourceArgs.entries) {
      test('${entry.key} 未注入源 → ERR_CALENDAR_SOURCE_UNAVAILABLE', () async {
        final r = await tool().call(entry.key, entry.value);
        expect(r.isError, isTrue, reason: entry.key);
        expect(errOf(r)['code'], contains('ERR_CALENDAR_SOURCE_UNAVAILABLE'),
            reason: entry.key);
      });
    }

    test('注入 feed 源后 query / feeds 走通', () async {
      final t = buildSystemPimTool(
        CommandGateway(),
        feeds: _FakeFeeds(),
      );
      final q = await t.call('calendar_query', {
        'rangeStart': '2026-10-01',
        'rangeEnd': '2026-10-07',
      });
      expect(q.isError, isFalse);
      expect(jsonOf(q)['events'], isNotEmpty);
      final f = await t.call('calendar_feeds', {});
      expect((jsonOf(f)['feeds'] as List).length, 1);
    });
  });

  group('订阅 URL 护栏（SSRF / 强制 HTTPS，安全关键）', () {
    test('https 正常通过；webcal 规整为 https', () {
      expect(guardCalendarUrl('https://example.com/a.ics').ok, isTrue);
      final w = guardCalendarUrl('webcal://example.com/a.ics');
      expect(w.ok, isTrue);
      expect(w.uri!.scheme, 'https');
    });

    test('http 明文 → 拒绝（禁止降级回退）', () {
      final r = guardCalendarUrl('http://example.com/a.ics');
      expect(r.ok, isFalse);
      expect(r.code, 'ERR_INVALID_URL');
    });

    for (final host in const [
      '127.0.0.1',
      '10.1.2.3',
      '192.168.1.1',
      '172.16.0.1',
      '172.31.255.255',
      '169.254.169.254',
      '0.0.0.0',
      'localhost',
      'cal.localhost',
      '::1',
      'fe80::1',
      'fc00::1',
      'fd12:3456::1',
      '[::ffff:127.0.0.1]',
    ]) {
      test('拒绝回环 / 私网 / 链路本地：$host', () {
        final r = guardCalendarUrl('https://$host/a.ics');
        expect(r.ok, isFalse, reason: host);
        expect(r.code, 'ERR_INVALID_URL', reason: host);
      });
    }

    test('公网地址 172.32.0.1（不在私网段）放行', () {
      expect(guardCalendarUrl('https://172.32.0.1/a.ics').ok, isTrue);
    });

    test('空值 / 无主机 → MISSING_ARGUMENT 或 ERR_INVALID_URL', () {
      expect(guardCalendarUrl(null).code, 'MISSING_ARGUMENT');
      expect(guardCalendarUrl('not a url').code, 'ERR_INVALID_URL');
      expect(guardCalendarUrl('ftp://example.com/a').code, 'ERR_INVALID_URL');
    });
  });
}

/// 可覆写的节假日表（验证 F3 注入与确定性）。
class _FakeHolidays implements HolidayProvider {
  _FakeHolidays();

  static const entries = <HolidayEntry>[
    HolidayEntry(date: '2026-10-01', name: '国庆节', type: 'holiday'),
    HolidayEntry(date: '2026-10-10', name: '国庆调休补班', type: 'workday'),
  ];

  /// 2026-10-01(四)~10-11(日)：10-01 假、10-03/04 周末、10-10 补班计入、10-11 周末。
  int get expectedWorkdays => 7;

  @override
  String get version => 'fake-1';

  @override
  List<HolidayEntry> between(String startDate, String endDate) => entries
      .where((e) => e.date.compareTo(startDate) >= 0 && e.date.compareTo(endDate) <= 0)
      .toList();
}

/// 事件源桩（验证注入后 R 档走通）。
class _FakeFeeds implements CalendarFeedProvider {
  @override
  Future<CalendarQueryResult> query({
    required String rangeStart,
    required String rangeEnd,
    String? timezone,
    List<String>? feedIds,
    bool includeSystem = true,
  }) async =>
      CalendarQueryResult(<CalendarEvent>[
        CalendarEvent(
          uid: 'uid-1',
          title: '国庆节',
          start: '2026-10-01T00:00:00+08:00',
          end: '2026-10-02T00:00:00+08:00',
          isAllDay: true,
          source: 'feed',
          feedId: 'f1',
          feedName: '节假日',
        ),
      ]);

  @override
  Future<List<CalendarFeed>> feeds() async => <CalendarFeed>[
        const CalendarFeed(id: 'f1', name: '节假日', url: 'https://example.com/h.ics', refreshMin: 720),
      ];

  @override
  Future<int> refresh({String? feedId}) async => 0;
}
