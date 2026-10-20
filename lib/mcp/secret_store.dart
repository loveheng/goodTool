library;

/// 凭证**安全存储端口**（系统安全存储抽象，standards §6.1）。
///
/// 铁律：地图/天气 API Key 等凭证**严禁**落明文 `SharedPreferences`、严禁出现在
/// 日志与崩溃堆栈。内核只认本端口——具体实现（Android Keystore 平台通道等）
/// 由 service 层实现并经装配注入。
///
/// 与 [SettingsKv] 的分工：`SettingsKv` 承载普通设置（token、开关、订阅列表），
/// 凭证由本端口承载；`lib/service/persistent_kv.dart` 的组合实现负责分流。
abstract class SecretStore {
  /// 读凭证；不存在返回 null。
  Future<String?> read(String key);

  /// 写凭证（覆盖）。
  Future<void> write(String key, String value);

  /// 删除凭证。
  Future<void> delete(String key);
}
