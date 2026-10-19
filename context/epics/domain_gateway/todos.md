---
memo: todos
format: v3
epic: domain_gateway
---

# domain_gateway · 域内待办
- [x] [2026-10-20] (功能) (层:L3) (重:轻) S7 装配收口：McpController.toolFaceFactory 收口各 buildXxxTool() 并注入 Provider（mcp_controller.dart:29）+ index.md 域级锚点回填 + arch-guard 启用网关写门禁扫描 (src: 用户)
- [ ] [2026-10-20] (优化) (层:L3) (重:轻) S8 Contract 收尾：移除旧返回形状兼容层（核查 mcp_server.dart/tool_face.dart 有无残留兼容分支）+ 清理 smoke_test 对已退役 sample 的引用；sample_tool_face.dart 已于 S7 提前退役，本项仅剩兼容层核查 (src: 用户)
- [ ] [2026-10-20] (功能) (层:L3) (重:中) 接入真实 LocationSensorProvider（geolocator + 权限流，落 lib/service 并注入 tool_face_assembly.dart）：当前 geo_current / geo_compass 走 NullLocationSensorProvider，返回 PERMISSION_DENIED（fail-closed，非降级），需新依赖故 S7 未引入 (src: ai)
- [ ] [2026-10-20] (集成) (层:L3) (重:中) 剩余能力域 system_pim（14 action，含 5 个 W 档，需 CalendarFeedProvider + CommandGateway 注册）与 weather（1 action）：二者落地后工具数 = 4 域，对齐 domain_gateway.md 的 26 action 矩阵 (src: 用户)
