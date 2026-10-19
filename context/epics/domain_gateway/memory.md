---
dev-loop: memory
format: v1
epic: domain_gateway
total-merged: 0
last-merge: none
---

# domain_gateway

- [挂载] docs/project/domain_gateway.md

## 进度
- 2026-10-20 **S1–S2 契约层已落地并全绿**：`McpToolFace.call` 返回完整 result，内核只透传；`lib/mcp/category_tool_face.dart` 四件套（SubAction/SubActionResult/CategoryTool/CategoryToolFace），单一出口保证 `category.action:code` 前缀不被早退绕过。
- **S3 calculator 数学内核（S3a–S3d）已迁移至 epics/calculator**（进度/决策/变更明细见该 epic memory + devlog）。
- 全链路现状（2026-10-20 S7 后）：202 tests + analyze 0 issue + arch-guard 7 条全过；线级工具面 = 2 个域工具（math_utility 3 action + geo 8 action），HTTP 与 Binder 双通道共用。

- 2026-10-20 **S7 装配收口已落地并全绿（202 项单测 + analyze 0 issue + arch-guard 7 条全过）**，能力面首次真正上线：

- **关键设计决策（S7）**：
  1. **装配工厂是「装配件」而非 service/tools 内建**：按 standards §1 分层矩阵，`service`（McpController）的出向只允许 `mcp`/`action`，故 `buildXxxTool()` 不得在 controller 内收口；反之 `tools` 域也不允许 import `service`（真实 Provider 住 service 层）。故新增 `lib/tool_face_assembly.dart`——与 `main.dart`/`ports.dart` 同级的装配件，可跨域 import，HTTP 调试通道与 Binder 生产通道**共用同一份装配**（禁两通道各自装配导致「HTTP 有、Binder 无」漂移）。
  2. **同步装配 + 异步配置 = 懒读 reader**：`mcpBinderMain` 是同步 `void`（无法 await），而高德 Key 走 KV 异步读。故 `AmapHttpProvider` 与 `buildGeoTool(webKeyReader/secretReader)` 一律改为「构造传 reader、请求时读」——装配保持同步，且用户补填 Key 后**无需重建工具面**即生效（单测已断言该收益）。`geo_tool.dart` 原 `amapWebKey`/`amapSecret` 静态字符串参数因此废弃。
  3. **真实 Provider 只落地 HTTP，定位仍缺位**：`lib/service/amap_http_provider.dart`（dart:io）补齐高德 REST 真实源，使 geo 的 6 个联网 action 真正可用（AndroidManifest 补 `INTERNET` 权限）；`LocationSensorProvider` 真实实现需 geolocator + 权限流（新依赖），本轮不引入——走 `NullLocationSensorProvider` 是 **fail-closed**（`geo_current`/`geo_compass` 返回 `PERMISSION_DENIED` 而非伪造坐标），已登记域内待办。
  4. **R7 启用靠退役而非白名单**：arch-guard 新增「tools 层禁 dispatch/admits 调用」扫描模式；白名单纪律是「只减不增」，故不为 `sample_tool_face.dart` 开口子——S7 提前退役该文件（原属 S8），连同 `ports.dart`/`overview.md`/`index.md` 引用一并清理，R7 零白名单启用。
  5. **注释也不得写出被禁调用写法**：R7 是 grep 级文本扫描，首跑命中 `geo_tool.dart`/`math_tool.dart` 注释里的 `.dispatch(`，改为「dispatch / admits 调用」措辞后通过（教训：机械门禁面前注释与代码同责）。

## 断点
- [断点] 下一步：S8 Contract 收尾（核查并移除旧返回形状兼容层——`mcp_server.dart`/`tool_face.dart` 是否残留兼容分支；smoke_test 对已退役 sample 的引用清理）+ 剩余能力域（weather / system_pim）排期。
