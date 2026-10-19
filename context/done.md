---
memo: done
format: v2
---

# 完成列表
- [2026-10-20] S1 McpToolFace.call 返回演进为完整 result（{content,isError}），McpServer._dispatch 透传并拆除 mcp_server.dart:118 硬编码 isError:false，SampleToolFace 同轮包一层 (src: 用户) (域: domain_gateway)
- [2026-10-20] S2 实现契约层 lib/mcp/category_tool_face.dart：SubAction(isWrite/buildCommand) + SubActionResult(success=!isError/withPrefix) + CategoryTool(入口鉴权+统一派发) + CategoryToolFace (src: 用户) (域: domain_gateway)
- [2026-10-20] 补网关派发契约断言：枚举外 action 返回 UNKNOWN_ACTION、未授权 W 档返回 PERMISSION_DENIED 且执行体未触达、isError 与 success 反向一致 (src: 用户) (域: misc)
- [2026-10-20] 网关契约落地：McpToolFace.call 签名按 Expand-Contract 三步演进为完整 result，同轮拆除 mcp_server.dart:118 硬编码 isError: false，SampleToolFace 包一层（禁内核双路分支） (src: 用户) (域: misc)
- [2026-10-20] S3a 单位换算引擎 UnitConverter（11 量纲 × 4 transform 纯函数）+ UnitRegistry 别名归一化单一真相源 + ConvertResult 错误模型 (src: ai) (域: domain_gateway)
- [2026-10-20] S3b 表达式 Sanitizer + Lexer（全角→半角 / 安全千分位逗号 / 币种符噪声 / to 关键字分割 / 隐式乘法边界） (src: ai) (域: domain_gateway)
- [2026-10-20] S3c Shunting-yard Parser（^ 右结合 / 一元负号优先级低于 ^ / 隐式乘法插入 / 括号嵌套深度上限） (src: ai) (域: domain_gateway)
- [2026-10-20] S3d Decimal 求值器 + DoS 阈值（EXPR_TOO_LONG/NESTING_TOO_DEEP/EVAL_STEP_LIMIT）；decimal 依赖引入须用户确认 (src: ai) (域: domain_gateway)
- [2026-10-20] S3e math_utility 领域网关适配层 lib/tools/math/math_tool.dart：buildMathTool 注册 calc_eval/unit_convert/unit_list 三 R 档 SubAction；双轨出参（result 格式化串 + numericValue 无损数值，超 double 无损范围退化为 string）+ 结构化错误携带 offset/candidates/suggestion 并经 withPrefix 注入前缀；G5 宽容解析；11 项单测 (src: ai) (域: domain_gateway)
- [2026-10-20] S4 geo 领域网关适配层 lib/tools/geo_tool.dart：buildGeoTool 注册 8 个 R 档 action（geo_current/geocode/reverse/search_poi/route/static_map/compass/distance），坐标 GCJ-02 归一化 + 静态图 URL 免 SDK 出图 + 错误全带 machine code；30 项单测 (src: ai) (域: domain_gateway)
