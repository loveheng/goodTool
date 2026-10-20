// 和风天气（QWeather）真实源（S5c）：`WeatherProvider` 端口的 service 层实现。
//
// 落点依据 standards §1.3「新平台/硬件能力 → lib/service + Provider 端口」：
// 端口定义在 lib/mcp/weather_provider.dart（内核只认抽象），联网实现住 service 层，
// 内核与 tools 层零 dart:io（arch-guard R4 无头约束）。
//
// 契约正文见 docs/product/weather.md，本文件逐条落实其中**硬性约束**：
// ① 两阶段查询（city → GeoAPI 换 LocationID）；② 五级回退链（lat/lng > city >
// 设置项 weather_location > 设备定位 > ERR_LOCATION_UNAVAILABLE）；③ 和风**HTTP 200
// 内仍可能业务失败**，必须拦 Body `code`；④ 响应强制 gzip（autoUncompress）；
// ⑤ 坐标拼接**经度在前**（lng,lat，两位小数）；⑥ 所有请求显式 `unit=m`；
// ⑦ now/forecast 并发聚合、alerts 弱依赖（失败仅降级为空数组）；
// ⑧ TTL 缓存 + 429 频控缓存回退。
//
// 错误一律翻译为带机器码的 [WeatherError] 信封，**永不返回 null**（weather.md 反模式修正）。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../mcp/geo_provider.dart';
import '../mcp/settings_kv.dart';
import '../mcp/weather_provider.dart';
import '../mcp/settings_keys.dart';

/// 城市解析端点域名（GeoAPI 固定，不随 `qweather_host` 配置走）。
const String qweatherGeoHost = 'geo.qweather.com';

/// 默认数据主机（开发/免费版；商业版在设置里填 `api.qweather.com`）。
const String qweatherDefaultApiHost = 'devapi.qweather.com';

/// SettingsKv 键：和风 API Key。
const String kQweatherKey = SettingsKeys.qweatherKey;

/// SettingsKv 键：数据主机（公共版 devapi / 商业版 api）。
const String kQweatherHost = SettingsKeys.qweatherHost;

/// SettingsKv 键：用户预设城市（Agent 无权写入，仅 App 设置页自设）。
const String kWeatherLocation = SettingsKeys.weatherLocation;

/// 天气数据缓存 TTL（开发版配额极低，命中即返回不发起新请求）。
const Duration qweatherCacheTtl = Duration(minutes: 30);

/// 单次请求超时。
const Duration qweatherRequestTimeout = Duration(seconds: 8);

/// 和风真实源：聚合 GeoAPI 解析、Host 路由、Body 业务码拦截、并发聚合、
/// TTL 缓存与频控回退。
///
/// 构造函数里的 `client`/`host`/`port`/`scheme`/`clock` 是**注入口**——生产走
/// 默认 HTTPS + KV 配置，单测注入本地 `HttpServer` 即可走通真实请求链路。
class QWeatherProvider implements WeatherProvider {
  QWeatherProvider(
    this._kv, {
    LocationSensorProvider? sensor,
    this.client,
    this.geoHost = qweatherGeoHost,
    String? apiHost,
    this.port,
    this.scheme = 'https',
    this.ttl = qweatherCacheTtl,
    DateTime Function()? clock,
  })  : _sensor = sensor ?? const NullLocationSensorProvider(),
        apiHostOverride = apiHost,
        clock = clock ?? DateTime.now;

  final SettingsKv _kv;
  final LocationSensorProvider _sensor;
  final HttpClient? client;
  final String geoHost;
  final String? apiHostOverride;
  final int? port;
  final String scheme;
  final Duration ttl;
  final DateTime Function() clock;

  /// `location#days` → 缓存条目（now 与 forecast 共享同一生命周期）。
  final Map<String, _CacheEntry> _cache = {};

  /// 城市名 → LocationID 映射缓存（免 GeoAPI 往返，降频控压力）。
  final Map<String, _Loc> _cityCache = {};

  @override
  Future<WeatherResult> forecast({
    String? city,
    double? lat,
    double? lng,
    int days = 3,
  }) async {
    try {
      final loc = await _resolve(city: city, lat: lat, lng: lng);
      final cacheKey = '${loc.location}#$days';
      final cached = _cache[cacheKey];
      if (cached != null && _isFresh(cached)) {
        return _markCached(cached.result);
      }
      try {
        final result = await _retryOnce(() => _fetchAll(loc, days));
        _cache[cacheKey] = _CacheEntry(result, clock());
        return result;
      } on _WeatherFail catch (e) {
        // 频控自愈 / 取数失败：有缓存一律回放（标 isCached），不静默编造数据。
        if (cached != null) {
          debugPrint('[DEGRADE][weather_${e.code}] 回放缓存: ${e.message}');
          return _markCached(cached.result);
        }
        rethrow;
      }
    } on _WeatherFail catch (e) {
      return WeatherResult.failure(
          WeatherError(e.code, e.message, suggestion: e.suggestion));
    }
  }

  // ---------------------------------------------------------------------------
  // 位置解析：五级回退链（weather.md「缺省回退链」）
  // ---------------------------------------------------------------------------

  Future<_Loc> _resolve({
    String? city,
    double? lat,
    double? lng,
  }) async {
    // 1) 显式经纬度（优先级最高，精确到点）
    if (lat != null && lng != null) {
      return _Loc(_lngLat(lng, lat), null, null);
    }
    // 2) 显式城市名
    if (city != null && city.trim().isNotEmpty) {
      return _lookupCity(city.trim());
    }
    // 3) 设置项 weather_location（原设计跳过此级，导致「设了城市却无定位权限」死锁）
    final preset = await _kv.settingsGet(kWeatherLocation);
    if (preset != null && preset.trim().isNotEmpty) {
      return _lookupCity(preset.trim());
    }
    // 4) 设备定位
    final reading = await _sensor.current();
    if (reading != null) {
      return _Loc(_lngLat(reading.lng, reading.lat), null, null);
    }
    // 5) 全部缺失
    throw const _WeatherFail(
      WeatherErr.locationUnavailable,
      '无法确定位置：未传入经纬度/城市，设置未预设城市，且设备无可用定位',
      '在 App 设置页预设城市，或授予定位权限',
    );
  }

  /// 和风坐标串规范：**经度在前、纬度在后**，保留两位小数。
  String _lngLat(double lng, double lat) =>
      '${lng.toStringAsFixed(2)},${lat.toStringAsFixed(2)}';

  /// 两阶段查询首段：城市中文名 → LocationID（命中映射缓存则免往返）。
  Future<_Loc> _lookupCity(String city) async {
    final hit = _cityCache[city];
    if (hit != null) return hit;

    final body = await _get(geoHost, '/v2/city/lookup', {'location': city});
    final raw = body['location'] is List ? body['location'] as List : const [];
    if (raw.isEmpty) {
      throw _WeatherFail(WeatherErr.cityNotFound, '查无此城：$city',
          '检查城市名/行政区写法，或改用经纬度查询');
    }
    final first = raw.firstWhere(
      (e) => e is Map,
      orElse: () => null,
    ) as Map?;
    if (first == null) {
      throw _WeatherFail(WeatherErr.cityNotFound, '城市解析结果结构异常：$city',
          '改用经纬度查询');
    }
    final id = first['id']?.toString();
    if (id == null || id.isEmpty) {
      throw _WeatherFail(WeatherErr.cityNotFound, '城市解析未返回 LocationID：$city',
          '改用经纬度查询');
    }
    // 出参 city 用和风**完整行政链**，消除重名县市歧义（非用户输入原词）。
    final adm1 = first['adm1']?.toString() ?? '';
    final adm2 = first['adm2']?.toString() ?? '';
    final name = first['name']?.toString() ?? city;
    // 相邻重复段折叠：和风在直辖市常把 adm1/adm2 都填「北京市」，直接拼接会得到
    // 「北京市 北京市 朝阳区」这类冗余行政链（文档出参示例为「北京市 朝阳区」）。
    final display = [adm1, adm2, name]
        .where((s) => s.isNotEmpty)
        .fold<List<String>>(<String>[], (List<String> acc, String s) {
      if (acc.isEmpty || acc.last != s) acc.add(s);
      return acc;
    }).join(' ');

    final loc = _Loc(id, display, id);
    _cityCache[city] = loc;
    return loc;
  }

  // ---------------------------------------------------------------------------
  // 取数：并发聚合 + 预警弱依赖
  // ---------------------------------------------------------------------------

  Future<WeatherResult> _fetchAll(_Loc loc, int days) async {
    final dailyPath = days <= 3 ? '/v7/weather/3d' : '/v7/weather/7d';
    final pair = await Future.wait<Map<String, Object?>>([
      _get(await _apiHost(), '/v7/weather/now', _weatherQuery(loc)),
      _get(await _apiHost(), dailyPath, _weatherQuery(loc)),
    ]);

    final nowBody = pair[0];
    final dailyBody = pair[1];
    final now = nowBody['now'] is Map
        ? (nowBody['now'] as Map).cast<String, Object?>()
        : null;
    final daily = dailyBody['daily'] is List
        ? (dailyBody['daily'] as List)
            .whereType<Map>()
            .map((e) => e.cast<String, Object?>())
            .toList()
        : const <Map<String, Object?>>[];

    // 预警为**弱依赖**：失败仅记 [DEGRADE] 并置 []，不阻断主数据。
    final alerts = await _fetchAlerts(loc);

    return WeatherResult.success(
      city: loc.city,
      locationId: loc.locationId,
      updateTime: (nowBody['updateTime'] ?? dailyBody['updateTime'])?.toString(),
      now: now,
      forecast: daily,
      alerts: alerts,
    );
  }

  /// 所有天气请求显式带 `unit=m`（公制），避免环境差异返回华氏度。
  Map<String, String> _weatherQuery(_Loc loc) =>
      {'location': loc.location, 'unit': 'm'};

  Future<List<Map<String, Object?>>> _fetchAlerts(_Loc loc) async {
    try {
      final body = await _get(
          await _apiHost(), '/v7/warning/now', _weatherQuery(loc));
      final raw = body['warning'] is List ? body['warning'] as List : const [];
      return raw
          .whereType<Map>()
          .map((e) => e.cast<String, Object?>())
          .toList();
    } catch (e) {
      // DEGRADE: [weather_alerts_unavailable] 预警弱依赖失败——仅降级为空数组，
      // 不阻断 now/forecast 主数据（weather.md「并发聚合与部分降级」）。
      debugPrint('[DEGRADE][weather_alerts_unavailable] 预警取数失败: $e');
      return const <Map<String, Object?>>[];
    }
  }

  /// 主数据失败先重试一次（weather.md：任一路失败先重试，仍失败转缓存/错误）。
  Future<T> _retryOnce<T>(Future<T> Function() run) async {
    try {
      return await run();
    } on _WeatherFail {
      return await run();
    }
  }

  // ---------------------------------------------------------------------------
  // 传输层：Key/Host 懒读 + gzip + 状态码与业务码双层拦截
  // ---------------------------------------------------------------------------

  Future<String> _apiHost() async {
    final override = apiHostOverride;
    if (override != null) return override;
    final h = await _kv.settingsGet(kQweatherHost);
    return (h == null || h.trim().isEmpty) ? qweatherDefaultApiHost : h.trim();
  }

  /// 单条 GET：Key 注入 + 超时 + 状态码拦截 + JSON 解析 + Body 业务码拦截。
  Future<Map<String, Object?>> _get(
    String host,
    String path,
    Map<String, String> query,
  ) async {
    final key = await _kv.settingsGet(kQweatherKey);
    if (key == null || key.trim().isEmpty) {
      throw const _WeatherFail(WeatherErr.keyMissing, '和风天气 API Key 未配置',
          '请在 App 设置页填入 QWeather API Key');
    }

    final external = client != null;
    // 和风响应强制 gzip：不解压则 jsonDecode 在二进制乱码上不可逆崩溃。
    final http = client ?? (HttpClient()..autoUncompress = true);
    try {
      final uri = Uri(
        scheme: scheme,
        host: host,
        port: port,
        path: path,
        queryParameters: <String, String>{...query, 'key': key},
      );
      final req = await http.getUrl(uri).timeout(qweatherRequestTimeout);
      final res = await req.close().timeout(qweatherRequestTimeout);
      if (res.statusCode == HttpStatus.tooManyRequests) {
        await res.drain<void>();
        throw const _WeatherFail(WeatherErr.rateLimited, '和风频控：请求过于频繁',
            '降低调用频率；已有缓存时会自动回放');
      }
      if (res.statusCode == HttpStatus.unauthorized ||
          res.statusCode == HttpStatus.forbidden ||
          res.statusCode == HttpStatus.paymentRequired) {
        await res.drain<void>();
        throw _WeatherFail(WeatherErr.unauthorized,
            '和风鉴权失败（HTTP ${res.statusCode}）',
            '核对 Key 绑定与额度、Host（开发版 devapi / 商业版 api）及接口权限');
      }
      if (res.statusCode == HttpStatus.notFound) {
        await res.drain<void>();
        throw const _WeatherFail(WeatherErr.cityNotFound,
            '该地点无天气数据（HTTP 404）', '检查城市名写法，或改用经纬度查询');
      }
      if (res.statusCode != HttpStatus.ok) {
        await res.drain<void>();
        throw _WeatherFail(WeatherErr.network,
            '和风返回 HTTP ${res.statusCode}', '稍后重试，或检查网络连接');
      }
      final text = await res
          .transform(utf8.decoder)
          .fold<String>('', (acc, s) => '$acc$s')
          .timeout(qweatherRequestTimeout);

      final Object? decoded;
      try {
        decoded = jsonDecode(text);
      } on FormatException {
        throw const _WeatherFail(
            WeatherErr.network, '和风响应不是合法 JSON（疑似未解压的 gzip 流）',
            '检查网络代理是否篡改响应');
      }
      if (decoded is! Map<String, Object?>) {
        throw const _WeatherFail(
            WeatherErr.network, '和风响应不是 JSON 对象', '稍后重试');
      }
      return _checkBody(decoded);
    } on _WeatherFail {
      rethrow;
    } on SocketException catch (e) {
      throw _WeatherFail(WeatherErr.network, '网络不可达：${e.message}',
          '检查网络连接后重试');
    } on TimeoutException {
      throw const _WeatherFail(
          WeatherErr.network, '和风请求超时', '检查网络连接后重试');
    } on HttpException catch (e) {
      throw _WeatherFail(WeatherErr.network, 'HTTP 层失败：${e.message}',
          '检查网络连接后重试');
    } on Exception catch (e) {
      throw _WeatherFail(WeatherErr.network, '和风请求失败：$e',
          '检查网络连接后重试');
    } finally {
      if (!external) http.close(force: true);
    }
  }

  /// **HTTP 200 内的业务码拦截**：和风鉴权失败/欠费/无数据时状态码常仍为 200，
  /// 真实状态藏在 Body `code`——只信 HTTP 码会拿着 `code:"401"` 去取 now → 空指针。
  Map<String, Object?> _checkBody(Map<String, Object?> body) {
    final code = body['code']?.toString();
    if (code == null || code == '200') return body;
    switch (code) {
      case '401':
      case '402':
      case '403':
        throw const _WeatherFail(WeatherErr.unauthorized,
            '和风鉴权失败：Key 无效、额度透支、Host 错配或无接口权限',
            '核对 Key 绑定与额度、Host（开发版 devapi / 商业版 api）及接口权限');
      case '404':
        throw const _WeatherFail(WeatherErr.cityNotFound,
            '该地点无天气数据', '检查城市名/行政区写法，或改用经纬度查询');
      case '429':
        throw const _WeatherFail(WeatherErr.rateLimited,
            '和风频控：配额已耗尽', '降低调用频率；已有缓存时会自动回放');
      default:
        throw _WeatherFail(WeatherErr.network, '和风返回未知业务码 $code',
            '稍后重试，或核对接口权限');
    }
  }

  // ---------------------------------------------------------------------------
  // 缓存
  // ---------------------------------------------------------------------------

  bool _isFresh(_CacheEntry e) => clock().difference(e.at) < ttl;

  /// 打上 `isCached: true`（缓存回放时对外可观察，Agent 不得当作实时数据）。
  WeatherResult _markCached(WeatherResult r) => WeatherResult.success(
        city: r.city,
        locationId: r.locationId,
        updateTime: r.updateTime,
        now: r.now,
        forecast: r.forecast,
        alerts: r.alerts,
        isCached: true,
      );
}

/// 位置解析结果：`location` 为和风查询串（LocationID 或 `lng,lat`）。
class _Loc {
  const _Loc(this.location, this.city, this.locationId);
  final String location;
  final String? city;
  final String? locationId;
}

class _CacheEntry {
  const _CacheEntry(this.result, this.at);
  final WeatherResult result;
  final DateTime at;
}

/// 内部失败信号（携带机器码，向上翻译为 [WeatherError]，不向 Agent 抛堆栈）。
class _WeatherFail implements Exception {
  const _WeatherFail(this.code, this.message, [this.suggestion]);
  final String code;
  final String message;
  final String? suggestion;
}
