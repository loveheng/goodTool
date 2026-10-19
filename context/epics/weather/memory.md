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

- 2026-10-20 **S5c 真实源 + S5d 装配完成，weather 域全量上线（241 项单测 + analyze 0 issue + arch-guard 7 条全过）**：线级能力面 = **3 域 12 action**（math_utility 3 + geo 8 + weather 1）。
- **关键实现决策（S5c）**：
  1. **HTTP 200 内仍有业务失败**：和风鉴权失败/欠费/无数据时状态码常为 200，真实状态在 Body `code`。只信 HTTP 码会拿着 `code:"401"` 去取 `now` → 空指针。故 `_checkBody` 在反序列化后**第一步**校验，按表翻译成 6 个机器码之一。
  2. **行政链相邻重复段折叠**：和风在直辖市把 `adm1`/`adm2` 都填「北京市」，按文档字面 `${adm1} ${adm2} ${name}` 拼接会得到「北京市 北京市 朝阳区」，与文档出参示例不符，故去重相邻段。
  3. **缓存回放一律标 `isCached`**：TTL 命中、429 频控、取数失败三种路径都回放缓存并打 `isCached: true`，让 Agent 明确「这不是实时数据」，而非静默当作新鲜数据（回放失败路径打 `[DEGRADE]` 日志）。
  4. **预警严格弱依赖**：`/v7/warning/now` 任何失败仅记日志 + `alerts: []`，不进入主响应重试/错误路径。
  5. **可测性靠注入口**：`client`/`geoHost`/`apiHost`/`port`/`scheme`/`ttl`/`clock` 全可注入，单测起本地 `HttpServer` 走**真实请求链路**（不 Mock HttpClient），时钟注入使 TTL 与频控自愈可被确定性断言。
- **已知限制**：天气回退链第 4 级（设备定位）受制于 `LocationSensorProvider` 仍为 Null 实现（真实实现需 geolocator，属 domain_gateway 待办）；无入参且未预设城市时回 `ERR_LOCATION_UNAVAILABLE`（fail-closed，非降级）。

## 断点
- [断点] weather 域已完成（S5a→S5d 全绿）。下一步候选：① 切 `CURRENT` 回 `domain_gateway` 落地 `system_pim`（14 action，含 5 个 W 档，是 R7 写门禁的首次真实验证点）；② 清 `McpServer._builtinInstructions` 的「拾光排程师」文案残留（需产品定位拍板）；③ 接入真实 `LocationSensorProvider`（geolocator），使 geo_current/geo_compass 与天气回退链末级真正可用。
