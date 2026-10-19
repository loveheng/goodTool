---
dev-loop: memory
format: v1
epic: weather
total-merged: 0
last-merge: none
---

# weather

- [挂载] docs/product/weather.md

## 进度
- 2026-10-20 **S5a 端口修订 + S5b 适配层已落地并全绿（16 项单测 + analyze 0 issue + arch-guard 7 条全过）**：
  - **端口（S5a）**：`lib/mcp/weather_provider.dart` 签名由 `Future<Map?> forecast3(String city)` 改为 `Future<WeatherResult> forecast({city, lat, lng, days})`。旧签名「失败返回 null」被 weather.md 判为反模式（Agent 会编造天气），且无生产调用方，故**一次性改完、不留兼容分支**；新增 `WeatherResult` 信封 + `WeatherError`（code/message/suggestion）+ `WeatherErr` 六个机器码（KEY_MISSING / UNAUTHORIZED / CITY_NOT_FOUND / LOCATION_UNAVAILABLE / NETWORK / RATE_LIMITED）；`NullWeatherProvider` 改返错误信封而非 null。
  - **适配层（S5b）**：`lib/tools/weather_tool.dart` 注册 R 档 `weather_forecast`，出参双轨信封（空字段省略，不吐 null），预警 `alerts` 恒 `[]`（弱依赖口径）；入参一律校验带码返回——`days` 1~7、`lat/lng` 成对，越界/非数值/单缺分别给 `INVALID_ARGUMENT` / `MISSING_ARGUMENT`，**不静默兜底为默认值**。
  - **已知限制（S5c/D 待办）**：真实源 `QWeatherProvider` 未实现，故本轮**不装配**进 `tool_face_assembly.dart`——否则线级多一个恒返 `ERR_WEATHER_KEY_MISSING` 的空工具，属「能力假上线」。

## 断点
- [断点] 下一步：S5c 实现 `lib/service/weather.dart` 的 `QWeatherProvider`——GeoAPI 解析 LocationID、五级回退链、Host 路由（devapi/api）、**200 内 Body code 拦截**（401/402/403→UNAUTHORIZED、404→CITY_NOT_FOUND、429→RATE_LIMITED）、gzip 解压、`unit=m`、`lng,lat` 顺序、now/forecast 并发聚合、alerts 弱依赖、TTL 30min 缓存与 429 缓存回退；随后 S5d 装配 + index.md 锚点 + 门禁。
