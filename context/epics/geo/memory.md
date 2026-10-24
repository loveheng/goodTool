---
dev-loop: memory
format: v1
epic: geo
total-merged: 1
last-merge: 2026-10-24
---

# geo

- [挂载] docs/product/geo.md

## 进度
- 2026-10-20 **S4 适配层已落地并全绿（30 项单测 + analyze 0 issue + arch-guard 6 条全过）**：`lib/tools/geo_tool.dart` 建 `buildGeoTool(sensor, http, {amapWebKey, amapSecret})`，注册 product/geo.md 定义的 8 个 R 档 action（geo_current / geo_geocode / geo_reverse / geo_search_poi / geo_route / geo_static_map / geo_compass / geo_distance），复用 `lib/geo` 纯 Dart 内核（`CoordConvert` / `AmapStaticMap` / `rdpSimplify` / `amapSign`）与 `GeoHttpProvider` / `LocationSensorProvider` 注入端口。全部为 R 档（`geo.md`「档位：均为 R」）→ `commandGateway` 传 null，工具文件零 `import command_gateway`、无 `.dispatch`/`.admits`，写门禁物理不可穿透（对齐 S3e 口径，守 arch-guard R1/R4）。
- **关键设计决策（S4）**：
  1. **坐标归一化统一在 SubAction 入口**：入参默认按 GPS 原生 WGS-84 解释，请求高德前一律 `CoordConvert.normalize(...,gcj02)`；单测断言请求查询串 `location`/`origin` 已被纠偏（≠ 原样透传）。
  2. **`geo_static_map` 的特殊性**：静态图是「拼 URL」而非发 JSON 请求，不过 `GeoHttpProvider`，故 `amap_web_key` / `amap_secret` 以**静态配置**随构造器注入（不给 LLM 露出 key 入参）；未配 Key 返回 `ERR_AMAP_KEY_MISSING`。
  3. **错误一律带 machine code、不以默认值兜底**：高德 REST 经 `_amapGet` 单一出口——`GeoHttpException.code`（如 `ERR_AMAP_KEY_MISSING`）、失败 `status` 的 `infocode`、结构漂移的 `AMAP_PARSE_ERROR`；非法入参分别抛 `MISSING_ARGUMENT` / `INVALID_ARGUMENT`，无「静默降级为默认 mode」。
  4. **`geo_distance` 分档**：`straight` 走本地 Haversine（不依赖网络与 Key，主线可用），`road` 才走高德驾车距离。
- **已知限制（非 S4 范围，已登记域内待办）**：`geo_route` 的 `mode=transit` 缺 `city` 时按 geo.md 本应「由起点自动逆地理推导」，当前实现返回 `MISSING_ARGUMENT` 并在 message 中给出自愈指引（先 `geo_reverse` 取 city），其余 7 个 action 端到端不受影响；自动推导留给后续排期。

- 2026-10-23 **进场自动定位根因修正已落地（analyze 0 issue + test 555 全绿 + arch-guard 7 条全过；新增 `test/system_location_sensor_test.dart` 13 例）**：
  - **根因**：定位源只 catch `TimeoutException`，geolocator 在系统定位开关关闭时抛 `LocationServiceDisabledException`、权限流程异常抛 `PermissionDeniedException` → 异常冒泡出端口 → UI `await` 抛出、`setState` 不执行 → 「定位中…」永久挂起、相机停在硬编码占位中心（用户报「定位原始起点」）。
  - **处置**：① 定位源任何失败一律 fail-closed 返 null（`[LOC]` 日志留原因）；② 分档回退 高精度 GPS(12s) → 低精度网络(8s) → 上次已知位置（仅采信 2 分钟内新鲜读数）；③ UI 侧 `_readLocation()` 兜底 try/catch（纵深防御），失败给可重试提示。
  - **未闭环**：真机未连（本轮无设备），进场自动定位的真实 GPS 冷启动表现与权限弹窗流程**仍待真机验收**。

- 2026-10-22~24 **地图 UI 全量演进（多轮迭代，测验 561 全绿收口）**：
  - **收藏地点**：favorite_place_store（geo_favorites 键上限 50）+ user_geo_favorite_add/delete 命令/Actor + FavoriteRepository（R5）+ 收藏夹分类（`FavoritePlace.folder` 派生分组——夹名随收藏存在、删空自然消失，不设删夹命令防级联；`groupFavoritesByFolder` 纯函数分组）。
  - **SSOT 修正**：静态切片轻量方案 ➔ 交互画布 flutter_map 8.x + 高德矢量瓦片（amap_flutter_map 整体退役，decisions.md 2026-10-22 裁定 Ref: decisions#2026-10-22；pub-cache 补丁债随之清零）。
  - **页面结构（后续 weather 页复用范式）**：全屏地图 + `DraggableScrollableSheet`（snap、竖屏 0.22/0.95 横屏 0.35/0.75、40dp 把手、`viewInsets.bottom` 防键盘遮挡）；搜索框手势用 **Listener 而非 GestureDetector**（TextField 竖拖选文本的竞技场冲突），聚焦时 `FocusNode` 守卫禁拖拽，±60dp 快甩展/收 240ms easeOut；面板内容 ChoiceChip 分段单功能完整面；浮动按钮列（缩放/指北/我的位置）+ 呼吸蓝点 + 暗色瓦片压暗遮罩 + 毛玻璃 + 指北针 + 比例尺。
  - **路线三件套**：默认起点=定位；步骤公共区块（徽章+TelemetryText+方位徽章）；`lib/geo/route_guidance.dart` 纯内核转向解析（掉头>环岛>出发/到达>小角度>左右>直行）+ 地图转向标 Marker。
  - **定位**：`SystemLocationSensorProvider`（geolocator 14.1.2）单实例四处共用（MCP geo_current / 地图 / 天气回退 / 状态页）；**任何异常 fail-closed 返 null**（geolocator 还会抛 LocationServiceDisabledException/PermissionDeniedException，不止 TimeoutException）；分档回退 GPS 12s→网络 8s→2 分钟内上次已知；geo_last_location 会话键 + Actor + Port 进场先恢复相机再刷新。
  - **体验修复三批（17 项）**：测距满 2 点不清空、搜索结果显式设起/终点按钮、收藏点击不隐式设终点、错误提示去机器码留人话、计算器合计语义/清空延迟释放、日历权限提示清理、天气数字键盘+天数前置校验、设置页按项隔离 saving 等；排查清单已清零。
  - **未闭环**：真机验收 17 项全量清单 + 定位真实 GPS 冷启动表现（无设备轮，已登记域内待办）。

## 断点
- [断点] 下一步：geo 深化两洞已闭环（ip_locate/current 兜底/poi around，测验全绿）；真机验证 IP 定位兜底链路 + transit city 自动逆推仍为域内 L3 待办
