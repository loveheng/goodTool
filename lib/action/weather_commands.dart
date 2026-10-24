library;

import 'command_gateway.dart';

/// 天气域用户侧命令族（`user_weather_*` 前缀）。
///
/// 多城市列表是**用户本人自决**的写（product/weather.md「用户侧城市管理」），
/// 命令名**不进 MCP 工具面**（weather 1 个 action 枚举内无 `user_*`），故 AI
/// **不可触达**——信任模型对齐 `user_save_draft`（`settings_commands.dart`）。
///
/// 命令**只承载载荷**，校验与落盘在 service 层 Actor（见
/// `lib/service/weather_city_actors.dart`）——UI 层不自行鉴权、不自行写存储。
class UserWeatherCityAddCommand extends Command {
  const UserWeatherCityAddCommand(Map<String, Object?> payload)
      : super('user_weather_city_add', payload);
}

/// 删除一条已添加城市。
class UserWeatherCityDeleteCommand extends Command {
  const UserWeatherCityDeleteCommand(Map<String, Object?> payload)
      : super('user_weather_city_delete', payload);
}
