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

/// GeoAPI 公共域名。
///
/// **已失效（2026-10-23 实测）**：`geoapi.qweather.com` 对 `/v2/city/lookup` 与
/// `/geo/v2/city/lookup` 一律返回 404 空体（连 401 鉴权错都不给），公共
/// `devapi`/`api` 则返回 403 `Invalid Host`。故公共域名全线不可用：
/// **GeoAPI 与天气端点都必须走账号专属 Host**（形如 `xxxx.re.qweatherapi.com`，
/// 控制台「项目管理」复制），它同时承载两者（GeoAPI 路径前缀 `/geo`）。
const String qweatherGeoHost = 'geoapi.qweather.com';

/// Host 归一化：用户从控制台复制粘贴可能带上 `https://`、尾部 `/` 甚至路径段，
/// 直接塞进 `Uri(host:)` 会拼出畸形 URI（请求必然失败且错误难懂）。归一为
/// **纯主机名**（小写、无协议、无路径、无端口）。
String normalizeQweatherHost(String raw) {
  var h = raw.trim();
  if (h.isEmpty) return '';
  final lower = h.toLowerCase();
  if (lower.startsWith('https://')) {
    h = h.substring('https://'.length);
  } else if (lower.startsWith('http://')) {
    h = h.substring('http://'.length);
  }
  final slash = h.indexOf('/');
  if (slash >= 0) h = h.substring(0, slash);
  return h.trim().toLowerCase();
}

/// SettingsKv 键：和风 API Key。
const String kQweatherKey = SettingsKeys.qweatherKey;

/// SettingsKv 键：账号专属 API Host（公共域名自 2024 年起停用，本项必填）。
const String kQweatherHost = SettingsKeys.qweatherHost;

/// SettingsKv 键：用户预设城市（Agent 无权写入，仅 App 设置页自设）。
const String kWeatherLocation = SettingsKeys.weatherLocation;

/// 天气数据缓存 TTL（开发版配额极低，命中即返回不发起新请求）。
const Duration qweatherCacheTtl = Duration(minutes: 30);

/// 单次请求超时。
const Duration qweatherRequestTimeout = Duration(seconds: 8);

/// 配额护栏②：出网取数的最小起跑间隔（串行队列相邻两次取数之间）。
/// 开发版和风 QPS 常限 20 甚至更低，300ms ≈ 3 QPS 上限留足余量；注入 0 关闭
/// （单测注入小值或 0）。pacing 走**真实时间**（与 Future.delayed 同钟），不经
/// 注入 clock——TTL/冷却的逻辑时间注入与墙钟节流分离，互不干扰。
const Duration qweatherFetchPacing = Duration(milliseconds: 300);

/// 配额护栏③：命中 429 后的冷却窗，冷却期内不再出网（防连环 429 白烧配额）。
const Duration qweatherRateLimitCooldown = Duration(seconds: 60);

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
    String? apiHost,
    this.port,
    this.scheme = 'https',
    this.ttl = qweatherCacheTtl,
    this.pacing = qweatherFetchPacing,
    this.rateLimitCooldown = qweatherRateLimitCooldown,
    DateTime Function()? clock,
  })  : _sensor = sensor ?? const NullLocationSensorProvider(),
        apiHostOverride = apiHost,
        clock = clock ?? DateTime.now;

  final SettingsKv _kv;
  final LocationSensorProvider _sensor;
  final HttpClient? client;

  /// 注入口：覆盖账号专属 Host（单测注入本地 HttpServer 用；生产恒走 KV 配置）。
  final String? apiHostOverride;
  final int? port;
  final String scheme;
  final Duration ttl;

  /// 配额护栏②注入口：出网取数最小起跑间隔（0 关闭）。
  final Duration pacing;

  /// 配额护栏③注入口：429 冷却窗时长。
  final Duration rateLimitCooldown;
  final DateTime Function() clock;

  /// `location#days` → 缓存条目（now 与 forecast 共享同一生命周期）。
  final Map<String, _CacheEntry> _cache = {};

  /// 城市名 → LocationID 映射缓存（免 GeoAPI 往返，降频控压力）。
  final Map<String, _Loc> _cityCache = {};

  // ---- 配额护栏（开发版配额极低；Agent 并发调用与 UI 逐城聚合叠加时防风暴） ----

  /// 护栏①：同 `location#days` 的在途取数合并——并发调用共享同一次出网
  /// （UI 逐城聚合 + Agent 同时查同城的场景下不重复消耗配额）。
  final Map<String, Future<WeatherResult>> _inflight = {};

  /// 护栏②：串行取数队列尾——不同 key 的并发取数排队出网，杜绝并发风暴；
  /// 队尾推进吞掉任务结果（成败都放行下一个，错误已由任务自身折叠为信封）。
  Future<void> _fetchQueue = Future<void>.value();

  /// 护栏② pacing 基准：上次取数起跑时刻（真实时间）。
  DateTime _lastFetchStart = DateTime.fromMillisecondsSinceEpoch(0);

  /// 护栏③：429 冷却截止时刻（注入 clock 驱动；null = 无冷却）。
  DateTime? _cooldownUntil;

  @override
  Future<WeatherResult> forecast({
    String? city,
    double? lat,
    double? lng,
    int days = 3,
  }) async {
    try {
      // Key 校验前置：Key 是每一跳请求（含 GeoAPI 城市解析）都必需的，
      // **缺失优先于 Host 缺失上报**——更基础的配置错先报，用户动作更明确。
      await _ensureKey();
      final loc = await _resolve(city: city, lat: lat, lng: lng);
      return await _guardedFetch('${loc.location}#$days', () async {
        final result = await _retryOnce(() => _fetchAll(loc, days));
        return result;
      });
    } on _WeatherFail catch (e) {
      return WeatherResult.failure(
          WeatherError(e.code, e.message, suggestion: e.suggestion));
    }
  }

  /// 共享取数通道（forecast 与域深化四件共用）：TTL 命中回放 → 429 冷却拦截 →
  /// 同 key singleflight 合并 → 串行队列 + pacing 出网。失败折叠在队列任务内
  /// （并发等待者拿到同一份，不再各自重试放大风暴）。
  Future<WeatherResult> _guardedFetch(
    String cacheKey,
    Future<WeatherResult> Function() doFetch,
  ) async {
    final cached = _cache[cacheKey];
    if (cached != null && _isFresh(cached)) {
      return _markCached(cached.result);
    }
    // 护栏③：429 冷却期内不出网——有任何缓存（含过期）即回放并标 isCached，
    // 否则带冷却指引失败（fail-closed，不硬闯频控白烧配额）。
    final cooldown = _cooldownUntil;
    if (cooldown != null && clock().isBefore(cooldown)) {
      if (cached != null) {
        debugPrint('[DEGRADE][weather_cooldown] 429 冷却期内回放缓存: $cacheKey');
        return _markCached(cached.result);
      }
      throw _WeatherFail(
        WeatherErr.rateLimited,
        '和风频控冷却中（约 ${cooldown.difference(clock()).inSeconds}s 后恢复出网）',
        '降低调用频率；冷却结束后重试，期间已有缓存会自动回放',
      );
    }
    // 护栏①：同 key 并发合并——在途取数直接共享，不重复出网。
    final shared = _inflight[cacheKey];
    if (shared != null) {
      return await shared;
    }
    final task = _enqueueFetch(cacheKey, doFetch);
    _inflight[cacheKey] = task;
    try {
      return await task;
    } finally {
      _inflight.remove(cacheKey);
    }
  }

  /// 护栏②：把取数任务挂到串行队列尾（先到先服务，相邻任务间按 [pacing] 留间隔）。
  ///
  /// 队尾推进吞掉任务结果——错误已在任务内折叠为失败信封，队列本身只关心
  /// 「前一个落定」，等待者从返回的 [task] 拿结果。
  Future<WeatherResult> _enqueueFetch(
    String cacheKey,
    Future<WeatherResult> Function() doFetch,
  ) {
    final task = _fetchQueue.then((_) => _pacedFetch(cacheKey, doFetch));
    _fetchQueue = task.then<void>((_) {}, onError: (_) {});
    return task;
  }

  /// 串行队列中的单次取数：pacing 补足间隔 → 出网 → 写缓存；
  /// 失败折叠为失败信封（429 额外开启冷却窗；有缓存一律回放标 isCached）。
  Future<WeatherResult> _pacedFetch(
    String cacheKey,
    Future<WeatherResult> Function() doFetch,
  ) async {
    final since = DateTime.now().difference(_lastFetchStart);
    if (since < pacing) {
      await Future<void>.delayed(pacing - since);
    }
    _lastFetchStart = DateTime.now();
    try {
      final result = await doFetch();
      _cache[cacheKey] = _CacheEntry(result, clock());
      return result;
    } on _WeatherFail catch (e) {
      if (e.code == WeatherErr.rateLimited) {
        // 护栏③：命中频控 → 开启冷却窗（防连环 429 白烧配额）。
        _cooldownUntil = clock().add(rateLimitCooldown);
      }
      // 频控自愈 / 取数失败：有缓存一律回放（标 isCached），不静默编造数据。
      final cached = _cache[cacheKey];
      if (cached != null) {
        debugPrint('[DEGRADE][weather_${e.code}] 回放缓存: ${e.message}');
        return _markCached(cached.result);
      }
      return WeatherResult.failure(
          WeatherError(e.code, e.message, suggestion: e.suggestion));
    }
  }

  // ---------------------------------------------------------------------------
  // 域深化四件：air / indices / astronomy / minutely（共用回退链与配额护栏）
  // ---------------------------------------------------------------------------

  @override
  Future<WeatherResult> air({String? city, double? lat, double? lng}) =>
      _projection(
        city: city,
        lat: lat,
        lng: lng,
        cachePrefix: 'air',
        path: '/v7/air/now',
        objectKey: 'airNow',
      );

  @override
  Future<WeatherResult> indices({
    String? city,
    double? lat,
    double? lng,
    int days = 1,
    String? type,
  }) {
    final path = days <= 1 ? '/v7/indices/1d' : '/v7/indices/3d';
    return _projection(
      city: city,
      lat: lat,
      lng: lng,
      cachePrefix: 'idx#${days <= 1 ? 1 : 3}'
          '${type == null || type.trim().isEmpty ? '' : '#$type'}',
      path: path,
      listKey: 'daily',
      extraQuery: type == null || type.trim().isEmpty
          ? null
          : {'type': type.trim()},
    );
  }

  @override
  Future<WeatherResult> astronomy({
    String? city,
    double? lat,
    double? lng,
    String? date,
  }) {
    final d = (date == null || date.trim().isEmpty)
        ? _deviceToday()
        : date.trim();
    return _projection(
      city: city,
      lat: lat,
      lng: lng,
      cachePrefix: 'solar#$d',
      path: '/v7/astronomy/solar',
      objectKey: 'solar',
      extraQuery: {'date': d},
    );
  }

  /// 设备本地今日 `YYYY-MM-DD`（astronomy 缺省日期）。
  static String _deviceToday() {
    final n = DateTime.now();
    String p(int v) => v.toString().padLeft(2, '0');
    return '${n.year.toString().padLeft(4, '0')}-${p(n.month)}-${p(n.day)}';
  }

  @override
  Future<WeatherResult> minutely({String? city, double? lat, double? lng}) =>
      _projection(
        city: city,
        lat: lat,
        lng: lng,
        cachePrefix: 'min',
        path: '/v7/minutely/5m',
        summaryOf: (body) => body['summary']?.toString(),
        listKey: 'minutely',
      );

  /// 域深化四件的公共骨架：Key 前置 → 回退链解析 → 独立键位走共享护栏通道 →
  /// 单端点投影（[objectKey] 进 `now`，[listKey] 进 `forecast`，[summaryOf]
  /// 兜 `now.summary`）。
  Future<WeatherResult> _projection({
    String? city,
    double? lat,
    double? lng,
    required String cachePrefix,
    required String path,
    String? objectKey,
    String? listKey,
    String? Function(Map<String, Object?>)? summaryOf,
    Map<String, String>? extraQuery,
  }) async {
    try {
      await _ensureKey();
      final loc = await _resolve(city: city, lat: lat, lng: lng);
      return await _guardedFetch('$cachePrefix:${loc.location}', () async {
        final host = await _apiHost();
        return _retryOnce(() => _fetchOne(
              host,
              path,
              <String, String>{..._weatherQuery(loc), ...?extraQuery},
              loc,
              objectKey: objectKey,
              listKey: listKey,
              summaryOf: summaryOf,
            ));
      });
    } on _WeatherFail catch (e) {
      return WeatherResult.failure(
          WeatherError(e.code, e.message, suggestion: e.suggestion));
    }
  }

  /// 单端点取数投影：`objectKey` 单对象段 → `now`；`listKey` 列表段 → `forecast`；
  /// `summaryOf`（分钟级降水总结）→ `now.summary`。空段不出键（不吐 null）。
  Future<WeatherResult> _fetchOne(
    String host,
    String path,
    Map<String, String> query,
    _Loc loc, {
    String? objectKey,
    String? listKey,
    String? Function(Map<String, Object?>)? summaryOf,
  }) async {
    final body = await _get(host, path, query);
    final now = objectKey != null && body[objectKey] is Map
        ? (body[objectKey] as Map).cast<String, Object?>()
        : null;
    final list = listKey != null && body[listKey] is List
        ? (body[listKey] as List)
            .whereType<Map>()
            .map((e) => e.cast<String, Object?>())
            .toList(growable: false)
        : const <Map<String, Object?>>[];
    final summary = now == null && summaryOf != null ? summaryOf(body) : null;
    return WeatherResult.success(
      city: loc.city,
      locationId: loc.locationId,
      updateTime: body['updateTime']?.toString(),
      now: now ?? (summary == null ? null : <String, Object?>{'summary': summary}),
      forecast: list,
    );
  }

  /// Key 校验（每次 forecast 前置一次）：缺失即带机器码失败，不静默兜底。
  Future<void> _ensureKey() async {
    final key = await _kv.settingsGet(kQweatherKey);
    if (key == null || key.trim().isEmpty) {
      throw const _WeatherFail(WeatherErr.keyMissing, '和风天气 API Key 未配置',
          '请在 App 设置页填入 QWeather API Key');
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

  /// GeoAPI 端点解析：**只用账号专属 Host**（公共 GeoAPI 域名已全量失效，见
  /// `qweatherGeoHost` 说明）。账号专属 Host 同时承载天气与 GeoAPI 城市解析
  /// （GeoAPI 路径前缀 `/geo`）。
  Future<({String host, String path})> _geoEndpoint() async {
    final raw = await _kv.settingsGet(kQweatherHost);
    final h = normalizeQweatherHost(raw ?? '');
    if (h.isNotEmpty) {
      return (host: h, path: '/geo/v2/city/lookup');
    }
    final override = apiHostOverride;
    if (override != null) {
      // 注入口（单测/注入）：与账号 Host 同口径。
      return (host: override, path: '/geo/v2/city/lookup');
    }
    // 公共 GeoAPI 兜底已失效：再拿它兜底只会拿到 404 空体，被翻译成误导性的
    // 「查无此城」——这里直接给真实原因（Host 未配置）。
    throw const _WeatherFail(
      WeatherErr.hostMissing,
      '未配置和风天气 API Host（城市解析亦需要）',
      '和风公共域名（devapi/api/geoapi）自 2024 年起已停用。请在 App 设置页填入'
      '账号专属 API Host（控制台「项目管理」复制，形如 xxxx.re.qweatherapi.com）；'
      '该 Host 同时服务天气与 GeoAPI 城市解析。',
    );
  }

  /// 两阶段查询首段：城市中文名 → LocationID（命中映射缓存则免往返）。
  Future<_Loc> _lookupCity(String city) async {
    final hit = _cityCache[city];
    if (hit != null) return hit;

    final ep = await _geoEndpoint();
    final body = await _get(ep.host, ep.path, {'location': city});
    final options = _parseCityOptions(body, fallbackName: city);
    if (options.isEmpty) {
      throw _WeatherFail(WeatherErr.cityNotFound, '查无此城：$city',
          '检查城市名/行政区写法，或改用经纬度查询');
    }
    final first = options.first;
    final lid = first.locationId;
    if (lid == null || lid.isEmpty) {
      throw _WeatherFail(WeatherErr.cityNotFound, '城市解析未返回 LocationID：$city',
          '改用经纬度查询');
    }
    final loc = _Loc(lid, first.name, lid);
    _cityCache[city] = loc;
    return loc;
  }

  /// 城市搜索（UI 搜索条）：GeoAPI lookup **多候选**投影；「查无此城」= 成功
  /// 空列表（非错误）。Key/Host 缺失等失败走结构化信封，不静默空列表。
  @override
  Future<CitySearchResult> searchCity(String query) async {
    final q = query.trim();
    if (q.isEmpty) {
      return const CitySearchResult.success(<QCityOption>[]);
    }
    try {
      await _ensureKey();
      final ep = await _geoEndpoint();
      final body = await _get(ep.host, ep.path, {'location': q});
      return CitySearchResult.success(_parseCityOptions(body, fallbackName: q));
    } on _WeatherFail catch (e) {
      if (e.code == WeatherErr.cityNotFound) {
        return const CitySearchResult.success(<QCityOption>[]);
      }
      return CitySearchResult.failure(
          WeatherError(e.code, e.message, suggestion: e.suggestion));
    }
  }

  /// 坐标反查城市（地图选点加城市）：GeoAPI lookup 直查坐标，**经度在前、
  /// 两位小数**（与天气查询 `_lngLat` 同口径）。「查无此城」（海域/无人区）=
  /// 成功空列表；Key/Host 缺失等失败走结构化信封，不静默空列表。
  @override
  Future<CitySearchResult> lookupCityByCoords({
    required double lat,
    required double lng,
  }) async {
    try {
      await _ensureKey();
      final ep = await _geoEndpoint();
      final body =
          await _get(ep.host, ep.path, {'location': _lngLat(lng, lat)});
      return CitySearchResult.success(
          _parseCityOptions(body, fallbackName: '所选位置'));
    } on _WeatherFail catch (e) {
      if (e.code == WeatherErr.cityNotFound) {
        return const CitySearchResult.success(<QCityOption>[]);
      }
      return CitySearchResult.failure(
          WeatherError(e.code, e.message, suggestion: e.suggestion));
    }
  }

  /// GeoAPI `location` 列表 → 类型化候选（行政链折叠与 `_lookupCity` 同口径）。
  List<QCityOption> _parseCityOptions(
    Map<String, Object?> body, {
    required String fallbackName,
  }) {
    final raw = body['location'] is List ? body['location'] as List : const [];
    return raw.whereType<Map>().map((e) {
      final m = e.cast<String, Object?>();
      final adm1 = m['adm1']?.toString() ?? '';
      final adm2 = m['adm2']?.toString() ?? '';
      final name = m['name']?.toString() ?? fallbackName;
      // 相邻重复段折叠：和风在直辖市常把 adm1/adm2 都填「北京市」（文档出参
      // 示例为「北京市 朝阳区」，见 `_lookupCity` 同款处理）。
      final display = [adm1, adm2, name]
          .where((s) => s.isNotEmpty)
          .fold<List<String>>(<String>[], (List<String> acc, String s) {
        if (acc.isEmpty || acc.last != s) acc.add(s);
        return acc;
      }).join(' ');
      final lat = double.tryParse(m['lat']?.toString() ?? '');
      final lng = double.tryParse(m['lon']?.toString() ?? '');
      return QCityOption(
        name: display,
        lat: lat ?? 0,
        lng: lng ?? 0,
        locationId: m['id']?.toString(),
      );
    }).toList(growable: false);
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
    final raw = await _kv.settingsGet(kQweatherHost);
    final h = normalizeQweatherHost(raw ?? '');
    // 2024 起公共 devapi/api 域名停用返回 403——不再 fallback 到已死的默认域名，
    // 改为明确引导用户配置账号专属 Host（控制台「项目管理」复制，形如
    // xxxx.re.qweatherapi.com），该 Host 同时服务天气与 GeoAPI。
    if (h.isEmpty) {
      throw const _WeatherFail(
        WeatherErr.hostMissing,
        '未配置和风天气 API Host',
        '自 2024 年起和风天气已停用公共 devapi/api 域名（返回 403）。请在 App 设置页'
        '填入账号专属 API Host（控制台「项目管理」复制，形如 xxxx.re.qweatherapi.com）；'
        '该 Host 同时用于天气与 GeoAPI 城市解析。',
      );
    }
    return h;
  }

  /// 单条 GET：Key 注入 + 超时 + 状态码拦截 + JSON 解析 + Body 业务码拦截。
  ///
  /// **错误体必须读出来**：和风把真实原因放在响应体里——403 时给 JSON:API 形态
  /// `{"error":{"title":"Invalid Host","detail":"An invalid or unauthorized API Host."}}`，
  /// 未开通的场景给中文「服务不可访问」。旧实现对 4xx 直接 `drain` 丢弃响应体，
  /// 用户只看到笼统「鉴权失败」，拿不到「Host 无效 / 服务未开通」这类可自愈真因。
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
      final text = await res
          .transform(utf8.decoder)
          .fold<String>('', (acc, s) => '$acc$s')
          .timeout(qweatherRequestTimeout);

      final Map<String, Object?>? decoded = _decodeObject(text);

      if (res.statusCode == HttpStatus.tooManyRequests) {
        throw const _WeatherFail(WeatherErr.rateLimited, '和风频控：请求过于频繁',
            '降低调用频率；已有缓存时会自动回放');
      }
      if (res.statusCode != HttpStatus.ok) {
        throw _failFromHttp(res.statusCode, decoded);
      }
      if (decoded == null) {
        throw const _WeatherFail(
            WeatherErr.network, '和风响应不是合法 JSON 对象（疑似未解压的 gzip 流）',
            '检查网络代理是否篡改响应');
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

  /// 响应体解码：JSON 对象 → Map；非 JSON / 非对象 → null（由调用方归类）。
  Map<String, Object?>? _decodeObject(String text) {
    if (text.trim().isEmpty) return null;
    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException {
      return null;
    }
    if (decoded is Map) return decoded.cast<String, Object?>();
    return null;
  }

  /// 非 200 响应 → 内部失败信号（**读错误体求真因**，不丢信息）。
  _WeatherFail _failFromHttp(int status, Map<String, Object?>? body) {
    final detail = body == null ? '' : _errorDetailOf(body);
    final suffix = detail.isEmpty ? '' : '：$detail';
    switch (status) {
      case HttpStatus.unauthorized:
        return _WeatherFail(WeatherErr.unauthorized,
            '和风鉴权失败（HTTP 401）$suffix',
            '核对 API Key 是否有效、且已绑定该 Host 所属账号');
      case HttpStatus.forbidden:
      case HttpStatus.paymentRequired:
        if (_isSecurityRestriction(detail)) {
          return _WeatherFail(
            WeatherErr.unauthorized,
            '和风安全限制拦截（HTTP $status）$suffix',
            'Key 与 Host 本身有效；请求被账号控制台的安全设置拦下'
                '（IP 白名单/访问限制）。请到和风控制台检查安全设置，'
                '或改用经纬度/预设城市绕开被拦的接口',
          );
        }
        if (_isHostProblem(detail)) return _hostInvalid(detail);
        return _WeatherFail(WeatherErr.unauthorized,
            '和风鉴权失败（HTTP $status）$suffix',
            '核对 Key 绑定与额度、接口权限；若提示 Invalid Host，须改用账号专属 Host');
      case HttpStatus.notFound:
        if (_isHostProblem(detail)) return _hostInvalid(detail);
        return _WeatherFail(WeatherErr.cityNotFound,
            '该地点无天气数据（HTTP 404）$suffix', '检查城市名写法，或改用经纬度查询');
      default:
        return _WeatherFail(WeatherErr.network,
            '和风返回 HTTP $status$suffix', '稍后重试，或检查网络连接');
    }
  }

  /// Host / 服务不通类真因：和风文案含 `Invalid Host`、「服务不可访问」等特征。
  bool _isHostProblem(String detail) {
    final d = detail.toLowerCase();
    return d.contains('invalid host') ||
        d.contains('服务不可访问') ||
        d.contains('not accessible') ||
        d.contains('service not found') ||
        d.contains('host not');
  }

  /// 安全限制类真因：控制台安全设置（IP 白名单/访问限制）拦截，Key 本身有效。
  bool _isSecurityRestriction(String detail) {
    final d = detail.toLowerCase();
    return d.contains('security restriction') || d.contains('安全限制');
  }

  /// Host 无效 / 服务未开通：独立错误码，便于 Agent 走「去设置改 Host」自愈。
  _WeatherFail _hostInvalid(String detail) => _WeatherFail(
        WeatherErr.hostInvalid,
        '和风 API Host 无效或未开通该服务${detail.isEmpty ? '' : '：$detail'}',
        '在 App 设置页核对账号专属 API Host（控制台「项目管理」复制，形如 '
        'xxxx.re.qweatherapi.com）；Key 须与该 Host 属同一账号绑定，'
        '且该账号已开通对应 API 权限。',
      );

  /// 错误体里的可读原因：JSON:API 形态 `error.title/detail`，或旧版 `message`。
  String _errorDetailOf(Map<String, Object?> body) {
    final err = body['error'];
    if (err is Map) {
      final title = err['title']?.toString() ?? '';
      final detail = err['detail']?.toString() ?? '';
      final joined = <String>[title, detail]
          .where((s) => s.trim().isNotEmpty)
          .join(' · ');
      if (joined.isNotEmpty) return joined;
    }
    final msg = body['message']?.toString() ?? '';
    if (msg.trim().isNotEmpty) return msg;
    final code = body['code']?.toString() ?? '';
    return code.isEmpty ? '' : 'code=$code';
  }

  /// **HTTP 200 内的业务码拦截**：和风鉴权失败/欠费/无数据时状态码常仍为 200，
  /// 真实状态藏在 Body `code`——只信 HTTP 码会拿着 `code:"401"` 去取 now → 空指针。
  Map<String, Object?> _checkBody(Map<String, Object?> body) {
    // JSON:API 错误体（HTTP 200 也可能带 `error` 段）：真因在 body 里，按同一张
    // 翻译表归并（HTTP 状态取 `error.status`）。
    final err = body['error'];
    if (err is Map) {
      final status = int.tryParse(err['status']?.toString() ?? '') ?? 400;
      throw _failFromHttp(status, body);
    }
    final code = body['code']?.toString();
    if (code == null || code == '200') return body;
    switch (code) {
      case '401':
      case '402':
      case '403':
        throw const _WeatherFail(WeatherErr.unauthorized,
            '和风鉴权失败：Key 无效、额度透支、Host 错配或无接口权限',
            '核对 Key 绑定与额度；若为 403 Invalid Host，自 2024 起须改用账号专属'
            'API Host（设置页 qweather_host，形如 xxxx.re.qweatherapi.com）');
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
