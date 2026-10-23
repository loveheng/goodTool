---
memo: todos
format: v3
epic: domain_gateway
---

# domain_gateway · 域内待办
- [x] [2026-10-20] (功能) (层:L3) (重:轻) S7 装配收口：McpController.toolFaceFactory 收口各 buildXxxTool() 并注入 Provider（mcp_controller.dart:29）+ index.md 域级锚点回填 + arch-guard 启用网关写门禁扫描 (src: 用户)
- [x] [2026-10-20] (优化) (层:L3) (重:轻) S8 Contract 收尾：旧返回形状兼容层核查完成（mcp_server.dart 已透传完整 result、tool_face.dart 已是完整 result 契约、smoke_test 无 sample 引用）；同轮删除 `suggest_user_setting` 工具名嗅探特例（内核不再感知业务工具名），建议通道上移为 `McpController.pushSuggestion`，并订正 serverInfo/通知的模板项目名残留 (src: 用户)
- [ ] [2026-10-20] (文档) (层:L1) (重:中) `McpServer._builtinInstructions` 仍为「拾光排程师」模板文案（自 shiguang 提取），与 goodTools 四大能力（计算/日历/地理/天气）角色不符——会误导 LLM 客户端按排程师行事。重写须产品定位拍板，故登记待办而非 S8 擅改 (src: ai)
- [ ] [2026-10-20] (功能) (层:L3) (重:中) 接入真实 LocationSensorProvider（geolocator + 权限流，落 lib/service 并注入 tool_face_assembly.dart）：当前 geo_current / geo_compass 走 NullLocationSensorProvider，返回 PERMISSION_DENIED（fail-closed，非降级），需新依赖故 S7 未引入 (src: ai)
- [x] 2026-10-20 weather（1 action）已随 S5 装配上线（db57093）；system_pim（14 action，含 5 个 W 档）地基已完成、进度见 epics/calendar，装配收口在 P2-⑧：届时线级 = 4 域 26 action，与 domain_gateway.md 矩阵闭环。本域待办：真实 LocationSensorProvider 接入（见上条） (src: 用户)
