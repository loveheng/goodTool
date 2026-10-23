// 收藏地点存储：FavoritePlaceStore（读）+ FavoritePlaceWriter（写）端口的双实现。
// 收藏是用户私有数据（geo.md「收藏地点（用户自决）」），写操作不进 MCP 工具面。
//
// - [InMemoryFavoritePlaceStore]：Binder isolate / 单测——无平台通道依赖，进程
//   重启即失（Binder isolate 本就每次拉起重建，语义可接受）。
// - [SharedPrefsFavoritePlaceStore]：真实持久化（shared_preferences，JSON 字符串
//   列表）。非凭证数据，不走 SecretStore/Keystore 分流。
//
// 纪律：写端口**只给用户侧 Actor 持有**（经装配件注入）；UI 层只见
// Repository 暴露的读端口（R5）。
library;

import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

/// shared_preferences 键（FavoritePlace JSON 数组）。
const String kGeoFavoritesPrefKey = 'geo_favorites';

/// 收藏条数硬上限（geo.md：防无限增长）。
const int favoritePlaceLimit = 50;

/// 收藏夹名长度上限（Actor 校验）。
const int favoriteFolderNameMaxLength = 20;

/// 收藏地点（用户自决数据）。
class FavoritePlace {
  const FavoritePlace({
    required this.id,
    required this.name,
    required this.lat,
    required this.lng,
    this.coordSystem = 'GCJ02',
    this.address,
    this.folder = '',
  });

  /// `geo_fav_` + 8 位十六进制。
  final String id;

  /// 地点名称（Actor 校验 1~40 字符）。
  final String name;

  final double lat;
  final double lng;

  /// `GCJ02`（默认，UI 选点来自高德检索结果）/ `WGS84`。
  final String coordSystem;

  /// 可选地址描述（≤100 字符）。
  final String? address;

  /// 收藏夹名；`''` = 未分类（默认）。收藏夹是**派生分组**而非独立实体：
  /// 夹名随收藏写入而存在，夹内收藏删空即夹自然消失（无级联删除风险）。
  /// 历史数据无此字段 → 解码归入未分类（数据完整保留，不丢弃）。
  final String folder;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'name': name,
        'lat': lat,
        'lng': lng,
        'coordSystem': coordSystem,
        if (address != null) 'address': address,
        'folder': folder,
      };

  /// 解码失败抛 [FormatException]，由调用方转结构化错误——不静默跳过坏行。
  static FavoritePlace fromJson(Map<String, Object?> m) => FavoritePlace(
        id: m['id'] as String,
        name: m['name'] as String,
        lat: (m['lat'] as num).toDouble(),
        lng: (m['lng'] as num).toDouble(),
        coordSystem: (m['coordSystem'] as String?) ?? 'GCJ02',
        address: m['address'] as String?,
        folder: (m['folder'] as String?)?.trim() ?? '',
      );
}

/// id 生成（对齐 marker_store：进程内足够唯一，删除按 id 精确匹配）。
String newFavoritePlaceId() =>
    'geo_fav_${Random.secure().nextInt(1 << 32).toRadixString(16).padLeft(8, '0')}';

/// 读端口（UI 经 Repository 只读聚合层访问，R5）。
abstract class FavoritePlaceStore {
  Future<List<FavoritePlace>> list();
}

/// 写端口（只给用户侧 Actor 持有）。
abstract class FavoritePlaceWriter {
  /// 新增一条，返回 id；超出 [favoritePlaceLimit] 抛 [FavoriteLimitExceeded]。
  Future<String> addPlace(FavoritePlace place);

  /// 按 id 删除；无匹配返回 false（Actor 转 NOT_FOUND）。
  Future<bool> deletePlace(String id);
}

/// 超出收藏上限（Actor 转 `FAVORITE_LIMIT_EXCEEDED`，不静默挤掉旧条目）。
class FavoriteLimitExceeded implements Exception {
  const FavoriteLimitExceeded(this.limit);
  final int limit;
}

/// 内存实现：进程重启即失。
class InMemoryFavoritePlaceStore
    implements FavoritePlaceStore, FavoritePlaceWriter {
  final List<FavoritePlace> _items = <FavoritePlace>[];

  @override
  Future<List<FavoritePlace>> list() async =>
      List<FavoritePlace>.unmodifiable(_items);

  @override
  Future<String> addPlace(FavoritePlace place) async {
    if (_items.length >= favoritePlaceLimit) {
      throw FavoriteLimitExceeded(favoritePlaceLimit);
    }
    _items.add(place);
    return place.id;
  }

  @override
  Future<bool> deletePlace(String id) async {
    final n = _items.length;
    _items.removeWhere((p) => p.id == id);
    return _items.length != n;
  }
}

/// SharedPreferences 持久化实现。
class SharedPrefsFavoritePlaceStore
    implements FavoritePlaceStore, FavoritePlaceWriter {
  SharedPrefsFavoritePlaceStore(this._prefs);

  final SharedPreferences _prefs;

  static const String key = kGeoFavoritesPrefKey;

  static Future<SharedPrefsFavoritePlaceStore> open() async =>
      SharedPrefsFavoritePlaceStore(await SharedPreferences.getInstance());

  @override
  Future<List<FavoritePlace>> list() async => _decode();

  @override
  Future<String> addPlace(FavoritePlace place) async {
    final all = _decode();
    if (all.length >= favoritePlaceLimit) {
      throw FavoriteLimitExceeded(favoritePlaceLimit);
    }
    await _save(<FavoritePlace>[...all, place]);
    return place.id;
  }

  @override
  Future<bool> deletePlace(String id) async {
    final all = _decode();
    final next = all.where((p) => p.id != id).toList(growable: false);
    if (next.length == all.length) return false;
    await _save(next);
    return true;
  }

  List<FavoritePlace> _decode() => (_prefs.getStringList(key) ?? const <String>[])
      .map((raw) =>
          FavoritePlace.fromJson(jsonDecode(raw) as Map<String, Object?>))
      .toList(growable: false);

  Future<void> _save(List<FavoritePlace> places) async {
    await _prefs.setStringList(
        key, places.map((p) => jsonEncode(p.toJson())).toList(growable: false));
  }
}
