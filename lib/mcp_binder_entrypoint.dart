import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'mcp/mcp_server.dart';
import 'service/keystore_secret_store.dart';
import 'service/persistent_kv.dart';
import 'tool_face_assembly.dart';

/// 模板本地 Binder 插件后台入口（headless FlutterEngine，goodhub-local-plugin 终点）。
/// 自 shiguang mcp_binder_entrypoint 提取：装配换成本模板端口件（InMemoryKv +
/// buildDefaultToolFace），通道名/entrypoint 名随模板包名。
///
/// 部署点：goodhub 经 `bindService(BIND_AUTO_CREATE)` 拉起原生 `McpBinderService`
/// （android/app/src/main/kotlin/.../McpBinderService.kt），原生侧创建独立
/// FlutterEngine 执行本 entrypoint；本 isolate 持有独立 McpServer/存储，经
/// MethodChannel `goodtools/mcp_binder` 把 `call(json)` 转现有
/// [McpServer.handleJsonRpc]（协议无关，与 HTTP 版同一套 _dispatch）。
/// 模式照抄 goodshare/shiguang 范本（已验证）；goodhub 契约 thirdconnect.md §1.2.2。
///
/// 设计红线：
/// - Binder 走同签名 `signature` 权限，零端口、零 `X-Api-Key` → tokenProvider 恒 null。
/// - 本 isolate 与 MainActivity 主 isolate 互相独立（各自一套 McpServer/存储），
///   故 Binder 路径不依赖 app 是否在前台——满足「随调随起」。
/// - 不走主壳装配（那会起 HTTP 监听/前台服务/远程配置，Binder isolate 只要 MCP 内核）。
/// - **装配单一真相源**：工具面经 `tool_face_assembly.dart` 的
///   [buildDefaultToolFace] 装配，与 HTTP 通道（main.dart）**共用同一份**——
///   新增能力只改装配工厂，两通道同步生效（禁各自装配导致的能力漂移）。
///
/// F1 `_async`+onEvent 终帧切片（契约 thirdconnect.md §1.2.2）：tools/call 由原生侧
/// 立回 `{"_async":true}` 占位帧，dispatch 照旧同步返回完整 JSON-RPC 响应字符串，
/// 由原生 Result 回调经 `IMcpCallback.onEvent` 转发为同 id 终帧——本 isolate 不感知
/// 切片；dispatch 内任何异常经 MethodChannel error 回调由原生侧兜底成 error 终帧。
const _kChannel = 'goodtools/mcp_binder';

@pragma('vm:entry-point')
void mcpBinderMain() {
  // 后台 isolate 无 UI，但 MethodChannel 需要 ServicesBinding 初始化。
  WidgetsFlutterBinding.ensureInitialized();

  // 装配：持久化 KV（**懒开**——本入口是同步 `void`，无法 await，故首次访问时才开
  // SharedPreferences）+ 凭证走 SecretStore 端口 + 共用工具面装配（见 tool_face_assembly.dart）。
  //
  // 跨 isolate 生效：SharedPreferences 底层是进程级存储，主 isolate（App UI）写入的
  // 设置对本 isolate 可见——故 UI 侧配置的订阅源 / 开关对生产通道同样生效。
  // 凭证同此口径（U5 收尾）：Keystore 持密钥、密文落专用 SharedPreferences，
  // 本 isolate 与主 isolate 解密同值——UI 写的 Key 对 Agent 可见；缺凭证时
  // 后端动作 fail-closed 返机器码（ERR_*_KEY_MISSING）。
  final kv = SecretAwareKv(
    plain: LazySharedPrefsKv(),
    secrets: const KeystoreSecretStore(),
  );
  final server = McpServer(
    toolFace: buildDefaultToolFace(kv: kv),
    tokenProvider: () => null, // Binder 同签名零鉴权
  );

  final channel = MethodChannel(_kChannel);
  channel.setMethodCallHandler((call) async {
    switch (call.method) {
      case 'dispatch':
        // 同步 JSON-RPC 请求 → 响应字符串（原生侧 B1 per-call ≤5s 超时兜底）。
        return await server.handleJsonRpc(call.arguments as String);
      case 'hostCallbackReady':
        // 宿主已注册 IMcpCallback（registerCallback）。注册后原生侧对 tools/call 走
        // _async 切片（call 立回占位帧，dispatch 结果经 onEvent 转发终帧）；
        // 本 isolate 无反向请求/进度帧，仅作可观测标记。
        return null;
      default:
        throw PlatformException(code: 'not_implemented', message: call.method);
    }
  });

  // 通知原生侧引擎就绪，解除 McpBinderService.call 首调竞态等待。
  // 用 microtask 确保上面 handler 已注册后再发 ready。
  scheduleMicrotask(() => channel.invokeMethod<void>('ready'));
}
