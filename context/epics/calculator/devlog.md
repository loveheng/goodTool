---
dev-loop: devlog
format: v1
epic: calculator
total-merged: 0
last-merge: none
---
- [2026-10-20] [变更]: S3d 完成：新增 lib/tools/math/expression_evaluator.dart + test/expression_evaluator_test.dart + 引入 decimal 依赖（pubspec）。Evaluator 走 Decimal 主链路（0.1+0.2=0.3 精确、链式不累计误差），超越函数/单位换算因固有非精确走 double 回装 Decimal（设计内非静默降级）；DoS 红线 EVAL_STEP_LIMIT（maxSteps=100000，可注入测试）。修复 decimal 3.2.6 API 坑：① Decimal/Decimal 除法返回 Rational → 须 .toDecimal(scaleOnInfinitePrecision:30)（1/3 类无限精度）；② Decimal.pow(int) 返回 Rational → .toDecimal()；③ Decimal 无 toInt → int.parse(round().toString())；④ math 无 cbrt → 用 pow(a,1/3)。自实现 _intPow 正确处理负底数/负指数（2^-2=0.25、(-2)^3=-8）。
- [2026-10-20] [验证]: 全链路全绿：flutter analyze → No issues found；flutter test → All tests passed (142)；toolbox run arch-guard → OK（6 条全过）；toolbox run docs-lint → ✓
- [2026-10-20] [变更]: S3e 完成：新增 lib/tools/math/math_tool.dart + test/math_tool_test.dart（11 项）。建 buildMathTool() 注册 calc_eval/unit_convert/unit_list 三 R 档 SubAction（双轨出参：result 格式化串 + numericValue 无损数值，超限退化为 string；结构化错误携带 offset/candidates/suggestion）。共享契约层同步增强：CategoryTool.commandGateway 改可空（R 档分类传 null，fail-closed）；SubActionResult 新增 structuredError 构造 + withPrefix 在 JSON 错误上原地注入前缀（保留自愈字段，G1/G5 不破），向后兼容。calc_eval 的 context/angleMode 内核暂未支持，以 warning 温和降级（待内核扩展）。analyze/arch-guard 全过。
