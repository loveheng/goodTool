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
- 全链路现状（2026-10-20）：142 tests + arch-guard 6 条 + docs-lint 全绿。

## 断点
- [断点] 下一步：S7 装配收口（McpController.toolFaceFactory 收口各 buildXxxTool 并注入 Provider）+ S8 Contract 收尾
