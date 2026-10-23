---
dev-loop: devlog
format: v1
epic: domain_gateway
total-merged: 1
last-merge: 2026-10-20
---
- [2026-10-20] [验证]: 全链路全绿：flutter analyze → No issues found；flutter test → All tests passed (142)；toolbox run arch-guard → OK（6 条全过）；toolbox run docs-lint → ✓。（S3 calculator 内核变更明细见 epics/calculator/devlog.md）
- [2026-10-20] [变更]: S7 装配收口——新增 `lib/tool_face_assembly.dart`（装配件）收口 `buildMathTool()` + `buildGeoTool(...)`，`main.dart`（HTTP 调试通道）与 `mcp_binder_entrypoint.dart`（Binder 生产通道）同步切到该装配，能力面首次上线（2 域工具 / 11 action）；新增 `lib/service/amap_http_provider.dart`（高德 REST 真实源，dart:io + Key 懒读），`AndroidManifest.xml` 补 `INTERNET` 权限。
- [2026-10-20] [变更]: `buildGeoTool` 的 `amapWebKey`/`amapSecret` 静态参数改为 `webKeyReader`/`secretReader` 懒读 reader——装配是同步的（Binder 入口无法 await）而 KV 读配置是异步的；副作用是补填 Key 后**无需重建工具面**即生效（单测已断言）。`test/geo_tool_test.dart` 两处构造随之调整。
- [2026-10-20] [决策]: 装配工厂落**装配件**而非 service/tools——`service`（McpController）出向不含 `tools`、`tools` 出向不含 `service`（真实 Provider 住 service 层），只有装配件可跨域 import，故不在 `mcp_controller.dart` 内收口。
- [2026-10-20] [决策]: arch-guard 启用 R7 走「退役」而非「白名单」——白名单纪律只减不增，故 S7 提前退役 `lib/tools/sample_tool_face.dart`（原属 S8），连同 `ports.dart`/`docs/product/overview.md`/`index.md` 引用一并清理，R7 零白名单上线。
- [2026-10-20] [收口]: arch-guard 6→7 条（新增 `lib/tools` 禁 dispatch/admits 调用），self-test 补坏样本与干净样本各一（防误报）；analyze 0 issue；flutter test 全绿 202（新增 tool_face_assembly 12 + amap_http_provider 6）。
- [2026-10-20] [变更]: S8 Contract 收尾——核查确认旧返回形状兼容层零残留；删除 `McpServer._dispatch` 的 `suggest_user_setting` 工具名嗅探特例（内核不再感知业务工具名），建议通道上移为 `McpController.pushSuggestion()`（`suggestionStream` 语义不变）；`serverInfo.name` → `goodtools`（`McpServer.serverName/serverVersion` 常量）、前台服务通知标题 → `goodTools`，清模板项目名残留。
- [2026-10-20] [决策]: `pushSuggestion` 由**宿主显式调用**而非内核回调——内核嗅探工具名在网关模式下必然静默失效（线级无该工具），且把业务语义写进内核违反分层；端口保留在 service 层（controller）供设置域未来接线。
- [2026-10-20] [遗留]: `McpServer._builtinInstructions` 仍是「拾光排程师」文案（自 shiguang 提取），与本 app 角色不符——重写需产品定位拍板，已登记域内待办，S8 不擅改。
- [2026-10-20] [收口]: `smoke_test.dart` 补 3 条内核契约断言（错误态 isError 透传、serverInfo 非模板名、pushSuggestion 广播）；analyze 0 issue；flutter test 全绿 205。
- [2026-10-21] [变更]: SDK 0.2.0 可见性对齐——`CategoryTool` 增 `visibility` 字段（新枚举 `ToolVisibility`：`private` / `shared`，默认 `private` = default-deny），`toSchema()` 恒定下发 `_meta.goodhub.visibility`；四个聚合工具（math_utility / geo / weather / system_pim）在各自 `buildXxxTool()` 显式标 `shared`。**必由 Dart 侧下发**：Kotlin 侧 `handleJsonRpc` 全量接管路由，SDK 反射派发器扫不到 `@McpTool(visibility=...)`，漏发即宿主按 default-deny 把四域全判私有。纯声明语义（不剔除条目、不拦 tools/call），曝光策略归宿主。
- [2026-10-21] [收口]: `android/app/build.gradle.kts` 升 `goodhub-mcp-plugin-core:0.2.0` 后实测依赖解析 **FAILED**（`mavenLocal()` 与 SDK 仓 `dist/maven-repo` 当时仅 0.1.0/0.1.1；GitHub Packages 匿名拉为 401）——在 goodhub-mcp-sdk 仓跑 `scripts/dist.sh` 产出 0.2.0 离线分发件后复验通过（`:app:dependencies` 解析出 plugin-core 0.2.0 → contract 0.2.0，`:app:compileReleaseKotlin` BUILD SUCCESSFUL）。**口径**：SDK 升版后本机消费前须先在 SDK 仓跑一次 dist.sh（mavenLocal 不会自动跟进）。
