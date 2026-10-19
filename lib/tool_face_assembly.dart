// 工具面装配收口（S7b）：把各领域网关（当前 `math_utility` / `geo`）收口为
// 1 个 [McpToolFace]，供**两条通道共用同一份装配**——
// HTTP 调试通道（main.dart → McpController.toolFaceFactory）与
// Binder 生产通道（mcp_binder_entrypoint.dart → McpServer.toolFace）。
//
// 落点依据 standards §1：本文件是**装配件**（与 main.dart / ports.dart 同级，
// 只持装配职责、不承载业务逻辑），故可跨域 import `tools` + `service` + `mcp`；
// 反之 `service`（McpController）不允许 import `tools`，装配不得下沉到 controller。
//
// 双通道共用同一工厂，避免「HTTP 一套工具、Binder 另一套」的双写漂移。
library;

import 'mcp/category_tool_face.dart';
import 'mcp/geo_provider.dart';
import 'mcp/settings_kv.dart';
import 'mcp/tool_face.dart';
import 'service/amap_http_provider.dart';
import 'tools/geo_tool.dart';
import 'tools/math/math_tool.dart';

/// app_settings 内部键：高德 Web 服务 Key。
///
/// 经 KV 懒读（非构造期读死）：装配面是同步的，而设置读取是异步的；顺带使
/// 用户在设置里补填 Key 后**无需重建工具面**即生效。
const String kAmapWebKey = 'amap_web_key';

/// app_settings 内部键：高德静态图数字签名密钥（可选，防 `INVALID_USER_SCODE`）。
const String kAmapSecret = 'amap_secret';

/// 装配本 app 的 MCP 工具面：[kv] 供高德 Key 懒读；[sensor]/[http] 可注入桩（单测）。
///
/// 现状能力面：`math_utility`（3 action，纯 Dart 零依赖）+ `geo`（8 action，
/// 经 [AmapHttpProvider] 出网）。二者**全 R 档**，故分类的写门禁端口传 null——
/// W 档子操作物理不可达（fail-closed，见 `CategoryTool.call`）。
McpToolFace buildDefaultToolFace({
  required SettingsKv kv,
  LocationSensorProvider? sensor,
  GeoHttpProvider? http,
}) {
  // 定位/磁力计：真实平台实现（geolocator + 权限流）尚未接入，缺省走 Null 实现——
  // 它是 **fail-closed** 而非兜底：`geo_current` / `geo_compass` 返回
  // `PERMISSION_DENIED` 机器码并引导用户授权，不返回伪造坐标（standards §1.2）。
  final sensors = sensor ?? const NullLocationSensorProvider();
  final amap = http ?? AmapHttpProvider(() => kv.settingsGet(kAmapWebKey));

  return CategoryToolFace(<CategoryTool>[
    buildMathTool(),
    buildGeoTool(
      sensors,
      amap,
      webKeyReader: () => kv.settingsGet(kAmapWebKey),
      secretReader: () => kv.settingsGet(kAmapSecret),
    ),
  ]);
}
