library;

import 'package:flutter/material.dart';

import '../ui_ports/geo_port.dart';
import 'components/app_components.dart';

/// 地图子页面：坐标纠偏（三系同屏）+ 两点测距（纯内核，零依赖恒可用）。
class GeoPage extends StatefulWidget {
  const GeoPage({super.key});

  @override
  State<GeoPage> createState() => _GeoPageState();
}

class _GeoPageState extends State<GeoPage> {
  static const GeoPort _port = GeoPort();

  final _lat = TextEditingController(text: '39.908722');
  final _lng = TextEditingController(text: '116.397499');
  final _lat2 = TextEditingController(text: '31.230416');
  final _lng2 = TextEditingController(text: '121.473701');
  GeoView? _geoView;
  GeoView? _distanceView;

  @override
  void dispose() {
    _lat.dispose();
    _lng.dispose();
    _lat2.dispose();
    _lng2.dispose();
    super.dispose();
  }

  double? _parse(String raw) => double.tryParse(raw.trim());

  void _runConvert() {
    final lat = _parse(_lat.text);
    final lng = _parse(_lng.text);
    setState(() {
      _geoView = (lat == null || lng == null)
          ? const GeoView(
              ok: false,
              errorCode: 'INVALID_ARGUMENT',
              message: '经纬度须为数字',
            )
          : _port.convertPoint(lat, lng);
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
          : _port.distance(a, b, c, d);
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    return ListView(
      padding: EdgeInsets.all(t.metrics.space16),
      children: <Widget>[
        SectionCard(
          title: '坐标纠偏',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('输入 WGS-84 坐标，同屏查看三坐标系结果（无需 Key 与权限）',
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
              FilledButton(onPressed: _runConvert, child: const Text('换算')),
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
                  ErrorLine(
                    code: _geoView!.errorCode,
                    message: _geoView!.message,
                  ),
              ],
            ],
          ),
        ),
        SizedBox(height: t.metrics.space16),
        SectionCard(
          title: '两点测距',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      controller: _lat,
                      decoration: const InputDecoration(labelText: '起点纬度'),
                    ),
                  ),
                  SizedBox(width: t.metrics.space8),
                  Expanded(
                    child: TextField(
                      controller: _lng,
                      decoration: const InputDecoration(labelText: '起点经度'),
                    ),
                  ),
                ],
              ),
              SizedBox(height: t.metrics.space8),
              Row(
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      controller: _lat2,
                      decoration: const InputDecoration(labelText: '终点纬度'),
                    ),
                  ),
                  SizedBox(width: t.metrics.space8),
                  Expanded(
                    child: TextField(
                      controller: _lng2,
                      decoration: const InputDecoration(labelText: '终点经度'),
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
                  ErrorLine(
                    code: _distanceView!.errorCode,
                    message: _distanceView!.message,
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
