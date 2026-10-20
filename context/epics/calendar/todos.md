---
memo: todos
format: v3
epic: calendar
---

# calendar · 域内待办
- [x] [2026-10-20] (功能) (层:L2) (重:中) S6-P1a 端口层 lib/mcp/calendar_provider.dart：CalendarFeedProvider / CalendarMarkerStore / HolidayProvider + CalendarEvent / CalendarFeed / CalendarMarker 模型 + 7 个错误码（含新增 ERR_CALENDAR_SOURCE_UNAVAILABLE，P1 fail-closed 用） (src: 用户)
- [x] [2026-10-20] (功能) (层:L2) (重:中) S6-P1b 纯 Dart 内核：lib/tools/calendar/date_math.dart（成分跨度逐月推进 / 工作日推演 / delta 按 days→months→workdays→hours 顺序 + 月末 clamp）+ lib/tools/calendar/url_guard.dart（webcal→https 强制、拒绝 http 回退、回环与私网 IPv4/IPv6 SSRF 护栏） (src: ai)
- [x] [2026-10-20] (功能) (层:L3) (重:轻) S6-P1c 命令层 lib/action/calendar_commands.dart：5 个 W 档 Command（命令名 = action 名，供 CategoryTool 网关 admits 校验查找） (src: ai)
- [x] [2026-10-20] (功能) (层:L2) (重:重) S6-P1d 适配层 lib/tools/system_pim_tool.dart：注册 14 个 action（3 个纯计算 R 档真实可用：date_calc/date_diff/workdays_between；6 个 R 档接 Provider，源未注入 fail-closed 返 ERR_CALENDAR_SOURCE_UNAVAILABLE 级机器码；5 个 W 档只 buildCommand）+ 43 项单测（14 action 对账、W 档门禁真验、纯函数确定性、C1 区间红线、SSRF 护栏） (src: ai)
- [x] [2026-10-20] (功能) (层:L2) (重:中) P2-① 官方节假日表导入：lib/tools/calendar/holiday_table.dart 内置 2026 年表（数据逐字照录国务院办公厅 2025-11-04 通报：法定假 33 天 + 调休补班 6 天，七假期 3/9/3/5/3/3/7 天），版本号 `cn-2026.1` 出参回写；`CnHolidayProvider.fromJson` 提供 OTA 静态 JSON 同构入口（坏输入抛 FormatException）；`buildSystemPimTool` 默认表已切为内置表 (src: ai)
- [ ] [2026-10-20] (功能) (层:L2) (重:中) P2-② 引入 package:timezone（**等用户确认新依赖**）：补 calendar_tz_convert 真实实现 + B1/B2/B3 时区归一（当前出参 timezone 恒 'UTC' 且纯日期计算无 offset） (src: 用户)
- [ ] [2026-10-20] (功能) (层:L2) (重:重) P2-③ 引入纯 Dart 农历库（**需用户确认新依赖**，1900–2100 公农历双向 + 节气）：补 calendar_resolve_date / calendar_month_grid / isLunar 标记周年推演（三种 leapPolicy） (src: 用户)
- [ ] [2026-10-20] (功能) (层:L2) (重:重) P2-④ RFC 5545 ICS 解析（VEVENT / RRULE 展开 / EXDATE / RECURRENCE-ID / STATUS:CANCELLED，C2）+ CalendarFeedProvider 真实源（service 层：webcal 规整、3 跳重定向上限、10s 超时回退缓存、频控 G2） (src: 用户)
- [x] [2026-10-20] (功能) (层:L2) (重:中) P2-⑤ W 档 Actor + 标记存储：新增 lib/service/calendar_actors.dart（5 个 Actor，feed 存 KV、subscribe 幂等 + SSRF 防御性复检、unsubscribe/marker_delete 作用域校验、refresh 在 ICS 未实现时 fail-closed）与 lib/service/marker_store.dart（内存 + SharedPreferences 双实现）；SubAction 增 G6 validate 前置校验钩子 + fromActor 信封派生 isError；refresh 的最小间隔与单源并发锁（G2）随 P2-④ ICS 拉取一并无落 (src: 用户)
- [ ] [2026-10-20] (功能) (层:L2) (重:中) P2-⑥ 标记存储（markers 私有 store）与周年展开推演（anniversaryCount / daysRemaining / 平年 2-29 对齐 2-28 并标 approximate）+ 2/3 出参脱敏（E 拍板：PII_MASK_PHONE_EMAIL / PII_MASK_LOCATION） (src: 用户)
- [ ] [2026-10-20] (功能) (层:L1) (重:中) P2-⑦ 设备系统日历读取（Android 日历权限 + 平台通道实现 CalendarFeedProvider 的 system 源）+ 隐私设置 `日程敏感字段过滤` 接入 (src: 用户)
- [ ] [2026-10-20] (集成) (层:L3) (重:轻) P2-⑧ 全部源就绪后，把 buildSystemPimTool 装配进 lib/tool_face_assembly.dart（届时线级 = 4 域 26 action，与 domain_gateway.md 矩阵闭环）+ index.md 锚点回填 + 门禁复跑 (src: ai)
