---
dev-loop: devlog
format: v1
epic: domain_gateway
total-merged: 0
last-merge: none
---

（开发过程日志按行追加：[变更]/[验证]/[note]/[SSOT 修正]；≥5 条自动归并进 memory.md——dev-loop §2）
- [2026-10-20] [变更]: S1+S2 完成：McpToolFace.call 返回演进为完整 result（mcp_server.dart 只透传并拆除硬编码 isError:false，SampleToolFace 包一层且未知工具改 isError:true）+ 新增 lib/mcp/category_tool_face.dart 契约层（SubAction/SubActionResult/CategoryTool/CategoryToolFace）+ test/category_gateway_test.dart 6 条契约断言；两处契约修正：① CategoryTool.call 改单一出口，保证 category.action 前缀注入不被早退分支绕过；② 子操作用 extends SubAction（implements 不继承 isWrite:false 默认，会让 20+ 个 R 档逐个手写 isWrite/buildCommand）
- [2026-10-20] [验证]: flutter analyze → No issues found；flutter test → All tests passed (38)；toolbox run arch-guard → OK（6 条全过）；toolbox run docs-lint → ✓
