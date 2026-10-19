library;

/// math_utility 领域网关（S3e）单测：双轨出参 + 结构化错误 + 派发门禁。
///
/// 覆盖 calc_eval / unit_convert / unit_list 三动作，验证 G1 错误前缀注入、
/// G5 宽容解析边界、双轨 numericValue 无损，以及未知 action 的 UNKNOWN_ACTION。
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:good_template/mcp/category_tool_face.dart';
import 'package:good_template/tools/math/math_tool.dart';

Map<String, Object?> _parse(SubActionResult r) {
  final text = r.content.first['text'] as String;
  return jsonDecode(text) as Map<String, Object?>;
}

void main() {
  final tool = buildMathTool();

  Future<Map<String, Object?>> run(
          String action, Map<String, Object?> params) async =>
      _parse(await tool.call(action, params));

  group('calc_eval 双轨出参', () {
    test('折扣精度精确 (2580 * 0.8 = 2064)', () async {
      final j = await run('calc_eval', {'expr': '2580 * 0.8'});
      expect(j['success'], isTrue);
      expect(j['numericValue'], 2064.0);
      expect(j['expression'], '2580 * 0.8');
    });

    test('Decimal 主链路 (0.1 + 0.2 = 0.3 精确)', () async {
      final j = await run('calc_eval', {'expr': '0.1 + 0.2'});
      expect(j['success'], isTrue);
      expect(j['numericValue'], 0.3); // 非 0.30000000000000004
    });

    test('内联 to 换算 (320 km/h to m/s)', () async {
      final j = await run('calc_eval', {'expr': '320 km/h to m/s'});
      expect(j['success'], isTrue);
      expect(j['numericValue'], closeTo(88.8889, 1e-3));
    });

    test('precision 控制小数位', () async {
      final j = await run('calc_eval', {'expr': '100 / 3', 'precision': 2});
      expect(j['success'], isTrue);
      expect(j['result'], '33.33');
    });
  });

  group('calc_eval 结构化错误（自愈）', () {
    test('语法错误带 prefix + offset', () async {
      final j = await run('calc_eval', {'expr': '1 + * 2'});
      expect(j['success'], isFalse);
      final err = j['error'] as Map<String, Object?>;
      expect(err['code'], startsWith('math_utility.calc_eval:'));
      expect(err['code'], contains('UNEXPECTED_TOKEN'));
      expect(err['offset'], isA<int>());
    });

    test('缺少必填 expr → MISSING_ARGUMENT', () async {
      final j = await run('calc_eval', {});
      expect(j['success'], isFalse);
      expect((j['error'] as Map<String, Object?>)['code'],
          contains('MISSING_ARGUMENT'));
    });
  });

  group('unit_convert 双轨出参', () {
    test('km/h → m/s', () async {
      final j = await run(
          'unit_convert', {'value': 100, 'from': 'km/h', 'to': 'm/s'});
      expect(j['success'], isTrue);
      expect(j['numericValue'], closeTo(27.7778, 1e-3));
      expect(j['toUnit'], 'm/s');
      expect(j['formula'], isA<String>());
    });

    test('未知单位返回 candidates 自愈', () async {
      final j = await run('unit_convert',
          {'value': 1, 'from': 'km/s', 'to': 'm/s'});
      expect(j['success'], isFalse);
      final err = j['error'] as Map<String, Object?>;
      expect(err['code'], contains('UNKNOWN_UNIT'));
      expect(err['candidates'], isA<List>());
      expect((err['candidates'] as List).isNotEmpty, isTrue);
    });
  });

  group('unit_list 分级自省', () {
    test('无参返回量纲概览（11 类）', () async {
      final j = await run('unit_list', {});
      expect(j['success'], isTrue);
      expect((j['dimensions'] as List).length, 11);
    });

    test('带 dimension 展开单位元数据', () async {
      final j = await run('unit_list', {'dimension': 'speed'});
      expect(j['success'], isTrue);
      expect(j['dimension'], 'speed');
      expect(j['baseUnit'], 'm/s');
      expect(j['units'], isA<List>());
    });
  });

  group('派发门禁', () {
    test('未知 action → UNKNOWN_ACTION（[前缀:code] 文本）', () async {
      final r = await tool.call('nope', {});
      expect(r.isError, isTrue);
      final text = r.content.first['text'] as String;
      expect(text, contains('UNKNOWN_ACTION'));
      expect(text, startsWith('[math_utility.nope:'));
    });
  });
}
