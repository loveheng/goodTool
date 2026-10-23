library;

import 'package:flutter/services.dart';

import '../mcp/secret_store.dart';

/// 与 Kotlin 侧 `SecretStoreChannel.kt` 保持一致的通道名（勿单方改动）。
const MethodChannel kSecretStoreChannel =
    MethodChannel('com.goodhub.goodtools/secret_store');

/// 凭证安全存储的**平台实现**（ui-console U5 收尾，替掉内存缺省）。
///
/// Android 侧：Keystore 持 AES-256-GCM 密钥（不可导出），密文落专用
/// SharedPreferences——**进程级存储，跨 isolate 可见**：UI 主 isolate 写的 Key，
/// Binder 生产 isolate 的 Agent 解密后同值（修掉内存实现的「重启失位 + 跨
/// isolate 不可见」两缺陷，`docs/project/index.md` 架构债 #1 据此结项）。
///
/// 装配面不变：构造形状与 `InMemorySecretStore()` 一致（const 无参），
/// `SecretAwareKv` / 各 Provider 无感。
///
/// 失败语义（standards §1.2 fail-closed）：平台异常一律透出
/// [SecretStoreException]，**不吞**——读取方（高德/和风 Provider）按存储故障
/// 上抛，动作返机器码，用户可观测、可重试（重写 Key 即覆盖修复）。
class KeystoreSecretStore implements SecretStore {
  const KeystoreSecretStore([this._channel = kSecretStoreChannel]);

  /// 平台通道（可注入：headless 单测用 mock messenger，生产用默认通道）。
  final MethodChannel _channel;

  @override
  Future<String?> read(String key) =>
      _invoke<String?>('read', <String, String>{'key': key});

  @override
  Future<void> write(String key, String value) async {
    await _invoke<Object?>('write', <String, String>{'key': key, 'value': value});
  }

  @override
  Future<void> delete(String key) =>
      _invoke<Object?>('delete', <String, String>{'key': key});

  Future<T?> _invoke<T>(String method, Map<String, String> args) async {
    try {
      return await _channel.invokeMethod<T>(method, args);
    } on MissingPluginException catch (e) {
      // 无平台引擎（如 headless 单测环境）：故障可观测，不降级为空存储。
      throw SecretStoreException(
        SecretStoreErr.unavailable,
        '凭证安全存储通道未注册（当前运行环境无平台引擎）：${e.message}',
      );
    } on PlatformException catch (e) {
      throw SecretStoreException(
        e.code,
        '凭证安全存储平台失败：${e.message ?? e.code}',
      );
    }
  }
}
