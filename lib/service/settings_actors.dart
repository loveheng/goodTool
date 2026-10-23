library;

import '../action/command_gateway.dart';
import '../mcp/settings_keys.dart';
import '../repository/settings_repository.dart';

/// 用户设置 Actor：把**用户本人**的设置写落到 KV。
///
/// 纪律同日历 W 档 Actor：
/// - 校验在 Actor 内（必填 / 枚举 / 取值域），失败回**结构化机器码 + suggestion**；
/// - 写后回**最新快照**（standards §5.2），不回 `void`；
/// - **凭证零明文留痕**（standards §6.1）：快照只带「是否已配置 + 掩码尾号」。
///
/// 与 AI 侧 Actor 的物理隔离：命令登记在 `CommandGateway` 的**用户侧注册表**，
/// AI 不可经 MCP 工具面触达（26 个 action 枚举内无 `user_*`）。
class SettingsActors {
  SettingsActors({required this.repository});

  final SettingsRepository repository;

  /// 登记进用户侧注册表（AI 不可触达）。
  void register(CommandGateway gateway) {
    gateway.registerUser('user_set_api_key', setApiKey);
    gateway.registerUser('user_set_privacy_switch', setPrivacySwitch);
    gateway.registerUser('user_set_identity_profile', setIdentityProfile);
    gateway.registerUser('user_set_setting', setSetting);
    gateway.registerUser('user_save_draft', saveDraft);
  }

  /// 保存计算器草稿台内容（UI 会话态持久化，非设置项）。
  ///
  /// 写后回**写入确认**（content 原文长度，standards §5.2 快照语义的轻量
  /// 变体——草稿无回显面，只确认落盘）。
  Future<UserCommandResult> saveDraft(Command cmd) async {
    final content = cmd.payload['content'];
    if (content is! String) {
      return const UserCommandResult.failure(
        'DRAFT_CONTENT_INVALID',
        '缺少必填参数 content（字符串，各块以 \\n 连接）',
        suggestion: 'content 取草稿台全部块文本的 \\n 拼接',
      );
    }
    await repository.kv
        .settingsSet(<String, String>{SettingsKeys.calculatorDraft: content});
    return UserCommandResult.success(<String, Object?>{
      'saved': true,
      'lines': content.split('\n').length,
    });
  }

  /// 设置后端 API Key：provider ∈ {`amap`, `qweather`}。
  ///
  /// 空串 = **清除**（两个后端 Provider 均把空串视为未配置，见
  /// `AmapHttpProvider` / `QWeatherProvider` 的 key 判空口径）。
  Future<UserCommandResult> setApiKey(Command cmd) async {
    final provider = cmd.payload['provider'];
    if (provider is! String || provider.trim().isEmpty) {
      return UserCommandResult.failure(
        'MISSING_ARGUMENT',
        '缺少 provider',
        suggestion: '请在 App 设置页选择要配置的厂商',
      );
    }
    final keyName = switch (provider.trim()) {
      'amap' => SettingsKeys.amapWebKey,
      'qweather' => SettingsKeys.qweatherKey,
      _ => null,
    };
    if (keyName == null) {
      return UserCommandResult.failure(
        'INVALID_ARGUMENT',
        '未知 provider：$provider',
        suggestion: 'provider 仅支持 amap / qweather',
      );
    }
    final key = cmd.payload['key'];
    if (key is! String) {
      return UserCommandResult.failure('MISSING_ARGUMENT', '缺少 key');
    }

    final values = <String, String>{keyName: key.trim()};
    // 高德静态图数字签名密钥是独立可选项（防 INVALID_USER_SCODE）。
    if (keyName == SettingsKeys.amapWebKey) {
      final secret = cmd.payload['secret'];
      if (secret is String) values[SettingsKeys.amapSecret] = secret.trim();
    }
    await repository.kv.settingsSet(values);
    return UserCommandResult.success(await repository.readSnapshot());
  }

  /// 设置脱敏开关（日程敏感字段过滤 / 模糊定位）。
  Future<UserCommandResult> setPrivacySwitch(Command cmd) async {
    final key = cmd.payload['key'];
    if (key is! String || key.trim().isEmpty) {
      return UserCommandResult.failure(
        'MISSING_ARGUMENT',
        '缺少 key',
        suggestion: '可选开关：${SettingsKeys.privacySwitchKeys.join(' / ')}',
      );
    }
    final name = key.trim();
    if (!SettingsKeys.privacySwitchKeys.contains(name)) {
      return UserCommandResult.failure(
        'INVALID_ARGUMENT',
        '未知开关：$name',
        suggestion: '可选开关：${SettingsKeys.privacySwitchKeys.join(' / ')}',
      );
    }
    final enabled = cmd.payload['enabled'];
    if (enabled is! bool) {
      return UserCommandResult.failure(
        'MISSING_ARGUMENT',
        '缺少 enabled（布尔）',
      );
    }
    return _applySwitch(name, enabled);
  }

  /// 设置用户身份画像（拼进 MCP 系统提示词）。
  Future<UserCommandResult> setIdentityProfile(Command cmd) async {
    final text = cmd.payload['text'];
    if (text is! String) {
      return UserCommandResult.failure('MISSING_ARGUMENT', '缺少 text');
    }
    await repository.kv
        .settingsSet({SettingsKeys.identityPrompt: text.trim()});
    return UserCommandResult.success(await repository.readSnapshot());
  }

  /// 设置非凭证类可读键（白名单：`SettingsKeys.plainReadableKeys`）。
  ///
  /// 空串 = 清除（视为未配置）。用于天气数据主机 / 预设城市等用户自设项；
  /// 与 `setApiKey`（凭证类）分工，本命令不碰任何凭证。
  Future<UserCommandResult> setSetting(Command cmd) async {
    final key = cmd.payload['key'];
    if (key is! String || key.trim().isEmpty) {
      return UserCommandResult.failure(
        'MISSING_ARGUMENT',
        '缺少 key',
        suggestion: '可选键：${SettingsKeys.plainReadableKeys.join(' / ')}',
      );
    }
    final name = key.trim();
    if (!SettingsKeys.plainReadableKeys.contains(name)) {
      return UserCommandResult.failure(
        'INVALID_ARGUMENT',
        '不可经此写入的键：$name',
        suggestion: '仅允许：${SettingsKeys.plainReadableKeys.join(' / ')}',
      );
    }
    final value = cmd.payload['value'];
    if (value is! String) {
      return UserCommandResult.failure('MISSING_ARGUMENT', '缺少 value（字符串）');
    }
    await repository.kv.settingsSet(<String, String>{name: value.trim()});
    return UserCommandResult.success(await repository.readSnapshot());
  }

  Future<UserCommandResult> _applySwitch(String name, bool enabled) async {
    await repository.kv.settingsSet({name: enabled ? '1' : '0'});
    return UserCommandResult.success(await repository.readSnapshot());
  }
}
