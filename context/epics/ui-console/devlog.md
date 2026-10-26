---
dev-loop: devlog
format: v1
epic: ui-console
total-merged: 1
last-merge: 2026-10-21
---
- [2026-10-26] [变更]: 首页快捷落地：仪表盘展示用户钉住的域子页面（默认日历）；能力页域卡增钉选控件（双通道：实心/轮廓图钉+「首页快捷」文字）；写路径新增 user_set_home_pinned_domain（用户侧注册表、Actor 值域校验 AppDomain 枚举名、AI 不可触达）+ 设置键 home_pinned_domain + 快照 homePinnedDomain 字段（不进设置页回显枚举）；域卡元数据/push 提为共享件 DomainCard/openDomainPage/kDomainEntries，hub 与仪表盘共用同一份子页面实例（main.dart 单点装配）
- [2026-10-26] [验证]: arch-guard 7/7 + analyze 0 issue + test 617 全绿（含新增首页快捷钉选 5 例）
- [2026-10-26] [变更]: 按用户追加拍板去掉首页快捷卡中间层：仪表盘直接内嵌钉住域的二级页面为首页本体（子页根件原样渲染——calendar/geo 自带 Scaffold、calculator/weather 裸件挂 HomeShell Scaffold 的 Material 祖先，不另包标题栏）；嵌入态 ShellNav 可用（日历「设置」/天气「去设置」引导在首页即活）；纯 UI 渲染层变更，内核零改动
- [2026-10-26] [验证]: arch-guard 7/7 + analyze 0 issue + test 617 全绿
