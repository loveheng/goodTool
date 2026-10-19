---
dev-loop: devlog
format: v1
epic: weather
total-merged: 0
last-merge: none
---
- [2026-10-20] [变更]: S5a 端口修订——`lib/mcp/weather_provider.dart` 按 product/weather.md「实现要点」把 `Future<Map<String,Object?>?> forecast3(String city)` 改签名为 `Future<WeatherResult> forecast({city, lat, lng, days})`：新增 `WeatherResult`（不可空信封）、`WeatherError`（code/message/suggestion）、`WeatherErr`（6 个机器码，命名对齐 `ERR_AMAP_*`）；`NullWeatherProvider` 由「返回 null」改为返回 `ERR_WEATHER_KEY_MISSING` 信封——旧签名的静默 null 被文档明确判为反模式（Agent 会编造天气），且无生产调用方，故一次性改完不留兼容分支。
- [2026-10-20] [变更]: S5b 适配层——新增 `lib/tools/weather_tool.dart` 注册 R 档 `weather_forecast`（action 名原样沿用 weather.md），出参为双轨信封（city/locationId/updateTime/now/forecast/alerts/isCached/days，空字段省略不吐 null）；`days` 缺省 3、越界或非整数 → `INVALID_ARGUMENT`（不兜底为默认值）；`lat`/`lng` 须成对，单缺 → `MISSING_ARGUMENT`，非数值 → `INVALID_ARGUMENT`。全 R 档 ⇒ 网关写门禁端口传 null。
- [2026-10-20] [决策]: 本轮**不装配**进 `tool_face_assembly.dart`——真实源（QWeatherProvider）未就绪时装配会让线级多一个恒返 `ERR_WEATHER_KEY_MISSING` 的空工具，属「能力假上线」；待 S5c 落地后随 S5d 一并装配。
- [2026-10-20] [收口]: 新增 `test/weather_tool_test.dart` 16 项（Mock Provider 走通派发闭环与错误口径）；analyze 0 issue；flutter test 全绿 221；arch-guard 7 条全过。
- [2026-10-20] [变更]: S5c 真实源——新增 `lib/service/weather.dart` 的 `QWeatherProvider`，逐条落实 weather.md 硬性约束：GeoAPI 两阶段换 LocationID（+ 城市映射缓存）、五级回退链（显式经纬度 > city > 设置项 weather_location > 设备定位 > `ERR_LOCATION_UNAVAILABLE`）、**HTTP 200 内的 Body `code` 拦截**（401/402/403→UNAUTHORIZED、404→CITY_NOT_FOUND、429→RATE_LIMITED）、`autoUncompress` 解压 gzip、坐标拼接**经度在前**两位小数、所有请求显式 `unit=m`、now/forecast `Future.wait` 并发且失败重试一次、`alerts` 弱依赖（失败仅 `[DEGRADE]` + `[]`）、TTL 30min 缓存与 429/失败缓存回退（标 `isCached`）。Key/Host 与高德同范式**懒读**（装配同步、配置异步）。
- [2026-10-20] [决策]: 行政链**相邻重复段折叠**——和风在直辖市会把 adm1/adm2 都填「北京市」，直接按文档 `${adm1} ${adm2} ${name}` 拼接会得到「北京市 北京市 朝阳区」，与文档出参示例「北京市 朝阳区」不符。
- [2026-10-20] [变更]: S5d 装配——`buildDefaultToolFace` 收口 `buildWeatherTool(QWeatherProvider(kv, sensor: sensors))`，线级能力面 = **3 域 12 action**（math_utility 3 + geo 8 + weather 1）；`tool_face_assembly_test` 断言同步（工具数 = 域数、action 合计 12、未配 Key 时和风动作 fail-closed）。
- [2026-10-20] [收口]: 新增 `test/qweather_provider_test.dart` 19 项（本地 HttpServer 走通真实链路：行政链、映射缓存、unit=m、lng,lat 顺序、回退链五级、200 内业务码、TTL 与频控自愈、预警弱依赖）；analyze 0 issue；flutter test 全绿 241；arch-guard 7 条全过。
