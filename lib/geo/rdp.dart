/// 道格拉斯-普克（Ramer–Douglas–Peucker）轨迹抽稀（纯 Dart，无头可跑）。
///
/// 用于路径规划长点阵抽稀：高德静态图 `paths` 参数拼接后 URL 若超过 2048 字符会
/// 触发 HTTP 414（URI Too Long）导致出图失败。本算法将长轨迹压到关键拐点，并硬性
/// 卡在 [maxPoints]（默认 80）以内，确保生成的静态图 URL 绝对可控。
library;

import 'dart:math';

import 'coord_convert.dart';

/// 局部等距平面投影点（米）。
class _XY {
  const _XY(this.x, this.y);
  final double x;
  final double y;
}

/// 将经纬度点投影到以 [refLat] 为基准的局部等距平面（米），消除经纬度度长不均。
List<_XY> _project(List<GeoPoint> pts, double refLat) {
  final latRad = refLat * pi / 180;
  final mx = 111320 * cos(latRad); // 每经度米数（随纬度收窄）
  const my = 110540.0; // 每纬度米数（近似常量）
  return pts.map((p) => _XY(p.lng * mx, p.lat * my)).toList();
}

/// 点 p 到线段 a-b 的垂直距离（米）。
double _perpDistance(_XY p, _XY a, _XY b) {
  final dx = b.x - a.x;
  final dy = b.y - a.y;
  final len2 = dx * dx + dy * dy;
  if (len2 == 0) {
    final ex = p.x - a.x;
    final ey = p.y - a.y;
    return sqrt(ex * ex + ey * ey);
  }
  var t = ((p.x - a.x) * dx + (p.y - a.y) * dy) / len2;
  t = t.clamp(0.0, 1.0);
  final cx = a.x + t * dx;
  final cy = a.y + t * dy;
  return sqrt((p.x - cx) * (p.x - cx) + (p.y - cy) * (p.y - cy));
}

/// RDP 抽稀：保留能代表原形的关键拐点，垂直距离阈值 [epsilonMeters]。
///
/// [points] 为原轨迹（任意坐标系，抽稀在投影平面进行，与坐标系无关）。
/// 结果上限 [maxPoints] 个点（超出则均匀下采样，首末点必保留）。
List<GeoPoint> rdpSimplify(
  List<GeoPoint> points, {
  double epsilonMeters = 10,
  int maxPoints = 80,
}) {
  if (points.length <= 2) return List.of(points);
  final refLat =
      points.fold<double>(0, (s, p) => s + p.lat) / points.length;
  final proj = _project(points, refLat);
  final keep = List.filled(points.length, false);
  keep[0] = true;
  keep[points.length - 1] = true;
  _rdp(proj, keep, 0, points.length - 1, epsilonMeters);
  final simplified = <GeoPoint>[];
  for (var i = 0; i < points.length; i++) {
    if (keep[i]) simplified.add(points[i]);
  }
  if (simplified.length <= maxPoints) return simplified;
  // 硬性上限：均匀下采样，首末点必保留。
  final n = simplified.length;
  final capped = <GeoPoint>[];
  for (var i = 0; i < maxPoints; i++) {
    final idx = (i * (n - 1) / (maxPoints - 1)).round();
    capped.add(simplified[idx]);
  }
  return capped;
}

void _rdp(
  List<_XY> proj,
  List<bool> keep,
  int first,
  int last,
  double eps,
) {
  var maxDist = 0.0;
  var index = -1;
  for (var i = first + 1; i < last; i++) {
    final d = _perpDistance(proj[i], proj[first], proj[last]);
    if (d > maxDist) {
      maxDist = d;
      index = i;
    }
  }
  if (maxDist > eps && index != -1) {
    keep[index] = true;
    _rdp(proj, keep, first, index, eps);
    _rdp(proj, keep, index, last, eps);
  }
}
