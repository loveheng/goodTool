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

  /// 行内解析调度器（Soulver 草稿台单行口径）：宽容归一 → 单位换算 /
  /// 表达式求值分流，纯 Dart 可 headless 单测。
  ///
  /// - 空行返回 null（不参与结果列）；
  /// - `ans` 关键字（大小写不敏感）替换为 [ans] 指向的上一非空行数值，
  ///   引用而 [ans] 为 null 时返回类型化失败（不静默）；
  /// - `85%` 后缀归一为 `(85/100)`，绕开内核 `A+B%` 歧义分支；
  /// - 单位换算：`<表达式> <单位> to|in <单位>`，数值部分支持表达式
  ///   （如 `2*10 km to mi`），先求值再换算；
  /// - 中文/全角符号（× ÷ ＋ － （ ））在此层归一，内核词法面不感知。
  CalcView? evalLine(String rawLine, {String? ans}) {
    final line = rawLine.trim();
    if (line.isEmpty) return null;

    var normalized = line
        .replaceAll('×', '*')
        .replaceAll('÷', '/')
        .replaceAll('＋', '+')
        .replaceAll('－', '-')
        .replaceAll('（', '(')
        .replaceAll('）', ')');

    // ans 引用：先于其余处理（避免被百分号/单位正则误伤）。
    if (RegExp(r'\bans\b', caseSensitive: false).hasMatch(normalized)) {
      if (ans == null || ans.isEmpty) {
        return const CalcView(
          ok: false,
          errorCode: 'ANS_UNAVAILABLE',
          message: 'ans 引用失败：上一行没有可用结果',
        );
      }
      normalized = normalized.replaceAll(
        RegExp(r'\bans\b', caseSensitive: false),
        ans,
      );
    }

    // 百分号后缀：`85%` → `(85/100)`。
    normalized = normalized.replaceAllMapped(
      RegExp(r'(\d+(?:\.\d+)?)%'),
      (m) => '(${m.group(1)}/100)',
    );

    // 单位换算：数值部分可为表达式（先求值再换算）。单位串收中文
    // （公里/英里等，注册表别名直查）；连接字 to / in / 换算 同义。
    final unitMatch = RegExp(
      r'^(.+?)\s*([A-Za-z°μΩ\u4e00-\u9fff/]+)\s+(?:to|in|换算)\s+([A-Za-z°μΩ\u4e00-\u9fff/]+)$',
    ).firstMatch(normalized);
    if (unitMatch != null) {
      final raw = unitMatch.group(1)!.trim();
      final value = double.tryParse(raw) ?? _evalNumeric(raw);
      if (value != null) {
        return convert(value, unitMatch.group(2)!, unitMatch.group(3)!);
      }
    }

    return eval(normalized);
  }

  /// 求值纯数值表达式（单位换算的数值部分用）；失败返回 null 走常规求值。
  double? _evalNumeric(String expression) {
    final view = eval(expression);
    return view.ok ? double.tryParse(view.numeric ?? '') : null;
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
