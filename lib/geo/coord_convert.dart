/// 坐标系与坐标转换内核（纯 Dart，无 Flutter 依赖，无头可跑）。
///
/// 覆盖：
/// - GPS 原生 **WGS-84** ↔ 高德 **GCJ-02（火星坐标）** ↔ 百度 **BD-09** 离线互转；
/// - 两点 **Haversine** 直线测距（米）。
///
/// 高德 Web 服务（检索/路线/静态图）强制 GCJ-02 入参；本内核在调用前统一归一化，
/// 杜绝百米级漂移（arch-guard R4：纯算法，不碰网络与平台）。
library;

import 'dart:math';

/// 经纬度点（纯数据载体）。
class GeoPoint {
  const GeoPoint(this.lat, this.lng);

  final double lat;
  final double lng;

  @override
  String toString() => 'GeoPoint(lat: $lat, lng: $lng)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GeoPoint &&
          lat == other.lat &&
          lng == other.lng;

  @override
  int get hashCode => lat.hashCode ^ lng.hashCode;
}

/// 地理坐标系枚举。
enum CoordSystem {
  /// GPS 原生（设备传感器直出）。
  wgs84,

  /// 高德 / 国测局火星坐标（高德 Web 服务强制入参）。
  gcj02,

  /// 百度坐标系。
  bd09,
}

/// 坐标转换异常（本地算法不应抛出；仅在校验不通过时用于显式阻断）。
class CoordConvertException implements Exception {
  const CoordConvertException(this.message);
  final String message;
  @override
  String toString() => 'CoordConvertException: $message';
}

/// 纯算法坐标纠偏器（单测 100% 确定性）。
///
/// 算法源自国测局 GCJ-02 公开近似（Krasovsky 1940 椭球参数），与业界
/// eviltransform 等价；`outOfChina` 之外直接原样返回，不做越界变换。
class CoordConvert {
  CoordConvert._();

  static const double _a = 6378245.0;
  static const double _ee = 0.00669342162296594323;
  static const double _pi = 3.1415926535897932384626;

  /// 中国境外：GCJ-02 变换仅在中国境内生效。
  static bool outOfChina(double lat, double lng) {
    if (lng < 72.004 || lng > 137.8347) return true;
    if (lat < 0.8293 || lat > 55.8271) return true;
    return false;
  }

  static double _transformLat(double x, double y) {
    var ret = -100.0 +
        2.0 * x +
        3.0 * y +
        0.2 * y * y +
        0.1 * x * y +
        0.2 * sqrt(x.abs());
    ret += (20.0 * sin(6.0 * x * _pi) + 20.0 * sin(2.0 * x * _pi)) * 2.0 / 3.0;
    ret += (20.0 * sin(y * _pi) + 40.0 * sin(y / 3.0 * _pi)) * 2.0 / 3.0;
    ret += (160.0 * sin(y / 12.0 * _pi) + 320 * sin(y * _pi / 30.0)) * 2.0 / 3.0;
    return ret;
  }

  static double _transformLng(double x, double y) {
    var ret = 300.0 +
        x +
        2.0 * y +
        0.1 * x * x +
        0.1 * x * y +
        0.1 * sqrt(x.abs());
    ret += (20.0 * sin(6.0 * x * _pi) + 20.0 * sin(2.0 * x * _pi)) * 2.0 / 3.0;
    ret += (20.0 * sin(x * _pi) + 40.0 * sin(x / 3.0 * _pi)) * 2.0 / 3.0;
    ret +=
        (150.0 * sin(x / 12.0 * _pi) + 300.0 * sin(x / 30.0 * _pi)) * 2.0 / 3.0;
    return ret;
  }

  /// WGS-84 → GCJ-02（火星坐标）。境外原样返回。
  static GeoPoint wgs84ToGcj02(GeoPoint p) {
    if (outOfChina(p.lat, p.lng)) return p;
    final d = _delta(p.lat, p.lng);
    return GeoPoint(p.lat + d.dLat, p.lng + d.dLng);
  }

  /// GCJ-02 → WGS-84（迭代精确反解）。境外原样返回。
  static GeoPoint gcj02ToWgs84(GeoPoint p) {
    if (outOfChina(p.lat, p.lng)) return p;
    var cur = p;
    for (var i = 0; i < 8; i++) {
      final g = wgs84ToGcj02(cur);
      final dLat = g.lat - p.lat;
      final dLng = g.lng - p.lng;
      if (dLat.abs() < 1e-9 && dLng.abs() < 1e-9) break;
      cur = GeoPoint(cur.lat - dLat, cur.lng - dLng);
    }
    return cur;
  }

  /// GCJ-02 → BD-09（百度）。境外原样返回。
  static GeoPoint gcj02ToBd09(GeoPoint p) {
    if (outOfChina(p.lat, p.lng)) return p;
    const xPi = _pi * 3000.0 / 180.0;
    final z = sqrt(p.lng * p.lng + p.lat * p.lat) +
        0.00002 * sin(p.lat * xPi);
    final theta = atan2(p.lat, p.lng) + 0.000003 * cos(p.lng * xPi);
    return GeoPoint(z * sin(theta) + 0.006, z * cos(theta) + 0.0065);
  }

  /// BD-09 → GCJ-02（百度）。境外原样返回。
  static GeoPoint bd09ToGcj02(GeoPoint p) {
    if (outOfChina(p.lat, p.lng)) return p;
    const xPi = _pi * 3000.0 / 180.0;
    final x = p.lng - 0.0065;
    final y = p.lat - 0.006;
    final z = sqrt(x * x + y * y) - 0.00002 * sin(y * xPi);
    final theta = atan2(y, x) - 0.000003 * cos(x * xPi);
    return GeoPoint(z * sin(theta), z * cos(theta));
  }

  /// WGS-84 → BD-09（组合）。
  static GeoPoint wgs84ToBd09(GeoPoint p) => gcj02ToBd09(wgs84ToGcj02(p));

  /// BD-09 → WGS-84（组合，迭代精确）。
  static GeoPoint bd09ToWgs84(GeoPoint p) => gcj02ToWgs84(bd09ToGcj02(p));

  /// 任意坐标系互转（统一入口）。
  static GeoPoint normalize(GeoPoint p, CoordSystem from, CoordSystem to) {
    if (from == to) return p;
    GeoPoint g;
    switch (from) {
      case CoordSystem.wgs84:
        g = wgs84ToGcj02(p);
      case CoordSystem.gcj02:
        g = p;
      case CoordSystem.bd09:
        g = bd09ToGcj02(p);
    }
    if (to == CoordSystem.gcj02) return g;
    switch (to) {
      case CoordSystem.wgs84:
        return gcj02ToWgs84(g);
      case CoordSystem.bd09:
        return gcj02ToBd09(g);
      case CoordSystem.gcj02:
        return g;
    }
  }

  /// GCJ-02 偏移量计算（私有）。
  static ({double dLat, double dLng}) _delta(double lat, double lng) {
    final dLat = _transformLat(lng - 105.0, lat - 35.0);
    final dLng = _transformLng(lng - 105.0, lat - 35.0);
    final radLat = lat / 180.0 * _pi;
    final magic = sin(radLat);
    final magic2 = 1 - _ee * magic * magic;
    final sqrtMagic = sqrt(magic2);
    final latDelta =
        (dLat * 180.0) / ((_a * (1 - _ee)) / (magic2 * sqrtMagic) * _pi);
    final lngDelta =
        (dLng * 180.0) / (_a / sqrtMagic * cos(radLat) * _pi);
    return (dLat: latDelta, dLng: lngDelta);
  }

  /// 两点 Haversine 直线距离（米），与坐标系无关（均按球面大圆计算）。
  static double haversineMeters(GeoPoint a, GeoPoint b) {
    const r = 6371000.0; // 地球平均半径（米）
    final dLat = _toRad(b.lat - a.lat);
    final dLng = _toRad(b.lng - a.lng);
    final s = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRad(a.lat)) * cos(_toRad(b.lat)) *
            sin(dLng / 2) * sin(dLng / 2);
    return 2 * r * asin(sqrt(s));
  }

  static double _toRad(double deg) => deg * _pi / 180.0;
}
