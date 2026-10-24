---
status: active
updated: 2026-10-24
---

# goodTools · 轻量地理与地图能力（高德 Web 服务 + 传感器）

## 范围

定位为**轻量级位置查询、路线推演与方向指引引擎**（移动端无头壳，业务逻辑在纯 Dart 内核）。

- 基于设备定位传感器、高德 Web 服务 REST API 与纯算法坐标转换，向 MCP 客户端及移动端 UI 提供定位、选点、正/逆地理编码、多模态路径规划、静态地图快照与指南针能力；
- 遵循产品架构红线（arch-guard R4 无头约束）：所有高德 HTTP 调用经抽象端口注入，内核不依赖 Flutter UI。
- **地图渲染（2026-10-22 SSOT 再修正）**：交互式地图画布改用**纯 Dart 渲染引擎 `flutter_map`**（XYZ 瓦片源指向高德 `appmaptile` 标准矢量瓦片，GCJ-02 坐标系）+ 功能面板——零原生依赖、零 Key、零 Gradle 风险（AGP 9/Flutter 3.47 工具链免疫）；高德官方插件 `amap_flutter_map`（Native 3D SDK）已整体退役（decisions.md 2026-10-22 结构性替换）。静态切片方案（下）保留为 MCP 出图通道与瓦片不可用时的降级预览存档。

## 坐标系规范与转换

- GPS 原生输出为 **WGS-84**；高德地图所有检索、路线规划与静态图切片强制使用 **GCJ-02（火星坐标）**。
- **强制归一化**：MCP 工具出入参默认明确携带 `coordSystem: "WGS84" | "GCJ02"`；调用高德 API 前，底层内核自动无损转换为 GCJ-02，杜绝百米定位漂移。
- 内核集成纯 Dart 版 WGS-84 ↔ GCJ-02 / BD-09 离线互转算法（无需网络，单测 100% 确定性）。

## 能力清单

- **当前定位**：读取传感器经纬度、精度（Accuracy）与海拔，按需输出指定坐标系。2026-10-22 起经 geolocator 接入真实系统定位（`SystemLocationSensorProvider`，WGS-84 出参；`geo_current` MCP action 真实可用；`geo_compass` 磁力计仍 fail-closed）。
  - **分档回退（2026-10-23）**：高精度（GPS，12s）→ 低精度（网络，8s）→ 上次已知位置（仅采信 2 分钟内的新鲜读数）；三档全败才返回 null（fail-closed，不伪造坐标）。
  - **异常一律收敛为 null（2026-10-23 根因修正）**：geolocator 在系统定位开关关闭时抛 `LocationServiceDisabledException`、权限流程异常抛 `PermissionDeniedException`——旧实现只 catch `TimeoutException`，异常冒泡出端口后 UI 的 `await` 抛出、`setState` 不执行，「定位中…」永久挂起且相机停在硬编码初始中心（用户报「进地图定位原始起点」）。现口径：任何失败一律返 null 并打 `[LOC]` 日志保留原因。
- **地理编码（正向 / 逆向 / POI 搜索）**：
  - 逆地理：经纬度 → 格式化地址、行政区划、周边代表性 POI；
  - 正向编码与搜索：地名/关键字 → 经纬度列表及建议地点（用于路线规划起终点输入）。
- **多模态路径规划（Route Planning）**：
  - 步行（walking）、骑行（bicycling）、驾车（driving）、公交跨区（transit）；
  - 输出：总耗时（秒）、总距离（米）、费用预估（打车/过路费）、关键转向步骤列表（Steps）。
  - **默认起点 = 当前位置**（2026-10-22）：起点未设时，路线规划自动以定位结果（WGS-84 → GCJ-02 归一）兜底；路线段另有「当前位置」快捷 chip 显式设定。定位不可用 → 面板内提示检查权限/开关，不伪造坐标。
  - **进场自动定位**（2026-10-23）：进入地图子页面即自动取位并把相机 fit 到真实位置（首帧用占位中心，定位成功后覆盖）；失败则顶部胶囊给可操作提示 + 右侧「我的位置」按钮可重试，**不静默停在占位起点**。
  - **步骤导航语义呈现**：每步渲染为「相对转向图标 + 正文 + 遥测轨距离 + 绝对方位徽章」——相对转向由 `lib/geo/route_guidance.dart` 从 instruction 关键词解析（掉头 > 环岛 > 小角度 > 左/右 > 直行 > 出发/到达，未识别不猜）；绝对方位取高德 `step.orientation`（中文方位 → 角度 → 旋向箭头 + 八方位名）。地图上另在每步折线起点放置同语义小转向标（面板看详情、地图看格局）。
- **静态地图切片（Static Map Snapshot）**：
  - 生成指定经纬度、缩放级别（Zoom）、标记点（Markers）或折线轨迹（Polyline）的高德静态地图图片 URL（供轻量移动端直接免 SDK 渲染展示）。
- **指南针与方位角**：
  - 磁力计航向角（0°~360°）、八方位名称（正北、西北等），经端口注入。
- **收藏地点（Favorite Places，用户自决）**：
  - 用户本人在地图子页面保存常去地点（名称 + 坐标 + 可选地址），供快速选点、路线规划起终点复用；
  - **写操作不进 MCP 工具面**——命令族 `user_geo_favorite_add` / `user_geo_favorite_delete` 只登记在 `CommandGateway` **用户侧注册表**，AI 不可经工具面触达（信任模型对齐 `user_save_draft`：收藏是用户本人的数据，写归用户自决）；
  - 读取走 Repository 只读聚合层（R5），UI 与 MCP 工具面并列共享同一存储。

## MCP 工具面（形态）

| 工具 | 档 | 入参 | 出参 | 职责 |
|---|---|---|---|---|
| `geo_current` | R | `{coordSystem?: "WGS84"\|"GCJ02"}` | `{lat, lng, accuracy?, coordSystem, timestamp, source: "gps"\|"ip"}` | 获取当前绝对坐标：GPS 定位优先；**无定位权限/硬件时回退 IP 定位**（`source: "ip"`，GCJ-02，无 accuracy） |
| `geo_ip_locate` | R | — | `{lat, lng, province?, city?, adcode?, coordSystem: "GCJ02", source: "ip"}` | IP 定位兜底原语（高德 `/v3/ip`，按出口 IP 粗定位）：`geo_current` 末级回退的独立入口；解析失败 fail-closed 报错不编造 |
| `geo_geocode` | R | `{address, city?}` | `{results: [{lat, lng, formattedAddress, province, city, district}]}` | 地址/地名转坐标 |
| `geo_reverse` | R | `{lat, lng, coordSystem?}` | `{formattedAddress, province, city, district, town, poiName?}` | 坐标转详细地址与行政区 |
| `geo_search_poi` | R | `{keywords, city?, near?: {lat, lng}, radius?}` | `{pois: [{id, name, type, address, lat, lng, distance?}]}` | POI 检索：传 `near` 走周边检索（`/v3/place/around`，`radius` 米，缺省由高德默认），否则城市关键字检索（`/v3/place/text`） |
| `geo_route` | R | `{from: {lat, lng}, to: {lat, lng}, mode: "driving"\|"walking"\|"bicycling"\|"transit", strategy?, city?}` | `{durationSec, distanceMeters, taxiCost?, steps: [{instruction, distance, duration}]}` | 多模态路径规划与导航步步拆解；`mode=transit` 时 `city` 必填（缺则内核自动逆地理推导） |
| `geo_static_map` | R | `{center?: {lat, lng}, zoom?: int, size?: "width*height", markers?: [...], paths?: [...], autoFit?: bool, bounds?: {minLat,minLng,maxLat,maxLng}, secret?: string}` | `{url: string}` | 生成高德静态轻量切片预览图 URL；`paths` 自动 RDP 抽稀≤80 点防 414；`autoFit`/`bounds` 自动逆算 zoom；`secret` 触发 `sig` 签名 |
| `geo_compass` | R | — | `{heading: double, direction: string, accuracy: int}` | 获取磁力计方位角与八方位文字 |
| `geo_distance` | R | `{from: {lat, lng}, to: {lat, lng}, mode?: "straight"\|"road"}` | `{meters, durationSec?}` | 纯直线测距（Haversine）或道路测距 |

> 档位：均为 R（只读查询）。

## 收藏地点数据模型（用户侧，非 MCP action）

| 字段 | 类型 | 必填 | 说明 |
|---|---|---|---|
| `id` | string | ✔ | `geo_fav_` + 8 位十六进制（对齐 marker_store id 口径，删除按 id 精确匹配） |
| `name` | string | ✔ | 地点名称（1~40 字符，trim 后非空） |
| `lat` / `lng` | double | ✔ | 经纬度；取值域校验（纬度 -90~90，经度 -180~180） |
| `coordSystem` | enum | — | `GCJ02`（默认）/ `WGS84`——UI 选点来自高德检索结果故默认 GCJ-02；请求静态图前内核统一归一化 |
| `address` | string | — | 可选地址描述（≤100 字符） |
| `folder` | string | — | 收藏夹名；缺省/空串 = **未分类**（1~20 字符，trim 后） |

- **收藏夹 = 派生分组（2026-10-22）**：收藏夹**不是独立实体**，而是收藏的 `folder` 属性按值分组——写新夹名即建夹（`user_geo_favorite_add` 的 `folder` 参数），夹内收藏删空则夹自然消失。**不设删夹命令**（无级联删除风险：不存在"删夹连带删内容"的破坏性操作）；历史数据无 `folder` 字段 → 解码归入未分类（数据完整保留）。
- **分组呈现规则**（`groupFavoritesByFolder`，ui_ports 纯函数）：非空夹名按字典序升序在前，未分类恒在最后；组内保持添加顺序。上限沿用全局 50 条；夹名上限 20 字符。
- **存储**：SharedPreferences 键 `geo_favorites`（JSON 字符串列表，非凭证数据**不走** SecretStore/Keystore 分流）；读端口 `FavoritePlaceStore` + 写端口 `FavoritePlaceWriter` 双实现（内存 / SharedPreferences），写端口**只给用户侧 Actor 持有**。
- **校验在 Actor 内**：缺必填 / 越界 / 超长回结构化机器码（`MISSING_ARGUMENT` / `INVALID_ARGUMENT` / `FAVORITE_LIMIT_EXCEEDED`——上限 50 条防无限增长），与日历 W 档 Actor 同纪律。

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

## 移动端地图 UI（Interactive Map，2026-10-22 修订）

**交互式地图画布**：`flutter_map`（`FlutterMap`）——纯 Dart 渲染：真平移/缩放/旋转手势（`MapOptions`）、点击选点（`onTap: (TapPosition, LatLng)`）、`MarkerLayer`（收藏地点 + 起终点 + 测距点）与 `PolylineLayer`（路线结果 + 测距线）覆盖物叠加；底图 = 高德标准矢量瓦片（`wprd0{s}.is.autonavi.com/appmaptile?…style=7`，GCJ-02，与画布数据同系无偏移）。瓦片源为**非官方承诺接口**，不可用时降级静态图（GeoMapPort）登记为域内待办，暂不加备用瓦片分支。

**Key 治理（仅 Web 服务，画布零 Key）**：

| Key | 平台/用途 | 配置方式 |
|---|---|---|
| `amap_web_key`（+可选 `amap_secret`） | Web 服务 REST（检索/路径规划/静态图） | KV 懒读（现有机制不变） |
| ~~`amap_android_key`~~ | **已退役**（2026-10-22，`amap_flutter_map` 移除） | — |

- **画布零 Key 收益**：SHA1 + 包名申领 Native Key 的治理负担、`privacyStatement` 合规弹窗义务、Manifest Native SDK 权限块（ACCESS_NETWORK/WIFI_STATE）一并消失；定位权限保留供未来传感器实现（`LocationSensorProvider`）接入。
- **夜间模式（待实施验证）**：高德无暗色瓦片，`MapType.night` 无等价物；当前以深色底（`MapOptions.backgroundColor` = surface）过渡，暗色视觉方案（`style=8` 叠加 / 滤镜）登记域内待办。

**功能面板（全屏地图 + 底部上滑面板，人机同源——与 MCP 工具面并列共享同一内核，2026-10-22 交互重构）**：

```text
┌────────────────────────────────────────────────────────┐
│                     （地图胶囊）                         │
│                                                        │
│              [ FlutterMap 全屏交互画布 ]                 │
│     收藏 Marker / 路线 Polyline / 点击选点 / 手势缩放      │
│                     （铺满整页）                         │
│                                                        │
├────────────────────────────────────────────────────────┤
│                    ══ 拖拽把手 ══                        │
│ 🔍 [ 搜索地点/地址 ____________ ] (geocode/POI → 选点)   │
│ [🔍搜索] [🧭路线] [⭐收藏] [📏测距] [🔧纠偏]  ← 功能分段    │
│ ── 当前分段的完整功能面（一次一个，不再纵向堆叠）─────    │
│ 路线段示例： 起点/终点状态 + 选点工具条 + 四模态 + 步骤      │
│ [ 🚶 步行 ] [ 🚴 骑行 ] [ 🚗 驾车 ] [ 🚌 公交 ]          │
│ 1. 沿科技园中一路向北步行 120 米 …   总 12分 · 850m       │
└────────────────────────────────────────────────────────┘
```

- **全屏地图**：画布铺满整页（`DraggableScrollableSheet` 浮层，非内嵌卡片）；
- **搜索框常驻面板顶部**：把手下方，面板收起/展开均可见；
- **功能分段（按钮替代堆叠，2026-10-22 重构）**：`[搜索][路线][收藏][测距][纠偏]` 五个分段按钮，点击后面板只展示该功能的完整界面——路线段 = 起终点状态 + 选点工具条 + 四模态 + 步骤结果；测距段 = 打点模式 + 进度 + 直线距离 + 清除；收藏段 = 列表 + 设起终点/删除 + 添加表单；纠偏段 = 输入 + 三系换算；搜索段 = 结果列表（设起点/终点），提交搜索后自动切入；
- **面板可推到近顶**：max 0.95（留 5% 呼吸位，不贴死顶边）；
- **数据 → 地图映射**：路线完成 → `fitCamera` 到折线 bounds；测距两点 → fit 到两点；搜索/收藏选点 → 落 Marker（padding 下留 320 避让面板遮挡区）；
- **手势适配（2026-10-22）**：
  1. 搜索框区域上滑 → 面板展开、下滑 → 收起（`Listener` 指针事件，避免与 TextField 竖直拖拽竞争）；
  2. 选点模式激活 → 面板自动收到 min，地图全屏可点；
  3. 地图手势面显式声明：单指拖拽 / 惯性 / 双指缩放平移 / 双击放大 / 双指旋转全开，`scrollWheelZoom` 关（无滚轮设备防误缩放）；
  4. 横屏面板 min 抬至 0.35，保证地图 ≥65% 可视；
  5. Marker 触摸区 46px（起点/终点/收藏）/ 28px（测距点），小屏可点；
  6. 安全区不重复避让：外层 CapabilitiesPage 已包 `SafeArea`，页面内只补键盘 `viewInsets.bottom`。

**历史轻量范式（降级预览，保留存档）**：

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
4. **收藏地点（v1 落地口径）**：地图预览下挂**收藏地点列表**——选中即作为地图中心点渲染静态图（带 marker），并作为路线规划终点的快捷入口；添加来自 POI 搜索结果或手动输入坐标；**v1 不做自由平移/缩放重取图**（每次交互都会发起新的静态图请求，烧配额且无节流价值——节流后再评估）。

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
