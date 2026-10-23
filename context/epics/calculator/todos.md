# calculator · todos

> 本轮主线：计算器子页面区块化演进（设计 SSOT = docs/project/calculator-blocks.md，Phase 1 范围）
> 格式：`- [ ]` 待办 / `- [x]` 完成（完成移入 done.md）；`（P2）`/`（v2）` 期次外登记不拆解

## Phase 1 · BlockCanvas 区块化（当前进行）

- [ ] T1 底座骨架：`lib/ui/components/block_canvas.dart` 建档——v1 最小面 API（非泛型、`BlockStatus { idle, busy, done }`、回调面 `onInputChanged/onBlockSplit/onBlockRemove/onPasteFission`）+ 受控一维区块列表 + widget 测试骨架（验收 §7.1）
- [ ] T2 焦点链管线（进底座）：FocusNode 池 + 焦点防跳变（先挂新再注旧）；行尾回车跳下一块（P1 不做中段拆块）；空块两段式退格删块（首退格"再按一次删除"微提示，文本变动/失焦即重置待删除态）；末尾常驻 ghost 块（无"+"按钮）；空白区命中聚焦 ghost 拉起键盘
- [ ] T3 IME Guard（进底座）：`composing.isValid` 期绝对静默（不 emit、不校验、不高亮），`isCollapsed` 后才对外；配套软校验通道：非法字符放行不吞键、块内高亮 + 结果位 `INVALID_CHARS`（§2.2，验收 §7.3）
- [ ] T4 弹性槽位引擎（进底座）：`TextPainter` 测量 + 95%/75% 迟滞沉降两行模式；两行模式结果槽 `maxLines:1 + ellipsis` 兜底截断（复制取底层无损值）；结果区独立 `GestureDetector` 阻断穿透——单击复制无损值 + 气泡、长按操作菜单；`IntrinsicWidth`/布局两段式，禁 Overlay（§2.4，验收 §7.4）
- [ ] T5 粘贴裂变协议（进底座）：多行粘贴拦截按 `\n` split 裂变 N 块；>30 行弹确认；复合事务 Page 级快照 + 单次撤销整体回滚；裂变后焦点收敛末块行尾 + `Scrollable.ensureVisible`（§3，验收 §7.6）
- [ ] T6 页面装配（留业务层）：`calculator_page.dart` 重写为 BlockCanvas 装配 + `evalLine` 注入——Page 级 `List<LineRecord>` 单源（结果不落块本地 State）；聚焦块免回写光标保护（widget 测试断言 selection 不变，验收 §7.7）；`ans` DAG 解析与级联刷新归页面侧（ans 指向上一成功块；上游故障 `UPSTREAM_ERROR (Line N)`，修复后下游级联恢复，验收 §7.5）
- [ ] T7 美学落地：`surfaceSunken` 块体 + 4dp 微缝、聚焦轨（`surfaceRaised` + 左缘 2dp 强调条）、`ans` 弱胶囊/`dataRef` 色、`telemetry` 等宽 + `tabularFigures`、聚焦迁移 ≤200ms Ease-out；行高全走 token 零魔法值（§4）
- [ ] T8 验收收口：§7 清单逐项自证（arch-guard 7/7、analyze 0 issue、test 全绿）；BlockCanvas 登记 `index.md`（goodTools-index 纪律）；calculator-blocks.md draft→active 回填落点 + ui-design.md §3 既有模式；真机侧载视觉验证清单交用户（§7.2/§7.8 手动项）

## Phase 2 · 健壮性 + 体验补全（P2，待 Phase 1 收口后拆解）

- [ ]（P2）光标中段回车拆块 / 非空行头退格合块
- [ ]（P2）`ans` 引用高亮强化 / 注释·分节块（全宽纯文本不触发求值）
- [ ]（P2）纯文本查看/导出（补跨块选择缺失）

## v2 · 高级工作流（登记不拆）

- [ ]（v2）长按拖拽排序；块级禁用 What-if；依赖关系可视化；统计汇总块（`sum`/`total`——需扩 `evalLine` 内核端口，落地前过方案准入，见 decisions.md 2026-10-21 ADR）
