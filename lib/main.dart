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
import 'mcp/pii_mask.dart';
import 'mcp/settings_keys.dart';
// Binder 后台 entrypoint 纳入编译根（import 闭包）：它不被 UI 引用，若不 import
// 则 kernel_blob 不含该库，headless 引擎 executeDartEntrypoint 报
// Dart_LookupLibrary not found → "Dart entrypoint 超时"（真机实证）。
// ignore: unused_import
import 'mcp_binder_entrypoint.dart';
import 'repository/favorite_repository.dart';
import 'repository/marker_repository.dart';
import 'repository/settings_repository.dart';
import 'service/amap_http_provider.dart';
import 'service/composite_calendar_provider.dart';
import 'service/favorite_place_store.dart';
import 'service/geo_favorite_actors.dart';
import 'service/geo_last_location_actor.dart';
import 'service/ics_feed_provider.dart';
import 'tools/calendar/ics_holiday_provider.dart';
import 'service/keystore_secret_store.dart';
import 'service/marker_store.dart';
import 'service/mcp_controller.dart';
import 'service/persistent_kv.dart';
import 'service/settings_actors.dart';
import 'service/system_calendar_port.dart';
import 'service/system_location_sensor.dart';
import 'service/weather.dart';
import 'service/weather_city_store.dart';
import 'service/weather_city_actors.dart';
import 'repository/weather_city_repository.dart';
import 'tool_face_assembly.dart';
import 'ui/calculator_page.dart';
import 'ui/calendar_page.dart';
import 'ui/capabilities_page.dart';
import 'ui/dashboard_page.dart';
import 'ui/geo_page.dart';
import 'ui/home_shell.dart';
import 'ui/settings_page.dart';
import 'ui/theme.dart';
import 'ui/weather_page.dart';
import 'ui_ports/calculator_port.dart';
import 'ui_ports/calendar_port.dart';
import 'ui_ports/draft_port.dart';
import 'ui_ports/geo_lbs_port.dart';
import 'ui_ports/geo_last_location_port.dart';
import 'ui_ports/settings_port.dart';
import 'ui_ports/status_port.dart';
import 'ui_ports/weather_port.dart';

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
  ///
  /// 逐段计时打点：启动卡「装配中…」时跑一次 logcat 即可定位慢点
  /// （grep "[boot-timing]"）。
  static Future<_AppScope> _assemble() async {
    final sw = Stopwatch()..start();
    void mark(String step) =>
        debugPrint('[boot-timing] $step: ${sw.elapsedMilliseconds}ms');
    // ① 存储：普通设置持久化，凭证走安全存储抽象（Keystore 持密钥、密文落专用
    // SharedPreferences——进程级、跨 isolate 可见，重启不丢、零明文留痕）。
    final plain = await SharedPrefsKv.open();
    mark('SharedPreferences.open');
    final kv = SecretAwareKv(
      plain: plain,
      secrets: const KeystoreSecretStore(),
    );
    final markerStore = await SharedPrefsMarkerStore.open();
    mark('MarkerStore.open');
    final favoriteStore = await SharedPrefsFavoritePlaceStore.open();
    mark('FavoritePlaceStore.open');
    final weatherCityStore = await SharedPrefsWeatherCityStore.open();
    mark('WeatherCityStore.open');

    // ② 日历合并源：ICS 订阅 + 系统日历（UI 与工具面**共用同一实例**）；
    // 脱敏开关态经 KV 注入合并源（U12a）——两路（ICS/系统）同开关语义。
    final feeds = CompositeCalendarProvider(
      IcsFeedProvider(kv),
      system: const MethodChannelSystemCalendarPort(),
      maskPiiEnabled: () async =>
          piiMaskEnabledBy(await kv.settingsGet(SettingsKeys.privacyMaskPii)),
    );

    // ②½ 节假日来源：ICS 驱动（订阅名称含『节假日』的源）。运行时预热（ICS 已本地
    // 缓存，快）后注入 UI 与命令面，二者共享同一实例与预热结果——不再写死内置表。
    final holidays = IcsHolidayProvider(feeds);
    await holidays.warm();

    // ③ 写门禁网关：用户设置 Actor 登记在**用户侧注册表**（AI 不可触达）。
    final gateway = CommandGateway();
    final repository = SettingsRepository(kv: kv);
    SettingsActors(repository: repository).register(gateway);
    // 收藏地点用户侧 Actor（AI 不可触达）：写端口只在此登记链持有。
    GeoFavoriteActors(
      store: favoriteStore,
      writer: favoriteStore,
    ).register(gateway);
    // 地图页「上次定位点」用户侧 Actor（AI 不可触达）：同上纪律。
    GeoLastLocationActor(kv: kv).register(gateway);
    // 天气多城市用户侧 Actor（AI 不可触达）：写端口只在此登记链持有。
    WeatherCityActors(
      store: weatherCityStore,
      writer: weatherCityStore,
    ).register(gateway);

    // ④ 工具面：与 Binder 生产通道共用同一装配（standards §3.3 S7 纪律）。
    // 天气源与工具面**共用同一 QWeatherProvider 实例**——否则 UI 与 Agent 各拉
    // 一次，频控与缓存分裂（同日历合并源纪律）。
    // 定位源同样单实例共用：MCP geo_current / 地图页「我的位置」/ 天气回退链
    // 末级 / 状态页就绪项四者同源（geolocator 系统定位，2026-10-22 接入）。
    final locationSensor = const SystemLocationSensorProvider();
    final weather = QWeatherProvider(
      kv,
      sensor: locationSensor,
    );
    // 高德 HTTP 源**共用同一实例**：MCP geo 工具面与 UI GeoLbsPort（地图页
    // 搜索/路线）同源出网——Key 懒读机制同一份，频控与失败口径同源。
    final amapHttp = AmapHttpProvider(() => kv.settingsGet(SettingsKeys.amapWebKey));
    final toolFace = buildDefaultToolFace(
      kv: kv,
      gateway: gateway,
      markers: markerStore,
      feeds: feeds,
      holidays: holidays,
      weather: weather,
      http: amapHttp,
      sensor: locationSensor,
    );

    // ⑤ 总控 + 前台服务保活 + HTTP 回环调试通道。
    final controller = McpController(
      kv: kv,
      toolFaceFactory: () => toolFace,
    );
    await controller.regenerateToken();
    mark('regenerateToken');
    // HTTP 调试服务**不随启动自启**（2026-10-20 产品决策）：MCP HTTP 仅调试用，
    // 入口收在设置页「关于」长按进的服务控制页（mcp_service_page.dart），手动开启；
    // 生产通道走 Binder 引擎（mcp_binder_entrypoint.dart），与本控无关。
    debugPrint('[boot-timing] total: ${sw.elapsedMilliseconds}ms');

    return _AppScope(
      controller: controller,
      settingsPort: SettingsPort(repository, gateway),
      draftPort: DraftPort(repository, gateway),
      lastLocationPort: GeoLastLocationPort(repository, gateway),
      statusPort: StatusPort(
        controller: controller,
        repository: repository,
        location: locationSensor,
        feeds: feeds,
      ),
      calculatorPort: const CalculatorPort(),
      geoLbsPort: GeoLbsPort(http: amapHttp),
      locationSensor: locationSensor,
      favoriteRepository: FavoriteRepository(store: favoriteStore),
      weatherCityRepository: WeatherCityRepository(store: weatherCityStore),
      calendarPort: CalendarPort(
        feeds: feeds,
        markers: MarkerRepository(store: markerStore),
        holidays: holidays,
      ),
      weatherPort: WeatherPort(weather),
      gateway: gateway,
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
      capabilities: CapabilitiesPage(
        pages: <AppDomain, Widget>{
          AppDomain.calculator: CalculatorPage(port: scope.draftPort),
          AppDomain.geo: GeoPage(
            lbsPort: scope.geoLbsPort,
            favorites: scope.favoriteRepository,
            gateway: scope.gateway,
            locationSensor: scope.locationSensor,
            lastLocation: scope.lastLocationPort,
            weatherPort: scope.weatherPort,
          ),
          AppDomain.calendar: CalendarPage(port: scope.calendarPort),
          AppDomain.weather: WeatherPage(
            port: scope.weatherPort,
            cities: scope.weatherCityRepository,
            gateway: scope.gateway,
          ),
        },
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
    required this.draftPort,
    required this.lastLocationPort,
    required this.statusPort,
    required this.calculatorPort,
    required this.geoLbsPort,
    required this.locationSensor,
    required this.favoriteRepository,
    required this.weatherCityRepository,
    required this.calendarPort,
    required this.weatherPort,
    required this.gateway,
  });

  final McpController controller;
  final SettingsPort settingsPort;
  final DraftPort draftPort;

  /// 地图页「上次定位点」读/写适配（读经 Repository，写经网关用户侧）。
  final GeoLastLocationPort lastLocationPort;
  final StatusPort statusPort;
  final CalculatorPort calculatorPort;

  /// LBS 端口（地图页搜索/四模态路线，与 MCP geo 工具面共用同一 HTTP 源）。
  final GeoLbsPort geoLbsPort;

  /// 定位源（系统定位；地图页「我的位置」与 MCP geo_current 共用）。
  final LocationSensorProvider locationSensor;

  /// 收藏地点只读聚合（R5；写经 [gateway] 用户侧注册表）。
  final FavoriteRepository favoriteRepository;

  /// 天气多城市只读聚合（R5；增删经 [gateway] 用户侧注册表）。
  final WeatherCityRepository weatherCityRepository;
  final CalendarPort calendarPort;
  final WeatherPort weatherPort;

  /// 写门禁网关（用户侧注册表：设置 + 收藏地点，AI 不可触达）。
  final CommandGateway gateway;
}
