library;

/// 表达式 / 换算的结构化错误（`docs/product/calculator.md`「结构化错误模型」）。
///
/// 铁律：**永不返回 null / 空响应**——失败一律带机器可读 [code] + 人类可读
/// [message]，可纠正分支附 [suggestion] 与 [candidates]，供 Agent 下一轮
/// 直接修正、UI 输入框下划线标红。
class MathError {
  const MathError({
    required this.code,
    required this.offset,
    required this.message,
    this.suggestion,
    this.candidates,
  });

  /// 机器码，至少覆盖 calculator.md 枚举：`UNEXPECTED_TOKEN` /
  /// `UNMATCHED_PARENTHESIS` / `UNDEFINED_SYMBOL` / `ARGUMENT_COUNT_MISMATCH` /
  /// `DIMENSION_MISMATCH` / `UNKNOWN_UNIT` / `UNEXPECTED_UNIT_IN_EXPR` /
  /// `AGG_EMPTY` / `UNDEFINED_VARIABLE` / `DIVISION_BY_ZERO` /
  /// `EXPR_TOO_LONG` / `NESTING_TOO_DEEP` / `EVAL_STEP_LIMIT`。
  final String code;

  /// 出错字符在**原始输入串**中的 0 起偏移（Sanitizer 位移已回填）。
  final int offset;

  /// 人类可读说明（可含上下文片段）。
  final String message;

  /// 纠错建议（如「是否想使用 'mph'？」）。
  final String? suggestion;

  /// 近邻合法候选（单位别名 / 合法算子 / 近似函数名 / 变量名）。
  final List<String>? candidates;

  Map<String, Object?> toJson() => {
        'code': code,
        'offset': offset,
        'message': message,
        if (suggestion != null) 'suggestion': suggestion,
        if (candidates != null && candidates!.isNotEmpty) 'candidates': candidates,
      };
}
