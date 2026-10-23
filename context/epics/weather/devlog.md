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
- [2026-10-23] [决策]: **不接和风 SDK**（用户提示「和风天气有 sdk 可以使用」→ 评估后否决）：① pub.dev 无官方 Flutter SDK 包（仅社区插件 `flutter_qweather` 0.0.11，老且为原生插件，引入会破坏无头架构与 arch-guard 分层）；② 官方 SDK（Android/iOS/小程序）初始化同样是 `API Key + API Host`，**不消除「必须账号专属 Host」这一根因**；③ 本仓自研 provider 已覆盖端口契约 + 19 项真实链路单测，换 SDK 收益不抵迁移代价。结论：保留自研实现并加固。
- [2026-10-23] [变更]: **公共域名全线停用口径 + 错误体真因透传**（用户「现在提示服务不可访问」；实测 `devapi`/`api` → 403 `Invalid Host`、`geoapi` → 404 空体，公共域名全不可用）：① 新增 `WeatherErr.hostInvalid = 'ERR_WEATHER_HOST_INVALID'`，把「Host 无效/服务未开通」从「鉴权失败」里拆出来（可自愈：去改 Host）；② `_get` 改为**读出错误体**再翻译——和风 JSON:API 形态 `{"error":{"status":403,"title":"Invalid Host","detail":"..."}}`、未开通场景中文「服务不可访问」，旧实现 4xx 直接 `drain` 丢体，用户只看到笼统「鉴权失败」；③ HTTP 200 但体内是 `error` 段的形态也拦截（否则会「成功但 now 为空」的假成功）；④ **Host 值归一化**（去 `https://`、尾部 `/`、路径段，统一小写）——用户粘贴控制台 URL 也能用，不再拼出畸形 URI；⑤ GeoAPI 改走**账号专属 Host 的 `/geo/v2/city/lookup`**，公共 GeoAPI 不再兜底（兜底只会拿 404 空体被误报成「查无此城」）；⑥ Key 校验前置到 `forecast()` 入口（Key 缺失优先于 Host 缺失上报）；⑦ 设置页 Host 说明改为「公共域名全停用 + 粘贴自动归一」
- [2026-10-23] [验证]: `test/qweather_provider_test.dart` 增 7 例（Host 归一化、KV Host 带协议出网、账号 Host 的 /geo 路径、未配 Host 城市解析零请求、403 Invalid Host、404「服务不可访问」、HTTP 200 + JSON:API 错误体）；analyze 0 issue；flutter test 555 全绿；arch-guard 7 条全过
