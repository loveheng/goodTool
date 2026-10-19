---
memo: todos
format: v3
epic: geo
---

# geo · 域内待办
- [x] [2026-10-20] (功能) (层:L1) (重:中) S4 落地 geo 分类 8 个 action（geo_current/geocode/reverse/search_poi/route/static_map/compass/distance），复用 lib/geo 内核与 GeoHttpProvider/LocationSensorProvider (src: 用户)
- [ ] [2026-10-20] (功能) (层:L3) (重:轻) geo_route mode=transit 的 city 自动逆推（geo.md「缺则内核自动逆地理推导」）：当前缺 city 返回 MISSING_ARGUMENT 并给出自愈指引，待补由起点坐标调 geo_reverse 推导城市名 (src: ai)
- [x] [2026-10-20] (集成) (层:L3) (重:中) buildGeoTool 注册进 MCP 线级并注入 Provider（共享 epic S7 已完成）：实际落点是 `lib/tool_face_assembly.dart` **装配件**（非 McpController 内——service 出向不含 tools），HTTP + Binder 双通道共用；注入 `AmapHttpProvider`（真实高德 REST，key 走 KV 懒读 `amap_web_key`/`amap_secret`），定位仍为 `NullLocationSensorProvider`（真实实现待 geolocator，见 domain_gateway 域内待办，此处不双写） (src: ai)
