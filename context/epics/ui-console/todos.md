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
- [ ] [2026-10-20] (功能) (层:L2) (重:重) U5 持久化（清 `index.md` 架构债 #1）：KV 持久化实现落地 + `SharedPrefsMarkerStore` 注入装配件，替掉 `InMemoryKv` / `InMemoryMarkerStore` 缺省——**已落**：`SecretAwareKv` 分流 + `SharedPrefsKv` 持久化 + `LazySharedPrefsKv`（同步装配、跨 isolate 可见，Binder 生产通道已接）+ `SharedPrefsMarkerStore` 注入；**剩余**：Keystore 平台实现 `SecretStore`——现为内存实现，故①重启凭证失位 ②**跨 isolate 不可见**（UI 写入的 Key 对 Binder 生产通道的 Agent 不可见）；已登记 `index.md` 架构债 #1，接口就位、接入不改装配面 (src: 用户)
- [x] [2026-10-20] (功能) (层:L2) (重:中) U6 主题与 token：`lib/ui/tokens/`（色彩/排印/几何/动效四组 token，**唯一出处**）+ `lib/ui/theme.dart`（M3、暗色优先、`ThemeExtension` 注入，等宽遥测轨） (src: ai)
- [x] [2026-10-20] (功能) (层:L2) (重:中) U7 通用组件 `lib/ui/components/`：状态点（色+形双通道）、权限药丸、细边框卡、等宽遥测文本、空态占位、编号列表——**零魔法值**，全取 token (src: ai)
- [x] [2026-10-20] (功能) (层:L2) (重:重) U8 仪表盘页 `lib/ui/dashboard_page.dart`：服务状态卡（运行/端口/客户端）+ 权限就绪矩阵（定位/日历/地图 Key 药丸）+ 实时调用流水（`McpServer.onCall`） (src: ai)
- [x] [2026-10-20] (功能) (层:L2) (重:重) U9 沙盒页 `lib/ui/sandbox_page.dart`：时空计算（当前坐标/火星坐标/测距）+ 日历快照（今日事件 + 重要标记）+ 高精计算器自测（**双轨出参**：格式化串 + 无损 numericValue） (src: ai)
- [x] [2026-10-20] (功能) (层:L2) (重:重) U10 设置页 `lib/ui/settings_page.dart`：MCP 服务段（启停/端口/令牌重生成）+ 地图与天气 Key 段 + 脱敏开关段 + 身份画像段；**写必走 U1 用户命令**，错误态情感化可操作（缺权限 → 警告卡 + 跳转系统授权） (src: ai)
- [x] [2026-10-20] (集成) (层:L3) (重:重) U11 页面装配：`lib/ui/home_shell.dart`（NavigationBar 三 Tab：仪表盘/沙盒/设置）+ `lib/main.dart` 接线（现状仅打印 token 的启动页 → 真页面），McpController 经 Provider 注入页面 (src: ai)
- [x] [2026-10-20] (功能) (层:L2) (重:中) U12a 隐私设置「日程敏感字段过滤」开关（UI 已落 `user_set_privacy_switch` 写入口 + 设置页开关；**剩余**：开关态尚未接到 `maskPii` 脱敏行为——内核目前是固定默认档） (src: 用户)
- [ ] [2026-10-20] (功能) (层:L2) (重:中) U12b 运行时日历权限申请 UI 入口（未授权 → `ERR_CALENDAR_PERMISSION` fail-closed 引导系统设置；需 Android 运行时权限请求，走平台通道） (src: 用户)
- [x] [2026-10-20] (集成) (层:L3) (重:重) U13 验收与登记：`toolbox run arch-guard` R1–R6 全过（**R1/R3/R5 机械扫描首次真正生效**）+ `flutter analyze` 0 issue + `flutter test` 全绿 + `docs/project/index.md` 代码落点表登记新落点 + `ui-console.md` 状态回填 (src: ai)
