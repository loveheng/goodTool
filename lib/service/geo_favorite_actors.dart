library;

import '../action/command_gateway.dart';
import 'favorite_place_store.dart';

/// 收藏地点用户侧 Actor：把**用户本人**的收藏写落到 store。
///
/// 纪律同日历 W 档 / 设置 Actor（`settings_actors.dart`）：
/// - 校验在 Actor 内（必填 / 取值域 / 超长），失败回**结构化机器码 + suggestion**；
/// - 写后回**写入确认**（id + 当前条数，standards §5.2 快照语义的轻量变体）；
/// - 写端口只在此持有；UI 经 Repository 读端口（R5）。
class GeoFavoriteActors {
  GeoFavoriteActors({required this.store, required this.writer});

  final FavoritePlaceStore store;
  final FavoritePlaceWriter writer;

  /// 登记进用户侧注册表（AI 不可触达）。
  void register(CommandGateway gateway) {
    gateway.registerUser('user_geo_favorite_add', addFavorite);
    gateway.registerUser('user_geo_favorite_delete', deleteFavorite);
  }

  /// 新增收藏地点。载荷 `{name, lat, lng, coordSystem?, address?, folder?}`。
  ///
  /// `folder` 可选：缺省/空串 = 未分类；1~[favoriteFolderNameMaxLength] 字符。
  /// 收藏夹是派生分组——写新夹名即建夹，无需独立建夹命令。
  Future<UserCommandResult> addFavorite(Command cmd) async {
    final p = cmd.payload;

    final name = p['name'];
    if (name is! String || name.trim().isEmpty) {
      return const UserCommandResult.failure(
        'MISSING_ARGUMENT',
        '缺少必填参数 name（非空字符串）',
        suggestion: 'name 取地点名称，1~40 字符',
      );
    }
    final trimmedName = name.trim();
    if (trimmedName.length > 40) {
      return UserCommandResult.failure(
        'INVALID_ARGUMENT',
        'name 超长（${trimmedName.length} > 40 字符）',
        suggestion: 'name 压缩到 40 字符以内',
      );
    }

    final lat = _asDouble(p['lat']);
    final lng = _asDouble(p['lng']);
    if (lat == null || lng == null) {
      return const UserCommandResult.failure(
        'MISSING_ARGUMENT',
        '缺少必填参数 lat / lng（数值）',
        suggestion: 'lat/lng 为 double；LLM 弱类型字符串由调用方宽容解析',
      );
    }
    if (lat < -90 || lat > 90 || lng < -180 || lng > 180) {
      return UserCommandResult.failure(
        'INVALID_ARGUMENT',
        '经纬度越界（lat=$lat, lng=$lng）',
        suggestion: '纬度 -90~90，经度 -180~180',
      );
    }

    final coordSystem = p['coordSystem'];
    var cs = 'GCJ02';
    if (coordSystem is String && coordSystem.trim().isNotEmpty) {
      final v = coordSystem.trim();
      if (v != 'GCJ02' && v != 'WGS84') {
        return UserCommandResult.failure(
          'INVALID_ARGUMENT',
          '未知 coordSystem：$v',
          suggestion: 'coordSystem 仅支持 GCJ02 / WGS84',
        );
      }
      cs = v;
    }

    final address = p['address'];
    String? trimmedAddress;
    if (address is String && address.trim().isNotEmpty) {
      trimmedAddress = address.trim();
      if (trimmedAddress.length > 100) {
        return const UserCommandResult.failure(
          'INVALID_ARGUMENT',
          'address 超长（> 100 字符）',
          suggestion: 'address 压缩到 100 字符以内',
        );
      }
    }

    final folderRaw = p['folder'];
    var folder = '';
    if (folderRaw is String && folderRaw.trim().isNotEmpty) {
      final v = folderRaw.trim();
      if (v.length > favoriteFolderNameMaxLength) {
        return UserCommandResult.failure(
          'INVALID_ARGUMENT',
          'folder 超长（${v.length} > $favoriteFolderNameMaxLength 字符）',
          suggestion: '收藏夹名压缩到 $favoriteFolderNameMaxLength 字符以内',
        );
      }
      folder = v;
    }

    final place = FavoritePlace(
      id: newFavoritePlaceId(),
      name: trimmedName,
      lat: lat,
      lng: lng,
      coordSystem: cs,
      address: trimmedAddress,
      folder: folder,
    );
    try {
      final id = await writer.addPlace(place);
      final count = (await _listCount());
      return UserCommandResult.success(<String, Object?>{
        'id': id,
        'name': trimmedName,
        'folder': folder,
        'count': count,
      });
    } on FavoriteLimitExceeded catch (e) {
      return UserCommandResult.failure(
        'FAVORITE_LIMIT_EXCEEDED',
        '收藏已达上限 ${e.limit} 条',
        suggestion: '删除不再需要的收藏后再添加',
      );
    }
  }

  /// 删除收藏地点。载荷 `{id}`。
  Future<UserCommandResult> deleteFavorite(Command cmd) async {
    final id = cmd.payload['id'];
    if (id is! String || id.trim().isEmpty) {
      return const UserCommandResult.failure(
        'MISSING_ARGUMENT',
        '缺少必填参数 id（收藏条目 id）',
      );
    }
    final deleted = await writer.deletePlace(id.trim());
    if (!deleted) {
      return UserCommandResult.failure(
        'NOT_FOUND',
        '收藏 id 不存在：${id.trim()}',
        suggestion: '先读收藏列表取有效 id（Agent 无权凭空操作）',
      );
    }
    return UserCommandResult.success(<String, Object?>{
      'deleted': true,
      'count': await _listCount(),
    });
  }

  Future<int> _listCount() async => (await store.list()).length;

  static double? _asDouble(Object? v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v.trim());
    return null;
  }
}
