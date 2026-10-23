import 'dart:math';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../mcp/mcp_server.dart';
import '../mcp/settings_kv.dart';
import '../mcp/settings_keys.dart';
import '../mcp/tool_face.dart';
import 'http_transport.dart';
import '../update/remote_config_store.dart';
import 'foreground_task_init.dart';

/// MCP 服务总控（抄改自拾贝 mcp_controller，§12）：token 与开关持久化 + 内嵌 HTTP server。
///
/// 暴露面口径（2026-10-15 拍板，schedule-app §11「MCP 暴露面」行）：生产通道 =
/// Binder 宿主进程内嵌入（mcp_binder_entrypoint，不经本控）；本控的 HTTP 服务
/// 仅绑 127.0.0.1 回环供 adb reverse 内部调试——不广播 mDNS、不展示 LAN 地址。
/// token/开关走 app_settings KV（`mcp_token`/`mcp_enabled` 为内部键，不经
/// update_settings 命令白名单）；前台服务保活（Doze 下持 CPU 锁+Wi-Fi 锁，
/// 见 foreground_task_init）。
class McpController extends ChangeNotifier {
  McpController({required this.kv, required this.toolFaceFactory});

  /// KV 持久化端口（拾光侧由 Repository 隐式实现，走 app_settings 表）。
  final SettingsKv kv;

  /// 工具面工厂（宿主装配业务工具面 + 天气等后端；内核不沾 Repository）。
  final McpToolFace Function() toolFaceFactory;

  /// 「建议用户改设置」广播通道（app UI 监听弹提示，入口见 [pushSuggestion]）。
  final StreamController<Map<String, Object?>> _suggestionController =
      StreamController<Map<String, Object?>>.broadcast();
  Stream<Map<String, Object?>> get suggestionStream => _suggestionController.stream;

  /// 宿主侧推送「建议用户改设置」（App UI 监听 [suggestionStream] 弹提示）。
  ///
  /// **S8 收尾后**：内核不再按工具名嗅探业务语义（原 `suggest_user_setting`
  /// 特例已删——工具面无该工具，它只会静默失效）。建议通道改由宿主/工具面
  /// 显式调用本方法，内核保持业务无关。
  void pushSuggestion(Map<String, Object?> args) {
    if (!_suggestionController.isClosed) _suggestionController.add(args);
  }

  static const defaultPort = 8765;

  /// app_settings 内部键（服务自身状态，非用户设置项）。
  static const _keyToken = 'mcp_token';
  static const _keyEnabled = 'mcp_enabled';

  /// 用户身份画像键（`SettingsKeys` 单一真相源；用户自设，Agent 无权写）。
  static const _keyIdentityPrompt = SettingsKeys.identityPrompt;

  /// 工具调用事件（代理内核 `McpServer.onCall`）——UI 侧订阅此流渲染实时调用流水。
  ///
  /// 本控**持有**该广播流并转发内核事件：内核 server 在 `enable()` 时才建、
  /// `disable()` 时即毁，若直接把 `_server?.onCall` 抛给订阅者，订阅会随
  /// server 重建而断流。故由本控做一层稳定代理（standards §7.1 成对生命周期）。
  final StreamController<McpCallEvent> _callEvents =
      StreamController<McpCallEvent>.broadcast();
  StreamSubscription<McpCallEvent>? _callEventSub;

  /// 工具调用事件流（UI 经 `lib/ui_ports` 订阅；类型化对象，非文本信封）。
  Stream<McpCallEvent> get callEvents => _callEvents.stream;

  McpServer? _server;
  HttpTransport? _transport;
  String? _token;
  String? _lastError;

  bool get running => _transport?.running ?? false;
  int get port => _transport?.port ?? defaultPort;
  String? get token => _token;
  String? get lastError => _lastError;

  /// 调试端点（仅回环可达；桌面经 `adb reverse tcp:8765 tcp:8765` 接入）。
  String get endpoint => 'http://127.0.0.1:$defaultPort/mcp';

  /// 冷启动装配：读/生成 token，并按上次开关状态自动恢复服务。
  Future<void> restoreIfNeeded() async {
    _token = await kv.settingsGet(_keyToken);
    if (_token == null || _token!.isEmpty) {
      _token = _generateToken();
      await kv.settingsSet({_keyToken: _token!});
    }
    if ((await kv.settingsGet(_keyEnabled)) != '1') return;
    final error = await enable();
    if (error != null) {
      debugPrint('[MCP] 冷启动自动恢复失败: $error');
    }
  }

  Future<void> regenerateToken() async {
    _token = _generateToken();
    await kv.settingsSet({_keyToken: _token!});
    notifyListeners();
  }

  String _generateToken() {
    final rnd = Random.secure();
    return List.generate(24, (_) => rnd.nextInt(16).toRadixString(16)).join();
  }

  /// 打开 MCP 服务。返回 null 表示成功，否则为错误信息。
  Future<String?> enable() async {
    _lastError = null;
    try {
      // 前台服务保活（Doze 下 MCP 应答须持 CPU/Wi-Fi 锁，见 foreground_task_init）；
      // VM 测试/平台未就绪时跳过，仅启 HTTP（fail-open，不阻断服务）。
      try {
        await ensureForegroundTaskInit();
        // startService **不阻塞装配链**：保活服务与 HTTP 就绪无依赖，ColorOS 实测
        // 该系统往返可拖 5s+（boot-timing 实证，曾让启动页「装配中」多等 5 秒）——
        // 页面先进，服务后台补启；失败照旧 [DEGRADE] 透出，不静默。
        unawaited(() async {
          try {
            await FlutterForegroundTask.startService(
              serviceTypes: [ForegroundServiceTypes.dataSync],
              notificationTitle: 'goodTools · MCP 服务运行中',
              notificationText:
                  '仅本机回环（内部调试）；桌面先 adb reverse tcp:$defaultPort tcp:$defaultPort',
            );
          } catch (e) {
            // DEGRADE: [fg_unavailable] 前台服务不可用（VM 测试/平台未就绪）——仅 HTTP 无保活
            debugPrint('[DEGRADE][fg_unavailable] 前台服务未启动: $e');
          }
        }());
      } catch (e) {
        // DEGRADE: [fg_unavailable] 前台服务不可用（VM 测试/平台未就绪）——仅 HTTP 无保活
        debugPrint('[DEGRADE][fg_unavailable] 前台服务未启动: $e');
      }
      _server ??= McpServer(
        toolFace: toolFaceFactory(),
        tokenProvider: () => _token,
        // 系统提示词热更入口：远程下发的 mcpInstructions 可覆盖内置政策精华；
        // 用户自填身份画像（identity_prompt）始终拼接待尊重（即配即用）。
        instructionsProvider: () async {
          final remote =
              RemoteConfigStore.instance.current.mcpInstructions;
          final base = remote != null && remote.trim().isNotEmpty
              ? remote.trim()
              : McpServer.builtinInstructions;
          final prompt = await kv.settingsGet(_keyIdentityPrompt);
          if (prompt != null && prompt.trim().isNotEmpty) {
            return '$base\n\n'
                '【用户身份画像】（由用户在 app 内填写，描述其自身身份与处境，排程时务必尊重）\n$prompt';
          }
          return base;
        },
      );
      _transport ??= HttpTransport(server: _server!);
      // 转发内核调用事件到本控的稳定流——server 重建时订阅不断流。
      _callEventSub ??= _server!.onCall.listen(_callEvents.add);
      await _transport!.start(port: defaultPort);
      // mDNS 广播随 2026-10-15 暴露面拍板退役（回环服务无需 LAN 发现，§11）。
      await kv.settingsSet({_keyEnabled: '1'});
    } catch (e) {
      _lastError = '$e';
      await _shutdown();
      notifyListeners();
      return _lastError;
    }
    notifyListeners();
    return null;
  }

  Future<void> disable() async {
    await _shutdown();
    await kv.settingsSet({_keyEnabled: '0'});
    notifyListeners();
  }

  Future<void> _shutdown() async {
    try {
      await _transport?.stop();
    } catch (_) {/* 服务可能已停止 */}
    _transport = null;
    // 释放内核资源（事件流控制器）并断开转发订阅（standards §7.1/§7.2 成对生命周期）。
    await _callEventSub?.cancel();
    _callEventSub = null;
    _server?.close();
    _server = null;
  }

}
