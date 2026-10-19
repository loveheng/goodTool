---
dev-loop: memory
format: v1
epic: misc
total-merged: 0
last-merge: none
---

# misc

- [契约] 领域网关（分类嵌入模式）按 S2 结构性引入放行；机械约束 = coding-standards §3.3 G1–G5：① 能力矩阵与 4 份 product 文档 26 个原子动作 1:1，action 名沿用文档原子名、禁改名禁自造；② 6 项通用能力（`create_calendar_event`/`set_alarm`/`web_search`/`fetch_webpage_content`/`get_step_counter`/`get_battery_thermal`）已删除；③ 写门禁由 `CategoryTool.call` 入口 `admits` 拦截 + 统一 `dispatch`，子操作只 `buildCommand`、禁自行鉴权/派发；④ `isError = !success` 唯一派生，`mcp_server.dart:118` 硬编码 false 同轮拆除。设计正文 = `docs/project/domain_gateway.md`（draft，待落地 `lib/`）；裁定档案 = `context/decisions.md` misc（2026-10-20）。
- [结算] docs-lint 存量告警已清零：`docs/overview.md` 移入 `docs/product/`（原文件落点与 README/index 索引分叉，且自身相对链接 4 处断链）；`toolbox run docs-lint` ✓ 通过。
## 断点
- [断点] 下一步：等待散修任务
