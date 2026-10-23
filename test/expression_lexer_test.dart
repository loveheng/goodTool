library;

/// 表达式 Sanitizer + Lexer 单测（纯 Dart，无设备可跑）。
///
/// 对应 calculator.md「Sanitizer Pipeline」与「开发顺序门禁」第 2 层：
/// 预清洗、全角→半角、千分位剥离、币种符规整、to 关键字分割、隐式乘法边界。
import 'package:flutter_test/flutter_test.dart';
import 'package:good_template/tools/math/expression_lexer.dart';

List<TokenType> _types(List<Token> ts) => ts.map((t) => t.type).toList();

void main() {
  group('Sanitizer · 全角→半角', () {
    test('（２＋３）×４ → (2+3)*4', () {
      final r = ExpressionLexer.lex('（２＋３）×４');
      expect(r.ok, isTrue);
      expect(r.sanitized.text, '(2+3)*4');
      expect(r.sanitized.notes, contains('全角→半角'));
      expect(_types(r.tokens),
          [TokenType.lparen, TokenType.number, TokenType.plus, TokenType.number,
           TokenType.rparen, TokenType.star, TokenType.number]);
    });
  });

  group('Sanitizer · 千分位（保守，不误伤参数分隔）', () {
    test('1,000,000 + 1 → 1000000 + 1', () {
      final r = ExpressionLexer.lex('1,000,000 + 1');
      expect(r.sanitized.text, '1000000 + 1');
      expect(r.sanitized.notes, contains('千分位逗号规整'));
    });

    test('sum(1,2,3) 的逗号不被规整', () {
      final r = ExpressionLexer.lex('sum(1,2,3)');
      expect(r.sanitized.text, 'sum(1,2,3)');
      expect(r.sanitized.notes, isNot(contains('千分位逗号规整')));
      expect(_types(r.tokens).where((t) => t == TokenType.comma).length, 2);
    });

    test('1,5 小数位组不匹配，原样保留', () {
      final r = ExpressionLexer.lex('1,5 + 2');
      expect(r.sanitized.text, '1,5 + 2');
    });
  });

  group('Sanitizer · 币种符剔除', () {
    test('¥2580 * 0.8 → 2580 * 0.8', () {
      final r = ExpressionLexer.lex('¥2580 * 0.8');
      expect(r.sanitized.text, '2580 * 0.8');
      expect(r.sanitized.notes, contains('剔除货币符'));
    });

    test('\$100 → 100', () {
      expect(ExpressionLexer.lex('\$100').sanitized.text, '100');
    });
  });

  group('Sanitizer · 位移回填到原始输入', () {
    test('币种符删除后 offset 仍指向原串位置', () {
      // 原始： ¥ 2 5 8 0 _ * _ * _ 2
      // 清洗：  2 5 8 0 _ * _ * _ 2
      // 第二个 * 在清洗串下标 7 → 原串下标 8
      final r = ExpressionLexer.lex('¥2580 * * 2');
      expect(r.ok, isTrue);
      final stars = r.tokens.where((t) => t.type == TokenType.star).toList();
      expect(stars.length, 2);
      expect(r.sanitized.originalOffset(stars[1].start), 8);
      expect(r.sanitized.originalOffset(stars[0].start), 6);
    });

    test('非法符号的 offset 指向原串', () {
      // 原串： ￥ 1 & 2 —— & 在原串下标 3
      final r = ExpressionLexer.lex('￥1 & 2');
      expect(r.ok, isFalse);
      expect(r.error!.code, 'UNEXPECTED_TOKEN');
      expect(r.error!.offset, 3);
      expect(r.error!.message, contains('非法符号'));
      expect(r.error!.candidates, isNotEmpty);
    });

    test('全角替换保持 1:1 位移', () {
      // 原串： １ ＋ ＆ ２ —— ＆ 不在归一表内 → 非法符号，位于原串下标 2
      final r = ExpressionLexer.lex('１＋＆２');
      expect(r.ok, isFalse);
      expect(r.error!.offset, 2);
    });
  });

  group('Lexer · 数字', () {
    test('整数 / 小数 / 前缀小数 / 科学计数法', () {
      for (final lit in ['2', '2.5', '.5', '1e3', '2E5', '1.5e-3', '0.0000001']) {
        final r = ExpressionLexer.lex(lit);
        expect(r.ok, isTrue, reason: lit);
        expect(_types(r.tokens), [TokenType.number], reason: lit);
        expect(r.tokens.first.value, double.parse(lit), reason: lit);
      }
    });

    test('5e 不被误吞为科学计数法（→ 5 * e 隐式乘法）', () {
      final r = ExpressionLexer.lex('5e');
      expect(_types(r.tokens), [TokenType.number, TokenType.ident]);
      expect(r.tokens[1].text, 'e');
    });
  });

  group('Lexer · 隐式乘法边界（不得误判为单位）', () {
    test('2pi → number + ident', () {
      final r = ExpressionLexer.lex('2pi');
      expect(_types(r.tokens), [TokenType.number, TokenType.ident]);
      expect(r.tokens[1].text, 'pi');
    });

    test('5sqrt(9) → number ident ( number )', () {
      final r = ExpressionLexer.lex('5sqrt(9)');
      expect(_types(r.tokens),
          [TokenType.number, TokenType.ident, TokenType.lparen, TokenType.number,
           TokenType.rparen]);
    });

    test('2(3)(4) → 连续括号', () {
      final r = ExpressionLexer.lex('2(3)(4)');
      expect(_types(r.tokens), [
        TokenType.number, TokenType.lparen, TokenType.number, TokenType.rparen,
        TokenType.lparen, TokenType.number, TokenType.rparen
      ]);
    });

    test('2 pi/2 不得并成一个单位串', () {
      final r = ExpressionLexer.lex('2 pi/2');
      expect(_types(r.tokens),
          [TokenType.number, TokenType.ident, TokenType.slash, TokenType.number]);
    });
  });

  group('Lexer · 内联 to 换算', () {
    test('320 km/h to m/s → number unit to unit', () {
      final r = ExpressionLexer.lex('320 km/h to m/s');
      expect(_types(r.tokens),
          [TokenType.number, TokenType.unit, TokenType.to, TokenType.unit]);
      expect(r.tokens[1].text, 'km/h');
      expect(r.tokens[3].text, 'm/s');
    });

    test('320 km to m（无斜杠单位同样确认）', () {
      final r = ExpressionLexer.lex('320 km to m');
      expect(_types(r.tokens),
          [TokenType.number, TokenType.unit, TokenType.to, TokenType.unit]);
      expect(r.tokens[1].text, 'km');
    });

    test('中文单位：100 斤 to kg', () {
      final r = ExpressionLexer.lex('100 斤 to kg');
      expect(_types(r.tokens),
          [TokenType.number, TokenType.unit, TokenType.to, TokenType.unit]);
      expect(r.tokens[1].text, '斤');
    });

    test('tomato 不得被误判为 to 关键字', () {
      final r = ExpressionLexer.lex('tomato');
      expect(_types(r.tokens), [TokenType.ident]);
      expect(r.tokens.first.text, 'tomato');
    });

    test('320 km/h tomato（to 后紧跟标识符字符 → 不确认单位）', () {
      final r = ExpressionLexer.lex('320 km/h tomato');
      expect(r.tokens.where((t) => t.type == TokenType.unit), isEmpty);
      expect(r.tokens.where((t) => t.type == TokenType.to), isEmpty);
    });
  });

  group('Lexer · 错误与阈值', () {
    test('空表达式 → UNEXPECTED_TOKEN', () {
      final r = ExpressionLexer.lex('   ');
      expect(r.ok, isFalse);
      expect(r.error!.code, 'UNEXPECTED_TOKEN');
      expect(r.error!.message, '表达式为空');
    });

    test('超长表达式 → EXPR_TOO_LONG', () {
      final r = ExpressionLexer.lex('1+' * (ExpressionLexer.maxExpressionLength ~/ 2 + 1));
      expect(r.ok, isFalse);
      expect(r.error!.code, 'EXPR_TOO_LONG');
      expect(r.error!.suggestion, isNotNull);
    });

    test('算子序列可词法通过（括号/语法错误留给 Parser）', () {
      final r = ExpressionLexer.lex('1 + * 2');
      expect(r.ok, isTrue);
      expect(_types(r.tokens),
          [TokenType.number, TokenType.plus, TokenType.star, TokenType.number]);
    });
  });
}
