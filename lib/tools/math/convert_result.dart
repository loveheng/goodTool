library;

/// 单位换算结果（纯函数出口，无 MCP 形状耦合）。
///
/// 失败统一带机器可读 [code] + [message] + [candidates]（自愈），
/// **永不返回 null**——交由上层转结构化信封，禁静默兜底
/// （`docs/product/calculator.md`「结构化错误模型」）。
class ConvertResult {
  const ConvertResult._({
    required this.success,
    this.value,
    this.fromUnit,
    this.toUnit,
    this.formula,
    this.code,
    this.message,
    this.candidates,
    this.warning,
  });

  const ConvertResult.ok({
    required double value,
    required String fromUnit,
    required String toUnit,
    required String formula,
    String? warning,
  }) : this._(
          success: true,
          value: value,
          fromUnit: fromUnit,
          toUnit: toUnit,
          formula: formula,
          warning: warning,
        );

  const ConvertResult.fail(String code, String message,
      {List<String>? candidates})
      : this._(
          success: false,
          code: code,
          message: message,
          candidates: candidates,
        );

  final bool success;

  /// 换算数值（失败为 null）。
  final double? value;

  /// 归一化后的标准代号（成功非空）。
  final String? fromUnit;
  final String? toUnit;

  /// 换算过程明细（供 UI 步骤抽屉 / Agent 解释）。
  final String? formula;

  /// 机器码：`UNKNOWN_UNIT` / `DIMENSION_MISMATCH` / `DIVISION_BY_ZERO`。
  final String? code;

  /// 人类可读说明。
  final String? message;

  /// 近邻合法候选（未知单位自愈）。
  final List<String>? candidates;

  /// 非致命提示（出现时 `success` 仍为 true）。
  final String? warning;
}
