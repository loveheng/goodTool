library;

/// math_utility 领域网关（S3e）单测：双轨出参 + 结构化错误 + 派发门禁。
///
/// 覆盖 calc_eval / unit_convert / unit_list 三动作，验证 G1 错误前缀注入、
/// G5 宽容解析边界、双轨 numericValue 无损，以及未知 action 的 UNKNOWN_ACTION。
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:goodtools/mcp/category_tool_face.dart';
import 'package:goodtools/tools/math/math_tool.dart';

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

    test('中文全链路内联换算（10 公里 换算 英里）与 to 等值', () async {
      final zh = await run('calc_eval', {'expr': '10 公里 换算 英里'});
      final en = await run('calc_eval', {'expr': '10 km to mi'});
      expect(zh['success'], isTrue);
      expect(zh['numericValue'], en['numericValue']);
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

  group('list_stats 高精度列表统计', () {
    test('max / min 返回 Decimal 比较结果与首达下标', () async {
      final mx = await run('list_stats',
          {'values': [3, '0.999999999999999999', 1], 'op': 'max'});
      expect(mx['success'], isTrue);
      expect(mx['result'], '3');
      expect(mx['index'], 0);

      final mn = await run('list_stats',
          {'values': [3, '0.999999999999999999', 1], 'op': 'min'});
      expect(mn['success'], isTrue);
      expect(mn['result'], '0.999999999999999999');
      expect(mn['index'], 1);
    });

    test('sort 升/降序；高精度数字串全程不转 double', () async {
      final v = ['0.123456789012345678', 1, '0.123456789012345679'];
      final asc = await run('list_stats', {'values': v, 'op': 'sort'});
      final nums = asc['numericValues'] as List;
      expect(nums[0], '0.123456789012345678'); // 双双以字符串无损传递
      expect(nums[1], '0.123456789012345679');
      expect(nums[2], 1);

      final desc = await run('list_stats',
          {'values': [1, 5, 3], 'op': 'sort', 'order': 'desc'});
      expect(desc['numericValues'], [5, 3, 1]);
      expect(desc['order'], 'desc');
    });

    test('sum / mean / median', () async {
      final sum = await run('list_stats',
          {'values': ['0.1', '0.2'], 'op': 'sum'});
      expect(sum['numericValue'], 0.3); // Decimal 精确，非 0.30000000000000004

      final mean = await run('list_stats',
          {'values': [1, 2, 3, 4], 'op': 'mean'});
      expect(mean['numericValue'], 2.5);

      final medianOdd = await run('list_stats',
          {'values': [5, 1, 3], 'op': 'median'});
      expect(medianOdd['numericValue'], 3);

      final medianEven = await run('list_stats',
          {'values': [1, 2, 3, 4], 'op': 'median'});
      expect(medianEven['numericValue'], 2.5);
    });

    test('precision 控制小数位', () async {
      final j = await run('list_stats',
          {'values': [1, 2], 'op': 'mean', 'precision': 2});
      expect(j['result'], '1.5');

      final j2 = await run('list_stats',
          {'values': [1, 1, 1], 'op': 'mean', 'precision': 0});
      expect(j2['result'], '1');
    });

    test('结构化错误：空数组 / 非法 op / 非法元素 / 非法 order', () async {
      final empty = await run('list_stats', {'values': <int>[], 'op': 'sum'});
      expect((empty['error'] as Map<String, Object?>)['code'],
          contains('MISSING_ARGUMENT'));

      final badOp = await run('list_stats',
          {'values': [1], 'op': 'avg'});
      final err = badOp['error'] as Map<String, Object?>;
      expect(err['code'], contains('INVALID_ARGUMENT'));
      expect(err['candidates'], contains('mean')); // 自愈候选

      final badElem = await run('list_stats',
          {'values': [1, 'abc'], 'op': 'sum'});
      expect((badElem['error'] as Map<String, Object?>)['message'],
          contains('values[1]'));

      final badOrder = await run('list_stats',
          {'values': [1], 'op': 'sort', 'order': 'up'});
      expect((badOrder['error'] as Map<String, Object?>)['code'],
          contains('INVALID_ARGUMENT'));
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
