library;

/// 模板端口默认实现：新 app 起步可直接用，接真实存储时替换。
/// - [InMemoryKv]：SettingsKv 端口的内存实现（服务端常驻进程够用；
///   需持久化时换成 sqlite/文件实现，签名同形即可）。
/// - 工具面：见 lib/tool_face_assembly.dart（领域网关装配收口，HTTP 与 Binder 双通道共用）。
import '../mcp/settings_kv.dart';

/// 内存 KV：总控 token/开关持久化端口的最小实现。
class InMemoryKv implements SettingsKv {
  final Map<String, String> _store = {};

  @override
  Future<String?> settingsGet(String key) async => _store[key];

  @override
  Future<void> settingsSet(Map<String, String> values) async =>
      _store.addAll(values);
}
