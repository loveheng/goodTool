library;

/// 表达式解析器单测（纯 Dart，无设备可跑）。
///
/// 对应 calculator.md「算子优先级与结合性」「隐式乘法」「百分比语义」
/// 及「DoS 防御（NESTING_TOO_DEEP）」。仅验证 AST 结构与错误/告警模型，
/// 数值求值由 S3d 求值器覆盖。
import 'package:flutter_test/flutter_test.dart';
import 'package:good_template/tools/math/expression_lexer.dart';
import 'package:good_template/tools/math/expression_parser.dart';

ParseResult parse(String src) =>
    ExpressionParser.parse(ExpressionLexer.lex(src));

// ── AST 取值小工具（避免每例重复 as 转换）─────────────────────────
NumberNode asNum(AstNode n) => n as NumberNode;
BinaryNode asBin(AstNode n) => n as BinaryNode;
UnaryNode asUnary(AstNode n) => n as UnaryNode;
IdentNode asIdent(AstNode n) => n as IdentNode;
CallNode asCall(AstNode n) => n as CallNode;
ConvertNode asConvert(AstNode n) => n as ConvertNode;
PostfixPercentNode asPct(AstNode n) => n as PostfixPercentNode;

void main() {
  group('优先级与结合性', () {
    test('2+3*4 → +(2, *(3,4))', () {
      final ast = parse('2+3*4').ast!;
      final bin = asBin(ast);
      expect(bin.op, '+');
      expect(asNum(bin.left).value, 2);
      final r = asBin(bin.right);
      expect(r.op, '*');
      expect(asNum(r.left).value, 3);
      expect(asNum(r.right).value, 4);
    });

    test('(2+3)*4 → *(+(2,3), 4)', () {
      final bin = asBin(parse('(2+3)*4').ast!);
      expect(bin.op, '*');
      expect(asBin(bin.left).op, '+');
      expect(asNum(bin.right).value, 4);
    });

    test('^ 右结合：2^3^2 → ^(2, ^(3,2))', () {
      final bin = asBin(parse('2^3^2').ast!);
      expect(bin.op, '^');
      expect(asNum(bin.left).value, 2);
      final r = asBin(bin.right);
      expect(r.op, '^');
      expect(asNum(r.left).value, 3);
      expect(asNum(r.right).value, 2);
    });

    test('-2^2 = -(2^2)（一元负号低于 ^）', () {
      final un = asUnary(parse('-2^2').ast!);
      expect(un.op, '-');
      final bin = asBin(un.operand);
      expect(bin.op, '^');
      expect(asNum(bin.left).value, 2);
      expect(asNum(bin.right).value, 2);
    });

    test('2*-3 → *(2, -(3))', () {
      final bin = asBin(parse('2*-3').ast!);
      expect(bin.op, '*');
      expect(asNum(bin.left).value, 2);
      expect(asUnary(bin.right).op, '-');
      expect(asNum(asUnary(bin.right).operand).value, 3);
    });

    test('-(3+2) → -(5)', () {
      final un = asUnary(parse('-(3+2)').ast!);
      expect(un.op, '-');
      expect(asBin(un.operand).op, '+');
    });
  });

  group('隐式乘法', () {
    test('2pi → *(2, pi)', () {
      final bin = asBin(parse('2pi').ast!);
      expect(bin.op, '*');
      expect(asNum(bin.left).value, 2);
      expect(asIdent(bin.right).name, 'pi');
    });

    test('5sqrt(9) → *(5, sqrt(9))', () {
      final bin = asBin(parse('5sqrt(9)').ast!);
      expect(bin.op, '*');
      expect(asNum(bin.left).value, 5);
      final call = asCall(bin.right);
      expect(call.name, 'sqrt');
      expect(asNum(call.args[0]).value, 9);
    });

    test('2(3)(4) → *( *(2,3), 4)', () {
      final outer = asBin(parse('2(3)(4)').ast!);
      expect(outer.op, '*');
      final inner = asBin(outer.left);
      expect(inner.op, '*');
      expect(asNum(inner.left).value, 2);
      expect(asNum(inner.right).value, 3);
      expect(asNum(outer.right).value, 4);
    });

    test('2(3+4) → *(2, +(3,4))', () {
      final bin = asBin(parse('2(3+4)').ast!);
      expect(bin.op, '*');
      expect(asBin(bin.right).op, '+');
    });

    test('2 3（两数字相邻）不隐式乘，报 UNEXPECTED_TOKEN', () {
      final r = parse('2 3');
      expect(r.ok, isFalse);
      expect(r.error!.code, 'UNEXPECTED_TOKEN');
    });
  });

  group('百分比语义', () {
    test('50% → %(50)', () {
      final pct = asPct(parse('50%').ast!);
      expect(asNum(pct.operand).value, 50);
    });

    test('200*10% → *(200, %(10))', () {
      final bin = asBin(parse('200*10%').ast!);
      expect(bin.op, '*');
      expect(asNum(bin.left).value, 200);
      expect(asPct(bin.right).operand is NumberNode, isTrue);
    });

    test('100 + 10% → 告警 PERCENT_AMBIGUITY，无错误', () {
      final r = parse('100 + 10%');
      expect(r.ok, isTrue);
      expect(r.warnings, isNotEmpty);
      expect(r.warnings.first.code, 'PERCENT_AMBIGUITY');
    });
  });

  group('函数调用', () {
    test('sum(1,2,3) → call(sum,[1,2,3])', () {
      final call = asCall(parse('sum(1,2,3)').ast!);
      expect(call.name, 'sum');
      expect(call.args.length, 3);
    });

    test('mod(a,b) 作为函数（非 % 取模）', () {
      final call = asCall(parse('mod(10,3)').ast!);
      expect(call.name, 'mod');
      expect(call.args.length, 2);
    });
  });

  group('内联 to 换算', () {
    test('320 km/h to m/s → Convert(320, km/h, m/s)', () {
      final c = asConvert(parse('320 km/h to m/s').ast!);
      expect(asNum(c.value).value, 320);
      expect(c.fromUnit, 'km/h');
      expect(c.toUnit, 'm/s');
    });

    test('换算可继续参与运算：320 km/h to m/s * 2', () {
      final bin = asBin(parse('320 km/h to m/s * 2').ast!);
      expect(bin.op, '*');
      expect(asConvert(bin.left).toUnit, 'm/s');
      expect(asNum(bin.right).value, 2);
    });
  });

  group('错误模型', () {
    test('括号不匹配 → UNMATCHED_PARENTHESIS', () {
      final r = parse('((2+3)');
      expect(r.ok, isFalse);
      expect(r.error!.code, 'UNMATCHED_PARENTHESIS');
    });

    test('运算符序列 2 + * 2 → UNEXPECTED_TOKEN 在 *', () {
      final r = parse('2 + * 2');
      expect(r.ok, isFalse);
      expect(r.error!.code, 'UNEXPECTED_TOKEN');
      expect(r.error!.message, contains('*'));
    });

    test('残缺表达式 2 + → UNEXPECTED_TOKEN', () {
      final r = parse('2 +');
      expect(r.ok, isFalse);
      expect(r.error!.code, 'UNEXPECTED_TOKEN');
    });

    test('孤立单位 → UNEXPECTED_TOKEN', () {
      final r = parse('km/h to m/s');
      expect(r.ok, isFalse);
      expect(r.error!.code, 'UNEXPECTED_TOKEN');
    });

    test('孤立 to → UNEXPECTED_TOKEN', () {
      final r = parse('to m/s');
      expect(r.ok, isFalse);
      expect(r.error!.code, 'UNEXPECTED_TOKEN');
    });

    test('括号嵌套超 50 → NESTING_TOO_DEEP', () {
      final deep = '${'(' * 51}1${')' * 51}';
      final r = parse(deep);
      expect(r.ok, isFalse);
      expect(r.error!.code, 'NESTING_TOO_DEEP');
    });
  });

  group('位移回填', () {
    test('全角表达式解析后错误 offset 指向原串', () {
      // １＋＊２：＊ 在全角串下标 2，但词法层已规整，解析层错误应指向原始 2
      final r = parse('１＋＊２');
      expect(r.ok, isFalse);
      expect(r.error!.code, 'UNEXPECTED_TOKEN');
      expect(r.error!.offset, 2);
    });
  });
}
