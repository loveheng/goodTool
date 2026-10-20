library;

/// goodTools 控制台入口：**双前端之一（人消费端）**。
///
/// 与 MCP 工具面（LLM 消费端）**并列共享同一内核**：
/// 纯 Dart 内核是唯一计算真相源，UI 经 `lib/ui_ports` 取类型化对象、
/// 经 `lib/action` 的 `CommandGateway` 写——UI **不**消费 MCP 文本信封（守 R2 / R4）。
///
/// 装配纪律（standards §1）：本文件是**装配件**，只做装配，不含业务逻辑。
/// 工具面收口在 `lib/tool_face_assembly.dart`（HTTP 调试通道与 Binder 生产通道共用）。
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'action/command_gateway.dart';
import 'mcp/geo_provider.dart';
import 'repository/marker_repository.dart';
import 'repository/settings_repository.dart';
import 'service/composite_calendar_provider.dart';
import 'service/ics_feed_provider.dart';
import 'service/in_memory_secret_store.dart';
import 'service/marker_store.dart';
import 'service/mcp_controller.dart';
import 'service/persistent_kv.dart';
import 'service/settings_actors.dart';
import 'service/system_calendar_port.dart';
import 'tool_face_assembly.dart';
import 'ui/dashboard_page.dart';
import 'ui/home_shell.dart';
import 'ui/sandbox_page.dart';
import 'ui/settings_page.dart';
import 'ui/theme.dart';
import 'ui_ports/calculator_port.dart';
import 'ui_ports/calendar_port.dart';
import 'ui_ports/geo_port.dart';
import 'ui_ports/settings_port.dart';
import 'ui_ports/status_port.dart';

void main() {
  runApp(const GoodToolsApp());
}

/// 应用根（暗色优先；M3）。
class GoodToolsApp extends StatelessWidget {
  const GoodToolsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return WithForegroundTask(
      child: MaterialApp(
        title: 'goodTools',
        theme: buildAppTheme(brightness: Brightness.light),
        darkTheme: buildAppTheme(brightness: Brightness.dark),
        themeMode: ThemeMode.dark,
        home: const _BootPage(),
      ),
    );
  }
}

/// 启动页：完成装配后切到控制台外壳。
///
/// 装配期做三件事：① 打开持久化存储（KV + 标记 store）；② 建日历合并源与写门禁
/// 网关（**与工具面共用同一实例**——否则 UI 与 Agent 各拉一次、频控与缓存分裂）；
/// ③ 起 HTTP 回环调试通道 + 前台服务保活。
class _BootPage extends StatefulWidget {
  const _BootPage();

  @override
  State<_BootPage> createState() => _BootPageState();
}

class _BootPageState extends State<_BootPage> {
  _AppScope? _scope;
  String? _error;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    try {
      final scope = await _assemble();
      if (!mounted) return;
      setState(() => _scope = scope);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    }
  }

  /// 装配全链（装配件职责，不含业务逻辑）。
  static Future<_AppScope> _assemble() async {
    // ① 存储：普通设置持久化，凭证走安全存储抽象（不落明文）。
    final plain = await SharedPrefsKv.open();
    final kv = SecretAwareKv(
      plain: plain,
      secrets: InMemorySecretStore(),
    );
    final markerStore = await SharedPrefsMarkerStore.open();

    // ② 日历合并源：ICS 订阅 + 系统日历（UI 与工具面**共用同一实例**）。
    final feeds = CompositeCalendarProvider(
      IcsFeedProvider(kv),
      system: const MethodChannelSystemCalendarPort(),
    );

    // ③ 写门禁网关：用户设置 Actor 登记在**用户侧注册表**（AI 不可触达）。
    final gateway = CommandGateway();
    final repository = SettingsRepository(kv: kv);
    SettingsActors(repository: repository).register(gateway);

    // ④ 工具面：与 Binder 生产通道共用同一装配（standards §3.3 S7 纪律）。
    final toolFace = buildDefaultToolFace(
      kv: kv,
      gateway: gateway,
      markers: markerStore,
      feeds: feeds,
    );

    // ⑤ 总控 + 前台服务保活 + HTTP 回环调试通道。
    final controller = McpController(
      kv: kv,
      toolFaceFactory: () => toolFace,
    );
    await controller.regenerateToken();
    await controller.enable();
    debugPrint('[goodTools] MCP endpoint: ${controller.endpoint}');

    return _AppScope(
      controller: controller,
      settingsPort: SettingsPort(repository, gateway),
      statusPort: StatusPort(
        controller: controller,
        repository: repository,
        location: const NullLocationSensorProvider(),
        feeds: feeds,
      ),
      calculatorPort: const CalculatorPort(),
      geoPort: const GeoPort(),
      calendarPort: CalendarPort(
        feeds: feeds,
        markers: MarkerRepository(store: markerStore),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scope = _scope;
    if (scope == null) {
      return Scaffold(
        body: Center(
          child: _error == null
              ? const Text('装配中…')
              : Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('装配失败：$_error', textAlign: TextAlign.center),
                ),
        ),
      );
    }
    return HomeShell(
      dashboard: DashboardPage(port: scope.statusPort),
      sandbox: SandboxPage(
        calculator: scope.calculatorPort,
        geo: scope.geoPort,
        calendar: scope.calendarPort,
      ),
      settings: SettingsPage(
        port: scope.settingsPort,
        controller: scope.controller,
      ),
    );
  }
}

/// 装配产物（UI 侧依赖的**只读**容器）。
///
/// 持端口而非具体实现——页面不直连 KV / store / Provider（R5）。
class _AppScope {
  const _AppScope({
    required this.controller,
    required this.settingsPort,
    required this.statusPort,
    required this.calculatorPort,
    required this.geoPort,
    required this.calendarPort,
  });

  final McpController controller;
  final SettingsPort settingsPort;
  final StatusPort statusPort;
  final CalculatorPort calculatorPort;
  final GeoPort geoPort;
  final CalendarPort calendarPort;
}
