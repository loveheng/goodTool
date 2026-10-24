---
dev-loop: devlog
format: v1
epic: calendar
total-merged: 1
last-merge: 2026-10-20
---
- [2026-10-24] [变更]: READ_CALENDAR 权限链路收口（盘点确认 P2-⑦ 代码侧已全通：Manifest 声明 + Kotlin 双引擎注册 + Dart 端口 + 合并源 + UI 授权卡 + MCP includeSystem；上轮评估误判缺口源于本文件过期头注释）：① system_pim_tool.dart 过期「唯一缺口」头注释更正为 P2 完成态（14/14 全真实可用）；② MethodChannelSystemCalendarPort 的 PERMISSION_DENIED 分支补结构化 suggestion（自愈三件套：指引 App 日历页一键授权或系统设置路径），合并源 _warn 透传 suggestion 到 MCP warnings（值空感知出键，lessons 已记该形态）；③ calendar/domain_gateway 台账过期残留同步闭环；真机验一次「授权→查询」闭环留待用户
- [2026-10-24] [验证]: flutter analyze → 0 issue；flutter test → 586 全绿（新增 composite warning 透传 suggestion 1 例）；arch-guard 7 条全过
- [2026-10-24] [变更]: system_pim 增 time_now（14→15 action，全 R 档纯函数零出网）：设备现时在指定时区的投影（ISO 带显式 offset，复用 TzMath.fmtIso 公开化）+ epochMs + date/weekday + isWorkday（DateMath 调休>法定假>周末口径）+ holidayName（表内有当日条目才回写，空表不编造放假）+ holidayTableVersion 回写判断依据——Agent 无时钟，反「今天/现在」类编日期幻觉的原语；docs/product/calendar.md 增行与 R 档清单（G1 先行）；system_pim_tool 过期头注释一并更正为 14/14→15/15 完成态
- [2026-10-24] [验证]: flutter analyze → 0 issue；flutter test → 607 全绿（system_pim 15 action 对账 + time_now 5 例：UTC 缺省/时区投影/节假日命中/调休补班/非法时区）；arch-guard 全过
- [2026-10-24] [变更]: 真机反馈「日历左右滑切月/年生硬直接变」落地：月视图 MonthGrid 与年视图 YearGrid 各包 AnimatedSwitcher（240ms，方向感知滑动+淡入）——_pendingShiftDx 记录滑向（下一项从右滑入/上一项从左滑入，对齐 PageView 语义），跳月/今天/年视图点选落月等无方向入口归零纯淡入；手势识别器包在 AnimatedSwitcher 外层，过渡期间连续滑动手势不丢；键 = 年-月（年-年），密度数据随既有时序异步刷新不变
- [2026-10-24] [验证]: flutter analyze → 0 issue；flutter test → 611 全绿；arch-guard 7 条全过
