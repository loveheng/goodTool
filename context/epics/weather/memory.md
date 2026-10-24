---
dev-loop: memory
format: v1
epic: weather
total-merged: 2
last-merge: 2026-10-24
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

- 2026-10-23 **公共域名停用口径 + 错误体真因透传已落地（test 555 全绿 + analyze 0 issue + arch-guard 7 条全过；provider 单测 19→26 例）**：
  - **实测事实**：和风公共域名全线停用——`devapi`/`api` → 403 `Invalid Host`（JSON:API 错误体），`geoapi` → 404 空体；**必须账号专属 Host**（形如 `xxxx.re.qweatherapi.com`，控制台「项目管理」复制），它同时承载天气与 GeoAPI（路径前缀 `/geo`）。
  - **关键决策**：① **不接 SDK**（pub.dev 无官方 Flutter SDK；官方 SDK 同样要 Key+Host，不消除根因；社区插件老且为原生插件，破坏无头架构）；② 新增 `ERR_WEATHER_HOST_INVALID`（Host 无效/服务未开通）与「Key 缺失优先于 Host 缺失」的上报次序；③ **错误体必须读出**再翻译（JSON:API `error.title/detail` + 中文「服务不可访问」），旧实现丢体导致用户只看到笼统「鉴权失败」；④ HTTP 200 + `error` 段也拦截（消除「成功但 now 为空」假成功）；⑤ Host 值归一化（去协议/斜杠/路径段）；⑥ GeoAPI 不再兜底公共域名（兜底只会被误报成「查无此城」）。
  - **用户侧待办**：天气仍需在设置页填 Key + 账号专属 Host 才能取数（**非代码可解**，SDK 也一样）。

- 2026-10-24 **403 Security Restriction 拆出（provider 单测 28 例）**：真机 403 实测为和风控制台**安全限制**（IP 白名单/访问限制）拦截——Key/Host 本身有效，`_isSecurityRestriction` 优先识别，文案指向控制台安全设置，不再落入笼统「鉴权失败」。

- 2026-10-24 **天气页改版 + 多城市持久化全量落地（[准入] S2 结构性引入，仿 geo 收藏五件套；576 项单测）**：
  - **领域层**：`weather_city_store`（`weather_cities` 键，上限 10 配额护栏 + 重名拒绝，内存/SharedPrefs 双实现）+ `WeatherCityRepository` 读聚合（R5）。
  - **命令面**：`user_weather_city_add/delete` + `WeatherCityActors`（**用户侧注册表，AI 不可触达**，不进 MCP 工具面）。
  - **搜索**：`WeatherProvider.searchCity`（GeoAPI lookup 多候选类型化信封，「查无此城」= 成功空列表）+ `WeatherPort.searchCity` 视图。
  - **UI**：weather_page 重构 = 城市列表 + 底部胶囊搜索条 + DraggableScrollableSheet 半/全屏（snap/把手/Listener 快甩/FocusNode 守卫/viewInsets 全对齐地图页范式），裸经纬度表单退役；`weather_location` 预设城市语义不变。

- 2026-10-24 **两项未闭环候选闭环（582 项单测 + analyze 0 issue + arch-guard 7 条全过）**：
  - **地图选点→加城市协同**：`WeatherProvider.lookupCityByCoords` 坐标反查（GeoAPI `location=lng,lat` **经度在前**两位小数，与天气查询同口径；「查无此城」= 成功空列表）→ `WeatherPort` 投影（与 searchCity 共用 `_toSearchView`）→ 地图页新增「天气」分段 + `_PickMode.weather` 选点模式（点地图落 pin → 反查候选 → 点「添加」经 `UserWeatherCityAddCommand` 入列）。**条目用候选回传的和风行政链名 + 城市质心坐标 + LocationID**——与搜索添加同源同构，重名校验语义一致，取数同走坐标直查；写路径守 R1（UI 只组装命令）。
  - **城市列表逐城缓存聚合**：weather_page 增逐城摘要（行内 temp/text + `isCached` 标记），与「点城市取数」**共用 provider 逐城 TTL 缓存**（同 `location#days` 键，days 缺省 3）——摘要先行预热、命中零出网、点详情直接回放缓存；未命中**逐城串行**补数（开发版和风配额护栏）；失败行内给人话不摆机器码；`_query` 最新结果同步回写摘要行；删除城市即剪枝。
- Ref: docs/product/weather.md ## 决策日志（不装配空工具 / 行政链相邻重复段折叠 / 不接和风 SDK 三条决策原文）

- 2026-10-24 **真机侧载验收通过（用户确认）**：天气页全量新交互（搜索添加/拖拽面板/点城市取数/行内摘要/地图选点加城市）+ 真机填 Key+Host 真实取数。

- 2026-10-24 **配额护栏三件套**（607 项单测收口前态）：`QWeatherProvider` 出网侧 ① **singleflight**（同 `location#days` 并发共享一次在途取数，`_inflight` 表）② **串行节流**（`_fetchQueue` 先到先服务，相邻起跑间隔 `pacing` 默认 300ms≈3 QPS 上限，注入口可关；pacing 走真实时间，与 TTL/冷却的注入 clock 分离）③ **429 冷却窗**（命中频控后 `rateLimitCooldown` 默认 60s 不出网：有缓存回放标 isCached、无缓存 `ERR_RATE_LIMITED` 带冷却指引；截止由注入 clock 驱动可测）。三件套只作用 forecast 类出网，`searchCity`/`lookupCityByCoords` 不受冷却拦截。口径在 weather.md「缓存策略与频控」。

- 2026-10-24 **域深化四件上线（weather 1→5 action，线级 4 域 33 action；607 项单测）**：`weather_air`（AQI /v7/air/now）/ `weather_indices`（生活指数 1d|3d，type 数字或逗号分隔）/ `weather_astronomy`（日出日落，date 缺省设备今日）/ `weather_minutely`（分钟级降水 summary+2h 序列）。**共用 Key/Host/传输层/回退链/配额护栏**：provider 抽 `_guardedFetch` 共享通道（TTL→冷却→singleflight→队列+pacing），四件**独立缓存键位**（`air:`/`idx:`/`solar:`/`min:` 前缀）不与预报互串；`_fetchOne` 单端点投影（objectKey→now / listKey→forecast / summaryOf→now.summary，空段不出键）；工具层 `_parseLocArgs` 五动作统一宽容解析（G5 不兜底）。**待真机验**：indices/astronomy/minutely 开发版账号是否含这些端点。G1 契约先行：weather.md 增四件契约表。

- 2026-10-24 **真机反馈手势化改版收口（611 项单测 + analyze 0 issue + arch-guard 7 条全过）**：① 详情并入城市卡——手风琴卡片就地展开（`_expandedId` 单开，无独立详情区块，缓存回放标记并入更新时间行）；② 手势代替按钮——Dismissible 左滑删除（乐观移除+失败经 store 重读回滚+撤销走 Actor 配额校验）、搜索提交走键盘搜索键；③ 核查收口：逐城缓存聚合与地图选点加城市经核查均已在位（零新增功能代码），回滚 UI 不消费的冗余 current/nowOf 单请求通道（与摘要=详情同键设计冲突）。
- Ref: docs/product/weather.md ## 决策日志（手势化+手风琴条目）

## 断点
- [断点] 下一步：天气域功能面收口（多城市+搜索+地图协同+逐城聚合全部落地，已随 5a27b55 提交）；下一步：真机侧载全量验收（天气页手势交互+地图选点加城市），或切其他任务
