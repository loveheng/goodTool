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
