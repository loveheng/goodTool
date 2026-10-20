---
dev-loop: memory
format: v1
epic: calendar
total-merged: 0
last-merge: none
---

# calendar

- [挂载] docs/product/calendar.md

## 进度
- 2026-10-20 **S6-P1 地基已落地并全绿（43 项单测 + analyze 0 issue + arch-guard 7 条全过）**：14 个 action 全部注册（action 名 1:1 沿用 calendar.md，单测钉死枚举），其中 **3 个纯函数 R 档真实可用**（`date_calc` / `date_diff` / `workdays_between`），**5 个 W 档**只 `buildCommand`（首次让 arch-guard R7 写门禁有真实验证对象），其余 6 个 R 档接 Provider、源未注入时 **fail-closed** 返 `ERR_CALENDAR_SOURCE_UNAVAILABLE`。
- **新增落点**：`lib/mcp/calendar_provider.dart`（端口 + 事件/订阅源/标记模型 + 7 个错误码）、`lib/tools/calendar/date_math.dart`（时间推演纯函数）、`lib/tools/calendar/url_guard.dart`（订阅 URL 的 SSRF/HTTPS 护栏）、`lib/action/calendar_commands.dart`（5 个 W 档命令）、`lib/tools/system_pim_tool.dart`（适配层）。
- **关键设计决策（P1）**：
  1. **命令名 = action 名**：`CategoryTool.call` 以 action 名查 `CommandGateway.admits`，二者不同名则 W 档一律被拒（fail-closed）。故 `calendar_subscribe` 等命令名与 action 严格同名。
  2. **校验职责下沉 Actor**：必填与 SSRF 校验在命令执行器（service 层）内做，工具层只把载荷原样封成命令——因为 `buildCommand` 无法返回 `SubActionResult`，在工具层抛异常会被内核兜成散文错误，破坏结构化错误口径。
  3. **节假日表绝不编造**：国务院年度安排凭记忆填充会造成错误的「今天放假/补班」判断，比不判断更糟。故默认 `EmptyHolidayProvider`（version `empty-0`），出参回写 `holidayTableVersion` 让 Agent 可知依据；真实表待官方数据导入（P2）。
  4. **跨度算法用逐月推进而非月份相减**：借位法在 `1/31 → 3/1` 上会算出 `days = -2`（借的是 end 上月的天数）。改为从 start 逐整月推进（先年后月）直到再进一月即超过 end，残余即天数。
  5. **excludeWeekends 语义钉死**：周六日一律不计（含落在周末的调休补班）；`workdays_between` 则按「调休补班 > 法定假 > 周末」优先级把补班计入——两个口径差异已写进各自 description。
  6. **URL 护栏不用 `dart:io` 的 `InternetAddress`**：地址判定走字符串与正则即可覆盖 RFC 1918 / 回环 / 链路本地，守住「内核不沾平台 API」。

- 2026-10-20 **S6-P2-① 节假日表落地（14 项单测，flutter test 298 全绿 + analyze 0 + arch-guard 7 条）**：新增 `lib/tools/calendar/holiday_table.dart`——内置 2026 年法定节假日表，**逐字照录国务院办公厅 2025-11-04 通报**（人民网/央广网/央视/中新社四方一致；法定假 33 天 + 调休补班 6 天；七假期 3/9/3/5/3/3/7 天；清明/端午/中秋原文为「放假」故无补班），版本号 `cn-2026.1` 并回写出参；`CnHolidayProvider.fromJson` 提供 **OTA 静态 JSON 同构入口**（ranges 区间展开 + workdays 补班，坏输入抛 `FormatException`）；`buildSystemPimTool` 默认表从 `EmptyHolidayProvider` 切为内置表。
- **重要含义**：至此 3 个纯计算 R 档的节假日判断**真实可用**（此前仅跳周末）。测试按官方日期逐字断言，并把「工作日判定优先级（调休补班 > 法定假 > 周末）」按具体日期钉死。

## 断点
- [断点] **尚未装配进 `tool_face_assembly.dart`**——6 个 R 档依赖的源（ICS / 农历 / 时区）与 5 个 W 档的 Actor 均未落地，此时接线等于线级摆 14 个恒失败的工具（与 S5「不假上线」同一纪律）。P2 源就绪后一并装配。
- [断点] 下一步（P2，按依赖顺序）：① **官方节假日表**导入（本地 bundle + 静态 JSON OTA，F3）；② `package:timezone` 引入（需用户确认新依赖）→ `tz_convert` + B1/B2/B3 时区归一；③ 纯 Dart 农历库引入（需用户确认）→ `resolve_date` / `month_grid` / `isLunar` 标记推演；④ ICS 解析与 RRULE 展开 + `CalendarFeedProvider` 真实源（service 层，含 SSRF 护栏调用、3 跳重定向、10s 超时缓存回退）；⑤ 5 个 W 档命令的 **Actor** 实现与 `CommandGateway` 登记；⑥ 标记存储与脱敏（E 拍板）；⑦ 系统日历读取（Android 权限 + 平台通道）；⑧ 全部就绪后装配 + index.md 锚点。
