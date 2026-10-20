---
status: active
updated: 2026-10-20
---

# goodTools · 功能 → 代码落点索引

> 域级锚点表，禁止一次性铺满：随实现长出来。落点精确到仓库相对路径；改前先查本表，跨域改动先登记再动手。机制与登记纪律见项目索引 skill（`.agents/skills/goodTools-index/SKILL.md`）。

## 1. 代码落点

| 域 | 功能 | 代码落点 | 备注（定位必读） |
|----|------|----------|------------------|
| 启动/入口 | App 入口与 MCP 绑定启动 | `lib/main.dart`、`lib/mcp_binder_entrypoint.dart`、`lib/ports.dart` | 端口/绑定参数集中在 `lib/ports.dart` |
| MCP 内核 | JSON-RPC 传输、MCP server、工具面接口、KV 持久化、示例工具、领域网关契约 | `lib/mcp/jsonrpc.dart`、`lib/mcp/mcp_server.dart`、`lib/mcp/tool_face.dart`、`lib/mcp/settings_kv.dart`、`lib/mcp/weather_provider.dart`、`lib/mcp/category_tool_face.dart`、`lib/mcp/calendar_provider.dart` | `mcp_server.dart` 是核心；`tool_face.dart` 定义工具注册接口（`call` 返回完整 result `{content,isError}`，内核只透传）；`category_tool_face.dart` = 领域网关契约层（工程规范 §3.3 G1–G5，**不进 barrel 导出**）；`calendar_provider.dart` = 日历端口 + 事件/订阅源/标记模型 + 7 个错误码 |
| 命令层（唯一写入口） | CommandGateway 分发，写必走 CommandHandler | `lib/action/command_gateway.dart`、`lib/action/calendar_commands.dart` | 工程规范 §2：R1 前瞻——UI 引入后写路径须组装命令交 CommandHandler；`calendar_commands.dart` = 日历 5 个 W 档命令（**命令名 = action 名**，供 `CategoryTool.admits` 查找） |
| 服务层 | Android 前台服务保活、HTTP 传输、MCP 控制、高德 REST 真实实现 | `lib/service/foreground_task_init.dart`、`lib/service/http_transport.dart`、`lib/service/mcp_controller.dart`、`lib/service/amap_http_provider.dart`、`lib/service/weather.dart` | 无头系统：删 UI 后此层须能独立跑通；`amap_http_provider.dart` 是 `GeoHttpProvider` 的真实实现（端口定义在 `lib/mcp/geo_provider.dart`），Key **每次请求懒读**（KV 异步、装配同步），缺失抛 `ERR_AMAP_KEY_MISSING`；`weather.dart` = 和风 `WeatherProvider` 真实源（200 内 Body code 拦截 + gzip + 并发聚合 + TTL 缓存） |
| 服务层 | 日历 W 档命令执行体 + 重要标记存储 + ICS 订阅源真实实现 | `lib/service/calendar_actors.dart`、`lib/service/marker_store.dart`、`lib/service/ics_feed_provider.dart` | `calendar_actors.dart` = 日历 5 个 W 档命令执行体（**由装配件登记进 CommandGateway**；feed 列表存 `SettingsKv`，幂等/作用域/护栏复检，输出统一 `{'success':…}` 信封）；`marker_store.dart` = `CalendarMarkerStore`（读）+ `CalendarMarkerWriter`（写，**只给 Actor 持有**）的内存与 SharedPreferences 双实现；`ics_feed_provider.dart` = `CalendarFeedProvider` 真实源（autoUncompress + 3 跳重定向 + 10s 超时回退缓存、G2 频控 30s、G3 退订清缓存、G4 `feedId:uid` 复合键、E 拍板 PII 脱敏） |
| 装配件 | 工具面装配收口（HTTP 调试通道 + Binder 生产通道共用同一份） | `lib/tool_face_assembly.dart` | 装配件（与 `main.dart`/`ports.dart` 同级，跨域 import 合法）：收口 `buildMathTool()` / `buildGeoTool(...)`；新增能力只改本文件，两通道同步生效；高德配置经 KV 懒读（`amap_web_key` / `amap_secret`） |
| 工具面扩展 | math_utility 领域网关（calc_eval / unit_convert / unit_list） | `lib/tools/math/math_tool.dart` | 全 R 档 ⇒ 写门禁端口传 null（W 档物理不可达）；双轨出参（格式化 `result` 串 + 无损 `numericValue`），结构化错误带 offset/candidates/suggestion；action 名 1:1 沿用 `product/calculator.md` |
| 工具面扩展 | geo 领域网关（geo_current / geocode / reverse / search_poi / route / static_map / compass / distance） | `lib/tools/geo_tool.dart` | 全 R 档；入参坐标默认 WGS-84，请求高德前统一 `CoordConvert.normalize` 到 GCJ-02；高德 REST 单一出口 `_amapGet`（`GeoHttpException.code` / `infocode` / `AMAP_PARSE_ERROR` 全带机器码，不以空值兜底）；静态图 Key/Secret 经 reader 懒读 |
| 工具面扩展 | weather 领域网关（weather_forecast） | `lib/tools/weather_tool.dart` | 全 R 档；出参双轨信封（空字段省略、不吐 null），`alerts` 恒 `[]`（弱依赖口径）；`days` 1~7 与 `lat/lng` 成对校验一律带码返回，不静默兜底 |
| 工具面扩展 | system_pim 领域网关（日历 14 action，含 5 个 W 档） | `lib/tools/system_pim_tool.dart` | 3 个纯计算 R 档真实可用（date_calc/date_diff/workdays_between）；6 个 R 档接 Provider、源未注入 fail-closed 返 `ERR_CALENDAR_SOURCE_UNAVAILABLE`；5 个 W 档只 buildCommand（**命令名 = action 名**，校验与 SSRF 护栏下沉 Actor）。**S6-P1 未装配进线级**（待 P2 源就绪） |
| 工具面扩展 | 日历时间推演内核 + 法定节假日表（纯 Dart） | `lib/tools/calendar/date_math.dart`、`lib/tools/calendar/holiday_table.dart` | `date_math.dart` = 成分跨度（逐月推进，不用毫秒相除）/ 工作日推演（调休补班 > 法定假 > 周末）/ delta 按 days→months→workdays→hours 顺序 + 月末 clamp，**禁 DateTime.now()**；`holiday_table.dart` = 2026 法定节假日表（**逐字照录国办 2025-11-04 通报**，`cn-2026.1`，法定假 33 天 + 调休补班 6 天）+ OTA 静态 JSON 同构入口 |
| MCP 内核 | ICS 解析与 PII 脱敏（日历域内核件，service 与 tools 双复用） | `lib/mcp/ics_parser.dart`、`lib/mcp/pii_mask.dart` | RFC 5545 子集（行展开/转义/组件边界）、RRULE 四 FREQ + INTERVAL/COUNT/UNTIL/BYMONTHDAY/BYDAY、EXDATE / RECURRENCE-ID override / STATUS:CANCELLED（C2）、单事件 365 实例截断（C1）；**ICS 时间解析禁 `toUtc()`**（会把墙钟按本机时区偏移，实例整体漂一天）；`pii_mask.dart` = E 拍板脱敏（默认只掩码电话/邮箱，同串同掩码保确定性） |
| 工具面扩展 | 天气端口信封（WeatherResult / WeatherError / 6 个错误码） | `lib/mcp/weather_provider.dart` | 端口签名 `forecast({city,lat,lng,days})` 返回**不可空信封**（旧 `forecast3 → Map?` 的静默 null 被 weather.md 判为反模式，已废弃无兼容分支） |
| 工具面扩展 | 计算器能力内核：单位注册表 + 换算引擎（纯 Dart 无头） | `lib/tools/math/unit_definition.dart`、`lib/tools/math/unit_registry.dart`、`lib/tools/math/convert_result.dart`、`lib/tools/math/unit_converter.dart` | 11 量纲 × 4 transform（linear/affine/reciprocal/iecSi）；别名归一化**单一真相源**，别名冲突 fail-fast；基准单位走显式表（≠ dimension 名）；契约见 `product/calculator.md` 附录 A |
| 工具面扩展 | 计算器表达式内核：Sanitizer + Lexer + Parser + Evaluator（纯 Dart 无头） | `lib/tools/math/math_error.dart`、`lib/tools/math/expression_sanitizer.dart`、`lib/tools/math/expression_lexer.dart`、`lib/tools/math/expression_parser.dart`、`lib/tools/math/expression_evaluator.dart` | Sanitizer 全角/`×`/`÷`/千分位/币种符保守清洗 + cleaned→original 位移回填；Lexer 单位 run 仅被 `to` 确认；Parser 递归下降产出 AST（`^` 右结合 / 一元负号低于 `^` / 隐式乘法 / `A+B%` 歧义 warning / `NESTING_TOO_DEEP`）；Evaluator 走 **Decimal 主链路**（`0.1+0.2=0.3` 精确）+ DoS 红线 `EVAL_STEP_LIMIT`，超越函数/单位换算因固有非精确走 double 回装 Decimal（非静默降级） |
| 自更新 | 安装器、远程配置热更、更新清单、更新服务 | `lib/update/installer.dart`、`lib/update/remote_config_store.dart`、`lib/update/update_manifest.dart`、`lib/update/update_service.dart` | 发布链路见 workflow skill 的 `release-r2` |
| 地理/地图内核 | 坐标纠偏（WGS-84↔GCJ-02↔BD-09）、Haversine 测距 | `lib/geo/coord_convert.dart` | 纯 Dart 无头，arch-guard R4；WGS-84→GCJ-02 自动归一 |
| 地理/地图内核 | 高德静态图 URL 构建器（免 Native 3D SDK 轻量渲染） | `lib/geo/static_map_url.dart` | 入参可声明任意坐标系，内部归一化到 GCJ-02；集成 sig 签名 / RDP 抽稀 / Auto-bounding 视口自适应 |
| 地理/地图内核 | 高德数字签名（Sig/MD5） | `lib/geo/amap_sign.dart` | 参数升序拼接 + secret → MD5，防 INVALID_USER_SCODE |
| 地理/地图内核 | 轨迹抽稀（RDP） | `lib/geo/rdp.dart` | 道格拉斯-普克，折线硬性≤80 点，防 URL 超 2048 触发 414 |
| 地理/地图内核 | 高德 HTTP / 位置传感器端口（依赖反转接缝） | `lib/mcp/geo_provider.dart` | 对齐 `weather_provider.dart`；未注入源抛 `ERR_AMAP_KEY_MISSING`（工程规范 §1.2） |
| 测试 | 纯 Dart 内核全链路测试（无设备可跑） | `test/smoke_test.dart`、`test/geo_test.dart`、`test/category_gateway_test.dart`、`test/unit_converter_test.dart`、`test/expression_lexer_test.dart`、`test/expression_parser_test.dart`、`test/expression_evaluator_test.dart`、`test/math_tool_test.dart`、`test/geo_tool_test.dart`、`test/tool_face_assembly_test.dart`、`test/amap_http_provider_test.dart`、`test/weather_tool_test.dart`、`test/qweather_provider_test.dart`、`test/system_pim_tool_test.dart` | 覆盖 InMemoryKv / CommandGateway / McpServer / 坐标互转闭环 / 静态图 URL / 八方位 / 网关派发契约（枚举外拦截、写门禁拦截、错误前缀注入、isError 唯一派生）/ 单位换算四模型与 reciprocal 跨制反比 / Sanitizer 保守清洗与位移回填 / 解析器优先级-结合性、隐式乘法、百分比歧义 warning、嵌套深度红线 / 求值器 Decimal 精确性、运算符语义、超越函数、单位换算、错误码与 EVAL_STEP_LIMIT / 领域网关适配层（math 3 + geo 8 对账、坐标归一化、错误机器码）/ **装配收口**（工具数 = 域数 2、action 合计 11、双通道共用、Key 懒读即配即生效、未配 Key fail-closed）/ **高德 REST 真实链路**（本地 `HttpServer` 验证 key 注入、非 200、非 JSON、结构漂移） |

## 2. 文档落点

| 主题 | 文档路径 | 状态 |
|------|----------|------|
| 工程规范 SSOT（架构红线 / 分层 / 工具面契约） | `docs/project/coding-standards.md` | active |
| 领域网关工具设计（分类嵌入模式） | `docs/project/domain_gateway.md` | draft（矩阵已按 4 份 product 文档 26 个原子动作 1:1 对账，待落地 `lib/`） |
| 产品概述（能力/架构/信任模型） | `docs/product/overview.md` | active |
| 日历能力 | `docs/product/calendar.md` | active |
| 计算器能力 | `docs/product/calculator.md` | active |
| 地理能力 | `docs/product/geo.md` | active |
| 天气能力 | `docs/product/weather.md` | active |
| UI 开发规范（用户层） | `docs/project/ui-design.md` | active |

> 三处同步纪律：本表 + `docs/README.md` + goodTools-docs 域表（goodTools-docs 维护协议）。

## 3. 架构债与依赖违例登记

> 活跃表只留未结项；清零时结项归档（压缩为「#N 摘要 → 落点 → 结项日期」，细节归 Git log / epic devlog）。散修须先登记再动手（goodTools-index §3）。

| # | 债 | 落点 | 状态 |
|---|----|------|------|
| （空） | 暂无登记项 | — | — |

<!-- 归档区（结项后移入，压缩为一行）：
- #N 摘要 → 落点 → 结项日期
-->

## 4. 工程基线数据

> standards 各条款引用的项目基线数据；变化时同轮更新。

### 4.1 直连白名单基线（arch-guard，只减不增）

当前 `scripts/agent-tools/arch-guard.sh` 白名单（历史例外）：

| 规则 | 白名单条目 | 原因 |
|------|-----------|------|
| R2（UI 内联 JSON） | `lib/ui/settings_page.dart` | 导出预览口径豁免（前瞻：暂无效） |

> R1/R3/R5 白名单为空（无 lib/ui）；R4/R6/R7 无白名单（R7 启用前 `lib/tools/sample_tool_face.dart` 已退役，故无需历史例外）。新增任何白名单边须显式注明原因，且只减不增。

### 4.2 超标清单（只减不增）

| 文件 | 治理策略 |
|------|----------|
| （空） | 软红线 800 行；超标即登记，降到阈值下即移出 |
