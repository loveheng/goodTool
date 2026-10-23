---
dev-loop: decisions
format: v1
epic: global
total-merged: 0
last-merge: none
---

# decisions

## misc

### [2026-10-20] 领域网关工具（分类嵌入模式）准入裁定 (src: 用户)

**场景/痛点** —— 四大能力若按原子粒度各自注册 MCP 工具，`tools/list` 每次全量注入 schema，工具数膨胀至 60+：Token 线性上涨，且模型在长清单里易幻觉指令名。`docs/project/domain_gateway.md`（draft）提出「1 域 = 1 工具 + `action` 枚举」方案，但其能力矩阵抄自通用 Kotlin 工具集，与 4 份 `docs/product/*.md` 已定义的 **26 个**原子动作严重不符——漏 20（正向/逆向地理编码、POI、路径规划、静态图、测距；日历 13 项含标记增删改、月网格、日期消歧、工作日透视、时区投影）、多 6（`create_calendar_event` / `set_alarm` / `web_search` / `fetch_webpage_content` / `get_step_counter` / `get_battery_thermal`），其中 `create_calendar_event` 直接违反 `calendar.md`「不做独立会议 / 日程管理」定位红线。

**可选方案** ——
- **A 结构性引入**（三层 `SubAction`/`CategoryTool`/`CategoryToolFace`）——**已选**；
- **B 原子工具平铺 + `switch(name)` 膨胀**——否决：每加一能力重复「schema + 分支 + 参数解析 + 错误前缀」四件套，边际成本递增（命中否决信号 #2）；
- **C 混合**（读走网关、写走原子）——否决：同一能力两条调用路径，命中否决信号 #3（双路分支）。

**最终决定** —— 判 **S2 结构性引入**，放行。网关对内核零侵入（`McpToolFace` 接缝语义不变），唯一内核配合是 `call` 返回演进为完整 result 且 `isError` 由结果派生。附带硬约束：
1. **能力矩阵 1:1 对齐**：分类 = 四大能力域 `geo`/`system_pim`/`math_utility`/`weather`，`action` 名原样沿用 product 文档原子名，**禁止改名、禁止自造**；合计 26 个。
2. **删除通用能力**：`create_calendar_event` / `set_alarm`（守 calendar.md 定位红线）、`web_search` / `fetch_webpage_content` / `get_step_counter` / `get_battery_thermal`（杜绝通用工具箱蔓延）。网关是能力聚合方式，不是能力来源；能力唯一来源 = `docs/product/*.md`。
3. **写门禁机械拦截**：`SubAction.isWrite` 默认 `false`；W 档子操作只实现 `buildCommand(params) → Command`，由 `CategoryTool.call` 入口前置 `admits` 校验 + 统一 `dispatch`。子操作禁自行鉴权、禁自行派发。
4. **`isError` 唯一派生**：`toMcpResult()` 内硬绑定 `isError = !success`；`mcp_server.dart:118` 硬编码 `false` 同轮拆除；演进不设兼容分支。

**AI 洞察** —— 网关的真实价值不在「少注册几个工具」：`tools/list` 仍要列出全部 action 名，Token 收益有上限。价值在于把「错误前缀生成 / 参数签名生成 / 写门禁」三件原本会被重复 N 次的事收口到派发层做一次——若子操作仍手写前缀或自己 `dispatch`，只是把重复搬了个家，判定应回退为补丁。另：`action` 名沿用 product 文档原子名（不改名），使「文档表格第一列 vs 各分类 `register()` 的 name 列表」成为可机械对账的断言，根除文档与实现双轨。

**收敛条件** —— ① 第 3 次在某子操作内出现手写 `${category}.${action}` 前缀 ⇒ 强制回网关层统一注入；② 第 2 次为兼容旧返回形状出现 `if (result is Map)` 类双路分支 ⇒ 一次性收口，禁止分期演进；③ 任一 `lib/tools/*_tool.dart` 出现 `.dispatch(` / `.admits(` ⇒ CI 阻断（待 arch-guard 补扫描模式）。

> 约束型：已同步落 `context/epics/misc/memory.md` 契约行，约束后续网关落地实现。
