---
dev-loop: memory
format: v1
epic: calculator
total-merged: 1
last-merge: 2026-10-22
---

# calculator

- [挂载] docs/product/calculator.md
- [设计] 区块化演进设计 SSOT = `docs/project/calculator-blocks.md`（draft；2026-10-21 会话裁定作为本轮实现口径，slug 锚定规则故不直接挂载，此行即指针）

## 进度
- 2026-10-20 **S3a–S3d 数学内核已落地并全绿（142 tests + arch-guard 6 条 + docs-lint）**：
  - S3a 单位换算：`UnitConverter`（11 量纲 × 4 transform）+ `UnitRegistry`（别名归一化单一真相源，冲突 fail-fast）+ `ConvertResult`（error 模型）。
  - S3b/S3c 表达式内核：`Sanitizer`（保守清洗 + cleaned→original 位移回填）+ `Lexer`（单位 run 仅被 `to` 确认）+ `Parser`（递归下降 AST，`^` 右结合、一元负号低于 `^`、隐式乘法、百分比歧义 warning、`NESTING_TOO_DEEP`）。
  - S3d 求值器（**已按规范引入 `decimal` 依赖**）：`ExpressionEvaluator` 走 Decimal 主链路（`0.1+0.2=0.3` 精确、链式不累计误差），超越函数/单位换算因固有非精确走 double 回装 Decimal（设计内非静默降级）；DoS 红线 `EVAL_STEP_LIMIT`（maxSteps=100000，可注入测试）。`UnitConverter` 仍用 `double`（registry 本就是近似常量、factor 比值不受影响）。
- 2026-10-20 **S3e 适配层已落地并全绿（11 项单测 + analyze/arch-guard 全过）**：`lib/tools/math/math_tool.dart` 建 `buildMathTool()` 注册 `calc_eval`/`unit_convert`/`unit_list` 三 R 档 SubAction；双轨出参（result 格式化串 + numericValue 无损数值，超 double 无损范围退化为 string）；结构化错误经 `SubActionResult.structuredError` 携带 offset/candidates/suggestion，前缀由派发层注入（G1/G5）；G5 宽容解析可选参数（parseDouble/parseInt）。math 全 R 档 → `commandGateway` 传 null，工具文件零 `import command_gateway.dart`、无 `.dispatch`/`.admits`，门禁必过。
- **已知限制（非 S3e 范围）**：calc_eval 的 `context` 变量注入与 `angleMode`（deg）需 S3 内核扩展，当前以 warning 温和降级；`roundingMode` 仅 halfUp 生效。
- **关键 API 坑（decimal 3.2.6）**：`Decimal/Decimal` 除法返回 `Rational` → 须 `.toDecimal(scaleOnInfinitePrecision:30)`（1/3 类无限精度）；`Decimal.pow(int)` 返回 `Rational` → `.toDecimal()`；`Decimal` 无 `toInt` → `int.parse(round().toString())`；`dart:math` 无 `cbrt` → `pow(a,1/3)`。自实现 `_intPow` 正确处理负底数/负指数。
- 2026-10-21 **S3e 后续增量（全部全绿：analyze 0 / arch-guard / docs-lint；测试数 142→496）**：
  - `list_stats` 子操作落地（Decimal 高精度 sort/max/min/sum/mean/median，全 R 档），G1 链路补齐 calculator.md 规格，矩阵 26→27。
  - 区块化 Phase 1 + 草稿纸模型（设计 SSOT=`calculator-blocks.md` 已转 active）：`BlockCanvas` 底座四件套（焦点链/IME Guard/粘贴裂变/弹性槽位）；块体透明去卡片化、IDE 行光标带 + Leader Dots + Gutter 行号、Reader Mode、Telemetry 汇总条；粘贴裂变拦截点在粘贴入口（框架 singleLineFormatter 先于用户格式器剥 \n——关键坑）；区块侧滑删除（Dismissible）与退格两段式并存。
  - 草稿持久化：`user_save_draft` 用户命令（AI 不可触达）+ `DraftPort`（读 Repository/写网关，R1/R5 合规），防抖 600ms 自动保存，示例草稿仅首启播种。
  - 中文映射：词法层 `换算` 与 `to` 同义；CJK 单位名全链路可用（注册表别名直查）；出参回显规范单位 id。
  - 子页面 SafeArea 修复：子页面由 capabilities_page 直包无 appBar，页面内容自带 SafeArea。

## 断点
- [断点] 下一步：输入中瞬态抑制已交付全绿；等待新子任务
