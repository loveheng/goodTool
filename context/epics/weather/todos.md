---
memo: todos
format: v3
epic: weather
---

# weather · 域内待办
- [x] [2026-10-20] (功能) (层:L1) (重:中) S5a 修订 WeatherProvider 端口为不可空结构化信封（WeatherResult/WeatherError + 6 个错误码对齐文档错误模型），NullWeatherProvider 改返 ERR_WEATHER_KEY_MISSING 信封而非 null (src: 用户)
- [x] [2026-10-20] (功能) (层:L1) (重:中) S5b 落地 lib/tools/weather_tool.dart：R 档 weather_forecast（双轨出参 + days 1~7 校验 + lat/lng 成对校验 + 预警恒 [] 弱依赖）+ 16 项单测 (src: 用户)
- [x] [2026-10-20] (功能) (层:L2) (重:中) S5c lib/service/weather.dart 的 QWeatherProvider：GeoAPI 解析 LocationID + 回退链五级 + Host 路由（devapi/api）+ Body code 拦截（401/402/403/404/429）+ gzip 解压 + unit=m + lng,lat 顺序 + now/forecast 并发聚合 + alerts 弱依赖 + TTL 30min 缓存 + 429/取数失败缓存回退；19 项单测（本地 HttpServer 真实链路） (src: 用户)
- [x] [2026-10-20] (集成) (层:L3) (重:轻) S5d 装配 buildWeatherTool 进 tool_face_assembly（随 S5c 真实源就绪一并上线）+ index.md/overview.md 锚点回填 + 门禁复跑 (src: ai)
- [x] [2026-10-20] (功能) (层:L3) (重:中) 真实 LocationSensorProvider 接入后，天气回退链第 4 级才真正可用（当前 Null 实现 → 无入参无设置城市时回 ERR_LOCATION_UNAVAILABLE）；该实现属 domain_gateway 域待办（geolocator），此处不双写 (src: ai) → **2026-10-22 已接入 geolocator（SystemLocationSensorProvider，main.dart 单实例共用），本项闭环** (src: ai)
- [x] [2026-10-23] (测试) (层:L3) (重:中) **真机填 Key + 账号专属 Host 验证一次真实取数**：代码侧已收口（公共域名停用口径 + 错误体真因透传 + Host 归一化），唯一未验证项是真实账号的响应体形态（尤其 `error.title/detail` 文案与 GeoAPI `/geo/v2` 路径）是否与单测构造一致 (src: ai)
- [ ] [2026-10-23] (决策) (层:L3) (重:轻) 和风 SDK **不接**（已评估否决）：pub.dev 无官方 Flutter SDK 包（仅社区插件 flutter_qweather 0.0.11，老且原生插件，破坏无头架构/arch-guard 分层）；官方 SDK（Android/iOS/小程序）初始化同为 Key+Host，不消除「必须账号专属 Host」根因。若未来和风出官方 Flutter SDK 且支持 Host 自动解析，可再评估 (src: ai)
