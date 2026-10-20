// P2-③ 农历引擎与表达式消歧测试：LunarMath 双向换算（官方历表事实逐字钉死）、
// ResolveExpression 全表达式族、以及经工具面的 calendar_resolve_date 真实链路。
//
// 测试事实来源（勿凭记忆改动）：2026 春节 = 2026-02-17；2026 中秋 = 2026-09-25；
// 2027 中秋 = 2027-09-15；2026 清明 = 2026-04-05；2025 年闰六月（初一 2025-07-25）；
// 2026 年寒露 = 2026-10-08；2026-10-01 = 农历八月廿一。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:good_template/action/command_gateway.dart';
import 'package:good_template/mcp/category_tool_face.dart';
import 'package:good_template/tools/calendar/lunar_math.dart';
import 'package:good_template/tools/calendar/resolve_expression.dart';
import 'package:good_template/tools/system_pim_tool.dart';

void main() {
  Map<String, Object?> jsonOf(SubActionResult r) =>
      jsonDecode(r.content.first['text']! as String) as Map<String, Object?>;

  group('LunarMath 双向换算', () {
    test('公历 → 农历：2026-09-25 = 八月十五（中秋）', () {
      final info = LunarMath.describe(DateTime.utc(2026, 9, 25));
      expect(info.lunarYear, 2026);
      expect(info.lunarMonth, 8);
      expect(info.lunarDay, 15);
      expect(info.isLeapMonth, isFalse);
      expect(info.monthText, '八');
      expect(info.dayText, '十五');
      expect(info.label, '十五'); // 非初一显示日
      expect(info.fullText, '2026年八月十五');
    });

    test('角标惯例：初一显示月名（2026-02-17 春节 → 正月）', () {
      final info = LunarMath.describe(DateTime.utc(2026, 2, 17));
      expect(info.lunarDay, 1);
      expect(info.label, '正月');
    });

    test('节气：2026-10-08 = 寒露；非节气日为空串', () {
      expect(LunarMath.solarTermOf(DateTime.utc(2026, 10, 8)), '寒露');
      expect(LunarMath.solarTermOf(DateTime.utc(2026, 10, 9)), '');
    });

    test('节气表：2026 年清明 = 2026-04-05（key 拼音归一后按中文名查）', () {
      final table = LunarMath.jieQiTableOfYear(2026);
      expect(table['清明'], DateTime.utc(2026, 4, 5));
      expect(table.containsKey('DA_XUE'), isFalse); // 拼音 key 已归一
      expect(table.containsKey('大雪'), isTrue);
    });

    test('农历 → 公历：2026 八月十五 → 2026-09-25；闰六月初一（2025）→ 2025-07-25', () {
      expect(LunarMath.lunarToSolar(2026, 8, 15), DateTime.utc(2026, 9, 25));
      expect(LunarMath.lunarToSolar(2025, 6, 1, isLeapMonth: true),
          DateTime.utc(2025, 7, 25));
    });

    test('闰月查询：2025 有闰六月，2026 无闰月', () {
      expect(LunarMath.leapMonthOf(2025), 6);
      expect(LunarMath.leapMonthOf(2026), 0);
    });

    test('非法农历日 fail-closed：不 clamp 不伪造', () {
      // 2026 无闰六月
      expect(() => LunarMath.lunarToSolar(2026, 6, 1, isLeapMonth: true),
          throwsA(isA<LunarMathException>()));
      // 月 / 日越界
      expect(() => LunarMath.lunarToSolar(2026, 13, 1),
          throwsA(isA<LunarMathException>()));
      expect(() => LunarMath.lunarToSolar(2026, 1, 0),
          throwsA(isA<LunarMathException>()));
    });
  });

  group('ResolveExpression 表达式族', () {
    final base = DateTime.utc(2026, 10, 20); // 周二

    test('lunar: 平月与闰月表达式', () {
      final r = ResolveExpression.resolve('lunar:2026-08-15');
      expect(r.date, DateTime.utc(2026, 9, 25));
      expect(r.description, contains('2026'));
      final leap = ResolveExpression.resolve('lunar:2025-闰6-01');
      expect(leap.date, DateTime.utc(2025, 7, 25));
    });

    test('lunar: 非法农历日 → LunarMathException（不 clamp）', () {
      // 底层抛 LunarMathException，工具层统一转 INVALID_ARGUMENT（见工具面组）。
      expect(() => ResolveExpression.resolve('lunar:2026-闰6-01'),
          throwsA(isA<LunarMathException>()));
    });

    test('today / today±N（须 baseDate）', () {
      expect(ResolveExpression.resolve('today', baseDate: base).date, base);
      expect(
          ResolveExpression.resolve('today+3', baseDate: base).date,
          DateTime.utc(2026, 10, 23));
      expect(
          ResolveExpression.resolve('today-7', baseDate: base).date,
          DateTime.utc(2026, 10, 13));
      expect(
        () => ResolveExpression.resolve('today+3'),
        throwsA(isA<ResolveException>()),
      );
    });

    test('next_<weekday>：严格下一个（含跨周、不含当天）', () {
      // 2026-10-20 周二 → 下一个周五 10-23
      expect(ResolveExpression.resolve('next_friday', baseDate: base).date,
          DateTime.utc(2026, 10, 23));
      // 当天就是周二：next_tuesday 跳到下周二 10-27
      expect(ResolveExpression.resolve('next_tuesday', baseDate: base).date,
          DateTime.utc(2026, 10, 27));
    });

    test('q1~q4_start：baseDate 所在年', () {
      expect(ResolveExpression.resolve('q4_start', baseDate: base).date,
          DateTime.utc(2026, 10, 1));
      expect(ResolveExpression.resolve('q1_start', baseDate: base).date,
          DateTime.utc(2026, 1, 1));
    });

    test('节日别名：农历节（中秋）/ 公历节（国庆）/ 节气节（清明）', () {
      expect(ResolveExpression.resolve('mid_autumn:2027').date,
          DateTime.utc(2027, 9, 15));
      expect(ResolveExpression.resolve('national_day:2026').date,
          DateTime.utc(2026, 10, 1));
      expect(ResolveExpression.resolve('qingming:2026').date,
          DateTime.utc(2026, 4, 5));
      // 不带年份须 baseDate
      expect(ResolveExpression.resolve('mid_autumn', baseDate: base).date,
          DateTime.utc(2026, 9, 25));
      expect(() => ResolveExpression.resolve('mid_autumn'),
          throwsA(isA<ResolveException>()));
    });

    test('未知别名 → INVALID_ARGUMENT + suggestion 枚举可用别名', () {
      try {
        ResolveExpression.resolve('not_a_festival');
        fail('should throw');
      } on ResolveException catch (e) {
        expect(e.code, 'INVALID_ARGUMENT');
        expect(e.suggestion, contains('mid_autumn'));
      }
    });
  });

  group('calendar_resolve_date 经工具面', () {
    Future<SubActionResult> call(Map<String, Object?> params) async =>
        buildSystemPimTool(CommandGateway())
            .call('calendar_resolve_date', params);

    test('lunar: 表达式 → 公历日 + 农历回显 + 周几（D3 结构化出参）', () async {
      final r = await call({'expression': 'lunar:2026-08-15'});
      expect(r.isError, isFalse);
      final j = jsonOf(r);
      expect(j['resolvedDate'], '2026-09-25');
      expect(j['weekday'], '周五'); // 2026-09-25
      expect(j['lunar'], '2026年八月十五');
      // 默认装配带内置 2026 官方节假日表：中秋 9/25 为法定假 → 非工作日
      expect(j['isWorkday'], isFalse);
      expect(j['holidayTableVersion'], 'cn-2026.1');
      expect(j['description'], isNotNull);
    });

    test('相对表达式缺 baseDate → MISSING_ARGUMENT（F1：不静默取当天）', () async {
      final r = await call({'expression': 'today+3'});
      expect(r.isError, isTrue);
      final err = jsonOf(r)['error'] as Map;
      expect(err['code'], contains('MISSING_ARGUMENT'));
      expect(err['suggestion'], isNotNull);
    });

    test('相对表达式带 baseDate 走通', () async {
      final r = await call({
        'expression': 'next_friday',
        'baseDate': '2026-10-20',
      });
      expect(r.isError, isFalse);
      expect(jsonOf(r)['resolvedDate'], '2026-10-23');
    });

    test('baseDate 非法 → INVALID_ARGUMENT', () async {
      final r = await call({'expression': 'today', 'baseDate': '2026-13-40'});
      expect(r.isError, isTrue);
      expect((jsonOf(r)['error'] as Map)['code'], contains('INVALID_ARGUMENT'));
    });
  });
}
