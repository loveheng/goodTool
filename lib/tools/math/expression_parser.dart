library;

import 'expression_lexer.dart';
import 'expression_sanitizer.dart';
import 'math_error.dart';

/// 抽象语法树节点（源无关；求值层据此遍历求值）。
sealed class AstNode {
  const AstNode();
}

/// 数字字面量。[raw] 为 cleaned 串中的原样文本，供 Decimal 精确解析
/// （避免 `double` 预先污染，如 `0.1+0.2`。
class NumberNode extends AstNode {
  NumberNode(this.raw) : value = double.parse(raw);
  /// 原始数字字面量文本（cleaned 串切片）。
  final String raw;
  /// double 视图（调试/兼容）。
  final double value;
}

/// 标识符：常量（`pi`/`e`）、变量名或函数名（由求值层消解）。
class IdentNode extends AstNode {
  const IdentNode(this.name);
  final String name;
}

/// 一元前缀：`-(x)` / `+(x)`。一元负号优先级**低于** `^`（故 `-2^2 = -(2^2)`）。
class UnaryNode extends AstNode {
  const UnaryNode(this.op, this.operand);
  final String op; // '-' | '+'
  final AstNode operand;
}

/// 后缀百分率：`x%` ≡ `x / 100`。
class PostfixPercentNode extends AstNode {
  const PostfixPercentNode(this.operand);
  final AstNode operand;
}

/// 二元运算：`+ - * / ^`。
class BinaryNode extends AstNode {
  const BinaryNode(this.op, this.left, this.right);
  final String op;
  final AstNode left;
  final AstNode right;
}

/// 函数调用：`name(args...)`。
class CallNode extends AstNode {
  const CallNode(this.name, this.args);
  final String name;
  final List<AstNode> args;
}

/// 内联单位换算：`<值> <单位> to <单位>`。求值层据此调用 `UnitConverter`。
class ConvertNode extends AstNode {
  const ConvertNode(this.value, this.fromUnit, this.toUnit);
  final AstNode value;
  final String fromUnit;
  final String toUnit;
}

/// 解析期非致命告警（如 `A + B%` 歧义诊断）。
class ParserWarning {
  const ParserWarning(this.code, this.message, this.offset);
  final String code;
  final String message;
  /// 出错字符在**原始输入串**中的偏移（UI 标红 / Agent 自愈用）。
  final int offset;

  Map<String, Object?> toJson() => {
        'code': code,
        'offset': offset,
        'message': message,
      };
}

/// 解析结果。失败时 [ast] 为 null、[error] 非空——**永不返回 null**。
class ParseResult {
  const ParseResult.ok(this.ast, this.sanitized, {this.warnings = const []})
      : error = null;
  const ParseResult.fail(this.error, this.sanitized, {this.warnings = const []})
      : ast = null;

  final AstNode? ast;
  final MathError? error;
  final SanitizeResult sanitized;
  final List<ParserWarning> warnings;

  bool get ok => error == null;
}

/// 表达式解析器（递归下降；calculator.md 显式裁定优先级/结合性）。
///
/// 优先级（由高到低）：`^`(右结合) > 一元 `-`/`+` > `* /`(左结合) > `+ -`(左结合)。
/// 隐式乘法在 `term` 层按「值结束 token ⊣ 值起始 token」相邻插入 `*`
/// （排除 `NUMBER NUMBER` 以避免 `2 3` 被静默当 `2*3`）。
class ExpressionParser {
  const ExpressionParser._();

  /// 括号嵌套深度硬上限（calculator.md「DoS 防御」）。
  static const int maxNestingDepth = 50;

  static ParseResult parse(LexResult lex) {
    if (!lex.ok) {
      // 词法层已失败（EXPR_TOO_LONG / UNEXPECTED_TOKEN 等），直接透传。
      return ParseResult.fail(lex.error!, lex.sanitized);
    }
    final p = _Parser(lex.tokens, lex.sanitized);
    try {
      final ast = p.parseExpr();
      if (!p.atEnd) {
        final t = p.tokens[p.pos];
        return ParseResult.fail(
          MathError(
            code: 'UNEXPECTED_TOKEN',
            offset: p.sanitized.originalOffset(t.start),
            message: '无法解析的多余符号 "${p.literal(t)}"',
            suggestion: '检查是否漏写运算符，或在多余符号前补 ")"',
          ),
          p.sanitized,
          warnings: p.warnings,
        );
      }
      return ParseResult.ok(ast, p.sanitized, warnings: p.warnings);
    } on _ParserError catch (e) {
      return ParseResult.fail(e.error, p.sanitized, warnings: p.warnings);
    }
  }
}

class _ParserError {
  _ParserError(this.error);
  final MathError error;
}

class _Parser {
  _Parser(this.tokens, this.sanitized);
  final List<Token> tokens;
  final SanitizeResult sanitized;
  int pos = 0;
  int depth = 0;
  final List<ParserWarning> warnings = [];

  /// 上一个已消费 token 的类型（隐式乘法判定用）。
  TokenType? _prevType;

  bool get atEnd => pos >= tokens.length;
  Token get current => tokens[pos];

  void advance() {
    _prevType = tokens[pos].type;
    pos++;
  }

  /// 上一个产出是否为「值结束」（隐式乘法左边界）。
  bool get _endsValue {
    final t = _prevType;
    return t == TokenType.number ||
        t == TokenType.ident ||
        t == TokenType.rparen ||
        t == TokenType.percent ||
        t == TokenType.unit;
  }

  Never fail(String code, int cleanedOffset, String message,
      {String? suggestion, List<String>? candidates}) {
    throw _ParserError(MathError(
      code: code,
      offset: sanitized.originalOffset(cleanedOffset),
      message: message,
      suggestion: suggestion,
      candidates: candidates,
    ));
  }

  String literal(Token t) => t.text ?? _symbol(t.type);

  static String _symbol(TokenType ty) {
    switch (ty) {
      case TokenType.plus:
        return '+';
      case TokenType.minus:
        return '-';
      case TokenType.star:
        return '*';
      case TokenType.slash:
        return '/';
      case TokenType.caret:
        return '^';
      case TokenType.percent:
        return '%';
      case TokenType.lparen:
        return '(';
      case TokenType.rparen:
        return ')';
      case TokenType.comma:
        return ',';
      case TokenType.to:
        return 'to';
      default:
        return '?';
    }
  }

  // ── 文法自顶向下 ──────────────────────────────────────────────
  // expr   := term (('+'|'-') term)*
  // term   := unary (('*'|'/') unary | 隐式乘法 unary)*
  // unary  := ('-'|'+') unary | power
  // power  := postfix ('^' unary)?          （^ 右结合，指数可含一元负号）
  // postfix:= primary ('%')*
  // primary:= NUMBER[<单位> to <单位>] | IDENT['(' args ')'] | '(' expr ')'

  AstNode parseExpr() {
    var left = parseTerm();
    while (!atEnd &&
        (current.type == TokenType.plus || current.type == TokenType.minus)) {
      final opTok = current;
      advance();
      final right = parseTerm();
      final node = BinaryNode(
          opTok.type == TokenType.plus ? '+' : '-', left, right);
      // A + B% / A - B% 歧义诊断（非致命 warning，不阻断求值）
      if (right is PostfixPercentNode) {
        warnings.add(ParserWarning(
          'PERCENT_AMBIGUITY',
          '检测到 "A ${opTok.type == TokenType.plus ? '+' : '-'} B%" 形式：'
          '严格语义为 A + (B/100)；若意图为 "(A+B)%" 请加括号',
          sanitized.originalOffset(opTok.start),
        ));
      }
      left = node;
    }
    return left;
  }

  AstNode parseTerm() {
    var left = parseUnary();
    while (!atEnd) {
      final t = current;
      if (t.type == TokenType.star || t.type == TokenType.slash) {
        advance();
        left = BinaryNode(t.type == TokenType.star ? '*' : '/', left,
            parseUnary());
      } else if (_isImplicitMul(t)) {
        // 触发 token（ident/number/lparen）即右操作数起始，交给 parseUnary
        // 自行消费——此处**不 advance**，否则会吞掉右操作数首 token。
        left = BinaryNode('*', left, parseUnary());
      } else {
        break;
      }
    }
    return left;
  }

  /// 隐式乘法：上一个产出是「值结束」且当前 token 是「值起始」时插入 `*`；
  /// 排除 `NUMBER NUMBER`（避免 `2 3` 被静默当 `2*3`）。
  bool _isImplicitMul(Token t) {
    if (!_endsValue) return false;
    if (t.type == TokenType.number) {
      return _prevType != TokenType.number;
    }
    return t.type == TokenType.ident || t.type == TokenType.lparen;
  }

  AstNode parseUnary() {
    if (atEnd) {
      fail('UNEXPECTED_TOKEN', tokens.last.end, '表达式意外结束（缺少操作数）',
          suggestion: '在运算符后补上操作数');
    }
    final t = current;
    if (t.type == TokenType.minus || t.type == TokenType.plus) {
      advance();
      // 允许 --5 / +-3；一元负号优先级低于 ^（由 parsePower 结构保证）
      return UnaryNode(t.type == TokenType.minus ? '-' : '+', parseUnary());
    }
    return parsePower();
  }

  AstNode parsePower() {
    final base = parsePostfix();
    if (!atEnd && current.type == TokenType.caret) {
      advance();
      // 指数部分直接调 parseUnary：既允许一元负号（-2^2 = -(2^2)），
      // 又让 ^ 右结合（2^3^2 = 2^(3^2)）。
      final exp = parseUnary();
      return BinaryNode('^', base, exp);
    }
    return base;
  }

  AstNode parsePostfix() {
    var node = parsePrimary();
    while (!atEnd && current.type == TokenType.percent) {
      advance(); // 消费 %，_prevType 记为 percent（值结束）
      node = PostfixPercentNode(node);
    }
    return node;
  }

  AstNode parsePrimary() {
    if (atEnd) {
      fail('UNEXPECTED_TOKEN', tokens.isEmpty ? 0 : tokens.last.end,
          '表达式意外结束',
          suggestion: '补充缺失的操作数或运算符');
    }
    final t = current;
    switch (t.type) {
      case TokenType.number:
        final raw = sanitized.text.substring(t.start, t.end);
        advance();
        if (!atEnd && current.type == TokenType.unit) {
          // 单位换算：<数值> <单位> to <单位>（词法层已保证 UNIT 必随 to）
          return _parseConvert(NumberNode(raw));
        }
        return NumberNode(raw);

      case TokenType.ident:
        final name = t.text!;
        advance();
        if (!atEnd && current.type == TokenType.lparen) {
          advance(); // 消费 '('
          final args = <AstNode>[];
          if (!atEnd && current.type != TokenType.rparen) {
            args.add(parseExpr());
            while (!atEnd && current.type == TokenType.comma) {
              advance();
              args.add(parseExpr());
            }
          }
          if (atEnd || current.type != TokenType.rparen) {
            fail('UNMATCHED_PARENTHESIS', t.start, '函数 "$name(" 缺少匹配的 ")"',
                suggestion: '在参数后补 ")"');
          }
          advance();
          return CallNode(name, args);
        }
        return IdentNode(name);

      case TokenType.lparen:
        advance();
        depth++;
        if (depth > ExpressionParser.maxNestingDepth) {
          fail('NESTING_TOO_DEEP', t.start,
              '括号嵌套深度超过 ${ExpressionParser.maxNestingDepth}',
              suggestion: '拆分表达式或移除多余括号');
        }
        final inner = parseExpr();
        if (atEnd || current.type != TokenType.rparen) {
          fail('UNMATCHED_PARENTHESIS', t.start, '缺少匹配的 ")"',
              suggestion: '在相应位置补 ")"');
        }
        advance();
        depth--;
        return inner;

      case TokenType.unit:
        fail('UNEXPECTED_TOKEN', t.start, '单位 "${t.text}" 未跟随数值',
            suggestion: '换算须写作 "<数值> <单位> to <单位>"');

      case TokenType.to:
        fail('UNEXPECTED_TOKEN', t.start, '关键字 "to" 前缺少 "<数值> <单位>"',
            suggestion: '换算须写作 "<数值> <单位> to <单位>"');

      case TokenType.plus:
      case TokenType.minus:
      case TokenType.star:
      case TokenType.slash:
      case TokenType.caret:
      case TokenType.percent:
      case TokenType.comma:
      case TokenType.rparen:
        fail('UNEXPECTED_TOKEN', t.start,
            '孤立符号 "${literal(t)}" 出现在表达式起始/运算符位置',
            suggestion: '检查是否多写或漏写操作数');
    }
  }

  /// 当前 token 为 UNIT（from unit），消费 `UNIT to UNIT` 产出 ConvertNode。
  AstNode _parseConvert(AstNode value) {
    final fromUnit = current.text!;
    advance();
    if (atEnd || current.type != TokenType.to) {
      fail('UNEXPECTED_TOKEN', current.start,
          '单位 "$fromUnit" 后缺少 "to"',
          suggestion: '换算须写作 "<数值> $fromUnit to <目标单位>"');
    }
    advance(); // 消费 to
    if (atEnd || current.type != TokenType.unit) {
      fail('UNEXPECTED_TOKEN', current.start, '"to" 后缺少目标单位',
          suggestion: '补充目标单位，如 "m/s"');
    }
    final toUnit = current.text!;
    advance();
    return ConvertNode(value, fromUnit, toUnit);
  }
}
