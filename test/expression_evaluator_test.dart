library;

/// 表达式求值器单测（纯 Dart，无设备可跑）。
///
/// 对应 calculator.md「精度要求」「健壮性」「结构化错误模型」「DoS 防御」。
/// 重点验证 Decimal 主链路精确性（0.1+0.2）、运算符语义、超越函数、
/// 单位换算、错误码与 EVAL_STEP_LIMIT。
import 'package:flutter_test/flutter_test.dart';
import 'package:good_template/tools/math/expression_evaluator.dart';

/// 解析并求值，返回格式化字符串（便于断言）。
String evalStr(String src) {
  final r = ExpressionEvaluator.evalExpression(src);
  expect(r.ok, isTrue, reason: '应求值成功：$src → ${r.error}');
  return formatDecimal(r.value!);
}

EvalResult evalResult(String src, {int maxSteps = 100000}) =>
    ExpressionEvaluator.evalExpression(src, maxSteps: maxSteps);

void main() {
  group('Decimal 精确性（核心诉求）', () {
    test('0.1 + 0.2 = 0.3（非 0.30000000000000004）', () {
      expect(evalStr('0.1 + 0.2'), '0.3');
    });

    test('2580 * 0.8 = 2064', () {
      expect(evalStr('2580 * 0.8'), '2064');
    });

    test('0.1 + 0.2 + 0.3 = 0.6（链式不累计误差）', () {
      expect(evalStr('0.1 + 0.2 + 0.3'), '0.6');
    });

    test('1 / 3 非精确但稳定（Decimal 有理截断）', () {
      expect(evalStr('1 / 3'), '0.333333333333');
    });
  });

  group('运算符语义', () {
    test('2 + 3 * 4 = 14', () => expect(evalStr('2 + 3 * 4'), '14'));
    test('(2 + 3) * 4 = 20', () => expect(evalStr('(2 + 3) * 4'), '20'));
    test('2 ^ 3 ^ 2 = 512（右结合）', () => expect(evalStr('2 ^ 3 ^ 2'), '512'));
    test('-2 ^ 2 = -4（一元负号低于 ^）', () => expect(evalStr('-2 ^ 2'), '-4'));
    test('(-2) ^ 2 = 4（负底数整数幂）', () => expect(evalStr('(-2) ^ 2'), '4'));
    test('(-2) ^ 3 = -8', () => expect(evalStr('(-2) ^ 3'), '-8'));
    test('2 ^ -2 = 0.25', () => expect(evalStr('2 ^ -2'), '0.25'));
    test('50% = 0.5', () => expect(evalStr('50%'), '0.5'));
    test('200 * 10% = 20', () => expect(evalStr('200 * 10%'), '20'));
    test('2pi ≈ 6.28318530718', () {
      final s = evalStr('2pi');
      expect(s, startsWith('6.2831853071'));
    });
    test('5sqrt(9) = 15（隐式乘法）', () => expect(evalStr('5sqrt(9)'), '15'));
  });

  group('超越函数', () {
    test('sqrt(9) = 3', () => expect(evalStr('sqrt(9)'), '3'));
    test('sqrt(2) ≈ 1.41421356237', () {
      expect(evalStr('sqrt(2)'), startsWith('1.4142135623'));
    });
    test('abs(-7) = 7', () => expect(evalStr('abs(-7)'), '7'));
    test('min(3, 8) = 3', () => expect(evalStr('min(3, 8)'), '3'));
    test('max(3, 8) = 8', () => expect(evalStr('max(3, 8)'), '8'));
    test('mod(10, 3) = 1', () => expect(evalStr('mod(10, 3)'), '1'));
    test('pow(2, 10) = 1024', () => expect(evalStr('pow(2, 10)'), '1024'));
    test('sin(0) = 0', () => expect(evalStr('sin(0)'), '0'));
    test('ln(e) = 1', () => expect(evalStr('ln(2.718281828459045)'), '1'));
  });

  group('内联 to 换算', () {
    test('320 km/h to m/s = 88.888...', () {
      expect(evalStr('320 km/h to m/s'), startsWith('88.8888888888'));
    });

    test('100 斤 to kg = 50', () => expect(evalStr('100 斤 to kg'), '50'));
  });

  group('错误模型', () {
    test('除零 → DIVISION_BY_ZERO', () {
      final r = evalResult('1 / 0');
      expect(r.ok, isFalse);
      expect(r.error!.code, 'DIVISION_BY_ZERO');
    });

    test('未知函数 → UNKNOWN_FUNCTION（带候选）', () {
      final r = evalResult('sqr(2)');
      expect(r.ok, isFalse);
      expect(r.error!.code, 'UNKNOWN_FUNCTION');
      expect(r.error!.candidates, isNotEmpty);
    });

    test('未定义变量 → UNDEFINED_VARIABLE', () {
      final r = evalResult('x');
      expect(r.ok, isFalse);
      expect(r.error!.code, 'UNDEFINED_VARIABLE');
    });

    test('负数开平方 → MATH_DOMAIN_ERROR', () {
      final r = evalResult('sqrt(-1)');
      expect(r.ok, isFalse);
      expect(r.error!.code, 'MATH_DOMAIN_ERROR');
    });

    test('参数个数不符 → ARGUMENT_COUNT_MISMATCH', () {
      final r = evalResult('sqrt(1, 2)');
      expect(r.ok, isFalse);
      expect(r.error!.code, 'ARGUMENT_COUNT_MISMATCH');
    });

    test('求值步数超限 → EVAL_STEP_LIMIT', () {
      final r = evalResult('1 + 1', maxSteps: 2);
      expect(r.ok, isFalse);
      expect(r.error!.code, 'EVAL_STEP_LIMIT');
    });

    test('词法层错误透传（超长）', () {
      final r = evalResult('1 + ' * 600);
      expect(r.ok, isFalse);
      // 超长优先在词法层被 EXPR_TOO_LONG 拦截
      expect(r.error!.code, 'EXPR_TOO_LONG');
    });
  });
}
