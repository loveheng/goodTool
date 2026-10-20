library;

import '../mcp/secret_store.dart';

/// 内存凭证存储：**不落盘**。
///
/// 存在的理由：凭证绝不能落明文 `SharedPreferences`（standards §6.1），而
/// Android Keystore 平台通道尚未接线——本实现是**当前唯一安全**的缺省：
/// 进程重启后凭证失位（用户需重填），**不**以明文形式留痕。
///
/// 平台实现（Keystore 通道）接线后，替换本类即可，装配面无需改动。
class InMemorySecretStore implements SecretStore {
  final Map<String, String> _store = <String, String>{};

  @override
  Future<String?> read(String key) async => _store[key];

  @override
  Future<void> write(String key, String value) async {
    _store[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _store.remove(key);
  }
}
