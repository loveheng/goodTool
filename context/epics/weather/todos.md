---
memo: todos
format: v3
epic: weather
---

# weather · 域内待办
- [x] [2026-10-20] (功能) (层:L1) (重:中) S5a 修订 WeatherProvider 端口为不可空结构化信封（WeatherResult/WeatherError + 6 个错误码对齐文档错误模型），NullWeatherProvider 改返 ERR_WEATHER_KEY_MISSING 信封而非 null (src: 用户)
- [x] [2026-10-20] (功能) (层:L1) (重:中) S5b 落地 lib/tools/weather_tool.dart：R 档 weather_forecast（双轨出参 + days 1~7 校验 + lat/lng 成对校验 + 预警恒 [] 弱依赖）+ 16 项单测 (src: 用户)
- [ ] [2026-10-20] (功能) (层:L2) (重:中) S5c lib/service/weather.dart 的 QWeatherProvider：GeoAPI 解析 LocationID + 回退链五级 + Host 路由（devapi/api）+ Body code 拦截（401/402/403/404/429）+ gzip 解压 + unit=m + lng,lat 顺序 + now/forecast 并发聚合 + alerts 弱依赖 + TTL 30min 缓存 + 429 缓存回退 (src: 用户)
- [ ] [2026-10-20] (集成) (层:L3) (重:轻) S5d 装配 buildWeatherTool 进 tool_face_assembly（**须待 S5c 真实源就绪**——否则线级暴露恒失败的空工具）+ index.md 锚点回填 + 门禁复跑 (src: ai)
