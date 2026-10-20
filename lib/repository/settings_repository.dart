library;

import '../action/settings_commands.dart';
import '../mcp/settings_kv.dart';
import '../mcp/settings_keys.dart';

/// 用户设置**读聚合层**（R5 落点）。
///
/// UI 与未来其他前端**经此读**用户设置，不直连 `SettingsKv`
/// （standards §1.0 R5：数据访问一律走 Repository）。
///
/// **写路径不在此**：写必走 `CommandGateway`（R1）——本类只持读端口 `SettingsKv`，
/// 写由 `lib/service/settings_actors.dart` 的 Actor 承担。
class SettingsRepository {
  SettingsRepository({required this.kv});

  final SettingsKv kv;

  /// 读单个键（内部/工具用；UI 侧优先读快照）。
  Future<String?> read(String key) => kv.settingsGet(key);

  /// 读当前用户设置快照（类型化；**凭证不回显明文**）。
  Future<UserSettingsSnapshot> readSnapshot() async {
    final configured = <String, bool>{};
    final masked = <String, String>{};
    for (final key in SettingsKeys.credentialKeys) {
      final value = await kv.settingsGet(key);
      final has = value != null && value.trim().isNotEmpty;
      configured[key] = has;
      masked[key] = has ? maskCredential(value.trim()) : '';
    }

    final switches = <String, bool>{};
    for (final key in SettingsKeys.privacySwitchKeys) {
      switches[key] = (await kv.settingsGet(key)) == '1';
    }

    final plain = <String, String>{};
    for (final key in SettingsKeys.plainReadableKeys) {
      final value = await kv.settingsGet(key);
      if (value != null && value.trim().isNotEmpty) plain[key] = value.trim();
    }

    final identity = await kv.settingsGet(SettingsKeys.identityPrompt);
    return UserSettingsSnapshot(
      credentialConfigured: configured,
      credentialMasked: masked,
      switches: switches,
      plainValues: plain,
      identityPrompt: (identity != null && identity.trim().isNotEmpty)
          ? identity.trim()
          : null,
    );
  }
}

/// 凭证掩码：只露尾 4 位（不足 4 位全掩）——standards §6.1 凭证零明文留痕。
String maskCredential(String value) {
  if (value.length <= 4) return '....';
  return '....${value.substring(value.length - 4)}';
}
