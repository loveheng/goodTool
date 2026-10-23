// weather 领域网关适配层（S5b）：把 WeatherProvider 端口包成 1 个 MCP 工具，
// 注册 product/weather.md 定义的唯一原子动作 `weather_forecast`（R 档）。
//
// 可见性（§3.3 G2）：仅公开 buildWeatherTool()；具体子操作以 `_WeatherForecastSub` 私有。
// 依赖性（arch-guard R1/R4）：weather.md「档位：R」⇒ 本文件不 import command_gateway.dart、
// 不出现 dispatch / admits 调用；取数全经 WeatherProvider 注入，无 dart:io / Flutter UI。
// 错误口径：一律结构化信封（code + message + suggestion），裸码由派发层加 `weather.` 前缀。
library;

import 'dart:convert';

import '../mcp/category_tool_face.dart';
import '../mcp/weather_provider.dart';

/// 合法预报天数（weather.md：1~3 走 /v7/weather/3d，>3 走 /v7/weather/7d）。
const int _minDays = 1;
const int _maxDays = 7;
const int _defaultDays = 3;

/// 公开入口：构建 `weather` 领域网关，注册 1 个子操作。
///
/// R 档-only（weather.md 档位表为 R），[CategoryTool.commandGateway] 传 null
/// ——[CategoryTool.call] 仅 W 档才触达网关，R 档物理不可穿透（fail-closed）。
///
/// [ToolVisibility.shared]：本域属四大聚合工具之一，声明允许宿主收进共享面。
CategoryTool buildWeatherTool(WeatherProvider provider) {
  final cat = CategoryTool(
    'weather',
    '天气：实时天气 + 3~7 天结构化预报 + 气象灾害预警（和风 QWeather 后端）。'
    '位置解析优先级 = 显式经纬度 > city 城市名 > 设置项 weather_location > 设备当前定位；'
    '全部缺失返回 ERR_LOCATION_UNAVAILABLE。与日历联动做出行建议时常用 days=7。',
    null,
    visibility: ToolVisibility.shared,
  );
  cat.register(_WeatherForecastSub(provider));
  return cat;
}

/// 单条 text content（JSON）：Agent 可直接解析复用。
SubActionResult _jsonSuccess(Map<String, Object?> payload) =>
    SubActionResult.success([
      {'type': 'text', 'text': jsonEncode(payload)}
    ]);

/// 结构化错误：吐**裸 machine code**，`weather.<action>:` 前缀由派发层注入（G1/G5）。
SubActionResult _err(String code, String message, {String? suggestion}) =>
    SubActionResult.structuredError(code, message, <String, Object?>{
      'code': code,
      'message': message,
      'suggestion': ?suggestion,
    });

/// weather_forecast：实时 + 多日预报 + 预警（R 档）。
class _WeatherForecastSub extends SubAction {
  _WeatherForecastSub(this._provider);

  final WeatherProvider _provider;

  @override
  String get name => 'weather_forecast';

  @override
  String get description =>
      '查询指定城市的实时天气与 3~7 天预报（温度/天气现象/降水/风向），并搭载气象灾害预警。'
      '城市名经 GeoAPI 解析为 LocationID，出参 city 返回和风完整行政链（消重名歧义）；'
      '预警为弱依赖，失败不影响主数据（恒返回空数组）。'
      '入参全空时按「设置城市 → 设备定位」回退，全部缺失报 ERR_LOCATION_UNAVAILABLE。';

  @override
  String get paramSignature =>
      'weather_forecast(city?: string, lat?: number, lng?: number, days?: int) [全可选]';

  @override
  Future<SubActionResult> execute(Map<String, Object?> params) async {
    // days 缺省 3；解析失败/越界一律带码返回，**不静默兜底为默认值**。
    final rawDays = params['days'];
    final int dayCount;
    if (rawDays == null) {
      dayCount = _defaultDays;
    } else {
      final d = parseInt(rawDays);
      if (d == null) {
        return _err('INVALID_ARGUMENT', 'days 不是合法整数：$rawDays',
            suggestion: 'days 取 $_minDays~$_maxDays（默认 $_defaultDays）');
      }
      if (d < _minDays || d > _maxDays) {
        return _err('INVALID_ARGUMENT', 'days 超出范围：$d',
            suggestion: 'days 取 $_minDays~$_maxDays：≤3 走三日预报，>3 走七日预报');
      }
      dayCount = d;
    }

    final city = _optString(params['city']);

    final latRaw = params['lat'];
    final lngRaw = params['lng'];
    // G5 宽容解析：不可解析一律 null → 带 code 的错误，**禁取默认值兜底**。
    final lat = latRaw == null ? null : parseDouble(latRaw);
    final lng = lngRaw == null ? null : parseDouble(lngRaw);
    if (latRaw != null && lat == null) {
      return _err('INVALID_ARGUMENT', 'lat 不是合法数值：$latRaw');
    }
    if (lngRaw != null && lng == null) {
      return _err('INVALID_ARGUMENT', 'lng 不是合法数值：$lngRaw');
    }
    if ((lat == null) != (lng == null)) {
      return _err('MISSING_ARGUMENT', 'lat 与 lng 须成对传入（或改用 city）',
          suggestion: '经纬度按 WGS-84/GCJ-02 均可，但必须成对；只给一个无法定位');
    }

    final r = await _provider.forecast(
      city: city,
      lat: lat,
      lng: lng,
      days: dayCount,
    );

    if (!r.success) {
      final e = r.error;
      return _err(
        e?.code ?? 'ERR_WEATHER_UNKNOWN',
        e?.message ?? '天气取数失败',
        suggestion: e?.suggestion,
      );
    }

    return _jsonSuccess(<String, Object?>{
      'success': true,
      if (r.city != null) 'city': r.city,
      if (r.locationId != null) 'locationId': r.locationId,
      if (r.updateTime != null) 'updateTime': r.updateTime,
      if (r.now != null) 'now': r.now,
      'forecast': r.forecast,
      'alerts': r.alerts,
      'isCached': r.isCached,
      'days': dayCount,
    });
  }

  String? _optString(Object? raw) =>
      raw is String && raw.trim().isNotEmpty ? raw.trim() : null;
}
