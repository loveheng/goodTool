---
memo: todos
format: v3
epic: ui-console
---

# ui-console · 域内待办

- [x] [2026-10-20] (功能) (层:L2) (重:重) U1 用户写入口：`CommandGateway` 增**用户侧注册表**（`registerUser` / `dispatchUser`，与 AI 侧 `register` 物理分离，跳过 AI 专属 `forbiddenKeys` 门）+ `lib/action/settings_commands.dart`（`user_set_api_key` / `user_set_privacy_switch` / `user_set_identity_profile`）+ `lib/service/settings_actors.dart`（Actor 落 KV / 写后回最新快照） (src: 用户)
- [x] [2026-10-20] (功能) (层:L2) (重:中) U2 内核调用事件流：`McpServer` 增 `onCall`（`{name, ts, elapsedMs, ok}`，内核侧吐、UI 侧 `StreamBuilder` 接，守 R4）+ `McpController` 代理暴露该流 (src: ai)
- [x] [2026-10-20] (功能) (层:L2) (重:中) U3 读聚合层 `lib/repository/`：`settings_repository.dart`（SettingsKv 类型化读）+ `marker_repository.dart`（marker_store 类型化读）——R5 落点，UI 经此读不直连存储 (src: ai)
- [x] [2026-10-20] (功能) (层:L2) (重:中) U4 适配层 `lib/ui_ports/`：`calculator_port` / `geo_port` / `weather_port` / `calendar_port` 四个纯 Dart 适配器 + 类型化视图模型（**禁 import Flutter**、禁内部 JSON 编解码，可 headless 单测） (src: ai)
- [x] [2026-10-20] (功能) (层:L2) (重:重) U5 持久化（清 `index.md` 架构债 #1）：KV 持久化实现落地 + `SharedPrefsMarkerStore` 注入装配件，替掉 `InMemoryKv` / `InMemoryMarkerStore` 缺省——**已落**：`SecretAwareKv` 分流 + `SharedPrefsKv` 持久化 + `LazySharedPrefsKv`（同步装配、跨 isolate 可见，Binder 生产通道已接）+ `SharedPrefsMarkerStore` 注入；**Keystore 平台实现已落**（2026-10-20 收尾）：`SecretStoreChannel.kt`（AES-256-GCM 密钥持 AndroidKeyStore、密文落专用 SharedPreferences、双引擎注册、fail-closed）+ `KeystoreSecretStore`（可注入 MethodChannel，平台故障透出 `SecretStoreException` 不吞 null）+ 双装配注入（main.dart / mcp_binder_entrypoint.dart）+ headless 单测 4 例；架构债 #1 结项归档；`InMemorySecretStore` 退位为单测替身 (src: 用户)
- [x] [2026-10-20] (功能) (层:L2) (重:中) U6 主题与 token：`lib/ui/tokens/`（色彩/排印/几何/动效四组 token，**唯一出处**）+ `lib/ui/theme.dart`（M3、暗色优先、`ThemeExtension` 注入，等宽遥测轨） (src: ai)
- [x] [2026-10-20] (功能) (层:L2) (重:中) U7 通用组件 `lib/ui/components/`：状态点（色+形双通道）、权限药丸、细边框卡、等宽遥测文本、空态占位、编号列表——**零魔法值**，全取 token (src: ai)
- [x] [2026-10-20] (功能) (层:L2) (重:重) U8 仪表盘页 `lib/ui/dashboard_page.dart`：服务状态卡（运行/端口/客户端）+ 权限就绪矩阵（定位/日历/地图 Key 药丸）+ 实时调用流水（`McpServer.onCall`） (src: ai)
- [x] [2026-10-20] (功能) (层:L2) (重:重) U9 沙盒页 `lib/ui/sandbox_page.dart`：时空计算（当前坐标/火星坐标/测距）+ 日历快照（今日事件 + 重要标记）+ 高精计算器自测（**双轨出参**：格式化串 + 无损 numericValue） (src: ai)
- [x] [2026-10-20] (功能) (层:L2) (重:重) U10 设置页 `lib/ui/settings_page.dart`：MCP 服务段（启停/端口/令牌重生成）+ 地图与天气 Key 段 + 脱敏开关段 + 身份画像段；**写必走 U1 用户命令**，错误态情感化可操作（缺权限 → 警告卡 + 跳转系统授权） (src: ai)
- [x] [2026-10-20] (集成) (层:L3) (重:重) U11 页面装配：`lib/ui/home_shell.dart`（NavigationBar 三 Tab：仪表盘/沙盒/设置）+ `lib/main.dart` 接线（现状仅打印 token 的启动页 → 真页面），McpController 经 Provider 注入页面 (src: ai)
- [x] [2026-10-20] (功能) (层:L2) (重:中) U12a 隐私设置「日程敏感字段过滤」开关接线：`piiMaskEnabledBy`（`'0'`=关、未设置=开——保护性缺省无回归）+ ICS 路查询现读 + 系统路经 `CompositeCalendarProvider.maskPiiEnabled` 闭包注入（tool_face_assembly 与 main.dart 同口径防双通道漂移）+ 设置快照默认态与内核同源 + 设置页文案订正（只脱敏地点/描述，标题不脱敏）；单测覆盖三态与现读生效 (src: 用户)
- [x] [2026-10-20] (功能) (层:L2) (重:中) U12b 运行时日历权限申请 UI 入口：Kotlin `requestCalendarPermission`（未授权 → 跳转应用详情设置页，回 `settings_opened`，不弹假授权）+ `lib/service/calendar_permission_port.dart`（端口 + MethodChannel 实现，fail-closed 机器码）+ `CalendarPort.requestPermission` 类型化视图 + 日历子页面警告卡「去授权」；单测覆盖 granted/settings_opened/平台故障/语义异常四路 (src: 用户)
- [x] [2026-10-20] (集成) (层:L3) (重:重) U13 验收与登记：`toolbox run arch-guard` R1–R6 全过（**R1/R3/R5 机械扫描首次真正生效**）+ `flutter analyze` 0 issue + `flutter test` 全绿 + `docs/project/index.md` 代码落点表登记新落点 + `ui-console.md` 状态回填 (src: ai)
- [x] [2026-10-20] (功能) (层:L2) (重:重) U14 域子页面拆分（用户拍板）：设计稿先行（ui-console.md §1 红线调和 + §3 重写为「三 Tab + hub + 四域子页面」+ ui-design.md §3.3 同步）；沙盒单页退役，新增 `capabilities_page`（hub，不就绪探测防双源）/ `calculator_page` / `geo_page` / `calendar_page`（只读 + U12b 权限引导）/ `weather_page`（缺 Key 引导跳设置 Tab）；新增 `lib/ui_ports/weather_port.dart`（和风 → 类型化视图，与工具面共用同一 QWeatherProvider 实例）；`home_shell` 改三 Tab + `ShellNav` InheritedWidget 导航；共享组件 `ErrorLine`/`CalcResultCard`/`GuidanceCard` 入 components；子页面**无写入口**（配置写只经设置页，R1 单一心智）、**不做日程管理**（红线调和见决策日志） (src: 用户)
- [ ] [2026-10-20] (验收) (层:L3) (重:中) U15 真机侧载核对：ui-console.md §6 视觉验收项（环境无模拟器，唯一途径）——需用户装 debug 包走查四域子页面/权限引导/天气引导/Keystore 凭证持久化（重启不丢 + Binder 通道可见） (src: 用户)
