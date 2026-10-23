library;

import '../geo/coord_convert.dart';
import '../geo/static_map_url.dart';
import '../service/favorite_place_store.dart';

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
/// 故地图子页面的这部分永远可用；设备定位另走 [GeoPort] 之外的 Provider 端口。
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

/// 收藏地点视图（类型化；地图子页面收藏列表渲染用）。
class FavoritePlaceView {
  const FavoritePlaceView({
    required this.id,
    required this.name,
    required this.lat,
    required this.lng,
    required this.coordSystem,
    this.address,
    this.folder = '',
  });

  final String id;
  final String name;
  final double lat;
  final double lng;

  /// `GCJ02` / `WGS84`（域模型原样透传，UI 展示与静态图归一化据此判断）。
  final String coordSystem;

  final String? address;

  /// 收藏夹名；`''` = 未分类。
  final String folder;

  /// 坐标展示串（6 位小数，对齐 [GeoPointView.formatted] 口径）。
  String get formatted => '${lat.toStringAsFixed(6)}, ${lng.toStringAsFixed(6)}';

  /// 域模型 → 视图模型（ui_ports 唯一出口；UI 禁直接消费 store 域模型）。
  static FavoritePlaceView fromFavorite(FavoritePlace p) => FavoritePlaceView(
        id: p.id,
        name: p.name,
        lat: p.lat,
        lng: p.lng,
        coordSystem: p.coordSystem,
        address: p.address,
        folder: p.folder,
      );

  /// 批量映射。
  static List<FavoritePlaceView> listFrom(List<FavoritePlace> places) =>
      places.map(fromFavorite).toList(growable: false);
}

/// 收藏夹分组（收藏夹 = 派生分组：夹名来自收藏的 folder 字段）。
class FavoriteFolderGroup {
  const FavoriteFolderGroup({required this.folder, required this.places});

  /// 夹名；`''` = 未分类。
  final String folder;

  final List<FavoritePlaceView> places;
}

/// 按收藏夹分组（纯函数，headless 可单测）：
/// 非空夹名按字典序升序在前，未分类（`''`）恒在最后；
/// 组内保持收藏列表原顺序（按添加时间）。
List<FavoriteFolderGroup> groupFavoritesByFolder(List<FavoritePlaceView> places) {
  final folders = <String>[];
  for (final p in places) {
    if (p.folder.isNotEmpty && !folders.contains(p.folder)) folders.add(p.folder);
  }
  folders.sort();
  final ordered = <String>[
    ...folders,
    if (places.any((p) => p.folder.isEmpty)) '',
  ];
  return <FavoriteFolderGroup>[
    for (final f in ordered)
      FavoriteFolderGroup(
        folder: f,
        places: places.where((p) => p.folder == f).toList(growable: false),
      ),
  ];
}

/// 静态地图预览结果（类型化；UI 只吃本视图，不碰 Key 明文）。
class GeoStaticMapView {
  const GeoStaticMapView({required this.ok, this.url, this.errorCode, this.message});

  final bool ok;

  /// 高德静态图 URL（成功时非空）。
  final String? url;

  /// 机器码（失败时非空，如 `ERR_AMAP_KEY_MISSING`）。
  final String? errorCode;

  final String? message;
}

/// 简易地图端口：静态图 URL 构建（免 Native SDK 轻量渲染）。
///
/// Key/Secret 经注入的懒读闭包获取（装配面同步、读取异步，改配置即时生效）；
/// 未配置 Key **fail-closed** 返 `ERR_AMAP_KEY_MISSING`，不以空 Key 拼 URL 假装可用
/// （standards §1.2，对齐 `AmapHttpProvider` 口径）。UI 不接触 Key 明文——
/// 懒读闭包由装配件（main.dart）注入。
class GeoMapPort {
  GeoMapPort({required this.readKey, required this.readSecret});

  /// 高德 Web 服务 Key 懒读（未配置回 null）。
  final Future<String?> Function() readKey;

  /// 数字签名密钥懒读（可选项，未配置回 null）。
  final Future<String?> Function() readSecret;

  /// 构建单点标记静态图 URL（收藏地点选中即渲染的场景）。
  ///
  /// [coordSystem] 声明入参坐标系（收藏点默认 GCJ-02），内核统一归一化。
  Future<GeoStaticMapView> staticMapUrl({
    required double lat,
    required double lng,
    String coordSystem = 'GCJ02',
    int zoom = 14,
    String? label,
  }) async {
    final key = await readKey();
    if (key == null || key.isEmpty) {
      return const GeoStaticMapView(
        ok: false,
        errorCode: 'ERR_AMAP_KEY_MISSING',
        message: '未配置高德 Web 服务 Key',
      );
    }
    final url = AmapStaticMap.buildUrl(
      key: key,
      center: GeoPoint(lat, lng),
      zoom: zoom,
      size: const (600, 360),
      scale: 2,
      markers: <StaticMapMarker>[
        StaticMapMarker(point: GeoPoint(lat, lng), label: label),
      ],
      coordSystem: coordSystem == 'WGS84' ? CoordSystem.wgs84 : CoordSystem.gcj02,
      secret: await readSecret(),
    );
    return GeoStaticMapView(ok: true, url: url);
  }
}
