library;

import '../mcp/secret_store.dart';

/// 内存凭证存储：**不落盘**。
///
/// 历史缺省（Keystore 平台通道接线前的唯一安全实现）：凭证绝不落明文
/// `SharedPreferences`（standards §6.1），进程重启失位但不以明文留痕。
///
/// **现状（U5 收尾后）**：生产装配已换 `KeystoreSecretStore`（Keystore 持密钥、
/// 密文跨 isolate 可见）；本类保留为 **headless 单测替身**——测试需要可断言的
/// 进程内凭证存储，且不得引入平台通道依赖。
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
