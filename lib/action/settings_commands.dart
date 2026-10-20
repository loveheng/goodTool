library;

import 'command_gateway.dart';

/// 用户侧设置命令族（`user_*` 前缀）。
///
/// 与日历 W 档命令族的分工：日历 5 个 W 档（`calendar_*`）是**用户委托写**——
/// 经 MCP 工具面到达，命令名必须 = action 名（`CategoryTool.admits` 查找）。
/// 本文件是**用户本人自决**的设置写（App 设置页），命令名**不进 MCP 工具面**
/// （26 个 action 枚举内无 `user_*`），故 AI **不可触达**——这是产品信任模型
/// 「敏感设置仅用户本人在 App 内自设」的机制化。
///
/// 命令**只承载载荷**，校验与落盘在 service 层 Actor（见
/// `lib/service/settings_actors.dart`）——与日历 W 档同一条纪律：
/// UI 层不自行鉴权、不自行写存储。
class UserSetApiKeyCommand extends Command {
  const UserSetApiKeyCommand(Map<String, Object?> payload)
      : super('user_set_api_key', payload);
}

/// 设置后端 API Key（地图 / 天气）。
class UserSetPrivacySwitchCommand extends Command {
  const UserSetPrivacySwitchCommand(Map<String, Object?> payload)
      : super('user_set_privacy_switch', payload);
}

/// 设置脱敏开关（日程敏感字段过滤 / 模糊定位）。
class UserSetIdentityProfileCommand extends Command {
  const UserSetIdentityProfileCommand(Map<String, Object?> payload)
      : super('user_set_identity_profile', payload);
}

/// 用户设置快照（写后回最新状态，standards §5.2；对齐读工具同形状）。
///
/// **凭证零明文留痕**（standards §6.1）：凭证类键只回显「是否已配置」与掩码尾号，
/// **不回显明文**；身份画像属用户自述内容、非凭证，原文回显。
class UserSettingsSnapshot {
  const UserSettingsSnapshot({
    required this.credentialConfigured,
    required this.credentialMasked,
    required this.switches,
    required this.plainValues,
    required this.identityPrompt,
  });

  /// 凭证类键 → 是否已配置。
  final Map<String, bool> credentialConfigured;

  /// 凭证类键 → 掩码值（形如 `....abcd`，只露尾 4 位；未配置时为空串）。
  final Map<String, String> credentialMasked;

  /// 脱敏开关键 → 是否开启。
  final Map<String, bool> switches;

  /// 非凭证类可读键 → 原值（如天气数据主机）。
  final Map<String, String> plainValues;

  /// 用户身份画像原文（用户自述，非凭证）。
  final String? identityPrompt;

  /// 某个凭证是否已配置。
  bool isConfigured(String key) => credentialConfigured[key] ?? false;

  /// 某个脱敏开关是否开启。
  bool isSwitchOn(String key) => switches[key] ?? false;
}
