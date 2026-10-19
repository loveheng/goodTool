// geo 领域网关适配层（S4）：把 lib/geo 纯 Dart 内核 + 注入端口包成 1 个 MCP 工具，
// 注册 product/geo.md 定义的 8 个原子动作——action 名原样沿用能力文档，不改名、不自造（G1）。
//
// 可见性（§3.3 G2）：仅公开 buildGeoTool()；具体子操作以 `_GeoXxxSub` 私有于本文件。
// 依赖性（arch-guard R1/R4）：geo.md「档位：均为 R」⇒ 全 R 档 —— 本文件不 import
// command_gateway.dart、不出现 `.dispatch(` / `.admits(`；所有 IO 经 LocationSensorProvider
// / GeoHttpProvider 注入，无 dart:io / Flutter UI，删 UI 亦可跑。
// GeoHttpProvider 内部 key 由实现从设置注入；唯 v3/staticmap 需拼 URL 而非发 JSON 请求，
// 故 web key/secret 以**静态配置**随 buildGeoTool 注入（不给 LLM 露出 key 入参）。
library;

import 'dart:convert';

import '../geo/coord_convert.dart';
import '../geo/static_map_url.dart';
import '../mcp/category_tool_face.dart';
import '../mcp/geo_provider.dart';

/// 合法的路径规划模式（高德四模态，超出即 INVALID_ARGUMENT，不静默兜底 driving）。
const Set<String> _routeModes = {'driving', 'walking', 'bicycling', 'transit'};

/// 公开入口：构建 `geo` 领域网关，注册 8 个子操作。
///
/// 全部 R 档（geo.md 档位表均为 R），[CategoryTool.commandGateway] 传 null
/// ——[CategoryTool.call] 仅 W 档才触达网关，R 档物理不可穿透（fail-closed）。
///
/// [sensor] 设备定位/磁力计端口；[http] 高德 Web 服务端口；
/// [amapWebKey]/[amapSecret] 静态图 URL 拼装所需配置（成像签名用，无则不出图）。
CategoryTool buildGeoTool(
  LocationSensorProvider sensor,
  GeoHttpProvider http, {
  String amapWebKey = '',
  String? amapSecret,
}) {
  final cat = CategoryTool(
    'geo',
    '地理与地图：当前定位 / 正逆地理编码 / POI 检索 / 多模态路径规划 / 静态图 / 指南针 / 测距。'
    '入参坐标可用 coordSystem 声明 WGS84|GCJ02（GPS 原生默认 WGS84），内核在调用高德前统一归一化到 GCJ-02。',
    null,
  );
  cat.register(_GeoCurrentSub(sensor));
  cat.register(_GeoCompassSub(sensor));
  cat.register(_GeoDistanceSub(http));
  cat.register(_GeoGeocodeSub(http));
  cat.register(_GeoReverseSub(http));
  cat.register(_GeoSearchPoiSub(http));
  cat.register(_GeoRouteSub(http));
  cat.register(_GeoStaticMapSub(amapWebKey, amapSecret));
  return cat;
}

// ---------------------------------------------------------------------------
// 出参与错误口径
// ---------------------------------------------------------------------------

/// 单条 text content（JSON）：Agent 可直接解析复用。
SubActionResult _jsonSuccess(Map<String, Object?> payload) =>
    SubActionResult.success([
      {'type': 'text', 'text': jsonEncode(payload)}
    ]);

/// 结构化错误：吐**裸 machine code**，`geo.<action>:` 前缀由派发层注入（G1/G5）。
SubActionResult _err(String code, String message) =>
    SubActionResult.structuredError(code, message, <String, Object?>{
      'code': code,
      'message': message,
    });

// ---------------------------------------------------------------------------
// 入参宽容解析（G5）：不可解析一律返回 null → 转带 code 的 error，**禁取默认值兜底**
// ---------------------------------------------------------------------------

/// 数值（高德偶以字符串形式返回 duration/distance）。
num? _num(Object? v) => v is num ? v : (v is String ? num.tryParse(v) : null);

/// `{lat, lng}` 对象 → 坐标点。
GeoPoint? _parsePoint(Object? val) {
  if (val is! Map) return null;
  final lat = parseDouble(val['lat']);
  final lng = parseDouble(val['lng']);
  if (lat == null || lng == null) return null;
  return GeoPoint(lat, lng);
}

/// 坐标系名 → 枚举；GPS 原生（设备/LLM 常见）默认 WGS-84。
CoordSystem _systemOf(Object? val) {
  final s = val is String ? val.trim().toUpperCase() : '';
  if (s == 'GCJ02') return CoordSystem.gcj02;
  if (s == 'BD09') return CoordSystem.bd09;
  return CoordSystem.wgs84;
}

String _nameOf(CoordSystem s) => switch (s) {
      CoordSystem.wgs84 => 'WGS84',
      CoordSystem.gcj02 => 'GCJ02',
      CoordSystem.bd09 => 'BD09',
    };

/// 高德 location 串 `"lng,lat"` → 坐标点。
GeoPoint? _parseLocationString(Object? val) {
  if (val is! String) return null;
  final parts = val.split(',');
  if (parts.length < 2) return null;
  final lng = double.tryParse(parts[0]);
  final lat = double.tryParse(parts[1]);
  if (lng == null || lat == null) return null;
  return GeoPoint(lat, lng);
}

/// 坐标 → 高德 `location`/`origin`/`destination` 查询串（统一 `lng,lat`）。
String _locQuery(GeoPoint p) =>
    '${p.lng.toStringAsFixed(6)},${p.lat.toStringAsFixed(6)}';

// ---------------------------------------------------------------------------
// 高德 REST 统一调用：异常/失败状态/结构漂移 → 带 code 的 error（不吞、不上抛）
// ---------------------------------------------------------------------------

Future<SubActionResult> _amapGet(
  GeoHttpProvider http,
  String path,
  Map<String, String> query,
  Map<String, Object?> Function(Map<String, Object?> body) parse,
) async {
  Map<String, Object?> body;
  try {
    body = await http.get(path, query);
  } on GeoHttpException catch (e) {
    // ERR_AMAP_KEY_MISSING / ERR_AMAP_API：机器码透出，引导 UI 弹配置卡（不闪退）。
    return _err(e.code, e.message);
  } on Exception catch (e) {
    return _err('AMAP_HTTP_ERROR', e.toString());
  }

  final status = body['status'];
  if (status != null && status.toString() != '1') {
    final info = body['info']?.toString() ?? '高德 Web 服务返回失败状态';
    final infocode = body['infocode']?.toString();
    return _err(
      infocode != null && infocode.isNotEmpty ? infocode : 'AMAP_API_ERROR',
      info,
    );
  }

  Map<String, Object?> payload;
  try {
    payload = parse(body);
  } on FormatException catch (e) {
    return _err('AMAP_PARSE_ERROR', '高德响应结构不符合预期：${e.message}');
  }
  return _jsonSuccess(<String, Object?>{'success': true, ...payload});
}

// ---------------------------------------------------------------------------
// geo_current：设备当前绝对坐标
// ---------------------------------------------------------------------------

class _GeoCurrentSub extends SubAction {
  _GeoCurrentSub(this._sensor);

  final LocationSensorProvider _sensor;

  @override
  String get name => 'geo_current';

  @override
  String get description =>
      '获取设备当前绝对坐标（经纬度 + 水平精度 + 时间戳），可用 coordSystem 指定输出坐标系'
      '（缺省按传感器原生系输出）。缺定位权限或无硬件返回 PERMISSION_DENIED，引导回 App 授权。';

  @override
  String get paramSignature =>
      'geo_current(coordSystem?: "WGS84"|"GCJ02"|"BD09") [全可选]';

  @override
  Future<SubActionResult> execute(Map<String, Object?> params) async {
    final reading = await _sensor.current();
    if (reading == null) {
      return _err('PERMISSION_DENIED', '无定位权限或定位硬件不可用');
    }
    final from = _systemOf(reading.coordSystem);
    // 未显式指定目标系时按传感器原生系原样输出，避免多余一次数值往返。
    final requested = params['coordSystem'] is String
        ? _systemOf(params['coordSystem'])
        : from;
    final p = CoordConvert.normalize(
        GeoPoint(reading.lat, reading.lng), from, requested);
    final payload = <String, Object?>{
      'success': true,
      'lat': p.lat,
      'lng': p.lng,
      'accuracy': reading.accuracy,
      'coordSystem': _nameOf(requested),
      'timestamp': reading.timestamp,
    };
    if (reading.altitude != null) payload['altitude'] = reading.altitude;
    return _jsonSuccess(payload);
  }
}

// ---------------------------------------------------------------------------
// geo_compass：磁力计方位角与八方位
// ---------------------------------------------------------------------------

class _GeoCompassSub extends SubAction {
  _GeoCompassSub(this._sensor);

  final LocationSensorProvider _sensor;

  @override
  String get name => 'geo_compass';

  @override
  String get description =>
      '获取磁力计航向角（0°~360°，正北为 0，顺时针）与八方位中文名（正北/东北/…）。'
      '无磁力计硬件返回 PERMISSION_DENIED。';

  @override
  String get paramSignature => 'geo_compass() [无入参]';

  @override
  Future<SubActionResult> execute(Map<String, Object?> params) async {
    final reading = await _sensor.compass();
    if (reading == null) {
      return _err('PERMISSION_DENIED', '无磁力计权限或传感器不可用');
    }
    return _jsonSuccess(<String, Object?>{
      'success': true,
      'heading': reading.heading,
      'direction': compassDirection(reading.heading),
      'accuracy': reading.accuracy,
    });
  }
}

// ---------------------------------------------------------------------------
// geo_distance：直线 / 道路测距
// ---------------------------------------------------------------------------

class _GeoDistanceSub extends SubAction {
  _GeoDistanceSub(this._http);

  final GeoHttpProvider _http;

  @override
  String get name => 'geo_distance';

  @override
  String get description =>
      '两点测距。mode=straight 纯 Haversine 球面直线距离（本地纯算，**不依赖网络与 Key**）；'
      'mode=road 走高德驾车距离与耗时（需 Key，并与 geo_route 同口径）。'
      '时常配合 geo_static_map 出图、math_utility.calc_eval 算打车费用。';

  @override
  String get paramSignature =>
      'geo_distance(from: {lat,lng}, to: {lat,lng}, mode?: "straight"|"road", '
      'coordSystem?: "WGS84"|"GCJ02") [必填: from, to]';

  @override
  Future<SubActionResult> execute(Map<String, Object?> params) async {
    final from = _parsePoint(params['from']);
    final to = _parsePoint(params['to']);
    if (from == null || to == null) {
      return _err('MISSING_ARGUMENT',
          '缺少必填参数 from / to（形如 {"lat": 39.9, "lng": 116.4}）');
    }
    final mode = params['mode'] is String ? params['mode'] as String : 'straight';
    if (mode != 'straight' && mode != 'road') {
      return _err('INVALID_ARGUMENT',
          '未知 mode="$mode"（仅支持 straight | road）');
    }

    if (mode == 'straight') {
      // 球面大圆距离：与坐标系口径无关（GCJ 偏移同量级于 algorithm 精度外）。
      return _jsonSuccess(<String, Object?>{
        'success': true,
        'meters': CoordConvert.haversineMeters(from, to),
        'mode': 'straight',
      });
    }

    // road：归一化到 GCJ-02 后取驾车路径距离（与高德 Web 服务强绑定，缺 Key 必失败）。
    final fromSys = _systemOf(params['coordSystem']);
    final gFrom = CoordConvert.normalize(from, fromSys, CoordSystem.gcj02);
    final gTo = CoordConvert.normalize(to, fromSys, CoordSystem.gcj02);
    return _amapGet(
      _http,
      '/v3/direction/driving',
      <String, String>{'origin': _locQuery(gFrom), 'destination': _locQuery(gTo)},
      (body) {
        final r = _parseRouteBody(body);
        if (r['distanceMeters'] == null) {
          throw const FormatException('驾车路径缺少 distance');
        }
        return <String, Object?>{
          'meters': r['distanceMeters'],
          'mode': 'road',
          if (r['durationSec'] != null) 'durationSec': r['durationSec'],
        };
      },
    );
  }
}

// ---------------------------------------------------------------------------
// geo_geocode：地址 → 坐标
// ---------------------------------------------------------------------------

class _GeoGeocodeSub extends SubAction {
  _GeoGeocodeSub(this._http);

  final GeoHttpProvider _http;

  @override
  String get name => 'geo_geocode';

  @override
  String get description =>
      '正向地理编码：地名/结构化地址 → 经纬度坐标（**GCJ-02**）与所属省市区。'
      '传 city 可限定城市提升命中率；结果经纬度可直接喂给 geo_route / geo_static_map 的起终点。';

  @override
  String get paramSignature =>
      'geo_geocode(address: string, city?: string) [必填: address]';

  @override
  Future<SubActionResult> execute(Map<String, Object?> params) async {
    final address = params['address'];
    if (address is! String || address.trim().isEmpty) {
      return _err('MISSING_ARGUMENT', '缺少必填参数 address（地址/地名字符串）');
    }
    final city = params['city'];
    final query = <String, String>{'address': address.trim()};
    if (city is String && city.trim().isNotEmpty) query['city'] = city.trim();

    return _amapGet(_http, '/v3/geocode/geo', query, (body) {
      final raw = body['geocodes'] is List
          ? body['geocodes'] as List
          : const <Object?>[];
      final results = raw.map((e) {
        final m = e is Map ? e : null;
        if (m == null) return null;
        final loc = _parseLocationString(m['location']);
        return <String, Object?>{
          if (loc != null) 'lat': loc.lat,
          if (loc != null) 'lng': loc.lng,
          'formattedAddress': m['formatted_address'],
          'province': m['province'],
          'city': m['city'],
          'district': m['district'],
        };
      }).whereType<Map<String, Object?>>().toList();
      return <String, Object?>{'count': results.length, 'results': results};
    });
  }
}

// ---------------------------------------------------------------------------
// geo_reverse：坐标 → 详细地址
// ---------------------------------------------------------------------------

class _GeoReverseSub extends SubAction {
  _GeoReverseSub(this._http);

  final GeoHttpProvider _http;

  @override
  String get name => 'geo_reverse';

  @override
  String get description =>
      '逆向地理编码：经纬度 → 格式化地址、省市县镇行政区划与周边代表性 POI。'
      '入参 coordSystem 缺省按 GPS 原生 WGS-84 解释，内核自动归一化到 GCJ-02 再查高德。';

  @override
  String get paramSignature =>
      'geo_reverse(lat: number|string, lng: number|string, '
      'coordSystem?: "WGS84"|"GCJ02"|"BD09") [必填: lat, lng]';

  @override
  Future<SubActionResult> execute(Map<String, Object?> params) async {
    final lat = parseDouble(params['lat']);
    final lng = parseDouble(params['lng']);
    if (lat == null || lng == null) {
      return _err('MISSING_ARGUMENT',
          '缺少必填参数 lat / lng（数值或可解析数字串）');
    }
    final g = CoordConvert.normalize(
        GeoPoint(lat, lng), _systemOf(params['coordSystem']), CoordSystem.gcj02);

    return _amapGet(
      _http,
      '/v3/geocode/regeo',
      <String, String>{'location': _locQuery(g), 'extensions': 'all'},
      (body) {
        final regeo = body['regeocode'] is Map
            ? body['regeocode'] as Map
            : throw const FormatException('缺少 regeocode 字段');
        final comp = regeo['addressComponent'] is Map
            ? regeo['addressComponent'] as Map
            : const <Object?, Object?>{};
        final pois = regeo['pois'] is List ? regeo['pois'] as List : const [];
        final firstPoi = pois.isNotEmpty && pois.first is Map
            ? (pois.first as Map)['name']
            : null;
        return <String, Object?>{
          'formattedAddress': regeo['formatted_address'],
          'province': comp['province'],
          'city': comp['city'],
          'district': comp['district'],
          'town': comp['township'],
          'poiName': ?firstPoi,
        };
      },
    );
  }
}

// ---------------------------------------------------------------------------
// geo_search_poi：关键字 POI 检索
// ---------------------------------------------------------------------------

class _GeoSearchPoiSub extends SubAction {
  _GeoSearchPoiSub(this._http);

  final GeoHttpProvider _http;

  @override
  String get name => 'geo_search_poi';

  @override
  String get description =>
      '关键字 POI 检索（高德搜索服务）。传 city 限定城市、传 near 做周边检索（坐标按 coordSystem'
      ' 解释后归一化到 GCJ-02）。返回 POI 名称/类型/地址/经纬度，可直接作 geo_route 的终点输入。';

  @override
  String get paramSignature =>
      'geo_search_poi(keywords: string, city?: string, near?: {lat,lng}, '
      'coordSystem?: "WGS84"|"GCJ02"|"BD09", radius?: number) [必填: keywords]';

  @override
  Future<SubActionResult> execute(Map<String, Object?> params) async {
    final keywords = params['keywords'];
    if (keywords is! String || keywords.trim().isEmpty) {
      return _err('MISSING_ARGUMENT', '缺少必填参数 keywords（检索关键字）');
    }
    final city = params['city'];
    final near = _parsePoint(params['near']);
    final radius = parseInt(params['radius']);

    final query = <String, String>{'keywords': keywords.trim()};
    if (city is String && city.trim().isNotEmpty) query['city'] = city.trim();
    if (near != null) {
      final g = CoordConvert.normalize(
          near, _systemOf(params['coordSystem']), CoordSystem.gcj02);
      query['location'] = _locQuery(g);
    }
    if (radius != null && radius > 0) query['radius'] = '$radius';

    return _amapGet(_http, '/v3/place/text', query, (body) {
      final raw = body['pois'] is List ? body['pois'] as List : const <Object?>[];
      final pois = raw.map((e) {
        final m = e is Map ? e : null;
        if (m == null) return null;
        final loc = _parseLocationString(m['location']);
        return <String, Object?>{
          'id': m['id'],
          'name': m['name'],
          'type': m['type'],
          'address': m['address'],
          if (loc != null) 'lat': loc.lat,
          if (loc != null) 'lng': loc.lng,
          if (m['distance'] != null) 'distance': _num(m['distance']),
        };
      }).whereType<Map<String, Object?>>().toList();
      return <String, Object?>{'count': pois.length, 'pois': pois};
    });
  }
}

// ---------------------------------------------------------------------------
// geo_route：多模态路径规划
// ---------------------------------------------------------------------------

class _GeoRouteSub extends SubAction {
  _GeoRouteSub(this._http);

  final GeoHttpProvider _http;

  @override
  String get name => 'geo_route';

  @override
  String get description =>
      '多模态路径规划（driving 驾车 / walking 步行 / bicycling 骑行 / transit 公交），'
      '出总耗时、总距离、驾车打车费用与关键转向步骤。'
      '注意：mode=transit 时 city 必填（高德强制要求，缺则返回 MISSING_ARGUMENT）。'
      '算打车/油费或 ETA 常配合 math_utility.calc_eval，出图配合 geo_static_map。';

  @override
  String get paramSignature =>
      'geo_route(from: {lat,lng}, to: {lat,lng}, mode: "driving"|"walking"|"bicycling"|"transit", '
      'strategy?: number, city?: string, coordSystem?: "WGS84"|"GCJ02"|"BD09") '
      '[必填: from, to, mode]';

  @override
  Future<SubActionResult> execute(Map<String, Object?> params) async {
    final from = _parsePoint(params['from']);
    final to = _parsePoint(params['to']);
    if (from == null || to == null) {
      return _err('MISSING_ARGUMENT',
          '缺少必填参数 from / to（形如 {"lat": 39.9, "lng": 116.4}）');
    }
    final mode = params['mode'];
    if (mode is! String || !_routeModes.contains(mode)) {
      return _err('INVALID_ARGUMENT',
          '缺少或非法参数 mode（仅支持 ${_routeModes.join(' / ')}）');
    }
    final city = params['city'];
    if (mode == 'transit' && (city is! String || city.trim().isEmpty)) {
      // 已知限制：city 自动逆推（由起点反查）暂未纳入 S4，显式报错并给出自愈指引。
      return _err('MISSING_ARGUMENT',
          'mode=transit 时 city 必填（高德公交换乘强制要求城市名）；'
          '可先以起点坐标调用 geo_reverse 取得 city 再规划');
    }

    final sys = _systemOf(params['coordSystem']);
    final gFrom = CoordConvert.normalize(from, sys, CoordSystem.gcj02);
    final gTo = CoordConvert.normalize(to, sys, CoordSystem.gcj02);
    final strategy = parseInt(params['strategy']);

    final query = <String, String>{
      'origin': _locQuery(gFrom),
      'destination': _locQuery(gTo),
    };
    if (strategy != null) query['strategy'] = '$strategy';
    if (mode == 'transit') query['city'] = (city as String).trim();

    return _amapGet(_http, _directionPath(mode), query, (body) {
      final r = _parseRouteBody(body);
      return <String, Object?>{'mode': mode, ...r};
    });
  }
}

String _directionPath(String mode) => switch (mode) {
      'walking' => '/v3/direction/walking',
      'bicycling' => '/v3/direction/bicycling',
      'transit' => '/v3/direction/transit/integrated',
      _ => '/v3/direction/driving',
    };

/// 解析高德路径响应（driving/walking/bicycling 走 `route.paths`，transit 走 `route.transits`），
/// 统一出 `{distanceMeters, durationSec, steps[], taxiCost?}`。
///
/// 结构漂移抛 [FormatException]，由 [_amapGet] 转成 `AMAP_PARSE_ERROR`——**不以 0 / 空列表兜底**。
Map<String, Object?> _parseRouteBody(Map<String, Object?> body) {
  final route = body['route'] is Map
      ? body['route'] as Map
      : throw const FormatException('缺少 route 字段');
  final paths = route['paths'] is List ? route['paths'] as List : const [];
  final transits =
      route['transits'] is List ? route['transits'] as List : const [];
  final candidates = <Object?>[...paths, ...transits];
  if (candidates.isEmpty || candidates.first is! Map) {
    throw const FormatException('route 下无 paths / transits 段');
  }
  final host = candidates.first as Map;

  final distanceMeters = _num(host['distance']);
  final durationSec = _num(host['duration']);
  if (distanceMeters == null && durationSec == null) {
    throw const FormatException('路径段缺少 distance / duration');
  }

  final rawSteps = host['steps'] is List ? host['steps'] as List : const [];
  final steps = rawSteps.map((s) {
    if (s is! Map) return null;
    return <String, Object?>{
      'instruction': s['instruction'],
      'distance': _num(s['distance']),
      'duration': _num(s['duration']),
    };
  }).whereType<Map<String, Object?>>().toList();

  final taxiCost = route['taxi_cost'] ?? host['cost'];
  return <String, Object?>{
    'distanceMeters': distanceMeters,
    'durationSec': durationSec,
    'steps': steps,
    if (taxiCost != null) 'taxiCost': _num(taxiCost),
  };
}

// ---------------------------------------------------------------------------
// geo_static_map：静态图 URL（免 Native SDK 渲染）
// ---------------------------------------------------------------------------

class _GeoStaticMapSub extends SubAction {
  _GeoStaticMapSub(this._webKey, this._fallbackSecret);

  /// 静态图所需的 Web 服务 Key（**配置注入，不给 LLM 露出入参**）。
  final String _webKey;

  /// 设置里的数字签名密钥；单次调用可用 params.secret 覆盖。
  final String? _fallbackSecret;

  @override
  String get name => 'geo_static_map';

  @override
  String get description =>
      '生成高德静态地图切片 URL（轻量预览图，移动端免 Native 3D SDK 即可渲染），支持中心点/缩放/'
      '标记点/折线轨迹。入参坐标按 GCJ-02 解释（可由 coordSystem 声明来源，内核归一化）；'
      'paths 自动 RDP 抽稀至 ≤80 点防 URL 超 2048（HTTP 414）；'
      '传 autoFit 或 bounds 时按点集逆算最佳 zoom，无需手工猜缩放。'
      '常作为 geo_route / geo_search_poi 结果的可视化输出。';

  @override
  String get paramSignature =>
      'geo_static_map(center?: {lat,lng}, zoom?: int, size?: string, markers?: [{lat,lng,size?,color?,label?}], '
      'paths?: [{points:[{lat,lng}], weight?, color?, transparency?}], autoFit?: bool, '
      'bounds?: {minLat,minLng,maxLat,maxLng}, coordSystem?: "WGS84"|"GCJ02", secret?: string) [全可选]';

  @override
  Future<SubActionResult> execute(Map<String, Object?> params) async {
    if (_webKey.trim().isEmpty) {
      // 不同于其它 geo 动作：URL 拼装不经过 GeoHttpProvider，故 Key 缺失须在此显式拦。
      return _err('ERR_AMAP_KEY_MISSING',
          '高德 Web 服务 Key 未配置（静态图出图需 amap_web_key）');
    }
    final zoom = parseInt(params['zoom']);
    final size = _parseSize(params['size']);
    final markers = _parseMarkers(params['markers']);
    final paths = _parsePaths(params['paths']);
    final autoFit = parseBool(params['autoFit']) ?? false;
    final bounds = _parseBounds(params['bounds']);
    final secret = params['secret'] is String
        ? params['secret'] as String
        : _fallbackSecret;
    final coordSystem = _systemOf(params['coordSystem']);

    final url = AmapStaticMap.buildUrl(
      key: _webKey,
      center: _parsePoint(params['center']),
      zoom: zoom,
      size: size,
      markers: markers,
      paths: paths,
      coordSystem: coordSystem,
      secret: secret,
      autoFit: autoFit,
      bounds: bounds,
    );
    return _jsonSuccess(<String, Object?>{'success': true, 'url': url});
  }

  /// 静态图尺寸 `"width*height"` → 元组。
  (int, int)? _parseSize(Object? val) {
    if (val is! String) return null;
    final parts = val.split('*');
    if (parts.length != 2) return null;
    final w = int.tryParse(parts[0].trim());
    final h = int.tryParse(parts[1].trim());
    if (w == null || h == null) return null;
    return (w, h);
  }

  List<StaticMapMarker> _parseMarkers(Object? val) {
    final out = <StaticMapMarker>[];
    if (val is! List) return out;
    for (final raw in val) {
      if (raw is! Map) continue;
      // 既接受 {point:{lat,lng},...}，也接受平铺 {lat,lng,...}。
      final p = _parsePoint(raw['point'] ?? raw);
      if (p == null) continue;
      out.add(StaticMapMarker(
        point: p,
        size: _parseMarkerSize(raw['size']),
        color: _parseColor(raw['color']) ?? 0xFF0000,
        label: raw['label'] is String ? raw['label'] as String : null,
      ));
    }
    return out;
  }

  MarkerSize _parseMarkerSize(Object? val) {
    if (val is! String) return MarkerSize.mid;
    return switch (val.trim().toLowerCase()) {
      'tiny' => MarkerSize.tiny,
      'small' => MarkerSize.small,
      'large' => MarkerSize.large,
      _ => MarkerSize.mid,
    };
  }

  List<StaticMapPath> _parsePaths(Object? val) {
    final out = <StaticMapPath>[];
    if (val is! List) return out;
    for (final raw in val) {
      if (raw is! Map) continue;
      final ptsRaw = raw['points'] is List ? raw['points'] as List : const [];
      final pts = ptsRaw
          .map(_parsePoint)
          .whereType<GeoPoint>()
          .toList(growable: false);
      if (pts.isEmpty) continue;
      out.add(StaticMapPath(
        pts,
        weight: parseInt(raw['weight']) ?? 5,
        color: _parseColor(raw['color']) ?? 0x0000FF,
        transparency: parseDouble(raw['transparency']) ?? 1.0,
      ));
    }
    return out;
  }

  LatLngBounds? _parseBounds(Object? val) {
    if (val is! Map) return null;
    final minLat = parseDouble(val['minLat']);
    final minLng = parseDouble(val['minLng']);
    final maxLat = parseDouble(val['maxLat']);
    final maxLng = parseDouble(val['maxLng']);
    if (minLat == null || minLng == null || maxLat == null || maxLng == null) {
      return null;
    }
    return LatLngBounds(
      minLat: minLat,
      minLng: minLng,
      maxLat: maxLat,
      maxLng: maxLng,
    );
  }

  /// 颜色：接受 int 或 `'0xFF0000'` / `'#FF0000'` 字符串。
  int? _parseColor(Object? val) {
    if (val is int) return val;
    if (val is! String) return null;
    final s = val.trim().toUpperCase().replaceFirst('#', '0X');
    final hex = s.startsWith('0X') ? s.substring(2) : s;
    if (hex.isEmpty || hex.length > 8) return null;
    return int.tryParse('0x$hex');
  }
}
