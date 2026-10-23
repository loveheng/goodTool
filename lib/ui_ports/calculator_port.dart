library;

import '../tools/math/expression_evaluator.dart';
import '../tools/math/unit_converter.dart';

/// 计算器 UI 视图模型（**类型化对象**，绝不透传 MCP 文本信封）。
///
/// 铁律：UI 渲染的数据必须是类型化对象——若 UI 吃 `McpToolFace.call` 的
/// `{content,isError}` 文本信封，必定要 `jsonDecode` → 触 R2
/// （ui-design §8.3 规则 2）。
class CalcView {
  const CalcView({
    required this.ok,
    this.text,
    this.numeric,
    this.formula,
    this.errorCode,
    this.message,
    this.suggestion,
    this.candidates = const <String>[],
    this.warning,
  });

  /// 是否成功。
  final bool ok;

  /// 格式化展示串（人类可读）。
  final String? text;

  /// 机器数值（Decimal 字符串，超 double 无损范围不丢精度）。
  final String? numeric;

  /// 换算过程明细（供步骤抽屉）。
  final String? formula;

  /// 机器码（失败时非空）。
  final String? errorCode;

  /// 人类可读说明。
  final String? message;

  /// 自愈建议（可纠正分支）。
  final String? suggestion;

  /// 近邻合法候选（未知单位自愈）。
  final List<String> candidates;

  /// 非致命提示（成功但有告警）。
  final String? warning;
}

/// 计算器 UI 适配层：收口内核调用 + 错误归一，供 `lib/ui` 直接消费。
///
/// **双轨出参**（与 MCP 侧同口径）：格式化 `text` + 无损 `numeric`——
/// 避免「UI 看起来准、Agent 拿到的是另一个数」。
class CalculatorPort {
  const CalculatorPort([this._converter = const UnitConverter()]);

  final UnitConverter _converter;

  /// 表达式求值。
  CalcView eval(String expression) {
    final result = ExpressionEvaluator.evalExpression(expression);
    if (!result.ok) {
      final error = result.error!;
      return CalcView(
        ok: false,
        errorCode: error.code,
        message: error.message,
        suggestion: error.suggestion,
        candidates: error.candidates ?? const <String>[],
      );
    }
    final value = result.value!;
    return CalcView(ok: true, text: value.toString(), numeric: value.toString());
  }

  /// 单位换算。
  CalcView convert(double value, String from, String to) {
    final result = _converter.convert(value, from, to);
    if (!result.success) {
      return CalcView(
        ok: false,
        errorCode: result.code,
        message: result.message,
        candidates: result.candidates ?? const <String>[],
      );
    }
    return CalcView(
      ok: true,
      text: '${result.value} ${result.toUnit}',
      numeric: '${result.value}',
      formula: result.formula,
      warning: result.warning,
    );
  }
}
