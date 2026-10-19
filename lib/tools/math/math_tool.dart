// math_utility 领域网关适配层（S3e）：把 calculator 数学内核包成 1 个 MCP 工具，
// 注册 calc_eval / unit_convert / unit_list 三个 R 档子操作。
//
// 可见性（§3.3 G2）：仅公开 buildMathTool()；具体子操作 _CalcEvalSub / _UnitConvertSub
// / _UnitListSub 以 `_` 前缀私有。本文件**不 import command_gateway.dart**、
// 不出现 .dispatch(/.admits( —— math 全 R 档，物理上不触达写门禁（arch-guard 红线）。
library;

import 'dart:convert';
import 'package:decimal/decimal.dart';
import '../../mcp/category_tool_face.dart';
import 'expression_evaluator.dart';
import 'unit_converter.dart';

/// 公开入口：构建 `math_utility` 领域网关（计算 + 换算），注册 3 个子操作。
///
/// 全部为 R 档（无写操作），[CategoryTool.commandGateway] 传 null
/// （[CategoryTool.call] 仅 W 档才触达网关，R 档物理不可穿透）。
CategoryTool buildMathTool() {
  final cat = CategoryTool(
    'math_utility',
    '计算与单位换算（高精度表达式求值 / 单位双向换算 / 单位自省）',
    null,
  );
  cat.register(_CalcEvalSub());
  cat.register(_UnitConvertSub());
  cat.register(_UnitListSub());
  return cat;
}

/// 双轨出参：把业务载荷包成单条 text content（JSON），Agent 可直接解析复用。
SubActionResult _jsonSuccess(Map<String, Object?> payload) => SubActionResult.success([
      {'type': 'text', 'text': jsonEncode(payload)}
    ]);

/// 数值双轨：优先无损数值；超出 double 无损表示范围退化为字符串
/// （calculator.md「numericValue 超 JSON 数值范围时退化为 string」）。
Object _numericValue(Decimal value) {
  final dv = value.toDouble();
  // 无损回判：double 再解析回 Decimal 仍等值 ⇒ 可安全用 num 传递
  return Decimal.parse(dv.toString()) == value ? dv : value.toString();
}

/// 统一结构化错误：产出双轨错误体（含 code/message/可选 offset/candidates），
/// 前缀由 [CategoryTool.call] 经 [SubActionResult.withPrefix] 注入（G1/G5）。
SubActionResult _err(String code, String message,
    {int? offset, List<String>? candidates, String? suggestion}) {
  final d = <String, Object?>{'code': code, 'message': message};
  if (offset != null) d['offset'] = offset;
  if (suggestion != null) d['suggestion'] = suggestion;
  if (candidates != null && candidates.isNotEmpty) d['candidates'] = candidates;
  return SubActionResult.structuredError(code, message, d);
}

class _CalcEvalSub extends SubAction {
  @override
  String get name => 'calc_eval';

  @override
  String get description =>
      '安全执行高精度算术与科学表达式求值。支持四则运算、幂(^右结合)、括号嵌套、'
      '科学函数(sqrt/abs/sin/cos/ln/log10 等)及常量(pi,e)；支持 "<值> <单位> to <单位>" 内联换算。'
      '注意：% 为后缀百分率(50%=0.5)；取模用 mod(a,b)；隐式乘法=显式*(1/2pi=(1/2)*pi)。';

  @override
  String get paramSignature =>
      'calc_eval(expr: string, precision?, roundingMode?, angleMode?, context?) [必填: expr]';

  @override
  Future<SubActionResult> execute(Map<String, Object?> params) async {
    final expr = params['expr'];
    if (expr is! String || expr.trim().isEmpty) {
      return _err('MISSING_ARGUMENT', '缺少必填参数 expr（字符串表达式）');
    }

    // G5 宽容解析可选参数：缺参/不可解析一律返回带 code 的 error，禁止兜底默认值。
    final precision = parseInt(params['precision']); // 小数位；null = 内部默认
    final angleMode = params['angleMode']; // 暂仅 rad 内核支持
    final roundingMode = params['roundingMode']; // 暂仅 halfUp
    final context = params['context']; // 变量注入（内核 S3 待扩展）

    final warnings = <String>[];
    if (angleMode is String && angleMode != 'rad') {
      warnings.add('angleMode="$angleMode" 暂未支持，按默认 rad（弧度）求值');
    }
    if (roundingMode is String && roundingMode != 'halfUp') {
      warnings.add('roundingMode="$roundingMode" 暂未支持，按默认 halfUp');
    }
    if (context is Map && context.isNotEmpty) {
      warnings.add('context 变量注入暂未支持（内核 S3 待扩展），已忽略');
    }

    final res = ExpressionEvaluator.evalExpression(expr);
    if (!res.ok) {
      final e = res.error!;
      final errJson = <String, Object?>{
        'code': e.code,
        'offset': e.offset,
        'message': e.message,
      };
      if (e.suggestion != null) errJson['suggestion'] = e.suggestion!;
      if (e.candidates != null && e.candidates!.isNotEmpty) {
        errJson['candidates'] = e.candidates!;
      }
      return SubActionResult.structuredError(e.code, e.message, errJson);
    }

    final value = res.value!;
    final payload = <String, Object?>{
      'success': true,
      'result': formatDecimal(value, scale: precision ?? 12),
      'numericValue': _numericValue(value),
      'expression': expr.trim(),
    };
    if (warnings.isNotEmpty) payload['warning'] = warnings.join('；');
    return _jsonSuccess(payload);
  }
}

class _UnitConvertSub extends SubAction {
  @override
  String get name => 'unit_convert';

  @override
  String get description =>
      '量纲双向换算（长度/质量/温度/面积/体积/速度/存储/压强/功率/油耗等 11 类）。'
      '别名容错（km/h、公里每小时、℃、celsius 均可）；未知单位见 error.candidates 自愈。';

  @override
  String get paramSignature =>
      'unit_convert(value: number|string, from: string, to: string, precision?, standard?) [必填: value, from, to]';

  @override
  Future<SubActionResult> execute(Map<String, Object?> params) async {
    final value = parseDouble(params['value']); // G5 宽容：num 或数字串
    final from = params['from'];
    final to = params['to'];
    if (value == null) {
      return _err('MISSING_ARGUMENT', '缺少必填参数 value（数值或可解析字符串）');
    }
    if (from is! String || to is! String) {
      return _err('MISSING_ARGUMENT', '缺少必填参数 from / to（单位代号字符串）');
    }
    final conv = const UnitConverter().convert(value, from, to);
    if (!conv.success) {
      final errJson = <String, Object?>{
        'code': conv.code!,
        'message': conv.message!,
      };
      if (conv.candidates != null && conv.candidates!.isNotEmpty) {
        errJson['candidates'] = conv.candidates!;
      }
      return SubActionResult.structuredError(conv.code!, conv.message!, errJson);
    }
    final out = conv.value!;
    final precision = parseInt(params['precision']);
    final payload = <String, Object?>{
      'success': true,
      'result':
          '${formatDecimal(Decimal.parse(out.toString()), scale: precision ?? 12)} ${conv.toUnit}',
      'numericValue': out,
      'fromUnit': conv.fromUnit,
      'toUnit': conv.toUnit,
      'formula': conv.formula,
    };
    if (conv.warning != null) payload['warning'] = conv.warning;
    return _jsonSuccess(payload);
  }
}

class _UnitListSub extends SubAction {
  @override
  String get name => 'unit_list';

  @override
  String get description =>
      '分级自省省 Token：无参返回量纲概览；传 dimension 展开该量纲单位、传 search 模糊检索单位别名。';

  @override
  String get paramSignature => 'unit_list(dimension?: string, search?: string) [全可选]';

  @override
  Future<SubActionResult> execute(Map<String, Object?> params) async {
    final dimension = params['dimension'];
    final search = params['search'];
    final converter = const UnitConverter();

    // 一级目录：量纲概览（无参 / 仅给空串）
    if (dimension is! String && search is! String) {
      final dims = converter
          .listDimensions()
          .map((d) => d['dimension'])
          .whereType<String>()
          .toList();
      return _jsonSuccess({'success': true, 'dimensions': dims});
    }

    final dim = dimension is String ? dimension : null;
    final q = search is String ? search : null;
    final units = converter.listUnits(dimension: dim, search: q);

    String? baseUnit;
    if (dim != null) {
      baseUnit = converter
          .listDimensions()
          .firstWhere((d) => d['dimension'] == dim,
              orElse: () => const <String, Object?>{})
          .cast<String, Object?>()['baseUnit'] as String?;
    }

    final payload = <String, Object?>{
      'success': true,
      'units': units,
    };
    if (dim != null) {
      payload['dimension'] = dim;
      if (baseUnit != null) payload['baseUnit'] = baseUnit;
    }
    return _jsonSuccess(payload);
  }
}
