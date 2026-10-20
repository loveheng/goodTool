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

/// [SecretStore] 平台失败的机器码（standards §1.2 fail-closed 透出）。
class SecretStoreErr {
  const SecretStoreErr._();

  /// 通道未注册（无平台引擎 / 非 Android 运行环境）。
  static const String unavailable = 'unavailable';
}

/// 凭证安全存储故障（fail-closed）：读取方按「存储不可用」处理，
/// **绝不**被吞成 null 假装「未配置」——那会让用户以为没填过 Key。
class SecretStoreException implements Exception {
  const SecretStoreException(this.code, this.message);

  /// 机器码（[SecretStoreErr.unavailable] 或平台侧 code，如 `KEYSTORE_ERROR`）。
  final String code;

  /// 人可读原因（禁含凭证明文）。
  final String message;

  @override
  String toString() => 'SecretStoreException($code): $message';
}
