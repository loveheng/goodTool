library;

/// 单位换算模型（`docs/product/calculator.md`）。
///
/// 注册表每个单位声明其 [TransformType]，引擎按类型套用**纯函数**——
/// 新增类型才改引擎，主链路不动（向后兼容纪律）。
enum TransformType {
  /// `out = in × factor_from / factor_to`（默认）。
  linear,

  /// `base = in × a_from + b_from`；`out = (base − b_to) / a_to`（温度，含原点偏移）。
  affine,

  /// 油耗/能效：消耗制（`l/100km`）与里程制（`mpg`/`km/L`）跨制严格反比例。
  reciprocal,

  /// 仅数据存储：SI（1000ⁿ）与 IEC（1024ⁿ）以**不同单位 ID** 承载。
  iecSi,
}

/// 单位定义。
///
/// [id] 为归一化后的标准代号（`unit_list` 自省与出参 `fromUnit`/`toUnit` 引用它）；
/// [aliases] 为归一化后命中的别名（大小写/符号容错），[symbols] 为人类可读展示符号。
class UnitDefinition {
  const UnitDefinition({
    required this.id,
    required this.name,
    required this.dimension,
    this.transform = TransformType.linear,
    this.factor = 1.0,
    this.offset = 0.0,
    this.reciprocalK = 0.0,
    this.aliases = const [],
    this.symbols = const [],
  });

  /// 标准代号（如 `km/h`、`MiB`、`l/100km`）。
  final String id;

  /// 中文名（自省 `unit_list` 输出用）。
  final String name;

  /// 所属量纲（如 `length`、`storage`）。
  final String dimension;

  final TransformType transform;

  /// linear / iecSi：相对**基准单位**的系数（如 `km` 相对 `m` = 1000）。
  final double factor;

  /// affine：原点平移量（作用于 factor 之后，如 K = C + 273.15）。
  final double offset;

  /// reciprocal：基准能效（`l/100km` = 1）时的单位值。
  final double reciprocalK;

  /// 归一化后命中的别名。
  final List<String> aliases;

  /// 人类可读符号。
  final List<String> symbols;

  /// 自省输出形状（`unit_list` 展开层）。
  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'symbols': symbols.isEmpty ? [id] : symbols,
      };
}
