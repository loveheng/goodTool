library;

import '../service/favorite_place_store.dart';

/// 收藏地点**读聚合层**（R5 落点）：UI 经此读收藏，不直连 store。
///
/// **写端口（`FavoritePlaceWriter`）不在此暴露**——收藏写必经 `CommandGateway`
/// 用户侧注册表（R1），写端口只给 service 层 Actor 持有（对齐
/// `marker_repository.dart` 口径）。
class FavoriteRepository {
  FavoriteRepository({required this.store});

  final FavoritePlaceStore store;

  /// 全量收藏列表（收藏无区间概念，直接全量；上限 50 条可控）。
  Future<List<FavoritePlace>> list() => store.list();
}
