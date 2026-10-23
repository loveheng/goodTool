---
dev-loop: devlog
format: v1
epic: calculator
total-merged: 1
last-merge: 2026-10-22
---
- [2026-10-22] [变更]: 草稿台长公式自适应换行修复：输入框 maxLines 1 → minLines 1/maxLines null（折行撑高块体，不再横向滚动，对齐 calculator.md「单行/多行自动微撑高」设计）；回车跳块（textInputAction.next→onSubmitted）不变；新增 _NoNewlineFormatter 接管「块内容恒单行文本」不变式（框架对 maxLines null 不再滤 \n，硬件回车直插路径由此拦截，evalLine 单行口径与粘贴裂变按行拆块依赖不变）
- [2026-10-22] [验证]: flutter analyze 0 issue；flutter test 521 全绿；arch-guard 7 条全过
- [2026-10-22] [变更]: 输入中瞬态错误抑制：新增 pending 分类（UNEXPECTED_TOKEN / UNDEFINED_VARIABLE 纯击键中间态），结果位淡灰「输入中…」替代红色机器码（对齐 calculator.md「轻量容错呈现」）；上游输入中时下游 UPSTREAM_ERROR 级联同步转输入中态（级联不闪红）；真故障（INVALID_CHARS/DIVISION_BY_ZERO/UNKNOWN_UNIT 等）仍红色机器码圈定；既有上游故障用例改非法字符构造真故障，新增输入中抑制 widget 用例
- [2026-10-22] [验证]: flutter analyze 0 issue；flutter test 522 全绿（新增输入中抑制用例 + 上游故障用例重构）；arch-guard 7 条全过
