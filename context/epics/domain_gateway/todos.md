---
memo: todos
format: v3
epic: domain_gateway
---

# domain_gateway · 域内待办
- [ ] [2026-10-20] (功能) (层:L0) (重:重) S3 落地 math_utility 分类 3 个 action（calc_eval/unit_convert/unit_list）+ 纯 Dart 求值换算内核（Decimal + Shunting-yard + 11 量纲 4 transform），作为网关范式验证位 (src: 用户)
- [ ] [2026-10-20] (功能) (层:L1) (重:中) S4 落地 geo 分类 8 个 action（geo_current/geocode/reverse/search_poi/route/static_map/compass/distance），复用 lib/geo 内核与 GeoHttpProvider/LocationSensorProvider (src: 用户)
- [ ] [2026-10-20] (功能) (层:L1) (重:中) S5 落地 weather 分类 1 个 action（weather_forecast）+ QWeatherProvider 实现（回退链 + 200 内业务码拦截 + gzip 解压） (src: 用户)
- [ ] [2026-10-20] (功能) (层:L2) (重:重) S6 落地 system_pim 分类 14 个 action（calendar_query/feeds/subscribe/unsubscribe/refresh/month_grid/resolve_date/marker_list/marker_add/marker_delete/date_calc/date_diff/workdays_between/tz_convert），含 CalendarFeedProvider + HolidayProvider 端口与 5 个 W 档写门禁 (src: 用户)
- [ ] [2026-10-20] (功能) (层:L3) (重:轻) S7 装配收口：McpController.toolFaceFactory 收口各 buildXxxTool() 并注入 Provider（mcp_controller.dart:29）+ index.md 域级锚点回填 + arch-guard 启用网关写门禁扫描 (src: 用户)
- [ ] [2026-10-20] (优化) (层:L3) (重:轻) S8 Contract 收尾：四大能力落地后移除旧返回形状兼容层并退役 lib/tools/sample_tool_face.dart，同步清理 smoke_test 引用 (src: 用户)
