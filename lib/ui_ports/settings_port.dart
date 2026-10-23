library;

import '../action/command_gateway.dart';
import '../action/settings_commands.dart';
import '../repository/settings_repository.dart';

/// 设置页 UI 适配层：**读经 Repository（R5），写经 CommandGateway（R1）**。
///
/// 写路径与 MCP 侧**同一唯一写入口**，但命令族不同：本端口派发的是
/// `user_*` 用户命令（`CommandGateway` 的用户侧注册表），AI 不可触达。
class SettingsPort {
  const SettingsPort(this._repository, this._gateway);

  final SettingsRepository _repository;
  final CommandGateway _gateway;

  /// 读当前设置快照（类型化；**凭证不回显明文**，只给「已配置 + 掩码尾号」）。
  Future<UserSettingsSnapshot> read() => _repository.readSnapshot();

  /// 设置后端 API Key（`provider` ∈ `amap` / `qweather`）。
  ///
  /// [key] 传空串 = 清除该 Key（后端 Provider 把空串视为未配置）。
  Future<UserCommandResult> setApiKey({
    required String provider,
    required String key,
    String? secret,
  }) =>
      _gateway.dispatchUser(
        UserSetApiKeyCommand(<String, Object?>{
          'provider': provider,
          'key': key,
          'secret': ?secret,
        }),
      );

  /// 设置脱敏开关（日程敏感字段过滤 / 模糊定位）。
  Future<UserCommandResult> setPrivacySwitch({
    required String key,
    required bool enabled,
  }) =>
      _gateway.dispatchUser(
        UserSetPrivacySwitchCommand(<String, Object?>{
          'key': key,
          'enabled': enabled,
        }),
      );

  /// 设置用户身份画像（拼进 MCP 系统提示词）。
  Future<UserCommandResult> setIdentityProfile(String text) =>
      _gateway.dispatchUser(
        UserSetIdentityProfileCommand(<String, Object?>{'text': text}),
      );
}
