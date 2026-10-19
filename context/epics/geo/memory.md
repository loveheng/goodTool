---
dev-loop: memory
format: v1
epic: geo
total-merged: 0
last-merge: none
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

## 断点
- [断点] **S7 已完成接线**：`buildGeoTool()` 由 `lib/tool_face_assembly.dart`（装配件）装配进 MCP 线级，HTTP 调试通道与 Binder 生产通道共用同一份；注入 `AmapHttpProvider`（真实高德 REST，Key 经 KV 懒读）与 `NullLocationSensorProvider`（真实定位需 geolocator，S7 未引入，fail-closed 返回 `PERMISSION_DENIED`）。S7 同轮把 `amapWebKey`/`amapSecret` 静态参数改为懒读 reader，故本 epic 的 `buildGeoTool` 构造签名有变。
- [断点] 下一步：等待新子任务。本域剩余项 = `geo_route` mode=transit 的 city 自动逆推（见本域 todos）；跨域主线 = domain_gateway 的 S8 与 system_pim / weather 域排期。
