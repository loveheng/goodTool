---
dev-loop: memory
format: v1
epic: good-template
total-merged: 1
last-merge: 2026-10-26
---

# good-template

- [挂载] docs/project/good-template.md

## 进度

- 2026-10-24 **受控快照落地**：sync-kernel.sh 入池（SYNC 31 件逐字 / STRUCT 6 件结构对齐 / IGNORE 域件豁免 + 源仓对账告警）+ Android SDK 化（minSdk 34 + goodhub-mcp-plugin-core 0.2.0、双引擎注册、删自拷 AIDL）+ 装配样板单点收口 + sample 去反模式（不可空信封）；模板仓 analyze 0 / test 7 / arch-guard 7 / sync-kernel 实跑 rc=0 / init-app 起底演练零残留。Ref: Git log
- 2026-10-24 **UI 组件闭包（用户三拍板）**：① 模板不约束新 app 页面设计——主题骨架（theme/app_theme_data + main 主题接线）不入模板，组件视觉值经 AppTokens 主题扩展由宿主注册；② 元组件口径——只收不可再分的积木，拼装成品不收（readiness 元类型上移 `lib/ui_ports/readiness.dart` 中性件，纯 Dart）；③ mcp_service_page 归「内核配套页随内核走」（MCP 调试服务是内部设施每个 app 都有）。终态：模板 7 件 UI 件、test 14 绿。Ref: `docs/project/good-template.md` §7 决策日志

## 断点
- [断点] 下一步：组件闭包终态：元组件 5 组 + 内核配套页 mcp_service_page（模板 7 件 UI 件，14 tests 绿，两仓待 commit）；可选：真机 goodhub bind 联调 / 切其他任务
