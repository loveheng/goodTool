// math_utility 领域网关适配层（S3e）：把 calculator 数学内核包成 1 个 MCP 工具，
// 注册 calc_eval / unit_convert / unit_list 三个 R 档子操作。
//
// 可见性（§3.3 G2）：仅公开 buildMathTool()；具体子操作 _CalcEvalSub / _UnitConvertSub
// / _UnitListSub 以 `_` 前缀私有。本文件**不 import command_gateway.dart**、
// 不出现 dispatch / admits 调用 —— math 全 R 档，物理上不触达写门禁（arch-guard 红线）。
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
///
/// [ToolVisibility.shared]：本域属四大聚合工具之一，声明允许宿主收进共享面。
CategoryTool buildMathTool() {
  final cat = CategoryTool(
    'math_utility',
    '计算与单位换算（高精度表达式求值 / 单位双向换算 / 单位自省）',
    null,
    visibility: ToolVisibility.shared,
    // SDK 0.2.0 annotations：三子操作（求值/换算/自省）均为纯函数，无副作用。
    readOnlyHint: true,
  );
  cat.register(_CalcEvalSub());
  cat.register(_UnitConvertSub());
  cat.register(_UnitListSub());
  cat.register(_ListStatsSub());
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
      '科学函数(sqrt/abs/sin/cos/ln/log10 等)及常量(pi,e)；支持 "<值> <单位> to <单位>" 内联换算，'
      '连接字 to/换算 同义，单位名可用中文别名（公里/英里/公斤/摄氏度等）。'
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
      '别名容错（km/h、公里每小时、公里、英里、℃、celsius 均可）；'
      '未知单位见 error.candidates 自愈。';

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

/// 列表元素 → [Decimal]：num 走类型分派，字符串走 [Decimal.tryParse] 保留完整精度。
/// 不可解析返回 null，由子操作转结构化错误（G5：禁兜底默认值）。
Decimal? _parseDecimalElement(Object? v) {
  if (v is int) return Decimal.fromInt(v);
  if (v is num) return Decimal.parse(v.toString());
  if (v is String) return Decimal.tryParse(v.trim());
  return null;
}

class _ListStatsSub extends SubAction {
  static const _ops = ['sort', 'max', 'min', 'sum', 'mean', 'median'];

  @override
  String get name => 'list_stats';

  @override
  String get description =>
      '高精度列表统计（Decimal 内核，不先转 double，长列表/高精度数值专用）：'
      'op 取 sort（升/降序排序）/ max / min（附下标）/ sum / mean / median。'
      '元素支持数值或高精度数字串（如 "0.123456789012345678"）。';

  @override
  String get paramSignature =>
      'list_stats(values: number[]|string[], op: string, order?: "asc"|"desc", precision?) '
      '[必填: values, op；op ∈ sort/max/min/sum/mean/median]';

  @override
  Future<SubActionResult> execute(Map<String, Object?> params) async {
    final rawValues = params['values'];
    final op = params['op'];
    if (rawValues is! List || rawValues.isEmpty) {
      return _err('MISSING_ARGUMENT', '缺少必填参数 values（非空数组：数值或高精度数字串）');
    }
    if (op is! String || !_ops.contains(op)) {
      return _err('INVALID_ARGUMENT', 'op 非法：$op',
          candidates: _ops,
          suggestion: 'op 取 ${_ops.join(" / ")} 之一');
    }

    // 逐元素解析，不可解析带下标报错（禁静默跳过/兜底）
    final values = <Decimal>[];
    for (var i = 0; i < rawValues.length; i++) {
      final d = _parseDecimalElement(rawValues[i]);
      if (d == null) {
        return _err('INVALID_ARGUMENT', 'values[$i] 不是合法数值：${rawValues[i]}');
      }
      values.add(d);
    }

    final precision = parseInt(params['precision']);
    if (precision != null && precision < 0) {
      return _err('INVALID_ARGUMENT', 'precision 须为非负整数：$precision');
    }
    // 直传值（sort/max/min 的元素）缺省原样输出保精度；显式 precision 才舍入。
    // 计算值（sum/mean/median）除法有尾迹，仍走 formatDecimal（缺省 12 位）。
    String fmtExact(Decimal d) =>
        precision != null ? formatDecimal(d, scale: precision) : d.toString();
    final scale = precision ?? 12;

    final payload = <String, Object?>{
      'success': true,
      'op': op,
      'count': values.length,
    };

    switch (op) {
      case 'sort':
        final order = params['order'] ?? 'asc';
        if (order is! String || (order != 'asc' && order != 'desc')) {
          return _err('INVALID_ARGUMENT', 'order 非法：$order',
              suggestion: 'order 取 asc / desc（缺省 asc）');
        }
        final sorted = [...values]..sort((a, b) => order == 'asc' ? a.compareTo(b) : b.compareTo(a));
        payload['result'] = sorted.map(fmtExact).toList();
        payload['numericValues'] = sorted.map(_numericValue).toList();
        if (order != 'asc') payload['order'] = order;
      case 'max' || 'min':
        var best = 0;
        for (var i = 1; i < values.length; i++) {
          final c = values[i].compareTo(values[best]);
          if (op == 'max' ? c > 0 : c < 0) best = i;
        }
        payload['result'] = fmtExact(values[best]);
        payload['numericValue'] = _numericValue(values[best]);
        payload['index'] = best;
      case 'sum' || 'mean':
        var sum = Decimal.zero;
        for (final v in values) {
          sum += v;
        }
        final result = op == 'sum'
            ? sum
            : (sum / Decimal.fromInt(values.length))
                .toDecimal(scaleOnInfinitePrecision: 30);
        payload['result'] = formatDecimal(result, scale: scale);
        payload['numericValue'] = _numericValue(result);
      case 'median':
        final sorted = [...values]..sort();
        final mid = sorted.length ~/ 2;
        final Decimal result = sorted.length.isOdd
            ? sorted[mid]
            : ((sorted[mid - 1] + sorted[mid]) / Decimal.fromInt(2))
                .toDecimal(scaleOnInfinitePrecision: 30);
        payload['result'] = formatDecimal(result, scale: scale);
        payload['numericValue'] = _numericValue(result);
    }
    return _jsonSuccess(payload);
  }
}
