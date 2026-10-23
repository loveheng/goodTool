library;

/// 单位换算引擎单测（纯 Dart，无设备可跑）。
///
/// 对应 calculator.md「开发顺序门禁」第 1 层与附录 A 修正骨架：
/// linear / affine / reciprocal / iec_si 四类 + reciprocal 跨制反比。
import 'package:flutter_test/flutter_test.dart';
import 'package:goodtools/tools/math/unit_converter.dart';
import 'package:goodtools/tools/math/unit_registry.dart';

void main() {
  const conv = UnitConverter();

  group('linear', () {
    test('320 km/h → m/s = 88.8889（calculator.md 锚点用例）', () {
      final r = conv.convert(320, 'km/h', 'm/s');
      expect(r.success, isTrue);
      expect(r.value, closeTo(88.8889, 1e-4));
      expect(r.fromUnit, 'km/h');
      expect(r.toUnit, 'm/s');
      expect(r.formula, isNotNull);
    });

    test('1 in → cm = 2.54', () {
      expect(conv.convert(1, 'in', 'cm').value, closeTo(2.54, 1e-9));
    });

    test('中文别名：公里每小时 / 千米每小时 均命中 km/h', () {
      expect(conv.convert(100, '公里每小时', 'm/s').fromUnit, 'km/h');
      expect(conv.convert(100, '千米每小时', 'm/s').fromUnit, 'km/h');
    });

    test('1 亩 → m2 = 666.667；1 斤 → kg = 0.5', () {
      expect(conv.convert(1, '亩', 'm2').value, closeTo(666.6667, 1e-3));
      expect(conv.convert(1, '斤', 'kg').value, closeTo(0.5, 1e-9));
    });
  });

  group('affine（温度）', () {
    test('100 ℃ → ℉ = 212', () {
      final r = conv.convert(100, '℃', '℉');
      expect(r.success, isTrue);
      expect(r.value, closeTo(212, 1e-6));
    });

    test('212 ℉ → c = 100', () {
      expect(conv.convert(212, '℉', 'c').value, closeTo(100, 1e-6));
    });

    test('0 c → K = 273.15；100 c → K = 373.15', () {
      expect(conv.convert(0, 'c', 'K').value, closeTo(273.15, 1e-9));
      expect(conv.convert(100, 'c', 'K').value, closeTo(373.15, 1e-9));
    });
  });

  group('reciprocal（油耗/能效）', () {
    test('跨制反比：8 l/100km → mpg = 235.215/8 = 29.4019', () {
      final r = conv.convert(8, 'l/100km', 'mpg');
      expect(r.success, isTrue);
      expect(r.value, closeTo(29.4019, 1e-3));
      expect(r.formula, contains('235.215'));
    });

    test('跨制反比：8 l/100km → km/L = 100/8 = 12.5', () {
      expect(conv.convert(8, 'l/100km', 'km/l').value, closeTo(12.5, 1e-9));
    });

    test('同制正比：8 mpg → km/L', () {
      final r = conv.convert(8, 'mpg', 'km/l');
      expect(r.value, closeTo(8 * 100 / 235.215, 1e-9));
    });

    test('输入 0 → DIVISION_BY_ZERO', () {
      final r = conv.convert(0, 'l/100km', 'mpg');
      expect(r.success, isFalse);
      expect(r.code, 'DIVISION_BY_ZERO');
      expect(r.value, isNull);
    });
  });

  group('iec_si（存储 SI/IEC 显式区分）', () {
    test('1 MB = 1e6 字节；1 MiB = 1048576 字节', () {
      expect(conv.convert(1, 'mb', 'b').value, closeTo(1e6, 1e-3));
      expect(conv.convert(1, 'mib', 'b').value, closeTo(1048576, 1e-3));
    });

    test('1 MB → MiB = 0.953674', () {
      expect(conv.convert(1, 'mb', 'mib').value, closeTo(0.953674, 1e-6));
    });

    test('1 KB → KiB = 0.9765625', () {
      expect(conv.convert(1, 'kb', 'kib').value, closeTo(0.9765625, 1e-9));
    });
  });

  group('错误模型', () {
    test('跨量纲 m → kg → DIMENSION_MISMATCH', () {
      final r = conv.convert(1, 'm', 'kg');
      expect(r.success, isFalse);
      expect(r.code, 'DIMENSION_MISMATCH');
      expect(r.message, contains('length'));
      expect(r.message, contains('mass'));
    });

    test('未知单位附 candidates 自愈（不被单字符噪声污染）', () {
      final r = conv.convert(1, 'mphs', 'km/h');
      expect(r.success, isFalse);
      expect(r.code, 'UNKNOWN_UNIT');
      expect(r.candidates, contains('mph'));
      expect(r.candidates, isNot(contains('s')));
    });

    test('完全未知单位不崩溃、candidates 可为空', () {
      final r = conv.convert(1, 'zzzz', 'km/h');
      expect(r.success, isFalse);
      expect(r.candidates, isA<List<String>?>());
    });
  });

  group('注册表', () {
    test('11 量纲，各带基准单位', () {
      expect(UnitRegistry.dimensions.length, 11);
      for (final d in UnitRegistry.dimensions) {
        expect(UnitRegistry.baseOf(d), isNotNull, reason: '量纲 $d 缺基准单位');
      }
      expect(UnitRegistry.baseOf('speed')!.id, 'm/s');
      expect(UnitRegistry.baseOf('storage')!.id, 'b');
      expect(UnitRegistry.baseOf('fuel_economy')!.id, 'l/100km');
    });

    test('裸 c 归属摄氏度（与光速的歧义已消解）', () {
      expect(UnitRegistry.find('c')!.id, 'c');
      expect(UnitRegistry.find('c')!.dimension, 'temperature');
      expect(UnitRegistry.find('lightspeed')!.id, 'lightspeed');
    });

    test('符号归一：℃/℉/m²/sq ft', () {
      expect(UnitRegistry.find('℃')!.id, 'c');
      expect(UnitRegistry.find('℉')!.id, 'f');
      expect(UnitRegistry.find('m²')!.id, 'm2');
      expect(UnitRegistry.find('sq ft')!.id, 'ft2');
    });
  });

  group('自省 unit_list', () {
    test('无参返回量纲概览', () {
      final dims = conv.listDimensions();
      expect(dims.length, 11);
      expect(dims.first['dimension'], 'area'); // 升序第一项
      expect(dims.first['baseUnit'], 'm2');
    });

    test('带 dimension 展开单位明细', () {
      final units = conv.listUnits(dimension: 'speed');
      expect(units.length, 5);
      expect(units.map((u) => u['id']), containsAll(['m/s', 'km/h', 'mph']));
      expect(units.first['name'], isNotNull);
    });

    test('带 search 过滤', () {
      final units = conv.listUnits(dimension: 'speed', search: '英里');
      expect(units.length, 1);
      expect(units.first['id'], 'mph');
    });
  });
}
