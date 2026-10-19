library;

import 'dart:math' as math;
import 'package:decimal/decimal.dart';
import 'expression_lexer.dart';
import 'expression_parser.dart';
import 'math_error.dart';
import 'unit_converter.dart';

/// 求值结果。失败带 [MathError]——**永不返回 null**。
class EvalResult {
  const EvalResult.ok(this.value) : error = null;
  const EvalResult.fail(this.error) : value = null;

  final Decimal? value;
  final MathError? error;

  bool get ok => error == null;
}

/// 表达式求值器（Decimal 主链路，calculator.md「精度 / 健壮性」）。
///
/// - 四则、百分比、整数幂在 [Decimal] 上精确求值（`0.1 + 0.2 == 0.3`）；
/// - 超越函数（`sqrt`/`sin`/`ln`/…）与单位换算因固有非精确性走 `double`，
///   结果回装 [Decimal]（换算因子本就是近似常量，属设计内，非静默降级）；
/// - DoS 防御：[EVAL_STEP_LIMIT] 限制求值步数，配合 Lexer 的
///   [EXPR_TOO_LONG] 与 Parser 的 [NESTING_TOO_DEEP]。
class ExpressionEvaluator {
  const ExpressionEvaluator._();

  /// 单表达式最大求值步数（AST 节点访问次数），超出即 [EVAL_STEP_LIMIT]。
  static const int maxSteps = 100000;

  static EvalResult evaluate(AstNode node, {int maxSteps = maxSteps}) {
    final ev = _Evaluator(maxSteps);
    try {
      return EvalResult.ok(ev.eval(node));
    } on _EvalError catch (e) {
      return EvalResult.fail(e.error);
    }
  }

  /// 一站式：词法 → 语法 → 求值。任一层失败透传其错误。
  static EvalResult evalExpression(String src, {int maxSteps = maxSteps}) {
    final lex = ExpressionLexer.lex(src);
    if (!lex.ok) return EvalResult.fail(lex.error!);
    final parsed = ExpressionParser.parse(lex);
    if (!parsed.ok) return EvalResult.fail(parsed.error!);
    return evaluate(parsed.ast!, maxSteps: maxSteps);
  }
}

class _EvalError {
  _EvalError(this.error);
  final MathError error;
}

class _Evaluator {
  _Evaluator(this.maxSteps);
  final int maxSteps;
  int _steps = 0;

  Never _fail(String code, String message,
      {String? suggestion, List<String>? candidates}) {
    throw _EvalError(MathError(
      code: code,
      offset: 0,
      message: message,
      suggestion: suggestion,
      candidates: candidates,
    ));
  }

  Decimal eval(AstNode node) {
    _steps++;
    if (_steps > maxSteps) {
      _fail('EVAL_STEP_LIMIT', '表达式求值步数超过 $maxSteps',
          suggestion: '拆分表达式或降低嵌套层数');
    }
    switch (node) {
      case NumberNode n:
        return Decimal.parse(n.raw);
      case IdentNode n:
        return _evalIdent(n.name);
      case UnaryNode n:
        final v = eval(n.operand);
        return n.op == '-' ? -v : v;
      case PostfixPercentNode n:
        return (eval(n.operand) / Decimal.fromInt(100)).toDecimal();
      case BinaryNode n:
        return _evalBinary(n.op, n.left, n.right);
      case CallNode n:
        return _evalCall(n.name, n.args);
      case ConvertNode n:
        return _evalConvert(n);
    }
  }

  Decimal _evalIdent(String name) {
    switch (name) {
      case 'pi':
        return Decimal.parse(math.pi.toString());
      case 'e':
        return Decimal.parse(math.e.toString());
      default:
        _fail('UNDEFINED_VARIABLE',
            "未定义标识符 '$name'（仅支持常量 pi / e 与函数调用）",
            candidates: _similarName(name, const ['pi', 'e']));
    }
  }

  Decimal _evalBinary(String op, AstNode left, AstNode right) {
    final l = eval(left);
    final r = eval(right);
    switch (op) {
      case '+':
        return l + r;
      case '-':
        return l - r;
      case '*':
        return l * r;
      case '/':
        if (r == Decimal.zero) {
          _fail('DIVISION_BY_ZERO', '除数不能为 0', suggestion: '检查分母是否为 0');
        }
        return (l / r).toDecimal(scaleOnInfinitePrecision: 30);
      case '^':
        return _pow(l, r);
      default:
        _fail('UNEXPECTED_TOKEN', '未知运算符 "$op"');
    }
  }

  /// `base^exp`：整数指数走 [Decimal] 精确幂；否则走 double（超越运算固有近似）。
  Decimal _pow(Decimal base, Decimal exp) {
    if (_isWhole(exp)) {
      final e = int.parse(exp.round().toString());
      if (e < 0 && base == Decimal.zero) {
        _fail('DIVISION_BY_ZERO', '0 的负数次幂无定义',
            suggestion: '检查底数与指数');
      }
      return _intPow(base, e);
    }
    final d = math.pow(base.toDouble(), exp.toDouble()).toDouble();
    if (d.isNaN || d.isInfinite) {
      _fail('MATH_DOMAIN_ERROR', '幂运算结果未定义（如负数开分数次幂）');
    }
    return _toDecimal(d);
  }

  /// 自实现整数幂：正确处理负底数（符号随奇偶）与负指数（= 1 / |base|^|e|），
  /// 避免依赖 Decimal.pow 的符号行为。
  Decimal _intPow(Decimal base, int e) {
    if (e == 0) return Decimal.fromInt(1);
    final sign = (base < Decimal.zero && e.isOdd) ? -1 : 1;
    var b = base.abs();
    var res = Decimal.fromInt(1);
    var exp = e.abs();
    while (exp > 0) {
      if (exp.isOdd) res *= b;
      b *= b;
      exp ~/= 2;
    }
    final magnitude = res * Decimal.fromInt(sign);
    if (e < 0) {
      return (Decimal.fromInt(1) / magnitude).toDecimal(scaleOnInfinitePrecision: 30);
    }
    return magnitude;
  }

  Decimal _evalCall(String name, List<AstNode> args) {
    final evaluated = args.map(eval).toList();
    switch (name) {
      // —— Decimal 精确（无超越）——
      case 'abs':
        _arity(name, evaluated, 1);
        return evaluated[0].abs();
      case 'min':
        _arity(name, evaluated, 2);
        return evaluated[0] <= evaluated[1] ? evaluated[0] : evaluated[1];
      case 'max':
        _arity(name, evaluated, 2);
        return evaluated[0] >= evaluated[1] ? evaluated[0] : evaluated[1];
      case 'mod':
        _arity(name, evaluated, 2);
        if (evaluated[1] == Decimal.zero) {
          _fail('DIVISION_BY_ZERO', 'mod 的除数不能为 0');
        }
        return evaluated[0] % evaluated[1];
      case 'pow':
        _arity(name, evaluated, 2);
        return _pow(evaluated[0], evaluated[1]);

      // —— 超越函数：走 double 回装 Decimal ——
      case 'sqrt':
        return _fn1(name, evaluated, math.sqrt,
            domain: (a) => a < 0, domainMsg: 'sqrt 不支持负数');
      case 'cbrt':
        return _fn1(name, evaluated, (a) => math.pow(a, 1 / 3).toDouble());
      case 'ln':
        return _fn1(name, evaluated, math.log,
            domain: (a) => a <= 0, domainMsg: 'ln 要求输入 > 0');
      case 'log':
      case 'log10':
        return _fn1(name, evaluated, (a) => math.log(a) / math.ln10,
            domain: (a) => a <= 0, domainMsg: 'log 要求输入 > 0');
      case 'exp':
        return _fn1(name, evaluated, math.exp,
            domain: (a) => a.abs() > 700, domainMsg: 'exp 输入过大导致溢出');
      case 'sin':
        return _fn1(name, evaluated, math.sin);
      case 'cos':
        return _fn1(name, evaluated, math.cos);
      case 'tan':
        return _fn1(name, evaluated, math.tan);
      case 'asin':
        return _fn1(name, evaluated, math.asin,
            domain: (a) => a < -1 || a > 1, domainMsg: 'asin 输入须在 [-1,1]');
      case 'acos':
        return _fn1(name, evaluated, math.acos,
            domain: (a) => a < -1 || a > 1, domainMsg: 'acos 输入须在 [-1,1]');
      case 'atan':
        return _fn1(name, evaluated, math.atan);
      case 'floor':
        return _fn1(name, evaluated, (a) => a.floorToDouble());
      case 'ceil':
        return _fn1(name, evaluated, (a) => a.ceilToDouble());
      case 'round':
        return _fn1(name, evaluated, (a) => a.roundToDouble());
      case 'sign':
        return _fn1(name, evaluated, (a) => a.sign);

      default:
        _fail('UNKNOWN_FUNCTION', "未知函数 '$name'",
            candidates: _similarName(name, _knownFns));
    }
  }

  void _arity(String name, List<Decimal> args, int want) {
    if (args.length != want) {
      _fail('ARGUMENT_COUNT_MISMATCH',
          "函数 '$name' 需要 $want 个参数，收到 ${args.length} 个",
          suggestion: '检查参数个数与分隔逗号');
    }
  }

  /// 单参超越函数：[domain] 越界时 [MATH_DOMAIN_ERROR]，结果 NaN/Inf 同样报错。
  Decimal _fn1(String name, List<Decimal> args, double Function(double) f,
      {bool Function(double)? domain, String? domainMsg}) {
    _arity(name, args, 1);
    final x = args[0].toDouble();
    if (domain != null && domain(x)) {
      _fail('MATH_DOMAIN_ERROR', domainMsg ?? "函数 '$name' 收到越界输入");
    }
    final d = f(x);
    if (d.isNaN || d.isInfinite) {
      _fail('MATH_DOMAIN_ERROR', "函数 '$name' 计算结果未定义");
    }
    return _toDecimal(d);
  }

  Decimal _evalConvert(ConvertNode n) {
    final v = eval(n.value);
    final conv = const UnitConverter().convert(v.toDouble(), n.fromUnit, n.toUnit);
    if (!conv.success) {
      _fail(conv.code!, conv.message!, candidates: conv.candidates);
    }
    return _toDecimal(conv.value!);
  }

  bool _isWhole(Decimal d) => d == d.round();

  /// double → Decimal。double.toString() 为标准十进制/科学计数法，
  /// Decimal.parse 可解析；结果本就近似（超越/单位固有），精确性非诉求。
  Decimal _toDecimal(double d) => Decimal.parse(d.toString());

  List<String> _similarName(String name, List<String> candidates) {
    int dist(String a, String b) {
      if (a == b) return 0;
      final m = a.length, n = b.length;
      if (m == 0) return n;
      if (n == 0) return m;
      var prev = List<int>.generate(n + 1, (i) => i);
      for (var i = 1; i <= m; i++) {
        final cur = List<int>.filled(n + 1, 0);
        cur[0] = i;
        for (var j = 1; j <= n; j++) {
          final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
          cur[j] = [
            prev[j] + 1,
            cur[j - 1] + 1,
            prev[j - 1] + cost,
          ].reduce((a, b) => a < b ? a : b);
        }
        prev = cur;
      }
      return prev[n];
    }

    return candidates.where((c) => dist(name, c) <= 2).toList();
  }

  static const List<String> _knownFns = [
    'sqrt', 'cbrt', 'abs', 'ln', 'log', 'log10', 'exp', 'sin', 'cos', 'tan',
    'asin', 'acos', 'atan', 'floor', 'ceil', 'round', 'sign', 'min', 'max',
    'mod', 'pow',
  ];
}

/// 数值展示格式化：四舍五入到 [scale] 位小数并去尾随 0。
///
/// `Decimal` 主链路保证 `0.1+0.2 → 0.3` 此类精确结果不被末尾噪声污染；
/// 超越/单位结果本就近似，按 [scale] 截断足矣。
String formatDecimal(Decimal d, {int scale = 12}) {
  final factor = Decimal.fromInt(10).pow(scale).toDecimal();
  final result = ((d * factor).round() / factor).toDecimal();
  var s = result.toString();
  if (s.contains('.')) {
    s = s.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
  }
  return s.isEmpty ? '0' : s;
}
