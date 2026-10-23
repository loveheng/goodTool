library;

import 'package:flutter/material.dart';

import '../mcp/weather_provider.dart';
import '../ui_ports/weather_port.dart';
import 'components/app_components.dart';
import 'home_shell.dart';

/// 天气子页面：城市 / 经纬度 + 天数 → 实时天气 + 逐日预报 + 气象预警。
///
/// 与 MCP 工具面共享同一 `WeatherProvider` 实例（装配期注入）——UI 与 Agent
/// 同源，频控与缓存不分裂；本页不消费文本信封（守 R2）。
class WeatherPage extends StatefulWidget {
  const WeatherPage({super.key, required this.port});

  final WeatherPort port;

  @override
  State<WeatherPage> createState() => _WeatherPageState();
}

class _WeatherPageState extends State<WeatherPage> {
  final _city = TextEditingController();
  final _lat = TextEditingController();
  final _lng = TextEditingController();
  final _days = TextEditingController(text: '3');
  WeatherView? _view;
  bool _loading = false;

  @override
  void dispose() {
    _city.dispose();
    _lat.dispose();
    _lng.dispose();
    _days.dispose();
    super.dispose();
  }

  double? _parse(String raw) {
    final t = raw.trim();
    return t.isEmpty ? null : double.tryParse(t);
  }

  Future<void> _query() async {
    final lat = _parse(_lat.text);
    final lng = _parse(_lng.text);
    if ((_lat.text.trim().isNotEmpty) != (_lng.text.trim().isNotEmpty)) {
      setState(() => _view = const WeatherView(
            ok: false,
            errorCode: 'MISSING_ARGUMENT',
            message: 'lat 与 lng 须成对传入（或改用城市名）',
          ));
      return;
    }
    final days = int.tryParse(_days.text.trim()) ?? 3;
    setState(() => _loading = true);
    final view = await widget.port.forecast(
      city: _city.text,
      lat: lat,
      lng: lng,
      days: days,
    );
    if (!mounted) return;
    setState(() {
      _view = view;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final view = _view;
    final configIncomplete = view != null &&
        !view.ok &&
        (view.errorCode == WeatherErr.keyMissing ||
            view.errorCode == WeatherErr.hostMissing ||
            view.errorCode == WeatherErr.hostInvalid);
    final shell = ShellNav.maybeOf(context);
    return ListView(
      padding: EdgeInsets.all(t.metrics.space16),
      children: <Widget>[
        SectionCard(
          title: '天气查询',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              TextField(
                controller: _city,
                decoration: const InputDecoration(
                    labelText: '城市名（留空则用下方经纬度）'),
              ),
              SizedBox(height: t.metrics.space8),
              Row(
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      controller: _lat,
                      decoration: const InputDecoration(labelText: '纬度（可选）'),
                    ),
                  ),
                  SizedBox(width: t.metrics.space8),
                  Expanded(
                    child: TextField(
                      controller: _lng,
                      decoration: const InputDecoration(labelText: '经度（可选）'),
                    ),
                  ),
                  SizedBox(width: t.metrics.space8),
                  Expanded(
                    child: TextField(
                      controller: _days,
                      decoration: const InputDecoration(labelText: '天数 1~7'),
                    ),
                  ),
                ],
              ),
              SizedBox(height: t.metrics.space8),
              FilledButton(
                onPressed: _loading ? null : _query,
                child: const Text('查询'),
              ),
              if (_loading) ...<Widget>[
                SizedBox(height: t.metrics.space8),
                Text('读取中…', style: t.typeScale.body),
              ],
            ],
          ),
        ),
        if (configIncomplete && shell != null) ...<Widget>[
          SizedBox(height: t.metrics.space16),
          GuidanceCard(
            message: '和风天气未正确配置',
            detail: view.errorCode == WeatherErr.hostMissing
                ? '在设置页填入账号专属 API Host（形如 xxxx.re.qweatherapi.com）后即可查询'
                : '在设置页填入 Key 后即可查询天气',
            actionLabel: '去设置',
            onAction: shell.onOpenSettings,
          ),
        ],
        if (view != null && !view.ok && !configIncomplete) ...<Widget>[
          SizedBox(height: t.metrics.space16),
          SectionCard(
            title: '查询失败',
            child: ErrorLine(
              code: view.errorCode,
              message: view.message,
              suggestion: view.suggestion,
            ),
          ),
        ],
        if (view != null && view.ok) ...<Widget>[
          SizedBox(height: t.metrics.space16),
          SectionCard(
            title: view.city ?? '天气',
            trailing: view.isCached
                ? Text('缓存回放',
                    style: t.typeScale.micro
                        .copyWith(color: t.palette.textMuted))
                : null,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (view.now != null) ...<Widget>[
                  Row(
                    children: <Widget>[
                      Text(view.now!.text, style: t.typeScale.listItem),
                      SizedBox(width: t.metrics.space8),
                      TelemetryText('${view.now!.temp ?? '--'}℃'),
                      if (view.now!.feelsLike != null) ...<Widget>[
                        SizedBox(width: t.metrics.space8),
                        TelemetryText('体感 ${view.now!.feelsLike}℃'),
                      ],
                    ],
                  ),
                  SizedBox(height: t.metrics.space4),
                  Text(
                    '湿度 ${view.now!.humidity ?? '--'}% · '
                    '${view.now!.windDir ?? '--'} ${view.now!.windScale ?? '--'} 级',
                    style: t.typeScale.micro
                        .copyWith(color: t.palette.textMuted),
                  ),
                  SizedBox(height: t.metrics.space12),
                ],
                for (final d in view.days)
                  Padding(
                    padding: EdgeInsets.only(bottom: t.metrics.space4),
                    child: Row(
                      children: <Widget>[
                        SizedBox(
                          width: 96,
                          child: Text(d.date, style: t.typeScale.telemetry),
                        ),
                        Expanded(
                          child: Text(d.textDay,
                              style: t.typeScale.compact),
                        ),
                        TelemetryText(d.tempRange),
                      ],
                    ),
                  ),
                for (final a in view.alerts) ...<Widget>[
                  SizedBox(height: t.metrics.space8),
                  Text(
                    '${a.severity ?? ''}${a.title}',
                    style: t.typeScale.compact.copyWith(color: t.palette.danger),
                  ),
                ],
                if (view.updateTime != null) ...<Widget>[
                  SizedBox(height: t.metrics.space8),
                  Text(
                    '更新时间 ${view.updateTime}',
                    style: t.typeScale.micro
                        .copyWith(color: t.palette.textMuted),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}
