// P2-② 时区投影测试：TzMath 纯函数（B3 offset / B4 DST / B5 bundled tz）
// + 经工具面的 calendar_tz_convert 真实链路 + B1 缺省链。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:goodtools/action/command_gateway.dart';
import 'package:goodtools/mcp/category_tool_face.dart';
import 'package:goodtools/tools/calendar/tz_math.dart';
import 'package:goodtools/tools/system_pim_tool.dart';

void main() {
  Map<String, Object?> jsonOf(SubActionResult r) =>
      jsonDecode(r.content.first['text']! as String) as Map<String, Object?>;

  group('TzMath 纯函数', () {
    test('resolveLocation：合法 IANA 名通过，非法名抛 TzMathException（不静默回退）', () {
      expect(TzMath.resolveLocation('Asia/Shanghai').name, 'Asia/Shanghai');
      expect(() => TzMath.resolveLocation('Not/AZone'),
          throwsA(isA<TzMathException>()));
    });

    test('显式 offset 入参按声明时刻投影（B3：出参带显式 offset）', () {
      final from = TzMath.resolveLocation('Asia/Shanghai');
      final to = TzMath.resolveLocation('UTC');
      final instant = TzMath.parseInput('2026-10-20T12:00:00+08:00', from);
      final out = TzMath.project(instant, to);
      expect(out['target'], '2026-10-20T04:00:00+00:00');
      expect(out['offset'], '+00:00');
      expect(out['offsetMinutes'], 0);
      expect(out['dstActive'], isFalse);
      expect(out['timezone'], 'UTC');
    });

    test('无时区信息的墙钟按 fromTz 解释（B2：浮动时间不落本机时区）', () {
      final from = TzMath.resolveLocation('Asia/Shanghai');
      final to = TzMath.resolveLocation('America/New_York');
      final instant = TzMath.parseInput('2026-07-15T12:00:00', from);
      final out = TzMath.project(instant, to);
      // 上海 12:00 = UTC 04:00 = 纽约 00:00（7 月处 EDT，UTC−4）
      expect(out['target'], '2026-07-15T00:00:00-04:00');
      expect(out['dstActive'], isTrue);
      expect(out['abbreviation'], 'EDT');
    });

    test('DST 边界两侧（B4）：夏令时内 EDT−4，冬令时 EST−5', () {
      final to = TzMath.resolveLocation('America/New_York');
      final summer =
          TzMath.project(DateTime.utc(2026, 7, 15, 12), to);
      final winter =
          TzMath.project(DateTime.utc(2026, 1, 15, 12), to);
      expect(summer['offset'], '-04:00');
      expect(summer['dstActive'], isTrue);
      expect(winter['offset'], '-05:00');
      expect(winter['dstActive'], isFalse);
    });

    test('纯日期入参按 fromTz 当日 00:00 解释', () {
      final from = TzMath.resolveLocation('UTC');
      final instant = TzMath.parseInput('2026-10-20', from);
      final out = TzMath.project(instant, from);
      expect(out['target'], '2026-10-20T00:00:00+00:00');
    });

    test('非法 datetime → TzMathException（不静默兜底）', () {
      final from = TzMath.resolveLocation('UTC');
      expect(() => TzMath.parseInput('not-a-time', from),
          throwsA(isA<TzMathException>()));
      expect(() => TzMath.parseInput(null, from), throwsA(isA<TzMathException>()));
    });
  });

  group('calendar_tz_convert 经工具面', () {
    Future<SubActionResult> call(Map<String, Object?> params) async =>
        buildSystemPimTool(CommandGateway()).call('calendar_tz_convert', params);

    test('真实投影：上海正午 → UTC', () async {
      final r = await call({
        'datetime': '2026-10-20T12:00:00+08:00',
        'fromTz': 'Asia/Shanghai',
        'toTz': 'UTC',
      });
      expect(r.isError, isFalse);
      final j = jsonOf(r);
      expect(j['target'], '2026-10-20T04:00:00+00:00');
      expect(j['fromTimezone'], 'Asia/Shanghai');
      expect(j['dstActive'], isFalse);
    });

    test('fromTz / toTz 缺省走 B1 链（缺省 UTC 端口，出参可追溯）', () async {
      final r = await call({'datetime': '2026-10-20T08:00:00Z'});
      expect(r.isError, isFalse);
      final j = jsonOf(r);
      expect(j['fromTimezone'], 'UTC');
      expect(j['timezone'], 'UTC');
      expect(j['target'], '2026-10-20T08:00:00+00:00');
    });

    test('非法时区名 → INVALID_ARGUMENT（带 suggestion，不漏库异常）', () async {
      final r = await call({
        'datetime': '2026-10-20T12:00:00Z',
        'fromTz': 'Mars/Olympus',
        'toTz': 'UTC',
      });
      expect(r.isError, isTrue);
      final err = jsonOf(r)['error'] as Map;
      expect(err['code'], contains('INVALID_ARGUMENT'));
      expect(err['suggestion'], isNotNull);
    });

    test('非法 datetime → INVALID_ARGUMENT', () async {
      final r = await call({'datetime': 'tomorrow', 'fromTz': 'UTC', 'toTz': 'UTC'});
      expect(r.isError, isTrue);
      expect((jsonOf(r)['error'] as Map)['code'], contains('INVALID_ARGUMENT'));
    });
  });
}
