---
status: active
updated: 2026-10-20
---

# goodTools · 轻量地理与地图能力（高德 Web 服务 + 传感器）

## 范围

定位为**轻量级位置查询、路线推演与方向指引引擎**（移动端无头壳，UI 仅做轻量渲染，业务逻辑在纯 Dart 内核，不强绑沉重的高德原生 3D 地图 SDK）。

- 基于设备定位传感器、高德 Web 服务 REST API 与纯算法坐标转换，向 MCP 客户端及移动端 UI 提供定位、选点、正/逆地理编码、多模态路径规划、静态地图快照与指南针能力；
- 遵循产品架构红线（arch-guard R4 无头约束）：所有高德 HTTP 调用经抽象端口注入，内核不依赖 Flutter UI。

## 坐标系规范与转换

- GPS 原生输出为 **WGS-84**；高德地图所有检索、路线规划与静态图切片强制使用 **GCJ-02（火星坐标）**。
- **强制归一化**：MCP 工具出入参默认明确携带 `coordSystem: "WGS84" | "GCJ02"`；调用高德 API 前，底层内核自动无损转换为 GCJ-02，杜绝百米定位漂移。
- 内核集成纯 Dart 版 WGS-84 ↔ GCJ-02 / BD-09 离线互转算法（无需网络，单测 100% 确定性）。

## 能力清单

- **当前定位**：读取传感器经纬度、精度（Accuracy）与海拔，按需输出指定坐标系。
- **地理编码（正向 / 逆向 / POI 搜索）**：
  - 逆地理：经纬度 → 格式化地址、行政区划、周边代表性 POI；
  - 正向编码与搜索：地名/关键字 → 经纬度列表及建议地点（用于路线规划起终点输入）。
- **多模态路径规划（Route Planning）**：
  - 步行（walking）、骑行（bicycling）、驾车（driving）、公交跨区（transit）；
  - 输出：总耗时（秒）、总距离（米）、费用预估（打车/过路费）、关键转向步骤列表（Steps）。
- **静态地图切片（Static Map Snapshot）**：
  - 生成指定经纬度、缩放级别（Zoom）、标记点（Markers）或折线轨迹（Polyline）的高德静态地图图片 URL（供轻量移动端直接免 SDK 渲染展示）。
- **指南针与方位角**：
  - 磁力计航向角（0°~360°）、八方位名称（正北、西北等），经端口注入。

## MCP 工具面（形态）

| 工具 | 档 | 入参 | 出参 | 职责 |
|---|---|---|---|---|
| `geo_current` | R | `{coordSystem?: "WGS84"\|"GCJ02"}` | `{lat, lng, accuracy, coordSystem, timestamp}` | 获取设备当前绝对坐标 |
| `geo_geocode` | R | `{address, city?}` | `{results: [{lat, lng, formattedAddress, province, city, district}]}` | 地址/地名转坐标 |
| `geo_reverse` | R | `{lat, lng, coordSystem?}` | `{formattedAddress, province, city, district, town, poiName?}` | 坐标转详细地址与行政区 |
| `geo_search_poi` | R | `{keywords, city?, near?: {lat, lng}}` | `{pois: [{id, name, type, address, lat, lng, distance?}]}` | 周边或城市关键字 POI 检索 |
| `geo_route` | R | `{from: {lat, lng}, to: {lat, lng}, mode: "driving"\|"walking"\|"bicycling"\|"transit", strategy?, city?}` | `{durationSec, distanceMeters, taxiCost?, steps: [{instruction, distance, duration}]}` | 多模态路径规划与导航步步拆解；`mode=transit` 时 `city` 必填（缺则内核自动逆地理推导） |
| `geo_static_map` | R | `{center?: {lat, lng}, zoom?: int, size?: "width*height", markers?: [...], paths?: [...], autoFit?: bool, bounds?: {minLat,minLng,maxLat,maxLng}, secret?: string}` | `{url: string}` | 生成高德静态轻量切片预览图 URL；`paths` 自动 RDP 抽稀≤80 点防 414；`autoFit`/`bounds` 自动逆算 zoom；`secret` 触发 `sig` 签名 |
| `geo_compass` | R | — | `{heading: double, direction: string, accuracy: int}` | 获取磁力计方位角与八方位文字 |
| `geo_distance` | R | `{from: {lat, lng}, to: {lat, lng}, mode?: "straight"\|"road"}` | `{meters, durationSec?}` | 纯直线测距（Haversine）或道路测距 |

> 档位：均为 R（只读查询）。

## 实现要点

- **网络解耦与注入端口（arch-guard R4）**：
  - 内核定义 `GeoHttpProvider`（抽象 HTTP 请求）与 `LocationSensorProvider`（抽象 GPS 与磁力计硬件，见 `lib/mcp/geo_provider.dart`）；
  - 高德 Web API（REST）具体请求由外层 Service 实现并注入，确保测试可用 Mock 数据走通 100% 确定性单测。
- **纯 Dart 内核算法（无头可跑）**：
  - 坐标纠偏 WGS-84 ↔ GCJ-02 / BD-09：`lib/geo/coord_convert.dart`；
  - 高德静态图 URL 构建（自动归一化到 GCJ-02、RDP 抽稀、自适应视口）：`lib/geo/static_map_url.dart`；
  - 高德数字签名（Sig/MD5）：`lib/geo/amap_sign.dart`；
  - 轨迹抽稀（RDP）：`lib/geo/rdp.dart`。
- **高德 Web 服务 Key 治理（密钥成对）**：
  - 配置为成对：`amap_web_key`（Web 服务 Key）+ 可选 `amap_secret`（数字签名密钥），由用户在“设置”中配置（经 `CommandGateway` 存入私有配置表）；
  - 高德对 Web 服务（含静态图 `v3/staticmap`、搜索/地理编码接口）开启**数字签名（Sig）**校验时，请求须携带 `sig`，否则返回 `INVALID_USER_SCODE`（签名无效）导致无法出图；内核按高德规范（`amapSign`：参数名 ASCII 升序拼接 + secret → MD5 32 位小写）自动生成；
  - 未配置 Key 时：纯数学计算（WGS84/GCJ02 转换、Haversine 测距、RDP 抽稀、视口自适应）正常可用；依赖高德的接口返回机器可读错误 `ERR_AMAP_KEY_MISSING`，引导 UI 弹出配置卡片。
- **路径规划与 Polyline 压缩（RDP 抽稀）**：
  - 高德返回的长路径坐标串（`116.48,39.99;116.49,39.98...`）在核心层完成数据规整与抽稀；
  - 静态图 `paths` 拼接后 URL 受约 **2048 字符**限制，超长触发 HTTP 414；内核强制用**道格拉斯-普克算法（RDP）**抽稀，点数硬性卡在 **80 点以内**（见 `lib/geo/rdp.dart`），避免海量点阵灌入；
  - 同理由 LLM 侧只回关键拐点（Steps），避免 Token 浪费。
- **静态图自适应视口（Auto-bounding）**：
  - Agent 难以猜测 `zoom`：当传入 `paths` 或多 `markers` 且未显式给 `center`/`zoom` 时，内核按点集自动计算最小外接矩形（Bounding Box），逆算几何中心与最佳 `zoom`（3~17，留边距），确保起终点与轨迹完整入框（见 `lib/geo/static_map_url.dart` 的 `autoFit` / `bounds`）。
- **公交换乘（Transit）容错**：
  - 高德 `transit` 路径规划**强制要求** `city`（或跨城 `city1`/`city2`），缺省直接报 `10001`（参数缺失）；
  - `geo_route` 入参 `mode: "transit"` 时 `city` 为必填；若调用方未传，内核自动用缓存或调用 `geo_reverse` 由当前/起点坐标推导城市名填入，防止校验失败。

## 移动端轻量地图 UI 范式（Lightweight Map Inspector）

放弃引入包体积巨大的 Native 3D 地图 SDK，采用**“静态切片/轻量矢量底图 + 拖拽式抽屉（Draggable Bottom Sheet）”**的轻量方案：

```text
┌────────────────────────────────────────────────────────┐
│  goodTools · 地理与位置               [⚙️ 设置] [🧭 定位] │
├────────────────────────────────────────────────────────┤
│ ┌────────────────────────────────────────────────────┐ │
│ │                                                    │ │
│ │             [ 静态地图切片预览 / 路线高亮 ]           │ │
│ │             (由 geo_static_map 产出)               │ │
│ │                                                    │ │
│ │   [ 🧭 324° 西北 ] (指南针浮标悬浮于右上角)          │ │
│ └────────────────────────────────────────────────────┘ │
├────────────────────────────────────────────────────────┤
│                       ══ 拖拽手柄 ══                    │
│ 📍 当前: 科技园中一路 10 号 · 腾讯大厦附近               │
│                                                        │
│ [ 🚶 步行 12分 ]  [ 🚴 骑行 5分 ]  [ 🚗 驾车 4分 (约¥14) ] │
├────────────────────────────────────────────────────────┤
│ 路线规划向导 (Route Sheet):                             │
│ 起点: 我的位置                                         │
│ 终点: [ 🔍 搜索目的地 / 点击地图选点... ]               │
│                                                        │
│ 核心路段步骤:                                           │
│ 1. 沿科技园中一路向北步行 120 米                        │
│ 2. 右转进入深南大道辅道，步行 350 米                    │
│ 3. 到达目的地                                          │
└────────────────────────────────────────────────────────┘

```

* **交互细节**：
1. **免 SDK 轻量渲染**：使用高德 Static Map Web 服务生成路径预览图，内存占用少、包体积增加为 0；
2. **指南针胶囊悬浮**：指南针角度实时悬浮在地图区域一角，点击可展开全屏大刻度罗盘；
3. **单手抽屉交互**：下方面板可上下拖拽，折叠时仅展示当前地址与最快耗时，展开时完整浏览导航步骤与换乘明细。

## 隐私与安全（脱敏与权限）

- **权限治理**：精准定位（GPS）与磁力计依赖系统授权；缺权限时在 UI 显示轻量授权引导卡（不闪退）。
- **模糊定位模式**：开启时，对外暴露的 `lat, lng` 强制截断至小数点后 2 位（精度约 1.1 公里），且正向逆向编码结果仅保留至行政区（区/县级），隐藏精准门牌号与 POI。
- **脱敏策略**：MCP Agent 检索路线时，出参中的详细起点如涉及家庭住址，自动受全局 `PII_MASK_LOCATION` 规则覆盖。

## 落地验证 Checklist

- [ ] **坐标系互转**：验证 WGS-84 经纬度输入后转为 GCJ-02，高德地图切片无偏移。
- [ ] **高德 Key 缺省容错**：未配 Key 时调用 `geo_route` 返回明确 `ERR_AMAP_KEY_MISSING`，引导用户设置。
- [ ] **路线规划解耦**：传入经纬度起终点，能正确解析出驾车、步行耗时与关键步骤。
- [ ] **轻量静态切片**：根据规划步骤生成的 `geo_static_map` URL 可正常直接在 UI 图像容器中渲染。
- [ ] **指南针确定性**：无传感器硬件或模拟器测试时，能通过 Mock 注入航向角并正确判定八方位（如 `324°` 输出为 `西北`）。

## 相关文档

- 产品概述：[overview.md](overview.md)
- UI 开发规范：[../project/ui-design.md](../project/ui-design.md)
- 架构红线：项目根 `AGENTS.md`（arch-guard R1–R6）
- 功能落点：`docs/project/index.md`（域：地理/地图内核 → `lib/geo/`、`lib/mcp/geo_provider.dart`）
