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
