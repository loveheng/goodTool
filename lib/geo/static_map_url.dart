/// 高德 Static Map（静态地图）URL 构建器（纯 Dart，无 Flutter 依赖，无头可跑）。
///
/// 不引入 Native 3D 地图 SDK：移动端只需用普通 Image / CachedNetworkImage 渲染
/// 本构建器产出的 URL 即可看地图、看折线轨迹，包体积增加为 0，且规避 PlatformView
/// 黑屏与内存泄漏。
///
/// 关键约束与加固（对齐高德 Web 服务实战）：
/// - 高德静态图强制 GCJ-02 入参：入参可声明任意坐标系（[coordSystem]），内部自动归一化。
/// - **签名防篡改**：传入 [secret] 时按高德规范追加 `sig`（见 [amapSign]），避免
///   `INVALID_USER_SCODE`。
/// - **防截断（RDP 抽稀）**：折线轨迹强制经 RDP 抽稀并卡在 ≤[maxPathPoints] 点，杜绝
///   URL 超 2048 字符触发 HTTP 414。
/// - **自适应视口**：传 [autoFit]=true 或显式 [bounds] 时，内核自动逆算几何中心与最佳
///   `zoom`，无需 Agent 手工猜测缩放级别（arch-guard R4：纯字符串拼装，不碰网络与平台）。
library;

import 'dart:math';

import 'amap_sign.dart';
import 'coord_convert.dart';
import 'rdp.dart';

/// 静态图标记点尺寸（高德合法值）。
enum MarkerSize {
  /// 极小。
  tiny,

  /// 小。
  small,

  /// 中（默认）。
  mid,

  /// 大。
  large,
}

/// 静态图标记点。
class StaticMapMarker {
  const StaticMapMarker({
    required this.point,
    this.size = MarkerSize.mid,
    this.color = 0xFF0000,
    this.label,
  });

  /// 标记经纬度（按 [coordSystem] 解释）。
  final GeoPoint point;

  /// 图标尺寸。
  final MarkerSize size;

  /// 颜色（0xRRGGBB）。
  final int color;

  /// 单字符标签（A–Z）；为空则不显示标签。
  final String? label;
}

/// 静态图折线轨迹。
class StaticMapPath {
  const StaticMapPath(
    this.points, {
    this.weight = 5,
    this.color = 0x0000FF,
    this.transparency = 1.0,
  });

  /// 轨迹点序列（按 [coordSystem] 解释）。
  final List<GeoPoint> points;

  /// 线宽（1–10）。
  final int weight;

  /// 颜色（0xRRGGBB）。
  final int color;

  /// 透明度（0.0 全透明 ~ 1.0 不透明）。
  final double transparency;
}

/// 经纬度边界框（最小外接矩形）。
class LatLngBounds {
  const LatLngBounds({
    required this.minLat,
    required this.minLng,
    required this.maxLat,
    required this.maxLng,
  });

  final double minLat;
  final double minLng;
  final double maxLat;
  final double maxLng;
}

/// 高德静态地图 URL 构建器。
class AmapStaticMap {
  AmapStaticMap._();

  static const String _host = 'restapi.amap.com';
  static const String _path = '/v3/staticmap';
  static const int _defaultWidth = 400;
  static const int _defaultHeight = 300;

  /// 构建静态图 URI（自动按 [coordSystem] 归一化到 GCJ-02）。
  ///
  /// - [coordSystem] 声明 [center] / [markers] / [paths] 入参的坐标系，默认 GCJ-02。
  /// - [secret] 非空时按高德规范追加 `sig`（需配合 `amap_web_key` + `amap_secret`）。
  /// - [autoFit] 为 true 且未显式给 [center]/[bounds] 时，按 markers+paths 自动逆算
  ///   `zoom` 与中心；[bounds] 显式优先。
  /// - [rdpEpsilonMeters] / [maxPathPoints] 控制折线抽稀强度与硬上限（防 URL 超长）。
  static Uri buildUri({
    required String key,
    GeoPoint? center,
    int? zoom,
    (int, int)? size,
    int scale = 1,
    List<StaticMapMarker> markers = const [],
    List<StaticMapPath> paths = const [],
    bool traffic = false,
    CoordSystem coordSystem = CoordSystem.gcj02,
    String? secret,
    bool autoFit = false,
    LatLngBounds? bounds,
    double rdpEpsilonMeters = 10,
    int maxPathPoints = 80,
  }) {
    final width = size?.$1 ?? _defaultWidth;
    final height = size?.$2 ?? _defaultHeight;

    // 1) 计算自适应视口（bounds 显式 > autoFit 推断 > 入参）。
    GeoPoint? fitCenter;
    int? fitZoom;
    if (bounds != null) {
      final f =
          _fitViewport(bounds.minLat, bounds.minLng, bounds.maxLat, bounds.maxLng, width, height);
      fitCenter = GeoPoint(f.lat, f.lng);
      fitZoom = f.zoom;
    } else if (autoFit && (markers.isNotEmpty || paths.isNotEmpty)) {
      var minLat = double.infinity;
      var minLng = double.infinity;
      var maxLat = -double.infinity;
      var maxLng = -double.infinity;
      void acc(GeoPoint p) {
        final g = CoordConvert.normalize(p, coordSystem, CoordSystem.gcj02);
        minLat = min(minLat, g.lat);
        minLng = min(minLng, g.lng);
        maxLat = max(maxLat, g.lat);
        maxLng = max(maxLng, g.lng);
      }

      for (final m in markers) {
        acc(m.point);
      }
      for (final p in paths) {
        for (final pt in p.points) {
          acc(pt);
        }
      }
      if (minLat != double.infinity) {
        final f = _fitViewport(minLat, minLng, maxLat, maxLng, width, height);
        fitCenter = GeoPoint(f.lat, f.lng);
        fitZoom = f.zoom;
      }
    }

    final effCenter = fitCenter ?? center;
    final effZoom = fitZoom ?? zoom ?? 12;

    final params = <String, String>{};
    if (effCenter != null) {
      final c = CoordConvert.normalize(effCenter, coordSystem, CoordSystem.gcj02);
      params['location'] = '${_fmt(c.lng)},${_fmt(c.lat)}';
    }
    params['zoom'] = effZoom.toString();
    if (size != null) params['size'] = '${size.$1}*${size.$2}';
    params['scale'] = scale.toString();
    if (traffic) params['traffic'] = '1';
    if (markers.isNotEmpty) {
      params['markers'] = markers.map((m) {
        final p = CoordConvert.normalize(m.point, coordSystem, CoordSystem.gcj02);
        final color = _hex(m.color);
        final label = m.label != null ? ',${m.label}' : '';
        return '${m.size.name},$color$label:${_fmt(p.lng)},${_fmt(p.lat)}';
      }).join('|');
    }
    if (paths.isNotEmpty) {
      params['paths'] = paths.map((p) {
        final simplified = rdpSimplify(
          p.points,
          epsilonMeters: rdpEpsilonMeters,
          maxPoints: maxPathPoints,
        );
        final pts = simplified.map((pt) {
          final g = CoordConvert.normalize(pt, coordSystem, CoordSystem.gcj02);
          return '${_fmt(g.lng)},${_fmt(g.lat)}';
        }).join(';');
        final color = _hex(p.color);
        final transp = p.transparency.toStringAsFixed(1);
        return '${p.weight},$color,$transp,,:$pts';
      }).join('|');
    }
    params['key'] = key;

    // 2) 数字签名（高德 Web 服务校验）：基于全部参数（含 key）升序拼接 + secret。
    if (secret != null && secret.isNotEmpty) {
      params['sig'] = amapSign(params, secret);
    }

    return Uri.https(_host, _path, params);
  }

  /// 便捷出口：直接返回字符串 URL。
  static String buildUrl({
    required String key,
    GeoPoint? center,
    int? zoom,
    (int, int)? size,
    int scale = 1,
    List<StaticMapMarker> markers = const [],
    List<StaticMapPath> paths = const [],
    bool traffic = false,
    CoordSystem coordSystem = CoordSystem.gcj02,
    String? secret,
    bool autoFit = false,
    LatLngBounds? bounds,
    double rdpEpsilonMeters = 10,
    int maxPathPoints = 80,
  }) =>
      buildUri(
        key: key,
        center: center,
        zoom: zoom,
        size: size,
        scale: scale,
        markers: markers,
        paths: paths,
        traffic: traffic,
        coordSystem: coordSystem,
        secret: secret,
        autoFit: autoFit,
        bounds: bounds,
        rdpEpsilonMeters: rdpEpsilonMeters,
        maxPathPoints: maxPathPoints,
      ).toString();

  /// 由边界框逆算几何中心与最佳 zoom（Web 墨卡托，留 0.5 级边距，范围 3~17）。
  static ({double lat, double lng, int zoom}) _fitViewport(
    double minLat,
    double minLng,
    double maxLat,
    double maxLng,
    int width,
    int height,
  ) {
    const ln2 = 0.6931471805599453;
    final zLng = (maxLng - minLng) <= 0
        ? 17.0
        : log(width * 360 / (256 * (maxLng - minLng))) / ln2;
    final yMin = _mercY(minLat);
    final yMax = _mercY(maxLat);
    final zLat = (yMax - yMin).abs() <= 0
        ? 17.0
        : log(height * 2 * pi / (256 * (yMax - yMin).abs())) / ln2;
    final raw = min(zLng, zLat);
    final withMargin = (raw - 0.5).clamp(3.0, 17.0);
    return (
      lat: (minLat + maxLat) / 2,
      lng: (minLng + maxLng) / 2,
      zoom: withMargin.floor(),
    );
  }

  /// 纬度 → Web 墨卡托 Y（自然对数）。
  static double _mercY(double latDeg) {
    final lat = latDeg * pi / 180;
    return log(tan(pi / 4 + lat / 2));
  }

  /// 坐标格式化（6 位小数，满足高德精度）。
  static String _fmt(double v) => v.toStringAsFixed(6);

  /// 0xRRGGBB → '0xRRGGBB'（大写）。
  static String _hex(int color) {
    final s = color.toRadixString(16).padLeft(8, '0').toUpperCase();
    return '0x${s.substring(2)}';
  }
}
