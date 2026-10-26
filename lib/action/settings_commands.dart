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

/// 设置身份画像。
class UserSetIdentityProfileCommand extends Command {
  const UserSetIdentityProfileCommand(Map<String, Object?> payload)
      : super('user_set_identity_profile', payload);
}

/// 设置非凭证类可读键（如天气数据主机 `qweather_host`、预设城市 `weather_location`）。
///
/// 仅允许白名单（SettingsKeys.plainReadableKeys）内的键，防止 UI 越权写任意 KV；
/// 与 `user_set_api_key`（凭证类）分工明确：本命令不碰任何凭证。
class UserSetSettingCommand extends Command {
  const UserSetSettingCommand(Map<String, Object?> payload)
      : super('user_set_setting', payload);
}

/// 保存计算器草稿台内容（UI 会话态持久化，非设置项）。
///
/// 载荷 `{'content': string}`——各块单行文本以 `\n` 连接（块本身 maxLines:1，
/// `\n` 无损）。走用户侧注册表：草稿是**用户本人的纸面**，AI 不可经工具面
/// 触达（写入 / 清空均归用户自决）。
class UserSaveDraftCommand extends Command {
  const UserSaveDraftCommand(Map<String, Object?> payload)
      : super('user_save_draft', payload);
}

/// 设置首页快捷方式钉住的域（载荷 `{'domain': string}`；值 = `AppDomain`
/// 枚举名，四域 calculator / calendar / geo / weather；校验在 Actor，UI 不自验）。
class UserSetHomePinnedDomainCommand extends Command {
  const UserSetHomePinnedDomainCommand(Map<String, Object?> payload)
      : super('user_set_home_pinned_domain', payload);
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
    required this.homePinnedDomain,
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

  /// 首页快捷方式钉住的域（`AppDomain` 枚举名；null = 未设置，渲染层回落默认域）。
  final String? homePinnedDomain;

  /// 某个凭证是否已配置。
  bool isConfigured(String key) => credentialConfigured[key] ?? false;

  /// 某个脱敏开关是否开启。
  bool isSwitchOn(String key) => switches[key] ?? false;
}
