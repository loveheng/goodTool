// 工具面装配收口（S7b）：把各领域网关（当前 `math_utility` / `geo` / `weather` /
// `system_pim`）收口为 1 个 [McpToolFace]，供**两条通道共用同一份装配**——
// HTTP 调试通道（main.dart → McpController.toolFaceFactory）与
// Binder 生产通道（mcp_binder_entrypoint.dart → McpServer.toolFace）。
//
// 落点依据 standards §1：本文件是**装配件**（与 main.dart / ports.dart 同级，
// 可跨域 import `tools` + `service` + `mcp`），故 `buildXxxTool()` 不得在
// controller（service 出向不含 tools）内收口。双通道共用同一工厂，避免
// 「HTTP 一套工具、Binder 另一套」的双写漂移。
//
// 配置与端口一律**懒读 / 可注入**：Key 与预设城市从 [SettingsKv] 读（装配是同步的，
// 而读配置是异步的——推到请求发生时读，顺带让用户改配置即时生效）；真实源缺位时
// 走各端口的 fail-closed 默认实现（见各处注释）。
library;

import 'action/command_gateway.dart';
import 'mcp/calendar_provider.dart';
import 'mcp/category_tool_face.dart';
import 'mcp/geo_provider.dart';
import 'mcp/settings_kv.dart';
import 'mcp/tool_face.dart';
import 'mcp/weather_provider.dart';
import 'service/amap_http_provider.dart';
import 'service/calendar_actors.dart';
import 'service/ics_feed_provider.dart';
import 'service/marker_store.dart';
import 'service/weather.dart';
import 'tools/calendar/holiday_table.dart';
import 'tools/geo_tool.dart';
import 'tools/math/math_tool.dart';
import 'tools/system_pim_tool.dart';
import 'tools/weather_tool.dart';

/// app_settings 内部键：高德 Web 服务 Key。
///
/// 经 KV 懒读（非构造期读死）：装配面是同步的，而设置读取是异步的；顺带使
/// 用户在设置里补填 Key 后**无需重建工具面**即生效。
const String kAmapWebKey = 'amap_web_key';

/// app_settings 内部键：高德静态图数字签名密钥（可选，防 `INVALID_USER_SCODE`）。
const String kAmapSecret = 'amap_secret';

/// 装配本 app 的 MCP 工具面：[kv] 供各后端 Key 懒读；[sensor]/[http]/[weather]/
/// [markers] 可注入桩（单测）；[gateway] 为写门禁端口（缺省新建 —— W 档工具
/// 需要，调用方也可传入既有网关复用）。
///
/// **能力面（4 域 26 action，与 `docs/project/domain_gateway.md` 矩阵闭环）**：
/// `math_utility`(3) / `geo`(8) / `weather`(1) / `system_pim`(14，含 5 个 W 档)。
/// 前三者全 R 档；system_pim 的 W 档由本工厂登记 Actor 后经网关派发。
///
/// 已知缺口（显式 fail-closed，**不是假上线**）：`calendar_resolve_date` 与
/// `calendar_tz_convert` 分别待农历引擎（P2-③）与 `package:timezone`（P2-②）
/// 引入；`LocationSensorProvider` 真实实现（geolocator）未接入。
McpToolFace buildDefaultToolFace({
  required SettingsKv kv,
  LocationSensorProvider? sensor,
  GeoHttpProvider? http,
  WeatherProvider? weather,
  CalendarMarkerStore? markers,
  CommandGateway? gateway,
}) {
  // 定位/磁力计：真实平台实现（geolocator + 权限流）尚未接入，缺省走 Null 实现——
  // 它是 **fail-closed** 而非兜底：`geo_current` / `geo_compass` 返回
  // `PERMISSION_DENIED` 机器码并引导用户授权，不返回伪造坐标（standards §1.2）；
  // 天气回退链第 4 级同样止步于此，最终回 `ERR_LOCATION_UNAVAILABLE`。
  final sensors = sensor ?? const NullLocationSensorProvider();
  final amap = http ?? AmapHttpProvider(() => kv.settingsGet(kAmapWebKey));
  final wx = weather ?? QWeatherProvider(kv, sensor: sensors);

  // 日历域：真实源（ICS 订阅 + 标记存储）+ 写门禁 Actor 登记。
  // InMemoryMarkerStore 同时实现读端口与写端口，故可直接喂给两侧。
  final writeGateway = gateway ?? CommandGateway();
  final markerStore = markers ?? InMemoryMarkerStore();
  final markerWriter = markers is CalendarMarkerWriter
      ? markers as CalendarMarkerWriter
      : markerStore as CalendarMarkerWriter;
  final ics = IcsFeedProvider(kv);
  registerCalendarActors(
    writeGateway,
    kv: kv,
    markers: markerWriter,
    feeds: ics,
  );

  return CategoryToolFace(<CategoryTool>[
    buildMathTool(),
    buildGeoTool(
      sensors,
      amap,
      webKeyReader: () => kv.settingsGet(kAmapWebKey),
      secretReader: () => kv.settingsGet(kAmapSecret),
    ),
    buildWeatherTool(wx),
    buildSystemPimTool(
      writeGateway,
      markers: markerStore,
      feeds: ics,
      holidays: cnHolidayBundled,
    ),
  ]);
}

/// 日历 W 档命令（供宿主/UI 层引用命令名；门禁以 action 名查找）。
const Set<String> calendarWriteActions = <String>{
  'calendar_subscribe',
  'calendar_unsubscribe',
  'calendar_refresh',
  'calendar_marker_add',
  'calendar_marker_delete',
};
