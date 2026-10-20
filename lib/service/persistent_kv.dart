library;

import 'package:shared_preferences/shared_preferences.dart';

import '../mcp/secret_store.dart';
import '../mcp/settings_kv.dart';
import '../mcp/settings_keys.dart';

/// `SharedPreferences` 持久化实现（**非凭证**键）。
///
/// 键值表实现（`SettingsKv` 端口），落盘原子由插件保证；**只承载普通设置**
/// （token、开关、订阅列表、身份画像）——凭证禁入（standards §6.1）。
class SharedPrefsKv implements SettingsKv {
  SharedPrefsKv(this._prefs);

  final SharedPreferences _prefs;

  /// 打开（异步；装配期 await 一次即得持久化实例）。
  static Future<SharedPrefsKv> open() async =>
      SharedPrefsKv(await SharedPreferences.getInstance());

  @override
  Future<String?> settingsGet(String key) async => _prefs.getString(key);

  @override
  Future<void> settingsSet(Map<String, String> values) async {
    for (final entry in values.entries) {
      await _prefs.setString(entry.key, entry.value);
    }
  }
}

/// 组合 KV：**凭证键分流到 [SecretStore]**，其余键走持久化 [SettingsKv]。
///
/// 装配层只装配本类一处，调用方（高德/和风 Provider、设置 Actor、总控）**无感**——
/// 它们仍只认 `SettingsKv` 端口，不需要知道凭证与普通设置的区别。
class SecretAwareKv implements SettingsKv {
  SecretAwareKv({
    required this.plain,
    required this.secrets,
    this.secretKeys = SettingsKeys.credentialKeys,
  });

  /// 普通设置存储（持久化）。
  final SettingsKv plain;

  /// 凭证存储（系统安全存储抽象）。
  final SecretStore secrets;

  /// 走凭证通道的键（默认 = 凭证类键）。
  final List<String> secretKeys;

  /// 某键是否走凭证通道。
  bool isSecret(String key) => secretKeys.contains(key);

  @override
  Future<String?> settingsGet(String key) async {
    if (isSecret(key)) return secrets.read(key);
    return plain.settingsGet(key);
  }

  @override
  Future<void> settingsSet(Map<String, String> values) async {
    final plainValues = <String, String>{};
    for (final entry in values.entries) {
      if (isSecret(entry.key)) {
        if (entry.value.isEmpty) {
          await secrets.delete(entry.key);
        } else {
          await secrets.write(entry.key, entry.value);
        }
      } else {
        plainValues[entry.key] = entry.value;
      }
    }
    if (plainValues.isNotEmpty) await plain.settingsSet(plainValues);
  }
}

/// **懒开**持久化 KV：装配保持**同步**，首次读/写时才 await `SharedPreferences`。
///
/// 存在的理由：Binder 生产通道的入口 `mcpBinderMain` 是**同步** `void`（无法
/// await），而 `SharedPreferences.getInstance()` 是异步——若在装配期 await，装配面
/// 就被迫异步。故把「打开」推迟到**首次访问**时（与本仓「Key 懒读」同一手法：
/// 装配同步、读取发生在请求发生时）。
///
/// 跨 isolate 生效：SharedPreferences 底层是**进程级**存储，MainActivity 主 isolate
/// 与 Binder isolate 打开的是同一份数据——故 UI 侧写入的设置对生产通道可见。
class LazySharedPrefsKv implements SettingsKv {
  LazySharedPrefsKv();

  Future<SharedPreferences>? _prefs;

  /// 打开（幂等；并发首访共享同一个 Future）。
  Future<SharedPreferences> _open() => _prefs ??= SharedPreferences.getInstance();

  @override
  Future<String?> settingsGet(String key) async =>
      (await _open()).getString(key);

  @override
  Future<void> settingsSet(Map<String, String> values) async {
    final prefs = await _open();
    for (final entry in values.entries) {
      await prefs.setString(entry.key, entry.value);
    }
  }
}
