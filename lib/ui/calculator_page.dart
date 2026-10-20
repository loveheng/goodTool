library;

import 'package:flutter/material.dart';

import '../ui_ports/calculator_port.dart';
import 'components/app_components.dart';

/// 计算器子页面：表达式求值 + 单位换算（能力自验，零依赖恒可用）。
///
/// 数据来自纯内核的类型化结果（双轨出参与 MCP 侧同口径）——本页不消费
/// `{content,isError}` 文本信封（守 R2）。
class CalculatorPage extends StatefulWidget {
  const CalculatorPage({super.key});

  @override
  State<CalculatorPage> createState() => _CalculatorPageState();
}

class _CalculatorPageState extends State<CalculatorPage> {
  static const CalculatorPort _port = CalculatorPort();

  final _expr = TextEditingController(text: '0.1 + 0.2');
  final _value = TextEditingController(text: '1');
  final _from = TextEditingController(text: 'km');
  final _to = TextEditingController(text: 'mi');
  CalcView? _evalView;
  CalcView? _convertView;

  @override
  void dispose() {
    _expr.dispose();
    _value.dispose();
    _from.dispose();
    _to.dispose();
    super.dispose();
  }

  double? _parse(String raw) => double.tryParse(raw.trim());

  void _runEval() {
    setState(() => _evalView = _port.eval(_expr.text));
  }

  void _runConvert() {
    final v = _parse(_value.text);
    setState(() {
      _convertView = v == null
          ? const CalcView(
              ok: false,
              errorCode: 'INVALID_ARGUMENT',
              message: '数值须为数字',
            )
          : _port.convert(v, _from.text, _to.text);
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    return ListView(
      padding: EdgeInsets.all(t.metrics.space16),
      children: <Widget>[
        SectionCard(
          title: '表达式求值',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              TextField(
                controller: _expr,
                decoration: const InputDecoration(labelText: '表达式'),
                onSubmitted: (_) => _runEval(),
              ),
              SizedBox(height: t.metrics.space8),
              FilledButton(onPressed: _runEval, child: const Text('求值')),
              if (_evalView != null) ...<Widget>[
                SizedBox(height: t.metrics.space8),
                CalcResultCard(view: _evalView!),
              ],
            ],
          ),
        ),
        SizedBox(height: t.metrics.space16),
        SectionCard(
          title: '单位换算',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      controller: _value,
                      decoration: const InputDecoration(labelText: '数值'),
                    ),
                  ),
                  SizedBox(width: t.metrics.space8),
                  Expanded(
                    child: TextField(
                      controller: _from,
                      decoration: const InputDecoration(labelText: '源单位'),
                    ),
                  ),
                  SizedBox(width: t.metrics.space8),
                  Expanded(
                    child: TextField(
                      controller: _to,
                      decoration: const InputDecoration(labelText: '目标单位'),
                    ),
                  ),
                ],
              ),
              SizedBox(height: t.metrics.space8),
              FilledButton(onPressed: _runConvert, child: const Text('换算')),
              if (_convertView != null) ...<Widget>[
                SizedBox(height: t.metrics.space8),
                CalcResultCard(view: _convertView!),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
