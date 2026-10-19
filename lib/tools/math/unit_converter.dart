library;

import 'convert_result.dart';
import 'unit_definition.dart';
import 'unit_registry.dart';

/// 单位换算引擎：模型驱动 + 多模型分派（`docs/product/calculator.md`）。
///
/// 每个单位在 [UnitRegistry] 声明 [TransformType]，引擎按类型套用**纯函数**；
/// 新增换算模型才改 [convert] 的 dispatch，新增量纲/单位只扩注册表。
///
/// v1 不做符号量纲代数——复合单位以**预计算 `factor` 的具体条目**入库
/// （如 `km/h` 相对 `m/s` = 1/3.6），v2 再演进 `composite` 幂次模型。
class UnitConverter {
  const UnitConverter();

  /// 双向换算。[value] 为待换算数值，[fromRaw]/[toRaw] 接受任意别名写法。
  ///
  /// 错误码口径（calculator.md）：`UNKNOWN_UNIT`（附 candidates 自愈）、
  /// `DIMENSION_MISMATCH`、`DIVISION_BY_ZERO`（油耗倒数输入为 0）。
  ConvertResult convert(double value, String fromRaw, String toRaw) {
    final from = UnitRegistry.find(fromRaw);
    if (from == null) {
      return ConvertResult.fail(
        'UNKNOWN_UNIT',
        "未知单位 '$fromRaw'",
        candidates: UnitRegistry.findSimilar(fromRaw),
      );
    }
    final to = UnitRegistry.find(toRaw);
    if (to == null) {
      return ConvertResult.fail(
        'UNKNOWN_UNIT',
        "未知单位 '$toRaw'",
        candidates: UnitRegistry.findSimilar(toRaw),
      );
    }
    if (from.dimension != to.dimension) {
      return ConvertResult.fail('DIMENSION_MISMATCH',
          '无法在 ${from.dimension} 与 ${to.dimension} 之间换算');
    }

    switch (from.transform) {
      case TransformType.affine:
        return _convertAffine(value, from, to);
      case TransformType.reciprocal:
        return _convertReciprocal(value, from, to);
      case TransformType.linear:
      case TransformType.iecSi:
        return _convertLinear(value, from, to);
    }
  }

  /// `base = in × a_from + b_from`；`out = (base − b_to) / a_to`（温度）。
  ConvertResult _convertAffine(
      double value, UnitDefinition from, UnitDefinition to) {
    final base = value * from.factor + from.offset;
    final out = (base - to.offset) / to.factor;
    return ConvertResult.ok(
      value: out,
      fromUnit: from.id,
      toUnit: to.id,
      formula: '(($value × ${from.factor} + ${from.offset}) - ${to.offset}) '
          '/ ${to.factor}',
    );
  }

  /// 油耗/能效：**消耗制**（`l/100km`）与**里程制**（`mpg`/`km/L`/`mpg_uk`）
  /// 跨制走严格反比例；同制走正比例。
  ConvertResult _convertReciprocal(
      double value, UnitDefinition from, UnitDefinition to) {
    if (value <= 0) {
      return const ConvertResult.fail(
          'DIVISION_BY_ZERO', '油耗换算输入必须大于 0');
    }
    final isFromConsumption = from.id == 'l/100km';
    final isToConsumption = to.id == 'l/100km';
    final double out;
    if (isFromConsumption ^ isToConsumption) {
      // 跨制：out = (K_from × K_to) / in（如 l/100km → mpg = 235.215 / in）
      out = (from.reciprocalK * to.reciprocalK) / value;
      return ConvertResult.ok(
        value: out,
        fromUnit: from.id,
        toUnit: to.id,
        formula: '(${from.reciprocalK} × ${to.reciprocalK}) / $value',
      );
    }
    // 同制（均里程制，或均为 l/100km）：out = in × K_to / K_from
    out = value * (to.reciprocalK / from.reciprocalK);
    return ConvertResult.ok(
      value: out,
      fromUnit: from.id,
      toUnit: to.id,
      formula: '$value × (${to.reciprocalK} / ${from.reciprocalK})',
    );
  }

  /// `out = in × factor_from / factor_to`（linear 与 iecSi 共用，
  /// iecSi 的 factor 已按 SI 1000ⁿ / IEC 1024ⁿ 预置）。
  ConvertResult _convertLinear(
      double value, UnitDefinition from, UnitDefinition to) {
    final out = value * from.factor / to.factor;
    return ConvertResult.ok(
      value: out,
      fromUnit: from.id,
      toUnit: to.id,
      formula: '$value × (${from.factor} / ${to.factor})',
    );
  }

  /// 量纲概览（`unit_list` 无参时的一级目录）。
  List<Map<String, Object?>> listDimensions() =>
      UnitRegistry.dimensions.map((d) {
        final base = UnitRegistry.baseOf(d);
        return <String, Object?>{
          'dimension': d,
          'baseUnit': base?.id ?? d,
          'unitCount': UnitRegistry.unitsOf(d).length,
        };
      }).toList(growable: false);

  /// 单位明细（`unit_list` 带 `dimension`/`search` 时的展开层；
  /// 不带 [dimension] 时铺开全部单位）。
  List<Map<String, Object?>> listUnits({String? dimension, String? search}) {
    final units =
        dimension != null ? UnitRegistry.unitsOf(dimension) : UnitRegistry.allUnits;
    final q = search?.trim().toLowerCase();
    if (q == null || q.isEmpty) {
      return units.map((u) => u.toJson()).toList(growable: false);
    }
    return units
        .where((u) =>
            u.id.toLowerCase().contains(q) ||
            u.name.contains(q) ||
            u.aliases.any((a) => a.toLowerCase().contains(q)))
        .map((u) => u.toJson())
        .toList(growable: false);
  }
}
