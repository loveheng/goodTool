---
dev-loop: devlog
format: v1
epic: calendar
total-merged: 0
last-merge: none
---
- [2026-10-20] [变更]: S6-P1 地基落地——新增 `lib/mcp/calendar_provider.dart`（CalendarFeedProvider / CalendarMarkerStore / HolidayProvider 端口 + CalendarEvent / CalendarFeed / CalendarMarker 模型 + 7 个错误码，含 P1 新增的 `ERR_CALENDAR_SOURCE_UNAVAILABLE`）、`lib/tools/calendar/date_math.dart`（时间推演纯函数：成分跨度逐月推进、工作日推演、delta 按 days→months→workdays→hours 顺序应用 + 月末 clamp）、`lib/tools/calendar/url_guard.dart`（订阅 URL 护栏：webcal→https 强制、拒绝 http 回退、IPv4/IPv6 回环与私网 SSRF 护栏，**不用 dart:io 的 InternetAddress**）。
- [2026-10-20] [变更]: S6-P1 命令层 + 适配层——新增 `lib/action/calendar_commands.dart`（5 个 W 档 Command，**命令名 = action 名**供 `CategoryTool.admits` 查找）与 `lib/tools/system_pim_tool.dart`（注册 product/calendar.md 的 14 个 action）：3 个纯计算 R 档真实可用（date_calc / date_diff / workdays_between），6 个 R 档接 Provider（源未注入 fail-closed，不返回空列表假装查到），5 个 W 档只 buildCommand。
- [2026-10-20] [决策]: **节假日表绝不编造**——国务院年度安排凭记忆填充会造成错误的「今天放假/补班」判断（比不判断更糟），故默认 `EmptyHolidayProvider`（version `empty-0`）且出参回写 `holidayTableVersion` 让 Agent 可知判断依据；真实表待官方数据导入（P2-①）。
- [2026-10-20] [决策]: **跨度算法用逐月推进而非月份相减借位**——借位法在 `1/31 → 3/1` 上会算出负数天内差（借的是 end 所在上月的天数）。改为从 start 逐整月推进（先年后月）直至再进一月即超过 end，残余即天数。
- [2026-10-20] [决策]: **校验职责下沉 Actor**——必填与 SSRF 校验在命令执行器（service 层）内做：`buildCommand` 无法返回 `SubActionResult`，在工具层抛异常会被内核兜成散文错误，破坏结构化错误口径。
- [2026-10-20] [收口]: `test/system_pim_tool_test.dart` 43 项：14 action 与日历.md 第一列 1:1 对账、**W 档写门禁真验**（未登记 Actor → PERMISSION_DENIED 且执行体未被触达——若触达会抛 UnsupportedError；登记后走 CommandGateway 派发且 payload 透传；越权键同样拦截）、时间推演确定性（闰年、月末 clamp、调休补班优先）、C1 90 天线红线、SSRF 护栏 14 组拒绝 + 2 组放行。analyze 0 issue；flutter test 全绿 284；arch-guard 7 条全过（R7 首次对 `lib/tools` 有真实扫描对象）。
- [2026-10-20] [决策]: **本轮不装配进 `tool_face_assembly`**——6 个 R 档的 ICS/农历/时区源与 5 个 W 档的 Actor 均未落地，接线等于线级摆 14 个恒失败工具（与 S5「能力不假上线」同一纪律）。待 P2 源就绪后一并装配，届时线级 = 4 域 26 action，与 `domain_gateway.md` 矩阵闭环。
- [2026-10-20] [变更]: P2-① 节假日表——新增 `lib/tools/calendar/holiday_table.dart`：内置 2026 年表（**逐字照录国务院办公厅 2025-11-04 通报**，人民网/央广网/央视/中新社四方转载一致；法定假 33 天 + 调休补班 6 天，七个假期 3/9/3/5/3/3/7 天；清明/端午/中秋原文为「放假」故无补班），版本号 `cn-2026.1`，出参回写 `holidayTableVersion`；`CnHolidayProvider.fromJson` 提供 OTA 静态 JSON 同构入口（ranges 区间展开 + workdays 补班；坏输入抛 `FormatException`，不静默吞）；`buildSystemPimTool` 默认表由 `EmptyHolidayProvider` 切为 `cnHolidayBundled`。
- [2026-10-20] [收口]: `test/holiday_table_test.dart` 14 项：七假期与六补班逐字对账、between 边界（同日 / 空区间 / 2027 未发布故空）、工作日判定优先级按日期逐个断言、端到端（1 月整月 30 天 21 工作日、国庆 10 天 3 工作日、2/13 后一个工作日落在补班日 2/14）、OTA 解析与坏输入。analyze 0 issue；flutter test 全绿 298；arch-guard 7 条全过。