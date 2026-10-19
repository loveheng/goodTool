---
memo: todos
format: v3
epic: geo
---

# geo · 域内待办
- [x] [2026-10-20] (功能) (层:L1) (重:中) S4 落地 geo 分类 8 个 action（geo_current/geocode/reverse/search_poi/route/static_map/compass/distance），复用 lib/geo 内核与 GeoHttpProvider/LocationSensorProvider (src: 用户)
- [ ] [2026-10-20] (功能) (层:L3) (重:轻) geo_route mode=transit 的 city 自动逆推（geo.md「缺则内核自动逆地理推导」）：当前缺 city 返回 MISSING_ARGUMENT 并给出自愈指引，待补由起点坐标调 geo_reverse 推导城市名 (src: ai)
- [ ] [2026-10-20] (集成) (层:L3) (重:中) buildGeoTool 注册进 McpController.toolFaceFactory 并注入真实 GeoHttpProvider/LocationSensorProvider 实现（属共享 epic S7 收口，domain_gateway 域内已登记条目；geo 侧需提供 amap_web_key / amap_secret 读取源）。注意 index.md 域级锚点回填（`math_tool.dart` + `geo_tool.dart` 及其测试）同属 S7 —— S3e/S4 均未单独回填，勿在此双写 (src: ai)
