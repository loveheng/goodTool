// weather 领域网关适配层（S5b + 域深化四件）：把 WeatherProvider 端口包成 1 个
// MCP 工具，注册 product/weather.md 定义的 5 个原子动作（全 R 档）——
// action 名原样沿用能力文档，不改名、不自造（G1）。
//
// 可见性（§3.3 G2）：仅公开 buildWeatherTool()；具体子操作以 `_WeatherXxxSub` 私有。
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

/// 生活指数合法天数（weather.md：1 走 /v7/indices/1d，3 走 /v7/indices/3d）。
const Set<int> _indexDays = {1, 3};

/// 公开入口：构建 `weather` 领域网关，注册 5 个子操作。
///
/// R 档-only（weather.md 档位表为 R），[CategoryTool.commandGateway] 传 null
/// ——[CategoryTool.call] 仅 W 档才触达网关，R 档物理不可穿透（fail-closed）。
///
/// [ToolVisibility.shared]：本域属四大聚合工具之一，声明允许宿主收进共享面。
CategoryTool buildWeatherTool(WeatherProvider provider) {
  final cat = CategoryTool(
    'weather',
    '天气：实时天气与 3~7 天结构化预报、气象灾害预警、实时空气质量 AQI、生活指数、'
    '日出日落、分钟级降水（和风 QWeather 后端）。'
    '位置解析优先级 = 显式经纬度 > city 城市名 > 设置项 weather_location > 设备当前定位；'
    '全部缺失返回 ERR_LOCATION_UNAVAILABLE。与日历联动做出行建议时常用 days=7。',
    null,
    visibility: ToolVisibility.shared,
  );
  cat.register(_WeatherForecastSub(provider));
  cat.register(_WeatherAirSub(provider));
  cat.register(_WeatherIndicesSub(provider));
  cat.register(_WeatherAstronomySub(provider));
  cat.register(_WeatherMinutelySub(provider));
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

/// 位置入参（city / lat / lng，五动作共用同一宽容解析口径，G5）。
class _LocArgs {
  const _LocArgs(this.city, this.lat, this.lng);

  final String? city;
  final double? lat;
  final double? lng;
}

/// city/lat/lng 宽容解析：lat/lng 须成对，不可解析一律产出带码错误，**禁兜底**。
/// 返回 `(args, null)` = 成功；`(null, err)` = 失败（err 已是终态结果）。
(_LocArgs?, SubActionResult?) _parseLocArgs(Map<String, Object?> params) {
  final city = params['city'];
  final latRaw = params['lat'];
  final lngRaw = params['lng'];
  final lat = latRaw == null ? null : parseDouble(latRaw);
  final lng = lngRaw == null ? null : parseDouble(lngRaw);
  if (latRaw != null && lat == null) {
    return (null, _err('INVALID_ARGUMENT', 'lat 不是合法数值：$latRaw'));
  }
  if (lngRaw != null && lng == null) {
    return (null, _err('INVALID_ARGUMENT', 'lng 不是合法数值：$lngRaw'));
  }
  if ((lat == null) != (lng == null)) {
    return (
      null,
      _err('MISSING_ARGUMENT', 'lat 与 lng 须成对传入（或改用 city）',
          suggestion: '经纬度按 WGS-84/GCJ-02 均可，但必须成对；只给一个无法定位')
    );
  }
  return (
    _LocArgs(
      city is String && city.trim().isNotEmpty ? city.trim() : null,
      lat,
      lng,
    ),
    null
  );
}

/// 失败信封 → 结构化错误结果（五动作共用）。
SubActionResult _failOf(WeatherResult r) {
  final e = r.error;
  return _err(
    e?.code ?? 'ERR_WEATHER_UNKNOWN',
    e?.message ?? '天气取数失败',
    suggestion: e?.suggestion,
  );
}

/// weather_air：实时空气质量 AQI（R 档）。
class _WeatherAirSub extends SubAction {
  _WeatherAirSub(this._provider);

  final WeatherProvider _provider;

  @override
  String get name => 'weather_air';

  @override
  String get description =>
      '查询实时空气质量（AQI 指数、等级、首要污染物与 pm2.5/pm10 等分项）。'
      '位置解析与 weather_forecast 同回退链；「出门要不要戴口罩/开净化器」类问题的数据源。';

  @override
  String get paramSignature =>
      'weather_air(city?: string, lat?: number, lng?: number) [全可选]';

  @override
  Future<SubActionResult> execute(Map<String, Object?> params) async {
    final (args, err) = _parseLocArgs(params);
    if (args == null) return err!;
    final r = await _provider.air(city: args.city, lat: args.lat, lng: args.lng);
    if (!r.success) return _failOf(r);
    return _jsonSuccess(<String, Object?>{
      'success': true,
      if (r.city != null) 'city': r.city,
      if (r.locationId != null) 'locationId': r.locationId,
      if (r.updateTime != null) 'updateTime': r.updateTime,
      if (r.now != null) 'air': r.now,
      'isCached': r.isCached,
    });
  }
}

/// weather_indices：生活指数（R 档）。
class _WeatherIndicesSub extends SubAction {
  _WeatherIndicesSub(this._provider);

  final WeatherProvider _provider;

  @override
  String get name => 'weather_indices';

  @override
  String get description =>
      '查询生活指数（穿衣/洗车/运动/紫外线/旅游/感冒等，和风 indices）。'
      'days=1|3（缺省 1）；type 为指数类型数字或逗号分隔多值，缺省由和风默认。'
      'Agent 出行/日程建议的直接素材，常与 weather_forecast 联用。';

  @override
  String get paramSignature =>
      'weather_indices(city?: string, lat?: number, lng?: number, '
      'days?: int(1|3), type?: string) [全可选]';

  @override
  Future<SubActionResult> execute(Map<String, Object?> params) async {
    final (args, err) = _parseLocArgs(params);
    if (args == null) return err!;

    final rawDays = params['days'];
    final int dayCount;
    if (rawDays == null) {
      dayCount = 1;
    } else {
      final d = parseInt(rawDays);
      if (d == null || !_indexDays.contains(d)) {
        return _err('INVALID_ARGUMENT', 'days 须为 1 或 3：$rawDays',
            suggestion: '1 走一日指数，3 走三日指数');
      }
      dayCount = d;
    }
    final rawType = params['type'];
    final String? type;
    if (rawType == null) {
      type = null;
    } else if (rawType is String && rawType.trim().isNotEmpty) {
      // 数字或逗号分隔数字（和风 type 允许多选）；其余形态拒绝，不兜底。
      final t = rawType.trim();
      if (t.split(',').every((p) => int.tryParse(p.trim()) != null)) {
        type = t;
      } else {
        return _err('INVALID_ARGUMENT',
            'type 须为指数类型数字或逗号分隔数字：$rawType');
      }
    } else {
      return _err('INVALID_ARGUMENT', 'type 须为字符串（数字或逗号分隔）：$rawType');
    }

    final r = await _provider.indices(
      city: args.city,
      lat: args.lat,
      lng: args.lng,
      days: dayCount,
      type: type,
    );
    if (!r.success) return _failOf(r);
    return _jsonSuccess(<String, Object?>{
      'success': true,
      if (r.city != null) 'city': r.city,
      if (r.locationId != null) 'locationId': r.locationId,
      if (r.updateTime != null) 'updateTime': r.updateTime,
      'indices': r.forecast,
      'isCached': r.isCached,
      'days': dayCount,
    });
  }
}

/// weather_astronomy：日出日落（R 档）。
class _WeatherAstronomySub extends SubAction {
  _WeatherAstronomySub(this._provider);

  final WeatherProvider _provider;

  @override
  String get name => 'weather_astronomy';

  @override
  String get description =>
      '查询指定日期的日出日落时刻（和风 solar）。date 缺省设备今日；'
      '「今天几点天黑 / 夜跑安不安全 / 拍照黄金时段」类问题的数据源。';

  @override
  String get paramSignature =>
      'weather_astronomy(city?: string, lat?: number, lng?: number, '
      'date?: "YYYY-MM-DD") [全可选]';

  @override
  Future<SubActionResult> execute(Map<String, Object?> params) async {
    final (args, err) = _parseLocArgs(params);
    if (args == null) return err!;
    final rawDate = params['date'];
    final String? date;
    if (rawDate == null) {
      date = null;
    } else if (rawDate is String &&
        RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(rawDate.trim())) {
      date = rawDate.trim();
    } else {
      return _err('INVALID_ARGUMENT', 'date 须为 YYYY-MM-DD：$rawDate');
    }
    final r = await _provider.astronomy(
      city: args.city,
      lat: args.lat,
      lng: args.lng,
      date: date,
    );
    if (!r.success) return _failOf(r);
    return _jsonSuccess(<String, Object?>{
      'success': true,
      if (r.city != null) 'city': r.city,
      if (r.locationId != null) 'locationId': r.locationId,
      if (r.updateTime != null) 'updateTime': r.updateTime,
      if (r.now != null) 'solar': r.now,
      'isCached': r.isCached,
    });
  }
}

/// weather_minutely：分钟级降水（R 档）。
class _WeatherMinutelySub extends SubAction {
  _WeatherMinutelySub(this._provider);

  final WeatherProvider _provider;

  @override
  String get name => 'weather_minutely';

  @override
  String get description =>
      '查询未来两小时分钟级降水（每 5 分钟一点 + 一句人话总结 summary）。'
      '「两小时内会不会下雨 / 要不要带伞」类问题的黄金数据源；'
      '需账号开通该接口，未开通按错误模型结构化报错。';

  @override
  String get paramSignature =>
      'weather_minutely(city?: string, lat?: number, lng?: number) [全可选]';

  @override
  Future<SubActionResult> execute(Map<String, Object?> params) async {
    final (args, err) = _parseLocArgs(params);
    if (args == null) return err!;
    final r = await _provider.minutely(
        city: args.city, lat: args.lat, lng: args.lng);
    if (!r.success) return _failOf(r);
    return _jsonSuccess(<String, Object?>{
      'success': true,
      if (r.city != null) 'city': r.city,
      if (r.locationId != null) 'locationId': r.locationId,
      if (r.updateTime != null) 'updateTime': r.updateTime,
      if (r.now?['summary'] != null) 'summary': r.now!['summary'],
      'minutely': r.forecast,
      'isCached': r.isCached,
    });
  }
}
