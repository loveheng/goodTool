---
dev-loop: devlog
format: v1
epic: geo
total-merged: 0
last-merge: none
---

# geo · 变更日志

- [2026-10-20] [变更]: S4 适配层完成：新增 `lib/tools/geo_tool.dart` + `test/geo_tool_test.dart`（30 项）。建 `buildGeoTool(sensor, http, {amapWebKey, amapSecret})` 注册 geo 分类 8 个 R 档 SubAction，action 名与 product/geo.md 表格第一列 1:1（新增单测对账 enum 列表，防改名/遗漏，domain_gateway G1）。要点：① 全 R 档 → `commandGateway` 传 null，工具文件零 `import command_gateway`、无 `.dispatch`/`.admits`（arch-guard R1/R4 门禁必过）；② 坐标归一化统一在 SubAction 入口做（入参默认按 GPS 原生 WGS84 解释，请求高德前 `CoordConvert.normalize` 到 GCJ-02，单测断言查询串已被纠偏）；③ 高德 REST 走 `_amapGet` 单一出口——异常/失败 status/结构漂移分别映射为 `GeoHttpException.code`、`infocode`、`AMAP_PARSE_ERROR`，一律带 code 返回，**不以 0 / 空列表兜底**；④ `geo_static_map` 不经过 GeoHttpProvider（拼 URL 而非发 JSON 请求），故 amap_web_key/secret 以静态配置随构造器注入，未配 Key 返回 `ERR_AMAP_KEY_MISSING`（不给 LLM 露出 key 入参）。
- [2026-10-20] [决策]: geo_distance 主线保 observable 可用性——`mode=straight` 走本地 Haversine（不依赖网络与 Key），`mode=road` 才走高德驾车；非法 mode 返回 `INVALID_ARGUMENT`，不静默降级为 straight。
- [2026-10-20] [收口]: analyze 0 issue；`flutter test` 全绿 184（新增 30）；arch-guard 6 条全过。注册进 `McpController.toolFaceFactory` 属共享 epic（S7），本 epic 未触碰 controller 与 `main.dart`。
