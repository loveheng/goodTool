---
dev-loop: memory
format: v1
epic: calculator
total-merged: 0
last-merge: none
---

# calculator

- [挂载] docs/product/calculator.md

## 进度
- 2026-10-20 **S3a–S3d 数学内核已落地并全绿（142 tests + arch-guard 6 条 + docs-lint）**：
  - S3a 单位换算：`UnitConverter`（11 量纲 × 4 transform）+ `UnitRegistry`（别名归一化单一真相源，冲突 fail-fast）+ `ConvertResult`（error 模型）。
  - S3b/S3c 表达式内核：`Sanitizer`（保守清洗 + cleaned→original 位移回填）+ `Lexer`（单位 run 仅被 `to` 确认）+ `Parser`（递归下降 AST，`^` 右结合、一元负号低于 `^`、隐式乘法、百分比歧义 warning、`NESTING_TOO_DEEP`）。
  - S3d 求值器（**已按规范引入 `decimal` 依赖**）：`ExpressionEvaluator` 走 Decimal 主链路（`0.1+0.2=0.3` 精确、链式不累计误差），超越函数/单位换算因固有非精确走 double 回装 Decimal（设计内非静默降级）；DoS 红线 `EVAL_STEP_LIMIT`（maxSteps=100000，可注入测试）。`UnitConverter` 仍用 `double`（registry 本就是近似常量、factor 比值不受影响）。
- 2026-10-20 **S3e 适配层已落地并全绿（11 项单测 + analyze/arch-guard 全过）**：`lib/tools/math/math_tool.dart` 建 `buildMathTool()` 注册 `calc_eval`/`unit_convert`/`unit_list` 三 R 档 SubAction；双轨出参（result 格式化串 + numericValue 无损数值，超 double 无损范围退化为 string）；结构化错误经 `SubActionResult.structuredError` 携带 offset/candidates/suggestion，前缀由派发层注入（G1/G5）；G5 宽容解析可选参数（parseDouble/parseInt）。math 全 R 档 → `commandGateway` 传 null，工具文件零 `import command_gateway.dart`、无 `.dispatch`/`.admits`，门禁必过。
- **已知限制（非 S3e 范围）**：calc_eval 的 `context` 变量注入与 `angleMode`（deg）需 S3 内核扩展，当前以 warning 温和降级；`roundingMode` 仅 halfUp 生效。
- **关键 API 坑（decimal 3.2.6）**：`Decimal/Decimal` 除法返回 `Rational` → 须 `.toDecimal(scaleOnInfinitePrecision:30)`（1/3 类无限精度）；`Decimal.pow(int)` 返回 `Rational` → `.toDecimal()`；`Decimal` 无 `toInt` → `int.parse(round().toString())`；`dart:math` 无 `cbrt` → `pow(a,1/3)`。自实现 `_intPow` 正确处理负底数/负指数。

## 断点
- [断点] calculator 已全部完成（S3a–S3e）。后续 `context`/`angleMode` 延伸见域内待办；跨文档下一里程碑 = S4 geo（切 CURRENT→epics/geo）。
