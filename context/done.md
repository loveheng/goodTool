---
memo: done
format: v2
---

# 完成列表
- [2026-10-20] S1 McpToolFace.call 返回演进为完整 result（{content,isError}），McpServer._dispatch 透传并拆除 mcp_server.dart:118 硬编码 isError:false，SampleToolFace 同轮包一层 (src: 用户) (域: domain_gateway)
- [2026-10-20] S2 实现契约层 lib/mcp/category_tool_face.dart：SubAction(isWrite/buildCommand) + SubActionResult(success=!isError/withPrefix) + CategoryTool(入口鉴权+统一派发) + CategoryToolFace (src: 用户) (域: domain_gateway)
- [2026-10-20] 补网关派发契约断言：枚举外 action 返回 UNKNOWN_ACTION、未授权 W 档返回 PERMISSION_DENIED 且执行体未触达、isError 与 success 反向一致 (src: 用户) (域: misc)
- [2026-10-20] 网关契约落地：McpToolFace.call 签名按 Expand-Contract 三步演进为完整 result，同轮拆除 mcp_server.dart:118 硬编码 isError: false，SampleToolFace 包一层（禁内核双路分支） (src: 用户) (域: misc)
