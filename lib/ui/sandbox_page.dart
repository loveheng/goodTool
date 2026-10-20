library;

import 'package:flutter/material.dart';

import '../ui_ports/calculator_port.dart';
import '../ui_ports/calendar_port.dart';
import '../ui_ports/geo_port.dart';
import 'components/app_components.dart';

/// 沙盒：不依赖外部模型，自行验证内核正确性。
///
/// 三段：时空计算（坐标纠偏 / 测距）、高精计算器（表达式 / 单位换算）、
/// 日历快照（今日事件 + 重要标记）。数据来自**纯内核与 Repository 的类型化结果**，
/// 与 MCP 工具面**并列共享同一内核**（不消费其文本信封，守 R2）。
class SandboxPage extends StatefulWidget {
  const SandboxPage({
    super.key,
    required this.calculator,
    required this.geo,
    required this.calendar,
  });

  final CalculatorPort calculator;
  final GeoPort geo;
  final CalendarPort calendar;

  @override
  State<SandboxPage> createState() => _SandboxPageState();
}

class _SandboxPageState extends State<SandboxPage> {
  final _lat = TextEditingController(text: '39.908722');
  final _lng = TextEditingController(text: '116.397499');
  final _lat2 = TextEditingController(text: '39.908722');
  final _lng2 = TextEditingController(text: '116.397499');
  GeoView? _geoView;
  GeoView? _distanceView;

  final _expr = TextEditingController(text: '0.1 + 0.2');
  final _value = TextEditingController(text: '1');
  final _from = TextEditingController(text: 'km');
  final _to = TextEditingController(text: 'mi');
  CalcView? _evalView;
  CalcView? _convertView;

  final _date = TextEditingController();
  CalendarSnapshotView? _snapshot;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    _date.text = '${now.year}-${two(now.month)}-${two(now.day)}';
  }

  @override
  void dispose() {
    _lat.dispose();
    _lng.dispose();
    _lat2.dispose();
    _lng2.dispose();
    _expr.dispose();
    _value.dispose();
    _from.dispose();
    _to.dispose();
    _date.dispose();
    super.dispose();
  }

  double? _parse(String raw) => double.tryParse(raw.trim());

  void _runGeo() {
    final lat = _parse(_lat.text);
    final lng = _parse(_lng.text);
    setState(() {
      _geoView = (lat == null || lng == null)
          ? const GeoView(
              ok: false,
              errorCode: 'INVALID_ARGUMENT',
              message: '经纬度须为数字',
            )
          : widget.geo.convertPoint(lat, lng);
    });
  }

  void _runDistance() {
    final a = _parse(_lat.text);
    final b = _parse(_lng.text);
    final c = _parse(_lat2.text);
    final d = _parse(_lng2.text);
    setState(() {
      _distanceView = (a == null || b == null || c == null || d == null)
          ? const GeoView(
              ok: false,
              errorCode: 'INVALID_ARGUMENT',
              message: '经纬度须为数字',
            )
          : widget.geo.distance(a, b, c, d);
    });
  }

  void _runEval() {
    setState(() => _evalView = widget.calculator.eval(_expr.text));
  }

  void _runConvert() {
    final v = _parse(_value.text);
    setState(() {
      _convertView = (v == null)
          ? const CalcView(
              ok: false,
              errorCode: 'INVALID_ARGUMENT',
              message: '数值须为数字',
            )
          : widget.calculator.convert(v, _from.text, _to.text);
    });
  }

  Future<void> _loadSnapshot() async {
    setState(() => _loading = true);
    final view = await widget.calendar.snapshot(date: _date.text.trim());
    if (!mounted) return;
    setState(() {
      _snapshot = view;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    return ListView(
      padding: EdgeInsets.all(t.metrics.space16),
      children: <Widget>[
        SectionCard(
          title: '时空计算 · 坐标纠偏',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('输入 WGS-84 坐标（纯内核计算，无需 Key 与权限）',
                  style: t.typeScale.compact),
              SizedBox(height: t.metrics.space8),
              Row(
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      controller: _lat,
                      decoration: const InputDecoration(labelText: '纬度'),
                    ),
                  ),
                  SizedBox(width: t.metrics.space8),
                  Expanded(
                    child: TextField(
                      controller: _lng,
                      decoration: const InputDecoration(labelText: '经度'),
                    ),
                  ),
                ],
              ),
              SizedBox(height: t.metrics.space8),
              FilledButton(onPressed: _runGeo, child: const Text('换算')),
              if (_geoView != null) ...<Widget>[
                SizedBox(height: t.metrics.space8),
                if (_geoView!.ok)
                  for (final p in _geoView!.points)
                    Padding(
                      padding: EdgeInsets.only(top: t.metrics.space4),
                      child: Row(
                        children: <Widget>[
                          SizedBox(
                            width: 72,
                            child: Text(p.label, style: t.typeScale.compact),
                          ),
                          TelemetryText(p.formatted),
                        ],
                      ),
                    )
                else
                  _ErrorLine(
                    code: _geoView!.errorCode,
                    message: _geoView!.message,
                  ),
              ],
            ],
          ),
        ),
        SizedBox(height: t.metrics.space16),
        SectionCard(
          title: '时空计算 · 两点测距',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      controller: _lat2,
                      decoration: const InputDecoration(labelText: '起点纬度'),
                    ),
                  ),
                  SizedBox(width: t.metrics.space8),
                  Expanded(
                    child: TextField(
                      controller: _lng2,
                      decoration: const InputDecoration(labelText: '起点经度'),
                    ),
                  ),
                ],
              ),
              SizedBox(height: t.metrics.space8),
              FilledButton(onPressed: _runDistance, child: const Text('测距')),
              if (_distanceView != null) ...<Widget>[
                SizedBox(height: t.metrics.space8),
                if (_distanceView!.ok)
                  TelemetryText(_distanceView!.distanceText)
                else
                  _ErrorLine(
                    code: _distanceView!.errorCode,
                    message: _distanceView!.message,
                  ),
              ],
            ],
          ),
        ),
        SizedBox(height: t.metrics.space16),
        SectionCard(
          title: '高精计算器 · 表达式求值',
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
                _CalcResultView(view: _evalView!),
              ],
            ],
          ),
        ),
        SizedBox(height: t.metrics.space16),
        SectionCard(
          title: '高精计算器 · 单位换算',
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
                _CalcResultView(view: _convertView!),
              ],
            ],
          ),
        ),
        SizedBox(height: t.metrics.space16),
        SectionCard(
          title: '日历快照',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      controller: _date,
                      decoration:
                          const InputDecoration(labelText: '日期 YYYY-MM-DD'),
                    ),
                  ),
                  SizedBox(width: t.metrics.space8),
                  FilledButton(
                    onPressed: _loading ? null : _loadSnapshot,
                    child: const Text('读取'),
                  ),
                ],
              ),
              SizedBox(height: t.metrics.space8),
              if (_loading)
                Text('读取中…', style: t.typeScale.body)
              else if (_snapshot != null)
                _SnapshotView(view: _snapshot!)
              else
                const EmptyState(message: '选择日期后读取当天事件与重要标记'),
            ],
          ),
        ),
      ],
    );
  }
}

/// 计算结果展示：**双轨出参**（格式化串 + 无损机器值）。
class _CalcResultView extends StatelessWidget {
  const _CalcResultView({required this.view});

  final CalcView view;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    if (!view.ok) {
      return _ErrorLine(
        code: view.errorCode,
        message: view.message,
        suggestion: view.suggestion,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(view.text ?? '', style: t.typeScale.listItem),
        SizedBox(height: t.metrics.space4),
        TelemetryText(view.numeric ?? ''),
        if (view.formula != null) ...<Widget>[
          SizedBox(height: t.metrics.space4),
          Text(
            view.formula!,
            style: t.typeScale.micro.copyWith(color: t.palette.textMuted),
          ),
        ],
        if (view.warning != null) ...<Widget>[
          SizedBox(height: t.metrics.space4),
          Text(
            view.warning!,
            style: t.typeScale.micro.copyWith(color: t.palette.l2Warn),
          ),
        ],
      ],
    );
  }
}

/// 结构化错误行：机器码 + 说明 + 自愈建议（不吞错、不静默）。
class _ErrorLine extends StatelessWidget {
  const _ErrorLine({this.code, this.message, this.suggestion});

  final String? code;
  final String? message;
  final String? suggestion;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          code == null ? (message ?? '') : '$code：${message ?? ''}',
          style: t.typeScale.compact.copyWith(color: t.palette.danger),
        ),
        if (suggestion != null)
          Padding(
            padding: EdgeInsets.only(top: t.metrics.space4),
            child: Text(
              suggestion!,
              style: t.typeScale.micro.copyWith(color: t.palette.textMuted),
            ),
          ),
      ],
    );
  }
}

/// 日历快照展示（事件 + 标记 + 子源告警）。
class _SnapshotView extends StatelessWidget {
  const _SnapshotView({required this.view});

  final CalendarSnapshotView view;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    if (view.errorCode != null) {
      return _ErrorLine(code: view.errorCode, message: view.message);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (view.warnings.isNotEmpty)
          for (final w in view.warnings)
            Padding(
              padding: EdgeInsets.only(bottom: t.metrics.space4),
              child: Text(
                w,
                style: t.typeScale.micro.copyWith(color: t.palette.l2Warn),
              ),
            ),
        if (view.events.isEmpty && view.markers.isEmpty)
          const EmptyState(message: '当天没有事件与重要标记')
        else ...<Widget>[
          for (final e in view.events)
            Padding(
              padding: EdgeInsets.only(bottom: t.metrics.space4),
              child: Row(
                children: <Widget>[
                  SizedBox(
                    width: 56,
                    child: Text(e.timeText, style: t.typeScale.telemetry),
                  ),
                  Expanded(
                    child: Text(e.title, style: t.typeScale.listItem),
                  ),
                ],
              ),
            ),
          for (final m in view.markers)
            Padding(
              padding: EdgeInsets.only(bottom: t.metrics.space4),
              child: Row(
                children: <Widget>[
                  SizedBox(
                    width: 56,
                    child: Text('标记', style: t.typeScale.telemetry),
                  ),
                  Expanded(
                    child: Text(
                      '${m.title}（${m.originalDate}）',
                      style: t.typeScale.listItem,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }
}
