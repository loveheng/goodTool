/// 地理 LBS 用户端口（人机同源）：地图页功能面板直接消费的高德能力。
///
/// 与 MCP 工具面（`lib/tools/geo_tool.dart`）**并列共享同一内核**：
/// 同一 `GeoHttpProvider` 端口、同一套 REST 路径与解析口径、同一 Key 懒读机制；
/// 差异只在出口——本端口吐**类型化视图**（UI 直接吃，禁 JSON 信封，R2），
/// MCP 侧吐文本信封（给 LLM）。
library;

import '../geo/coord_convert.dart';
import '../mcp/geo_provider.dart';

/// 地点视图（地理编码 / POI 检索结果）。
class PlaceView {
  const PlaceView({
    required this.name,
    required this.lat,
    required this.lng,
    this.id,
    this.address,
    this.district,
  });

  final String? id;
  final String name;
  final String? address;

  /// 省/市/区拼接（有则展示）。
  final String? district;

  /// GCJ-02 坐标（高德返回即 GCJ-02；画布 Marker 直接可用）。
  final double lat;
  final double lng;

  /// 坐标展示串（6 位小数，对齐 `GeoPointView.formatted` 口径）。
  String get formatted => '${lat.toStringAsFixed(6)}, ${lng.toStringAsFixed(6)}';
}

/// 路线步骤视图（instruction + 可选折线，供画布叠加）。
class RouteStepView {
  const RouteStepView({
    required this.instruction,
    this.distanceMeters,
    this.durationSec,
    this.polyline = const <LatLng>[],
    this.orientation,
  });

  final String instruction;
  final double? distanceMeters;
  final double? durationSec;

  /// 步骤折线（GCJ-02 点序列；高德 step.polyline 解析，画布 Polyline 叠加用）。
  final List<LatLng> polyline;

  /// 高德 `step.orientation` 原样（中文绝对方位，如「北」「东南」；
  /// transit 段常缺）。解析成角度经 `route_guidance.absoluteBearingOf`。
  final String? orientation;
}

/// 路线规划结果视图。
class RouteView {
  const RouteView({
    required this.ok,
    this.mode,
    this.distanceMeters,
    this.durationSec,
    this.taxiCost,
    this.steps = const <RouteStepView>[],
    this.errorCode,
    this.message,
  });

  final bool ok;

  /// `walking` | `bicycling` | `driving` | `transit`。
  final String? mode;
  final double? distanceMeters;
  final double? durationSec;
  final double? taxiCost;
  final List<RouteStepView> steps;

  final String? errorCode;
  final String? message;

  /// 耗时展示串（秒 → 分）。
  String get durationText {
    final s = durationSec;
    if (s == null) return '';
    final min = (s / 60).round();
    return min >= 60 ? '${(min / 60).floor()}小时${min % 60}分' : '$min分钟';
  }

  /// 距离展示串（米 → 千米自适应，对齐 [GeoView.distanceText] 口径）。
  String get distanceText {
    final m = distanceMeters;
    if (m == null) return '';
    if (m < 1000) return '${m.toStringAsFixed(0)} m';
    return '${(m / 1000).toStringAsFixed(1)} km';
  }
}

/// 搜索结果视图（地理编码 + POI 双源合并）。
class GeoSearchView {
  const GeoSearchView({
    required this.ok,
    this.places = const <PlaceView>[],
    this.warnings = const <String>[],
    this.errorCode,
    this.message,
  });

  final bool ok;

  /// 合并结果（地理编码命中在前，POI 在后）。
  final List<PlaceView> places;

  /// 单源失败但另一源成功时的告警（不静默吞错）。
  final List<String> warnings;

  final String? errorCode;
  final String? message;
}

/// 简单经纬度对（GCJ-02；与画布 `flutter_map`/latlong2 的 LatLng 解耦，保持本层无 Flutter 依赖）。
class LatLng {
  const LatLng(this.lat, this.lng);
  final double lat;
  final double lng;
}

/// 地图页 LBS 端口：搜索选点 / 四模态路径规划。
///
/// 入参坐标默认 GCJ-02（地图画布点击即 GCJ-02；收藏点带 coordSystem 声明），
/// 请求高德前统一归一化——与 MCP `geo_route` 同口径。
class GeoLbsPort {
  GeoLbsPort({required this.http});

  final GeoHttpProvider http;

  /// 搜索地点：地理编码（地址→坐标）与 POI 关键字检索**双源合并**。
  ///
  /// 双源都失败 → 失败视图（带首源机器码）；单源失败 → 成功 + warnings（不静默）。
  Future<GeoSearchView> searchPlaces(
    String keywords, {
    String? city,
    CoordSystem coordSystem = CoordSystem.gcj02,
    GeoPoint? near,
  }) async {
    final kw = keywords.trim();
    if (kw.isEmpty) {
      return const GeoSearchView(
        ok: false,
        errorCode: 'MISSING_ARGUMENT',
        message: '搜索词为空',
      );
    }
    final warnings = <String>[];
    final places = <PlaceView>[];
    Object? firstError;

    // 源 1：地理编码。
    try {
      final query = <String, String>{'address': kw};
      if (city != null && city.trim().isNotEmpty) query['city'] = city.trim();
      final body = await http.get('/v3/geocode/geo', query);
      final raw = body['geocodes'] is List ? body['geocodes'] as List : const [];
      for (final e in raw) {
        final m = e is Map ? e : null;
        final loc = _parseLoc(m?['location'] as String?);
        if (m == null || loc == null) continue;
        places.add(PlaceView(
          name: (m['formatted_address'] as String?) ?? kw,
          lat: loc.$1,
          lng: loc.$2,
          district: _districtOf(m),
        ));
      }
    } on GeoHttpException catch (e) {
      warnings.add('geocode: ${e.code}');
      firstError ??= e;
    }

    // 源 2：POI 关键字检索。
    try {
      final query = <String, String>{'keywords': kw, 'offset': '10'};
      if (city != null && city.trim().isNotEmpty) query['city'] = city.trim();
      if (near != null) {
        final g = CoordConvert.normalize(near, coordSystem, CoordSystem.gcj02);
        query['location'] = _locQuery(g);
      }
      final body = await http.get('/v3/place/text', query);
      final raw = body['pois'] is List ? body['pois'] as List : const [];
      for (final e in raw) {
        final m = e is Map ? e : null;
        final loc = _parseLoc(m?['location'] as String?);
        if (m == null || loc == null) continue;
        places.add(PlaceView(
          id: m['id'] as String?,
          name: (m['name'] as String?) ?? kw,
          lat: loc.$1,
          lng: loc.$2,
          address: m['address'] as String?,
          district: _districtOf(m),
        ));
      }
    } on GeoHttpException catch (e) {
      warnings.add('poi: ${e.code}');
      firstError ??= e;
    }

    if (places.isEmpty) {
      final e = firstError;
      return GeoSearchView(
        ok: false,
        errorCode: e is GeoHttpException ? e.code : 'NO_RESULT',
        message: e is GeoHttpException ? e.message : '未找到匹配地点',
      );
    }
    return GeoSearchView(ok: true, places: places, warnings: warnings);
  }

  /// 四模态路径规划（与 MCP `geo_route` 同路径/同解析口径，另解析步骤折线）。
  ///
  /// [mode] ∈ `walking` / `bicycling` / `driving` / `transit`；`transit` 时
  /// [city] 必填（高德强制，缺省不自动推导——UI 面板让用户显式选城市）。
  Future<RouteView> route({
    required GeoPoint from,
    required GeoPoint to,
    required String mode,
    String? city,
    CoordSystem coordSystem = CoordSystem.gcj02,
  }) async {
    if (mode != 'walking' && mode != 'bicycling' && mode != 'driving' && mode != 'transit') {
      return RouteView(
        ok: false,
        errorCode: 'INVALID_ARGUMENT',
        message: '未知出行方式：$mode',
      );
    }
    if (mode == 'transit' && (city == null || city.trim().isEmpty)) {
      return const RouteView(
        ok: false,
        errorCode: 'CITY_REQUIRED',
        message: '公交规划须指定城市',
      );
    }
    final gFrom = CoordConvert.normalize(from, coordSystem, CoordSystem.gcj02);
    final gTo = CoordConvert.normalize(to, coordSystem, CoordSystem.gcj02);
    final path = switch (mode) {
      'walking' => '/v3/direction/walking',
      'bicycling' => '/v3/direction/bicycling',
      'transit' => '/v3/direction/transit/integrated',
      _ => '/v3/direction/driving',
    };
    final query = <String, String>{
      'origin': _locQuery(gFrom),
      'destination': _locQuery(gTo),
    };
    if (mode == 'transit') query['city'] = city!.trim();

    try {
      final body = await http.get(path, query);
      return _parseRoute(body, mode);
    } on GeoHttpException catch (e) {
      return RouteView(ok: false, mode: mode, errorCode: e.code, message: e.message);
    } on FormatException catch (e) {
      return RouteView(
        ok: false,
        mode: mode,
        errorCode: 'AMAP_PARSE_ERROR',
        message: e.message,
      );
    }
  }

  // -------------------------------------------------------------------------
  // 解析（口径对齐 geo_tool.dart `_parseRouteBody`；另带步骤折线）
  // -------------------------------------------------------------------------

  RouteView _parseRoute(Map<String, Object?> body, String mode) {
    final route = body['route'] is Map
        ? body['route'] as Map
        : throw const FormatException('缺少 route 字段');
    final paths = route['paths'] is List ? route['paths'] as List : const [];
    final transits = route['transits'] is List ? route['transits'] as List : const [];
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
    final steps = <RouteStepView>[];
    for (final s in rawSteps) {
      if (s is! Map) continue;
      steps.add(RouteStepView(
        instruction: (s['instruction'] as String?) ?? '',
        distanceMeters: _num(s['distance']),
        durationSec: _num(s['duration']),
        polyline: _parsePolyline(s['polyline'] as String?),
        orientation: (s['orientation'] as String?)?.trim(),
      ));
    }

    final taxiCost = _num(route['taxi_cost']) ?? _num(host['cost']);
    return RouteView(
      ok: true,
      mode: mode,
      distanceMeters: distanceMeters,
      durationSec: durationSec,
      taxiCost: taxiCost,
      steps: steps,
    );
  }

  /// `"lng,lat;lng,lat"` → 点序列（GCJ-02）。
  static List<LatLng> _parsePolyline(String? raw) {
    if (raw == null || raw.isEmpty) return const <LatLng>[];
    final pts = <LatLng>[];
    for (final pair in raw.split(';')) {
      final loc = _parseLoc(pair);
      if (loc != null) pts.add(LatLng(loc.$1, loc.$2));
    }
    return pts;
  }

  static (double, double)? _parseLoc(String? raw) {
    if (raw == null) return null;
    final parts = raw.split(',');
    if (parts.length != 2) return null;
    final lng = double.tryParse(parts[0].trim());
    final lat = double.tryParse(parts[1].trim());
    if (lng == null || lat == null) return null;
    return (lat, lng);
  }

  static String? _districtOf(Map m) {
    final province = m['province'];
    final city = m['city'];
    final district = m['district'];
    final parts = <String>[
      if (province is String && province.isNotEmpty) province,
      if (city is String && city.isNotEmpty && city != province) city,
      if (district is String && district.isNotEmpty) district,
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  static String _locQuery(GeoPoint p) =>
      '${p.lng.toStringAsFixed(6)},${p.lat.toStringAsFixed(6)}';

  static double? _num(Object? v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }
}
