library;

import '../geo/coord_convert.dart';

/// 坐标点视图（类型化；遥测轨渲染用）。
class GeoPointView {
  const GeoPointView({
    required this.label,
    required this.lat,
    required this.lng,
  });

  /// 坐标系标签（如 `WGS-84` / `GCJ-02` / `BD-09`）。
  final String label;

  final double lat;
  final double lng;

  /// 定点格式化（6 位小数 ≈ 0.1m 精度）。
  String get formatted => '${lat.toStringAsFixed(6)}, ${lng.toStringAsFixed(6)}';
}

/// 坐标换算 / 测距结果视图。
class GeoView {
  const GeoView({
    required this.ok,
    this.points = const <GeoPointView>[],
    this.distanceMeters,
    this.errorCode,
    this.message,
  });

  /// 是否成功。
  final bool ok;

  /// 三坐标系下的同一点（成功时非空）。
  final List<GeoPointView> points;

  /// 两点直线距离（米；测距时非空）。
  final double? distanceMeters;

  /// 机器码（失败时非空）。
  final String? errorCode;

  /// 人类可读说明。
  final String? message;

  /// 距离展示串（米 → 千米自适应）。
  String get distanceText {
    final meters = distanceMeters;
    if (meters == null) return '';
    if (meters < 1000) return '${meters.toStringAsFixed(1)} m';
    return '${(meters / 1000).toStringAsFixed(3)} km';
  }
}

/// 时空计算适配层：坐标纠偏与测距。
///
/// 纯 Dart 内核（`lib/geo/coord_convert.dart`）——**不需任何 Key、不需任何权限**，
/// 故沙盒页的这部分永远可用；设备定位另走 [GeoPort] 之外的 Provider 端口。
class GeoPort {
  const GeoPort();

  /// 校验经纬度范围；越界返回带机器码的失败（不静默兜底）。
  static bool _valid(double lat, double lng) =>
      lat >= -90 && lat <= 90 && lng >= -180 && lng <= 180;

  /// 把一个 WGS-84 坐标换算到三种坐标系。
  GeoView convertPoint(double lat, double lng) {
    if (!_valid(lat, lng)) {
      return const GeoView(
        ok: false,
        errorCode: 'INVALID_ARGUMENT',
        message: '经纬度越界（纬度 -90~90，经度 -180~180）',
      );
    }
    final source = GeoPoint(lat, lng);
    return GeoView(
      ok: true,
      points: <GeoPointView>[
        GeoPointView(label: 'WGS-84', lat: lat, lng: lng),
        GeoPointView(
          label: 'GCJ-02',
          lat: CoordConvert.wgs84ToGcj02(source).lat,
          lng: CoordConvert.wgs84ToGcj02(source).lng,
        ),
        GeoPointView(
          label: 'BD-09',
          lat: CoordConvert.wgs84ToBd09(source).lat,
          lng: CoordConvert.wgs84ToBd09(source).lng,
        ),
      ],
    );
  }

  /// 两点直线测距（米；坐标系无关）。
  GeoView distance(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    if (!_valid(lat1, lng1) || !_valid(lat2, lng2)) {
      return const GeoView(
        ok: false,
        errorCode: 'INVALID_ARGUMENT',
        message: '经纬度越界（纬度 -90~90，经度 -180~180）',
      );
    }
    final meters = CoordConvert.haversineMeters(
      GeoPoint(lat1, lng1),
      GeoPoint(lat2, lng2),
    );
    return GeoView(ok: true, distanceMeters: meters);
  }
}
