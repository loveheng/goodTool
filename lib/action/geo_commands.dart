library;

import 'command_gateway.dart';

/// 地理域用户侧命令族（`user_geo_*` 前缀）。
///
/// 收藏地点是**用户本人自决**的写（geo.md「收藏地点（用户自决）」），命令名
/// **不进 MCP 工具面**（geo 8 个 action 枚举内无 `user_*`），故 AI **不可触达**
/// ——信任模型对齐 `user_save_draft`（`settings_commands.dart`）。
///
/// 命令**只承载载荷**，校验与落盘在 service 层 Actor（见
/// `lib/service/geo_favorite_actors.dart`）——UI 层不自行鉴权、不自行写存储。
class UserGeoFavoriteAddCommand extends Command {
  const UserGeoFavoriteAddCommand(Map<String, Object?> payload)
      : super('user_geo_favorite_add', payload);
}

/// 删除一条收藏地点。
class UserGeoFavoriteDeleteCommand extends Command {
  const UserGeoFavoriteDeleteCommand(Map<String, Object?> payload)
      : super('user_geo_favorite_delete', payload);
}

/// 记住地图页上次定位点（`{lat, lng}`，GCJ-02）——UI 会话态持久化，
/// 供下次进场先恢复到上次位置再刷新定位（不回占位原点）。
class UserGeoSaveLastLocationCommand extends Command {
  const UserGeoSaveLastLocationCommand(Map<String, Object?> payload)
      : super('user_geo_save_last_location', payload);
}
