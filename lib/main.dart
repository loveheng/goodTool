library;

/// goodhub 服务端模板 · 最小壳：装配端口 → MCP HTTP 起服 → 前台常驻。
/// 新 app 起底三步：
/// 1. 实现/替换 lib/ports.dart 的 SettingsKv（换真实存储）；
/// 2. 写自己的领域网关（参照 lib/tools/*_tool.dart）+ 在 lib/tool_face_assembly.dart 登记；
/// 3. 在 tool_face_assembly.dart 里替换/扩充工具面（HTTP 与 Binder 双通道共用）。
/// 验收：`node tool/mcp-bridge/e2e-check.mjs`（token 见控制台日志）。
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'mcp/settings_kv.dart';
import 'ports.dart';
import 'service/foreground_task_init.dart';
import 'service/mcp_controller.dart';
import 'tool_face_assembly.dart';

void main() {
  runApp(const _TemplateApp());
}

class _TemplateApp extends StatelessWidget {
  const _TemplateApp();

  @override
  Widget build(BuildContext context) {
    // 前台服务就绪后由回调装配 MCP 总控（UI 仅承载生命周期，无业务页面）
    return WithForegroundTask(
      child: MaterialApp(
        title: 'good_template',
        theme: ThemeData(useMaterial3: true),
        home: const _BootPage(),
      ),
    );
  }
}

class _BootPage extends StatefulWidget {
  const _BootPage();

  @override
  State<_BootPage> createState() => _BootPageState();
}

class _BootPageState extends State<_BootPage> {
  String _status = '装配中…';

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    // 1) 端口装配：KV 内存实现（真实 app 换 sqlite/文件实现）
    final SettingsKv kv = InMemoryKv();

    // 2) MCP 总控：token/开关走 KV，工具面工厂注入业务。
    //    工具面（math_utility / geo 领域网关）收口在 tool_face_assembly.dart，
    //    与 Binder 生产通道共用同一份装配；当前能力全 R 档，故无写命令需登记
    //    （W 档落地时在此登记 CommandGateway 并注入装配工厂）。
    final controller = McpController(
      kv: kv,
      toolFaceFactory: () => buildDefaultToolFace(kv: kv),
    );
    await controller.regenerateToken();

    // 4) 前台服务保活（Doze 下 MCP 应答须持 CPU 键+Wi-Fi 键；VM/未就绪仅 HTTP）
    try {
      await ensureForegroundTaskInit();
      await FlutterForegroundTask.startService(
        serviceTypes: [ForegroundServiceTypes.dataSync],
        notificationTitle: 'good_template · MCP 服务运行中',
        notificationText: '仅本机回环；桌面 adb reverse tcp:8765 tcp:8765',
      );
    } catch (_) {
      // DEGRADE: [fg_unavailable] 前台服务不可用（VM 测试/平台未就绪）——仅 HTTP 无保活
    }

    // 5) HTTP 回环起服 + 冷启动恢复
    final error = await controller.enable();
    debugPrint('[good_template] MCP endpoint: ${controller.endpoint}');
    debugPrint('[good_template] token: ${controller.token}');
    setState(() {
      _status = error == null
          ? 'MCP 已起服：${controller.endpoint}\ntoken: ${controller.token}'
          : '起服失败: $error';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_status, textAlign: TextAlign.center),
        ),
      ),
    );
  }
}
