---
status: active
updated: 2026-10-26
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
| 服务层 | 日历 W 档命令执行体 + 重要标记存储 + 收藏地点存储 + 天气城市存储 + ICS/系统日历订阅源真实实现 | `lib/service/calendar_actors.dart`、`lib/service/marker_store.dart`、`lib/service/favorite_place_store.dart`、`lib/service/geo_favorite_actors.dart`、`lib/service/weather_city_store.dart`、`lib/service/weather_city_actors.dart`、`lib/service/ics_feed_provider.dart`、`lib/service/system_calendar_port.dart`、`lib/service/composite_calendar_provider.dart` | `calendar_actors.dart` = 日历 5 个 W 档命令执行体（**由装配件登记进 CommandGateway**；feed 列表存 `SettingsKv`，幂等/作用域/护栏复检，输出统一 `{'success':…}` 信封）；`marker_store.dart` = `CalendarMarkerStore`（读）+ `CalendarMarkerWriter`（写，**只给 Actor 持有**）的内存与 SharedPreferences 双实现；`favorite_place_store.dart` = `FavoritePlaceStore`（读）+ `FavoritePlaceWriter`（写，**只给 Actor 持有**）内存/SharedPreferences 双实现（`geo_favorites` 键，上限 50 条）；`geo_favorite_actors.dart` = 收藏用户侧 Actor（`user_geo_favorite_add/delete`，**登记在用户侧注册表 AI 不可触达**，校验收口 + 写后回确认）；`ics_feed_provider.dart` = `CalendarFeedProvider` 真实源（autoUncompress + 3 跳重定向 + 10s 超时回退缓存、G2 频控 30s、G3 退订清缓存、G4 `feedId:uid` 复合键、E 拍板 PII 脱敏）；`system_calendar_port.dart` = `SystemCalendarPort` 的 MethodChannel 实现（平台异常→机器码）；`composite_calendar_provider.dart` = ICS + system 合并源（D1 排序、G4 复合键 `system:<uid>:<start>`、子源失败出 `warnings` 不静默） |
| 装配件 | 工具面装配收口（HTTP 调试通道 + Binder 生产通道共用同一份） | `lib/tool_face_assembly.dart` | 装配件（与 `main.dart`/`ports.dart` 同级，跨域 import 合法）：收口 **4 个域**（`buildMathTool()` / `buildGeoTool(...)` / `buildWeatherTool(...)` / `buildSystemPimTool(...)`），线级 = **33 action**（math 4 / geo 9 / weather 5 / pim 15，含 5 个 W 档）；新增能力只改本文件，两通道同步生效；日历侧同时新建（或复用注入的）`CommandGateway` 并登记 5 个 Actor；四域工具经各自 `buildXxxTool()` 统一标 `visibility: shared`（SDK 0.2.0） |
| 工具面扩展 | math_utility 领域网关（calc_eval / unit_convert / unit_list / list_stats） | `lib/tools/math/math_tool.dart` | 全 R 档 ⇒ 写门禁端口传 null（W 档物理不可达）；双轨出参（格式化 `result` 串 + 无损 `numericValue`），结构化错误带 offset/candidates/suggestion；action 名 1:1 沿用 `product/calculator.md`；`list_stats` Decimal 内核全程不转 double（长列表/高精度数值专用） |
| 工具面扩展 | geo 领域网关（geo_current / geocode / reverse / search_poi / route / static_map / compass / distance） | `lib/tools/geo_tool.dart` | 全 R 档；入参坐标默认 WGS-84，请求高德前统一 `CoordConvert.normalize` 到 GCJ-02；高德 REST 单一出口 `_amapGet`（`GeoHttpException.code` / `infocode` / `AMAP_PARSE_ERROR` 全带机器码，不以空值兜底）；静态图 Key/Secret 经 reader 懒读 |
| 工具面扩展 | weather 领域网关（forecast + air/indices/astronomy/minutely 域深化四件） | `lib/tools/weather_tool.dart` | 全 R 档（5 action）；出参双轨信封（空字段省略、不吐 null），`alerts` 恒 `[]`（弱依赖口径）；`days` 1~7（indices 1|3）、`lat/lng` 成对、astronomy `date` 格式校验一律带码返回，不静默兜底 |
| 工具面扩展 | system_pim 领域网关（日历 15 action，含 5 个 W 档） | `lib/tools/system_pim_tool.dart` | **已装配进线级**（4 域 33 action，33 个全部可用）；`time_now` = 当前时刻锚点（设备时区投影 + 工作日/节假日上下文，反 Agent 编日期）；3 个纯计算 R 档真实可用（date_calc/date_diff/workdays_between）；6 个 R 档接 Provider、源未注入 fail-closed 返 `ERR_CALENDAR_SOURCE_UNAVAILABLE`；5 个 W 档只 buildCommand（**命令名 = action 名**，校验与 SSRF 护栏下沉 Actor），经 `CommandGateway` 在生产路径闭环 |
| 工具面扩展 | 日历时间推演内核 + 法定节假日表（纯 Dart） | `lib/tools/calendar/date_math.dart`、`lib/tools/calendar/holiday_table.dart`、`lib/tools/calendar/marker_math.dart`、`lib/tools/calendar/lunar_math.dart`、`lib/tools/calendar/resolve_expression.dart`、`lib/tools/calendar/tz_math.dart` | `date_math.dart` = 成分跨度（逐月推进，不用毫秒相除）/ 工作日推演（调休补班 > 法定假 > 周末）/ delta 按 days→months→workdays→hours 顺序 + 月末 clamp，**禁 DateTime.now()**；`holiday_table.dart` = 2026 法定节假日表（**逐字照录国办 2025-11-04 通报**，`cn-2026.1`，法定假 33 天 + 调休补班 6 天）+ OTA 静态 JSON 同构入口；`marker_math.dart` = 重要标记推演（周年对齐、平年 02-29→02-28 标 `approximate`、农历标记标 `lunarPending` 不展开、42 格月网格 + badge）；`lunar_math.dart` = 农历/节气换算（闰月=负月份、节气 key 归一）；`resolve_expression.dart` = 日期表达式消歧（today±N / next_<weekday> / 季度首 / `lunar:YYYY-闰M-DD` / 节日别名，相对式须显式 baseDate）；`tz_math.dart` = 时区投影（自带 offset 与纯墙钟分流、bundled latest.tzf 幂等初始化、DST 库级判定） |
| MCP 内核 | ICS 解析与 PII 脱敏（日历域内核件，service 与 tools 双复用） | `lib/mcp/ics_parser.dart`、`lib/mcp/pii_mask.dart` | RFC 5545 子集（行展开/转义/组件边界）、RRULE 四 FREQ + INTERVAL/COUNT/UNTIL/BYMONTHDAY/BYDAY、EXDATE / RECURRENCE-ID override / STATUS:CANCELLED（C2）、单事件 365 实例截断（C1）；**ICS 时间解析禁 `toUtc()`**（会把墙钟按本机时区偏移，实例整体漂一天）；`pii_mask.dart` = E 拍板脱敏（默认只掩码电话/邮箱，同串同掩码保确定性） |
| 工具面扩展 | 天气端口信封（WeatherResult / WeatherError / 6 个错误码） | `lib/mcp/weather_provider.dart` | 端口签名 `forecast({city,lat,lng,days})` 返回**不可空信封**（旧 `forecast3 → Map?` 的静默 null 被 weather.md 判为反模式，已废弃无兼容分支）；城市搜索面 = `searchCity`（搜索条）+ `lookupCityByCoords`（地图选点反查，`location=lng,lat` 经度在前），同为 GeoAPI lookup 多候选信封，「查无此城」= 成功空列表 |
| 工具面扩展 | 计算器能力内核：单位注册表 + 换算引擎（纯 Dart 无头） | `lib/tools/math/unit_definition.dart`、`lib/tools/math/unit_registry.dart`、`lib/tools/math/convert_result.dart`、`lib/tools/math/unit_converter.dart` | 11 量纲 × 4 transform（linear/affine/reciprocal/iecSi）；别名归一化**单一真相源**，别名冲突 fail-fast；基准单位走显式表（≠ dimension 名）；契约见 `product/calculator.md` 附录 A |
| 工具面扩展 | 计算器表达式内核：Sanitizer + Lexer + Parser + Evaluator（纯 Dart 无头） | `lib/tools/math/math_error.dart`、`lib/tools/math/expression_sanitizer.dart`、`lib/tools/math/expression_lexer.dart`、`lib/tools/math/expression_parser.dart`、`lib/tools/math/expression_evaluator.dart` | Sanitizer 全角/`×`/`÷`/千分位/币种符保守清洗 + cleaned→original 位移回填；Lexer 单位 run 仅被 `to` 确认；Parser 递归下降产出 AST（`^` 右结合 / 一元负号低于 `^` / 隐式乘法 / `A+B%` 歧义 warning / `NESTING_TOO_DEEP`）；Evaluator 走 **Decimal 主链路**（`0.1+0.2=0.3` 精确）+ DoS 红线 `EVAL_STEP_LIMIT`，超越函数/单位换算因固有非精确走 double 回装 Decimal（非静默降级） |
| 自更新 | 安装器、远程配置热更、更新清单、更新服务 | `lib/update/installer.dart`、`lib/update/remote_config_store.dart`、`lib/update/update_manifest.dart`、`lib/update/update_service.dart` | 发布链路见 workflow skill 的 `release-r2` |
| 地理/地图内核 | 坐标纠偏（WGS-84↔GCJ-02↔BD-09）、Haversine 测距 | `lib/geo/coord_convert.dart` | 纯 Dart 无头，arch-guard R4；WGS-84→GCJ-02 自动归一 |
| 地理/地图内核 | 高德静态图 URL 构建器（免 Native 3D SDK 轻量渲染） | `lib/geo/static_map_url.dart` | 入参可声明任意坐标系，内部归一化到 GCJ-02；集成 sig 签名 / RDP 抽稀 / Auto-bounding 视口自适应 |
| 地理/地图内核 | 高德数字签名（Sig/MD5） | `lib/geo/amap_sign.dart` | 参数升序拼接 + secret → MD5，防 INVALID_USER_SCODE |
| 地理/地图内核 | 轨迹抽稀（RDP） | `lib/geo/rdp.dart` | 道格拉斯-普克，折线硬性≤80 点，防 URL 超 2048 触发 414 |
| 地理/地图内核 | 高德 HTTP / 位置传感器端口（依赖反转接缝） | `lib/mcp/geo_provider.dart` | 对齐 `weather_provider.dart`；未注入源抛 `ERR_AMAP_KEY_MISSING`（工程规范 §1.2） |
| 平台层（Android 原生） | 系统日历读取 + 权限引导通道（平台通道实现 `SystemCalendarPort` / `CalendarPermissionPort`） | `android/app/src/main/kotlin/com/goodhub/goodtools/SystemCalendarChannel.kt` | MethodChannel `com.goodhub.goodtools/calendar`；查 `CalendarContract.Instances`；**双引擎注册**（`MainActivity.configureFlutterEngine` + `McpBinderService.initEngine`——生产 Binder 通道漏挂即 `MissingPluginException`）；子线程查询，READ_CALENDAR 缺权 fail-closed；`requestCalendarPermission`（U12b）：未授权 → 跳转应用详情设置页（`ACTION_APPLICATION_DETAILS_SETTINGS`），回 `settings_opened`，不弹假授权 |
| 平台层（Android 原生） | 凭证安全存储通道（平台通道实现 `SecretStore`，U5 结项） | `android/app/src/main/kotlin/com/goodhub/goodtools/SecretStoreChannel.kt` | MethodChannel `com.goodhub.goodtools/secret_store`；Keystore 持 AES-256-GCM 密钥（别名 `goodtools_secret_store_v1`，不可导出，硬件支持进 TEE/StrongBox），密文 Base64(IV‖密文) 落**专用** SharedPreferences `goodtools_secrets`（与普通设置物理隔离）；**双引擎注册**；**不设用户认证**（常驻壳 Agent 须无解锁读凭证，威胁模型=设备物理沦陷）；fail-closed：任何密钥/密文异常转 `KEYSTORE_ERROR`，不假装「未配置」 |
| 读聚合层 | 用户设置、重要标记、收藏地点与天气城市的类型化读（R5 落点） | `lib/repository/settings_repository.dart`、`lib/repository/marker_repository.dart`、`lib/repository/favorite_repository.dart`、`lib/repository/weather_city_repository.dart` | UI 经此读，**不直连** KV / store；只持读端口（标记/收藏**写端口不在此暴露**——写必经 CommandGateway 用户侧注册表）；设置快照对凭证**只回显「已配置 + 掩码尾号」** |
| UI 适配层 | 人前端的类型化适配（纯 Dart，无 Flutter） | `lib/ui_ports/calculator_port.dart`、`lib/ui_ports/geo_port.dart`、`lib/ui_ports/geo_lbs_port.dart`、`lib/ui_ports/settings_port.dart`、`lib/ui_ports/status_port.dart`、`lib/ui_ports/calendar_port.dart`、`lib/ui_ports/weather_port.dart` | 唯一出口：把内核结果转成**类型化视图模型**（`CalcView` / `GeoView` / `FavoritePlaceView` / `GeoStaticMapView` / `PlaceView` / `RouteView` / `CallEventView` / `CalendarSnapshotView` / `WeatherView`），UI **禁**消费 MCP 文本信封（否则必 jsonDecode 触 R2）；可 headless 单测；`calendar_port` 另持运行时权限申请端口（U12b）；`geo_port` 另含 `GeoMapPort`（静态图 URL 构建，Key/Secret 懒读闭包由装配件注入，缺 Key fail-closed `ERR_AMAP_KEY_MISSING`，UI 不接触 Key 明文）；`geo_lbs_port.dart` = **人机同源 LBS 端口**（`GeoLbsPort`：搜索=geocode+POI 双源合并、四模态路径规划含步骤折线，与 MCP geo 工具面**共用同一 `GeoHttpProvider` 实例与解析口径**，transit 缺城市前置拦 `CITY_REQUIRED`） |
| 用户层 | 控制台三 Tab（仪表盘 / 能力 / 设置）+ 四域子页面 + 通用组件 + 主题 | `lib/ui/home_shell.dart`、`lib/ui/dashboard_page.dart`、`lib/ui/capabilities_page.dart`、`lib/ui/calculator_page.dart`、`lib/ui/geo_page.dart`、`lib/ui/calendar_page.dart`、`lib/ui/weather_page.dart`、`lib/ui/settings_page.dart`、`lib/ui/components/app_components.dart`、`lib/ui/components/block_canvas.dart`、`lib/ui/components/calendar_grid.dart`、`lib/ui/theme.dart`、`lib/ui/tokens/app_tokens.dart`、`lib/ui/tokens/app_theme_data.dart` | 唯一 import material 的地方；token 唯一出处 = `lib/ui/tokens/`（色彩/排印/几何/动效四组，深浅**语义名一致**）；组件**零魔法值**；状态**双通道**（色 + 形/文字）；域子页面只读查询/本地计算、**无写入口**（配置写只经设置页，R1 单一心智）；hub→子页面 push 导航，子页面经 `ShellNav` 回跳设置 Tab。计算器子页面 = **区块草稿计算台（草稿纸模型）**（设计 SSOT = `project/calculator-blocks.md`）：纸面为连续书写表面（块体透明零容器感，聚焦行 = IDE 式光标带 + Leader Dots 引线 + Gutter 行号），每逻辑块一行算式 + 内嵌实时结果；装配 `BlockCanvas` 底座（焦点链 / IME Guard / 粘贴裂变 / 弹性槽位四件套，系统共用组件、对领域零感知）+ `CalculatorPort.evalLine` 行内解析注入（纯 Dart：全角归一 / `85%` 后缀 / `<表达式> 单位 to 单位` / `ans` 引用上一成功块），Page 级 `LineRecord` 受控单源、150ms 防抖全量重算、聚焦块光标不回写；纸面级能力 = Gutter 行号 / Telemetry 汇总条（有效行·最终 ans·累计总和）/ 全局工具条（全纸复制·清空·Reader Mode）/ 上游故障点击导航；手写板/点按键盘/LaTeX 面已退役（ML Kit 与 flutter_math_fork 依赖已卸载）。地图子页面 = **FlutterMap 全屏交互画布**（纯 Dart 渲染 + 高德 XYZ 瓦片源 GCJ-02，`amap_flutter_map` 已退役——decisions.md 2026-10-22）：右侧浮动控件列（我的位置/缩放/指北）+ 指北针/比例尺观仪 + 底部上滑六分段面板（搜索/路线/收藏/测距/天气/纠偏），LBS 经 `GeoLbsPort` 人机同源；「天气」分段 = 选点加城市（落点 → `lookupCityByCoords` 坐标反查 → 候选点「添加」经 `user_weather_city_add` 入列，与天气页城市列表同库）；瓦片源为非官方承诺接口，失效降级静态图为域内待办。天气子页面 = **手风琴城市卡（摘要行逐城聚合与详情同键共用 provider 逐城 TTL 缓存，点卡就地展开实时+逐日+预警详情，无独立详情区块）** + 底部胶囊搜索条 + 半/全屏面板搜索添加（`DraggableScrollableSheet` 范式对齐地图页）；**手势即操作**（左滑卡片删除 Dismissible+撤销 SnackBar、点卡展开/收起、键盘搜索键提交，页面零操作按钮）；城市增删经用户侧命令族（AI 不可触达）；首页 = 直接内嵌用户钉住的域二级页（默认日历，无卡片中间层；设置键 `home_pinned_domain` 仅 `user_set_home_pinned_domain` 写；共享件 `DomainCard`/`openDomainPage`/`kDomainEntries` 在 `capabilities_page.dart`，hub push 与首页内嵌共用同一份子页面实例） |
| 用户写入口 | 用户侧命令族（`user_*`）+ 设置/收藏/天气城市 Actor + 网关用户侧注册表 | `lib/action/command_gateway.dart`、`lib/action/settings_commands.dart`、`lib/action/geo_commands.dart`、`lib/action/weather_commands.dart`、`lib/service/settings_actors.dart`、`lib/service/geo_favorite_actors.dart`、`lib/service/weather_city_actors.dart` | 网关**用户侧注册表**（`registerUser`/`dispatchUser`）与 AI 侧**物理分离**——AI 不可触达（信任模型机制化）；返回**类型化对象**非文本信封；用户侧跳过 AI 专属 `forbiddenKeys` 门（该门拦 AI 不拦用户本人）；`geo_commands.dart` = 收藏地点命令族（`user_geo_favorite_add/delete`），校验与落盘在 `geo_favorite_actors.dart` |
| 凭证与持久化 | 设置键单一真相源 + 凭证安全存储端口 + 持久化 KV 分流 + Keystore 平台实现 + 脱敏开关接线 | `lib/mcp/settings_keys.dart`、`lib/mcp/secret_store.dart`、`lib/service/keystore_secret_store.dart`、`lib/service/in_memory_secret_store.dart`、`lib/service/persistent_kv.dart` | 键常量收口（此前散落三处）；`SecretAwareKv` 把**凭证键分流到 SecretStore**、其余键走 SharedPreferences——凭证**不落明文**（standards §6.1）；平台实现 = `KeystoreSecretStore`（Keystore 持密钥、密文跨 isolate 可见，U5 结项，架构债 #1 清零）；`InMemorySecretStore` 退位为 headless 单测替身；平台失败透出 `SecretStoreException`（fail-closed，不吞 null）；`privacy_mask_pii` 开关经 `piiMaskEnabledBy`（`'0'`=关，未设置=开，保护性缺省）注入 ICS/系统两路合并源，每次查询现读 |
| MCP 内核 | 工具调用事件流（内核侧吐，UI 侧订阅） | `lib/mcp/mcp_server.dart` | `McpCallEvent{name,ts,elapsedMs,ok}`——`ok` 由工具面 `isError` **唯一派生**；`McpController` 做稳定代理（server 重建不断流）；类型化对象非文本信封 |
| 测试 | 纯 Dart 内核全链路测试（无设备可跑） | `test/smoke_test.dart`、`test/geo_test.dart`、`test/category_gateway_test.dart`、`test/unit_converter_test.dart`、`test/expression_lexer_test.dart`、`test/expression_parser_test.dart`、`test/expression_evaluator_test.dart`、`test/math_tool_test.dart`、`test/geo_tool_test.dart`、`test/tool_face_assembly_test.dart`、`test/amap_http_provider_test.dart`、`test/weather_tool_test.dart`、`test/qweather_provider_test.dart`、`test/system_pim_tool_test.dart`、`test/holiday_table_test.dart`、`test/ics_parser_test.dart`、`test/ics_feed_provider_test.dart`、`test/calendar_actors_test.dart`、`test/marker_math_test.dart`、`test/composite_calendar_provider_test.dart`、`test/tz_math_test.dart`、`test/lunar_math_test.dart`、`test/ui_console_test.dart`、`test/keystore_secret_store_test.dart`、`test/calendar_privacy_permission_test.dart`、`test/calendar_permission_port_test.dart`、`test/weather_port_test.dart`、`test/geo_favorite_test.dart`、`test/geo_lbs_port_test.dart`、`test/weather_city_store_test.dart` | 覆盖 InMemoryKv / CommandGateway / McpServer / 坐标互转闭环 / 静态图 URL / 八方位 / 网关派发契约（枚举外拦截、写门禁拦截、错误前缀注入、isError 唯一派生）/ 单位换算四模型与 reciprocal 跨制反比 / Sanitizer 保守清洗与位移回填 / 解析器优先级-结合性、隐式乘法、百分比歧义 warning、嵌套深度红线 / 求值器 Decimal 精确性、运算符语义、超越函数、单位换算、错误码与 EVAL_STEP_LIMIT / 领域网关适配层（math 3 + geo 9 对账、坐标归一化、错误机器码、IP 定位兜底与周边检索端点）/ **装配收口**（工具数 = 域数 4、action 合计 26、双通道共用、Key 懒读即配即生效、未配 Key fail-closed）/ **高德 REST 真实链路**（本地 `HttpServer` 验证 key 注入、非 200、非 JSON、结构漂移）/ 日历域全链路（15 action 对账含 time_now、W 档门禁真验、节假日表逐字对账、RFC 5545 展开与 EXDATE/override、农历三策略、时区 DST、ICS 拉取与复合键、合并源 warnings）/ **人前端接缝**（AI 侧不可触达 `user_*` 命令、凭证零明文回显、凭证键与普通键分流、Actor 结构化失败、适配层双轨出参与越界拒绝）/ **收藏链路**（store 读写删与上限、Actor 校验全分支与 AI 侧 fail-closed、GeoMapPort 缺 Key fail-closed 与坐标归一化、视图映射）/ **GeoLbsPort**（搜索双源合并与 warnings、路线四模态解析含步骤折线、WGS84 归一化链路、transit 城市前置拦、机器码透传）/ **天气链路**（provider 真实链路与 200 内业务码、searchCity/lookupCityByCoords 反查、域深化四件投影与独立缓存键位、配额护栏三件套、UI 适配投影、城市 store/Actor 校验）/ **首页快捷钉选**（四域枚举一致 / 结构化失败 / AI 侧隔离 / 未设默认态） |

| Android 桥接 | 本地 Binder 插件服务（server 端）+ 契约 SDK 依赖 | `android/app/src/main/kotlin/com/goodhub/goodtools/McpBinderService.kt`、`android/app/build.gradle.kts` | **2026-10-20 改用官方 SDK**（`com.zzh.goodhub.mcp:goodhub-mcp-plugin-core`，2026-10-21 升 **0.2.0**）：继承 `GoodHubPluginService` + 重写 `handleJsonRpc` 接管路由（业务层在 Dart，SDK 反射派发器扫不到 `@McpTool`，不接管则 `tools/list` 返回空、工具全丢）；**F1**：tools/call 走 `_async` + onEvent 终帧切片，不得退化；终帧推送用 SDK `tryEmitEvent`（回报成败，保住 `[DEGRADE]` 可观测性）；契约唯一物理副本在 goodhub-mcp-sdk 仓 `:contract`，本仓自拷贝 `android/app/src/main/aidl/` 已删 |
| MCP 内核 | 工具可见性标记（SDK 0.2.0 `ToolVisibility`，纯声明） | `lib/mcp/category_tool_face.dart`（`ToolVisibility` + `CategoryTool.toSchema`） | 四个聚合工具（math_utility / geo / weather / system_pim）显式 `visibility: ToolVisibility.shared`；`toSchema()` 下发每个工具对象的 `_meta.goodhub.visibility`（`private` / `shared`）。**必由 Dart 侧下发**：Kotlin 侧全量接管路由，SDK 反射派发器扫不到注解参数，漏发即宿主按 default-deny 判私有；默认 `private`（漏标即最严），标记不影响条目数与 `tools/call` 路由，曝光策略归宿主 |

## 2. 文档落点

| 主题 | 文档路径 | 状态 |
|------|----------|------|
| 工程规范 SSOT（架构红线 / 分层 / 工具面契约） | `docs/project/coding-standards.md` | active |
| 领域网关工具设计（分类嵌入模式） | `docs/project/domain_gateway.md` | active（33 action 全可用，能力矩阵 1:1 对账闭环） |
| 产品概述（能力/架构/信任模型） | `docs/product/overview.md` | active |
| 日历能力 | `docs/product/calendar.md` | active |
| 计算器能力 | `docs/product/calculator.md` | active |
| 地理能力 | `docs/product/geo.md` | active |
| 天气能力 | `docs/product/weather.md` | active |
| UI 开发规范（用户层） | `docs/project/ui-design.md` | active |
| 控制台 UI 落地设计（人前端页面规格与接缝） | `docs/project/ui-console.md` | active |

> 三处同步纪律：本表 + `docs/README.md` + goodTools-docs 域表（goodTools-docs 维护协议）。

## 3. 架构债与依赖违例登记

> 活跃表只留未结项；清零时结项归档（压缩为「#N 摘要 → 落点 → 结项日期」，细节归 Git log / epic devlog）。散修须先登记再动手（goodTools-index §3）。

| # | 债 | 落点 | 状态 |
|---|----|------|------|
| （空——#1 已结项，见归档区） | | | |

<!-- 归档区（结项后移入，压缩为一行）：
- #1 凭证无平台级安全存储（内存 SecretStore 重启失位 + 跨 isolate 不可见）→ `SecretStoreChannel.kt`（Keystore AES-256-GCM + 密文专用 SharedPreferences）+ `keystore_secret_store.dart` 装配注入 → 结项 2026-10-20
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

### 4.3 环境基线（SDK 与契约）

| 项 | 值 | 依据 |
|---|---|---|
| `minSdk` | **34**（Android 14） | 插件接入 SDK（`goodhub-mcp-plugin-core` / `goodhub-mcp-contract`）两模块均 `minSdk=34`，app 低于 34 会 manifest merger 直接失败（`uses-sdk:minSdkVersion 24 cannot be smaller than version 34`）；goodhub 本地插件链路本身即 Android 14+ 基线 |
| 契约来源 | `com.zzh.goodhub.mcp:goodhub-mcp-contract`（SDK 仓 `:contract` 模块提供） | 契约唯一物理副本在独立仓 `goodhub-mcp-sdk`；本仓自拷贝 `android/app/src/main/aidl/` 已删（2026-10-20） |
| 插件 SDK | `com.zzh.goodhub.mcp:goodhub-mcp-plugin-core:0.2.0` | 版本与 `contract_version` 绑定，见 SDK 仓 `VERSION`；0.2.0 增 `@McpTool(visibility/readOnlyHint/destructiveHint)`，**本仓业务在 Dart ⇒ 可见性由 `CategoryTool.toSchema` 自下发**（见 §1 落点行） |
| 仓内解析通路 | `mavenLocal()` + 离线分发件目录（`-PmcpSdkDist=<dir>` 覆盖，默认 sibling 仓 `dist/maven-repo`） | 公网坐标（GitHub Packages）需 token（匿名 401），详见 SDK 仓 README §2；**SDK 升版后本机消费前须先在 SDK 仓跑一次 `scripts/dist.sh`**（mavenLocal 不自动跟进，否则解析 FAILED——0.2.0 升级实测踩到） |
