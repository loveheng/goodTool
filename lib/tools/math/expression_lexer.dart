library;

import 'expression_sanitizer.dart';
import 'math_error.dart';

/// 词法单元类型。
enum TokenType {
  /// 数字字面量（[Token.value] 为解析值）。
  number,

  /// 标识符：常量（`pi`/`e`）、函数名（`sqrt`/`sum`…）或变量名。
  ident,

  /// 单位串（如 `km/h`、`m/s`、`亩`）——**仅当其后紧跟 `to` 关键字时确认**。
  unit,

  /// 内联换算关键字（`<值> <单位> to <单位>`）。
  to,

  plus,
  minus,
  star,
  slash,
  percent,
  caret,
  lparen,
  rparen,
  comma,
}

/// 词法单元。[start]/[end] 为**清洗后字符串**中的偏移；回原始串用
/// [SanitizeResult.originalOffset]。
class Token {
  const Token({
    required this.type,
    required this.start,
    required this.end,
    this.value,
    this.text,
  });

  final TokenType type;
  final int start;
  final int end;

  /// number 的数值。
  final double? value;

  /// ident / unit / to 的原文。
  final String? text;
}

/// 词法分析结果。失败时 [tokens] 为空、[error] 非空——**永不返回 null**。
class LexResult {
  const LexResult.ok(this.tokens, this.sanitized) : error = null;
  const LexResult.fail(this.error, this.sanitized) : tokens = const [];

  final List<Token> tokens;
  final MathError? error;
  final SanitizeResult sanitized;

  bool get ok => error == null;
}

/// 表达式词法分析器（纯 Dart，无头可跑）。
///
/// 设计要点：
/// - **位移在清洗后空间**：所有 offset 先按清洗后串计算，再由
///   [SanitizeResult.originalOffset] 回填到原始输入（UI 标红 / Agent 自愈）。
/// - **单位确认规则**：数字后的标识符串**仅当其后紧跟 `to`** 时才判为
///   [TokenType.unit]。否则按普通标识符处理——这样 `2pi` → `2*pi`（隐式乘法）、
///   `2 pi/2` → `2*(pi/2)` 都不会被误判成单位；裸单位参与四则的
///   `UNEXPECTED_UNIT_IN_EXPR` 由求值层在查不到变量时升级上报（那里才持有
///   单位注册表），词法层保持零注册表依赖。
class ExpressionLexer {
  const ExpressionLexer._();

  /// 表达式最大字符长度（calculator.md「DoS 防御」硬阈值）。
  static const int maxExpressionLength = 1000;

  /// 合法算子候选（`UNEXPECTED_TOKEN` 自愈用）。
  static const List<String> _operators = ['+', '-', '*', '/', '%', '^', '(', ')', ','];

  static LexResult lex(String raw) {
    final s = ExpressionSanitizer.sanitize(raw);
    final text = s.text;

    if (text.length > maxExpressionLength) {
      return LexResult.fail(
        MathError(
          code: 'EXPR_TOO_LONG',
          offset: s.originalOffset(maxExpressionLength),
          message: '表达式长度 ${text.length} 超过上限 $maxExpressionLength',
          suggestion: '拆分为多次调用，或经 calc_eval 的 context 注入中间变量',
        ),
        s,
      );
    }

    final tokens = <Token>[];
    var i = 0;

    while (i < text.length) {
      final ch = text[i];

      if (_isSpace(ch)) {
        i++;
        continue;
      }

      // ── 数字（含 `.5` 前缀形式与科学计数法）────────────────────
      if (_isDigit(ch) ||
          (ch == '.' && i + 1 < text.length && _isDigit(text[i + 1]))) {
        final start = i;
        while (i < text.length && _isDigit(text[i])) {
          i++;
        }
        if (i < text.length && text[i] == '.') {
          i++;
          while (i < text.length && _isDigit(text[i])) {
            i++;
          }
        }
        // 科学计数法：仅当 e/E 后紧跟（可选符号 +）数字时才吞入，
        // 否则 `5e` 保持 `5` + ident `e`（隐式乘法）。
        if (i < text.length && (text[i] == 'e' || text[i] == 'E')) {
          var j = i + 1;
          if (j < text.length && (text[j] == '+' || text[j] == '-')) {
            j++;
          }
          if (j < text.length && _isDigit(text[j])) {
            i = j;
            while (i < text.length && _isDigit(text[i])) {
              i++;
            }
          }
        }
        final lit = text.substring(start, i);
        final v = double.tryParse(lit);
        if (v == null) {
          return LexResult.fail(
            MathError(
              code: 'UNEXPECTED_TOKEN',
              offset: s.originalOffset(start),
              message: '无法解析数字 "$lit"',
            ),
            s,
          );
        }
        tokens.add(Token(
            type: TokenType.number,
            start: start,
            end: i,
            value: v,
            text: lit));
        continue;
      }

      // ── 单位 run：两种确认来源 ──────────────────────────────────
      //   ① 前置 `to` 关键字（换算**目标**单位，已确认）；
      //   ② 数字后紧跟 `to`（换算**源**单位，需前瞻确认）。
      // 其余位置的标识符串一律按普通 ident 处理——保证 `2pi`、`2 pi/2`
      // 不被误判为单位（隐式乘法由 Parser 负责）。
      final prev = tokens.isNotEmpty ? tokens.last : null;
      if ((prev?.type == TokenType.number || prev?.type == TokenType.to) &&
          _isIdentStart(ch)) {
        final start = i;
        var j = i;
        while (j < text.length && _isUnitChar(text[j])) {
          j++;
        }
        var confirmed = prev!.type == TokenType.to;
        if (!confirmed) {
          var k = j;
          while (k < text.length && _isSpace(text[k])) {
            k++;
          }
          confirmed = k + 2 <= text.length &&
              _isConvertKeyword(text.substring(k, k + 2)) &&
              (k + 2 == text.length || !_isIdentPart(text[k + 2]));
        }
        if (confirmed) {
          tokens.add(Token(
              type: TokenType.unit,
              start: start,
              end: j,
              text: text.substring(start, j)));
          i = j;
          continue;
        }
        // 未确认 → 落到普通标识符分支（隐式乘法由 Parser 处理）
      }

      // ── 标识符 / `to` 关键字 ────────────────────────────────────
      if (_isIdentStart(ch)) {
        final start = i;
        while (i < text.length && _isIdentPart(text[i])) {
          i++;
        }
        final name = text.substring(start, i);
        tokens.add(Token(
          type: _isConvertKeyword(name) ? TokenType.to : TokenType.ident,
          start: start,
          end: i,
          text: name,
        ));
        continue;
      }

      // ── 算子 / 括号 / 逗号 ──────────────────────────────────────
      final single = _singleChar(ch);
      if (single != null) {
        tokens.add(Token(type: single, start: i, end: i + 1));
        i++;
        continue;
      }

      final off = s.originalOffset(i);
      return LexResult.fail(
        MathError(
          code: 'UNEXPECTED_TOKEN',
          offset: off,
          message: '在位置 $off 发现非法符号 "$ch"',
          suggestion: '检查是否出现多余算子或未支持符号，'
              '例如将 "5 + * 2" 修改为 "5 * 2"',
          candidates: _operators,
        ),
        s,
      );
    }

    if (tokens.isEmpty) {
      return LexResult.fail(
        MathError(
          code: 'UNEXPECTED_TOKEN',
          offset: 0,
          message: '表达式为空',
          suggestion: '输入算式，如 "2580 * 0.8" 或 "320 km/h to m/s"',
        ),
        s,
      );
    }

    return LexResult.ok(tokens, s);
  }

  /// 内联换算连接字：`to` 与中文 `换算` 同义（calculator.md「中文映射」——
  /// 均为 2 字符，前瞻边界检查共用同一长度）。
  static bool _isConvertKeyword(String word) => word == 'to' || word == '换算';

  static bool _isSpace(String c) =>
      c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == '\u3000';

  static bool _isDigit(String c) {
    final u = c.codeUnitAt(0);
    return u >= 48 && u <= 57;
  }

  static bool _isAsciiLetter(String c) {
    final u = c.codeUnitAt(0);
    return (u >= 65 && u <= 90) || (u >= 97 && u <= 122);
  }

  /// 标识符首字符：ASCII 字母 / 下划线 / 中文（单位别名含中文）。
  static bool _isIdentStart(String c) =>
      _isAsciiLetter(c) || c == '_' || _isCjk(c);

  /// 标识符后续字符：首字符集 + 数字。
  static bool _isIdentPart(String c) => _isIdentStart(c) || _isDigit(c);

  /// 单位串字符：标识符字符集 + `/`（`km/h`、`l/100km`、`m/s`）。
  /// 注意不含 `.`——`2 pi/2` 不得被并成一个单位串。
  static bool _isUnitChar(String c) => _isIdentPart(c) || c == '/';

  static bool _isCjk(String c) {
    final u = c.codeUnitAt(0);
    return u >= 0x4e00 && u <= 0x9fff;
  }

  static TokenType? _singleChar(String c) {
    switch (c) {
      case '+':
        return TokenType.plus;
      case '-':
        return TokenType.minus;
      case '*':
        return TokenType.star;
      case '/':
        return TokenType.slash;
      case '%':
        return TokenType.percent;
      case '^':
        return TokenType.caret;
      case '(':
        return TokenType.lparen;
      case ')':
        return TokenType.rparen;
      case ',':
        return TokenType.comma;
      default:
        return null;
    }
  }
}
