---
status: active
updated: 2026-10-19
---

# goodTools · 计算器能力（普通计算 + 单位换算）

## 范围

两类数值能力：① **普通/科学表达式计算**；② **单位换算**。纯 Dart、无 UI 依赖、确定性、可单测，属产品四大能力之一。内核为无头系统（arch-guard R4），所有计算逻辑不得依赖 Flutter UI。

**双模服务对象**：同一内核同时服务两类调用方——（a）人类用户经 UI 交互（**移动端公式栏 + 历史流范式**）；（b）MCP 客户端（LLM Agent、Cursor、Claude Desktop 等）。设计坚持 **「同一内核，双模呈现与自愈适配」**：内核保证确定性、纯函数、防御性求值；呈现层按调用方需求输出「格式化展示串 + 机器数值」双轨、`offset` + `suggestion/candidates` 复合报错体，并对 Agent 输入做前置清洗、对自省做分级检索以节省 Token。

**交互范式**：抛弃传统「9 宫格按键 + 单行显示屏」与桌面双栏草稿纸，转向 **移动端单手即时公式栏 + 紧凑辅键抽屉 + 历史信息流卡片** 的轻量原生态（Vertical Stream）。用户即敲即得、无需等号；上方历史流可点击回填，软键盘上方固定 Accessory 符号条补齐科学符号与单位宏。该范式天然契合无头 Dart 内核与 MCP 协议：原子工具 `calc_eval` / `unit_convert` 供 Agent 精确调用；Agent 若需连续计算，通过 `calc_eval` 的 `context` 注入上一轮变量即可闭环，内核无需维护多行会话状态机。

设计方向：**纯 Dart + AST/Shunting-yard 安全求值 + 维度驱动换算 + MCP 工具面暴露**。本文件为能力规格（设计基线），`lib/` 尚未落地实现，实现期以本文件为接口契约。

## 能力清单

### 普通/科学表达式求值（`calc_eval`）

- **算子、优先级与结合性（显式裁定）**（由高到低）：
  1. `^`（幂）— **右结合**
  2. 一元 `-`
  3. `* / %` — **左结合**
  4. `+ -` — **左结合**
  - 括号 `()` 改变结合，支持嵌套配对。
  - **结合性细则**：`^` 为右结合，故 `2^3^2 = 2^(3^2) = 2^9 = 512`（**非** `(2^3)^2 = 64`）。Shunting-yard 中 `^` 入栈时**不与同优先级栈顶弹出**（右结合处理）；`+ - * / %` 入栈时与同优先级栈顶**弹出**（左结合）。
  - **隐式乘法优先级裁定**：隐式 `*` 与显式 `*` **完全等同**——同级优先级、左结合。因此 `1/2pi` ≡ `(1/2) * pi`（**非** `1/(2*pi)`）；`2*3^2` 与 `2(3)^2` 等价，均为 `2*(3^2)=18`。若需分母整体结合，调用方**必须显式加括号** `1/(2pi)`。
- **单位换算内联（`to` 运算符）**：表达式内支持 `value <unit> to <unit>` 语法糖，等价于调用 `unit_convert`（如 `320 km/h to m/s` → `88.89 m/s`）。单位须命中归一化别名表，否则报 `UNKNOWN_UNIT`。
- **常量**：`pi`（`π`）、`e`（自然常数 2.71828…）。
- **函数库**：
  - 基础：`sqrt`, `abs`, `exp`（e^x）。
  - 对数/幂：`ln`（自然对数）、`log10`、`log2`、`pow(x, y)`、`log(x, base?)`（base 缺省为 e）。
  - 三角（默认 **弧度 rad**）：`sin` `cos` `tan` `asin` `acos` `atan`；另提供 `deg(x)`/`rad(x)` 单位转换函数。
  - 舍入/极值：`floor` `ceil` `round` `trunc` `min(a,b)` `max(a,b)`。
  - 聚合函数：`sum(...)`（求和）、`avg(...)`/`mean(...)`（算术平均）、`count(...)`（计数）。入参为标量、变量或表达式列表（如 `sum(rent, food, utilities)`、`avg(10, 20, 30)`），用于清单/多值聚合；**多参数即满足需求，不再支持电子表格级行区间切片**（`lineN..lineM` 已移除）。
- **百分比 `%` 语义（显式裁定）**：`%` 为**后缀百分率运算符**，`x%` ≡ `x / 100`。
  - `50%` → `0.5`；`200 * 10%` → `20`；`100 + 10%` → `100.1`（即 `100 + 0.1`，**非** 110）。
  - "在 X 上增加 X 的 p%" 须显式写成 `X * (1 + p%)` 或 `X + X*p%`，解析器不做上下文隐式推断。
  - 取模（Modulo）改用二元函数 `mod(a, b)`（如 `mod(10, 3) = 1`），避免与 `%` 歧义。
  - **歧义智能诊断（自愈提示）**：当检测到 `A + B%` / `A - B%` 形式（如 `100 + 10%`）时，内核维持严格语义（`A + B/100`），但在出参附加**非致命 `warning`**：「当前解析为 A + (B/100)；如需计算基数增幅请用 `A * (1 + B%)`」。UI 可弹提示，Agent 可读 `warning` 自我修正，不影响 `success: true`。
- **一元负号与连续算子**：支持 `-5 + 3`、`2 * -3`、`-(3 + 2)`、`-2^2`（= `-(2^2)` = `-4`，因一元负号优先级低于 `^`）。
- **隐式乘法（显式裁定）**：在以下相邻处自动插入 `*`：
  - `2(3 + 4)` → `2*(3+4)`；`2pi` → `2*pi`；`5sqrt(9)` → `5*sqrt(9)`；`2(3)(4)` → `2*3*4`。
  - **安全边界**：词法器把 `2.5` 视为单个数字，绝不拆成 `2 * .5`；隐式 `*` 不跨数字字面量内部触发。
- **精度与舍入（IEEE 754 陷阱补正）**：底层基于**高精度十进制**（实现期引入 `decimal` 包或自制定长定点），避免 `0.1 + 0.2 = 0.30000000000000004` 类失真；折扣/金融场景（`2580 * 0.8`）必须确定性精确。
  - 入参 `precision`：结果保留**小数位数**（默认按内部精度，不强制截断）。
  - 入参 `roundingMode`：`halfUp`（四舍五入，默认）/ `floor`（向下截断）/ `ceil` / `halfEven`（银行家舍入）。
  - 中间运算全程走 Decimal，仅最终按 `precision` + `roundingMode` 收口，避免中途截断累积误差。
  - **科学计数法抑制（展示层裁定）**：`result` 格式化时，当 `|numericValue| ∈ [1e-6, 1e15]` 强制以常规十进制小数字符串展开（如 `0.0000001 + 0.0000002` → `0.0000003`，而非 `3e-7`），避免移动端 UI / Markdown 渲染科学计数法失真；超出该区间（极小/极大）才允许科学计数法并限制有效位数。
  - **超越函数精度边界（显式策略）**：四则运算与**有理数/整数幂**（`pow` 当指数为整数时）走纯 Decimal；而 `sqrt`/`sin`/`cos`/`tan`/`ln`/`exp`/`log*` 等超越函数数学上为无理数，`decimal` 库通常无全套高精度超越实现，落地策略为：
    - 内部以 `double` 高精度（或引入任意精度数学扩展，如配合 CORDIC/Taylor 级数）计算后**转回 Decimal** 收口；
    - 转回时对结果按内部精度截断/舍入，**不**将 `double` 误差暴露到主链路中间值；
    - 文档约束：超越函数结果精度受 `double` 本底限制，非 Decimal 全链路；若业务要求更高，实现期评估引入任意精度数学扩展，但**不得**因此放宽四则主链路的 Decimal 精确度。

### 单位换算（`unit_convert`）

- **量纲覆盖（11 类）**：长度 `length`、质量 `mass`、时间 `time`、温度 `temperature`、面积 `area`、体积 `volume`、速度 `speed`、数据存储 `storage`、压强 `pressure`、功率 `power`、油耗能效 `fuel_economy`。
- **换算模型（模型驱动，4 类 `transform`）**：注册表每个单位声明其 `transform`，引擎按类型套用**纯函数**：
  - `linear`：`out = in × factor_from / factor_to`（默认）。`factor` 为相对**基准单位**的系数（如 `km` 相对 `m` 的 factor = 1000）。
  - `affine`：`base = in × a_from + b_from`，`out = (base − b_to) / a_to`（温度，含原点偏移）。
  - `reciprocal`（油耗/能效 `fuel_economy`）：量纲内部单位分两类——**消耗制（consumption）**如 `l/100km`（数值越小越省油）与**里程制（economy）**如 `mpg`、`km/L`、`mpg_uk`（数值越大越省油），二者严格反比例。判定逻辑：若两端**同制**（均里程制，或均为 `l/100km`）走正比 `out = in × reciprocalK_to / reciprocalK_from`；若**跨制**（一端 `l/100km`、另一端里程制）走反比 `out = (reciprocalK_from × reciprocalK_to) / in`。输入为 `0`（∞ 能效）时返回 `DIVISION_BY_ZERO`。各单位 `reciprocalK` = 相对基准 `l/100km` 的换算比（`l/100km`=1、`km/L`=100、`mpg`=235.215、`mpg_uk`≈282.48），详见附录 A 修正骨架。
  - `iec_si`：仅数据存储量纲，显式区分十进制（SI，1000ⁿ）与二进制（IEC，1024ⁿ）。实现上以**不同单位 ID**（`MB` vs `MiB`）承载，各自 `factor` 相对 `byte`：SI `factor = 10^(3·n)`、IEC `factor = 2^(10·n)`。
  - **v1 不作符号量纲代数**：速度/面积/体积/压强/功率等复合单位均以**预计算 `factor` 的具体单位条目**入库（如 `km/h` 相对 `m/s` 的 factor = 1/3.6），不在主链路做 `m² = m¹·m¹` 符号推演（对齐「量纲混合运算边界」裁定；v2 再演进 `composite` 幂次模型）。
- **支持量纲与单位对照表**：

  | 量纲 | 基准单位 | 支持单位代号 / 常用别名 | 关键规则 |
  |---|---|---|---|
  | length | `m` | `m`,`km`,`cm`,`mm`,`in`,`ft`,`yd`,`mi`,`nmi`,`米`,`千米`,`公里` | 线性 |
  | mass | `kg` | `kg`,`g`,`mg`,`t`(吨),`lb`,`oz`,`斤`,`两`,`千克`,`克` | 线性（1 斤 = 0.5 kg） |
  | time | `s` | `s`,`ms`,`min`,`h`,`d`,`wk`,`yr`,`秒`,`分`,`小时`,`天` | 线性（1 yr = 365 d） |
  | temperature | `K` | `c`/`celsius`/`℃`, `f`/`fahrenheit`/`℉`, `k`/`kelvin` | 仿射；绝对零度截断 |
  | area | `m2` | `m2`(`m²`),`km2`,`cm2`,`ft2`(`sq ft`),`ha`,`acre`,`亩` | 线性（1 亩 ≈ 666.67 m²） |
  | volume | `l` | `l`(`L`),`ml`,`m3`,`gal`(`gal_us`),`gal_uk`,`fl_oz`,`升`,`毫升` | 线性 |
  | speed | `m/s` | `m/s`,`km/h`,`mph`,`knot`,`c`(光速) | 线性（1 km/h = 1/3.6 m/s） |
  | storage | `byte` | **SI** `b`,`kb`,`mb`,`gb`,`tb`；**IEC** `kib`,`mib`,`gib`,`tib` | `MB`=10⁶、`MiB`=2²⁰ 字节（`iec_si`） |
  | pressure | `pa` | `pa`,`kpa`,`mpa`,`bar`,`psi`,`atm`,`mmhg` | 线性 |
  | power | `w` | `w`,`kw`,`mw`,`hp`(公制/英制马力) | 线性（1 公制 hp ≈ 735.49875 W） |
  | fuel_economy | `l/100km` | `l/100km`,`mpg`(`mpg_us`),`mpg_uk`,`km/l` | 反比例模型：消耗制 `l/100km` 与里程制 `mpg`/`km/L` 跨制走倒数（`out = K/in`）、同制走正比；输入 0 报 `DIVISION_BY_ZERO` |

- **油耗/能效（fuel_economy，反比例模型）**：基准 `l/100km`（消耗制）。各能效单位 `reciprocalK`（相对基准 `l/100km` 的换算比）：`l/100km`=1、`km/L`=100、`mpg`=235.215、`mpg_uk`≈282.48。同制（均为里程制）走正比 `out = in × reciprocalK_to / reciprocalK_from`；跨制（`l/100km` 与里程制之间）走反比 `out = (reciprocalK_from × reciprocalK_to) / in`（即 `l/100km → mpg`：`235.215 / in`，`l/100km → km/L`：`100 / in`）。输入 `0` 返回 `DIVISION_BY_ZERO`。
- **数据存储（SI / IEC 显式区分）**：`iec_si` 模型，`MB`=10⁶、`MiB`=2²⁰ 字节。单位代号即意图，不靠全局开关；接口可选 `standard: "SI" | "IEC"` 仅作校验/提示。
- **别名归一化（大小写/符号容错）**：入参先做 `小写 + 去空格/符号` 归一，再查别名表；归一化器集中维护 `℃→celsius`、`°c→celsius`、`℉→fahrenheit`、`m²→m2`、`sq ft→ft2` 等映射，未知单位基于归一化表做近邻匹配产出 `candidates`，避免直接抛 `UnknownUnitException`。
- **内联 `to` 换算语法（解析策略）**：`calc_eval` 支持中缀 `to`（如 `320 km/h to m/s`）。词法识别 `to` 关键字后：① 前缀切片为「数值+单位」表达式、后缀切片为目标单位；② 提取数值与单位，分流转 `UnitConverter.convert`；③ 结果（如 `88.89 m/s`，数值 `88.8889`）可继续作为值参与后续运算（如 `v = 320 km/h to m/s`）。主链路出现裸单位四则仍受「量纲混合运算边界」约束报 `UNEXPECTED_UNIT_IN_EXPR`。
- **连接字与中文映射（2026-10-21）**：连接字 `to` / `换算` 同义（如 `10 公里 换算 英里`）；单位名可用注册表**中文别名**（公里/英里/公斤/摄氏度/亩/斤等），词法层标识符集含 CJK，`evalLine` 行内正则同步收 CJK 与三连接字（`to|in|换算`）。**出参回显规范单位 id**（如 `英里` → `mi`），与 `unit_convert` MCP 口径一致，不回显原文别名。

### 聚合函数与变量上下文（`calc_eval` 扩展）

- **聚合函数**：`sum(...)`（求和）、`avg(...)`/`mean(...)`（算术平均）、`count(...)`（计数）。入参为标量、变量或表达式列表（如 `sum(rent, food, utilities)`、`avg(10, 20, 30)`），用于清单/多值聚合；**多参数即满足需求，不再支持电子表格级行区间切片**（`lineN..lineM` 已移除）。
  - 空参/空集语义：`sum()` / `count()` 返回 `0`；`avg()` 无有效数字入参时返回 `AGG_EMPTY`（分母为零，见错误模型）。
- **变量上下文（`context`，供 Agent 链式计算）**：`calc_eval(expr, context?)` 接受 `context: {varName: value}` 注入种子变量；表达式中的变量名优先从 `context` 解析，未命中且非保留字则返回 `UNDEFINED_VARIABLE`。Agent 可在多轮调用间复用上一轮结果（如下一轮传入 `{subtotal: 2064}`），闭环工具链而**无需内核维护多行会话状态**。
- **严格性纪律**：`calc_eval` / `unit_convert`（尤其 Agent 调用）**默认严格**，不剥离词、不忽略注释，确保可预测与自愈；宽松自然语言混合不在原子工具内支持。
- **量纲混合运算边界（v1 阶段硬约束）**：
  - v1 核心引擎**不实现**通用符号量纲代数（不支持 `100 km / 2 h` 自动推导 `50 km/h`，亦不支持 `5 m * 3 m = 15 m²`）。
  - 算术主链路中带单位的语法**仅限** `<值> <单位> to <单位>` 单一换算闭环；主链路出现裸单位参与四则（`UNEXPECTED_UNIT_IN_EXPR`）须报错，避免一期引入沉重量纲推导系统。v2 再按需演进量纲代数。

### 高精度列表统计（`list_stats`）

- **动机**：`sort / max / min` 对小数组 Agent 可自行完成，工具价值在**长列表**与**高精度数值**（如 `"0.123456789012345678"` 这类超出 double 无损表示的数字串，LLM 直接比较/排序必然失真）——故列表统计**全程 Decimal 内核，不先转 double**。
- **入参**：`{values: number[]|string[], op: string, order?, precision?}`；`op ∈ sort / max / min / sum / mean / median`。
  - `sort`：按 `order`（`asc` 缺省 / `desc`）排序，返回格式化数组 + 无损数组；
  - `max` / `min`：附首达下标 `index`（比较在 Decimal 上进行）；
  - `sum` / `mean`：`mean` 除法走 `scaleOnInfinitePrecision: 30` 后按 `precision`（缺省 12）舍入；
  - `median`：先排序，偶数个取中间两数 Decimal 平均。
- **严格性纪律**：逐元素解析，任一元素不可解析即返回 `INVALID_ARGUMENT`（带下标 `values[i]`），**禁静默跳过或兜底默认值**；`values` 空数组返回 `MISSING_ARGUMENT`。

## MCP 工具面（形态）

| 工具 | 入参 | 出参 | 说明 |
|---|---|---|---|
| `calc_eval` | `{expr: string, precision?, roundingMode?, angleMode?, context?}` | `{success, result, numericValue, expression, warning?, error?}` | 单行公式求值；支持内联 `to` 换算与多参聚合 `sum/avg/count`；`context` 注入变量供 Agent 链式计算；双轨出参供下游免解析传递 |
| `unit_convert` | `{value: number\|string, from: string, to: string, precision?, standard?}` | `{success, result, numericValue, fromUnit, toUnit, formula, warning?, error?}` | 维度双向换算；`formula` 输出过程，`warning` 承载非致命提示，未知单位附 `candidates` 自愈 |
| `unit_list` *(自省)* | `{dimension?: string, search?: string}` | `{dimensions: [...]}` 或 `{units: [...]}` | 分级自省省 Token：无参返回量纲概览，带参展开单位元数据 |
| `list_stats` | `{values: number\|string[], op: string, order?, precision?}` | `{success, op, count, result, numericValue?, index?, error?}` | 高精度列表统计（sort/max/min/sum/mean/median）；Decimal 内核全程不转 double，双轨出参供链式传递 |

### `calc_eval`

- **成功出参（双轨）**：
```json
{
  "success": true,
  "result": "2,064.00",
  "numericValue": 2064.0,
  "expression": "2580 * 0.8",
  "warning": null
}
```
  - `result`：格式化展示串（按 `precision`/`roundingMode` 收口，可含千分位分隔符，供 UI / Markdown 渲染）。
  - `numericValue`：机器友好数值（JSON number）；当超出 JSON 数值无损表示范围时退化为 string，供 Agent / 下游工具直接传参，无需再解析 `result`。
  - `expression`：经 Sanitizer 清洗后的规范化表达式，便于 Agent 回看与复用。
- **失败出参（复合报错体）**：
```json
{
  "success": false,
  "error": {
    "code": "UNEXPECTED_TOKEN",
    "offset": 7,
    "message": "在位置 7 发现非法符号 '*'",
    "suggestion": "检查是否出现多余算子，例如将 '5 + * 2' 修改为 '5 * 2'",
    "candidates": ["*", "+", "-"]
  }
}
```

### `unit_convert`

- **成功出参（双轨）**：
```json
{
  "success": true,
  "result": "27.7778 m/s",
  "numericValue": 27.7778,
  "fromUnit": "km/h",
  "toUnit": "m/s",
  "formula": "100 / 3.6",
  "warning": null
}
```
  - `fromUnit` / `toUnit`：归一化后的标准代号（供 Agent 精确引用）。
  - `formula`：换算过程明细（含数值与系数），供 UI 步骤抽屉或 Agent 解释说明。
  - `warning`：非致命提示（如精度截断、SI/IEC 歧义），出现时 `success` 仍为 `true`。
- **失败出参（未知单位 / 跨量纲自愈）**：
```json
{
  "success": false,
  "error": {
    "code": "UNKNOWN_UNIT",
    "offset": 0,
    "message": "未知单位 'miles per hour'",
    "suggestion": "是否想使用 'mph'？",
    "candidates": ["mph", "km/h", "m/s"]
  }
}
```
  - 跨量纲（如 `m → kg`）返回 `DIMENSION_MISMATCH`；输入 `0` 做油耗倒数换算返回 `DIVISION_BY_ZERO`。

### `unit_list`（分级自省，省 Token）

- **入参**：`dimension?`（指定量纲，如 `"speed"`、`"storage"`）、`search?`（模糊关键词，如 `"mile"`、`"字节"`）。
- **行为**：
  - **无入参**：返回 `{"dimensions": ["length","mass","time","temperature","area","volume","speed","storage","pressure","power","fuel_economy"]}`，体积极小，既作 Agent 一级检索目录（防 Token 爆炸），也作 UI 级联菜单首层。
  - **有入参**：展开符合条件的单位元数据，例 `unit_list({dimension:"speed"})` →
    ```json
    {
      "dimension": "speed",
      "baseUnit": "m/s",
      "units": [
        {"id": "km/h", "name": "千米每小时", "symbols": ["km/h", "kph", "公里/小时"]},
        {"id": "m/s", "name": "米每秒", "symbols": ["m/s", "mps"]},
        {"id": "mph", "name": "英里每小时", "symbols": ["mph", "mi/h"]}
      ]
    }
    ```
    满足 UI 下拉联想与 Agent 精准查询。

### MCP Agent 鲁棒性与自愈保障

1. **出参双轨制**：`calc_eval` / `unit_convert` 均输出 `result`（格式化字符串）与 `numericValue`（数值），供 Agent 在多工具链（Chain of Tools）中免解析传递。
2. **错误自愈模型（Agent Self-healing）**：失败时除 `code` 和 `offset` 外，必须输出 `suggestion`（推荐修正写法）与 `candidates`（近邻合法候选），避免 LLM 盲猜或重复试错；Agent 可借助 `calc_eval` 的 `context` 注入上一轮变量达成自愈。
3. **输入前置清洗**：见下方 Sanitizer Pipeline；自动规整全角/千分位/币种符，提升工具调用成功率；原子工具 `calc_eval` / `unit_convert` 始终保持严格，不静默剥词。
4. **轻量自省控制（Token Conservation）**：`unit_list` 不传参时仅返回量纲名列表；传 `dimension`/`search` 才展开具体单位与别名，避免挤占 LLM 上下文。

### 双模交互支持（User UI & MCP Agent）

1. **输入防御性清洗（Sanitizer Pipeline，核心解析前统一执行）**：
   - 全角字符转半角：`（）＋－＊／，：` → `()+-*/,:`；
   - 过滤安全的千分位逗号：`1,000,000` → `1000000`（仅在逗号左右均为数字且符合千分位位组时规约，避免误伤小数/函数参数分隔）；
   - 剔除首尾空白及常见非量纲前置符号：货币符 `¥`/`$`、单位前缀噪声（如 `¥2580` → `2580`、`$100` → `100`）。
   - 清洗为**无损/保守**策略：仅当确定无歧义时才改写，否则交后续语法报错（`UNEXPECTED_TOKEN`），不静默吞错。
2. **双轨结果承载（Dual-track Payload）**：`result` 格式化展示串（适配 UI 显示与 Markdown 渲染，可含千分位、单位）；`numericValue` 高精度数值类型（适配 Agent / 下游工具参数链）。
3. **双重纠错赋能（Dual Error Handling）**：`offset` 供 UI 文本框错误下划线与光标定位；`suggestion` 与 `candidates` 供 Agent 自愈与 UI 输入联想；二者同体返回，互不替代。
4. **渐进式自省（Progressive Introspection）**：`unit_list` 分级检索，默认仅返回量纲分类摘要（节省 Agent Token），按量纲过滤或搜索时展开单位细节（满足 UI 级联选择器渲染）。

### Tool Schema 规范化（Prompt 级，LLM 理解工具的唯一依据）

MCP Server 注册工具时，`description` 与 `inputSchema` 即 LLM 的唯一入口，须固化且含关键语义裁定：

- **`calc_eval`**：
  - description 模板：`安全执行高精度算术与科学表达式求值。支持四则运算、幂(^，右结合)、括号嵌套、科学函数(sqrt, abs, sin, cos, ln, log10 等)及常数(pi, e)；支持 '<值> <单位> to <单位>' 换算。注意：% 为后缀百分率(如 50% = 0.5)，取模请用 mod(a,b)；隐式乘法与显式 * 等价(1/2pi = (1/2)*pi)。`
  - `inputSchema.properties`：`expr`(string, required, 描述含示例)、`precision`(integer, 小数位)、`roundingMode`(enum halfUp/floor/ceil/halfEven, default halfUp)、`angleMode`(enum rad/deg, default rad)、`context`(object, 种子变量)。
- **`unit_convert`**：description 须列出支持的维度大类、强调别名容错（`km/h`/`公里每小时`/`celsius`/`℃` 均可）、并提示未知单位时看 `error.candidates` 自愈。
- **`unit_list`**：description 说明无参返回量纲概览、传 `dimension`/`search` 展开细节，引导 Agent 按需二次查询以省 Token。
- **`list_stats`**：description 须强调 Decimal 高精度内核（小数组无需调用，长列表/高精度数值专用）、`op` 六值枚举与 `values` 元素支持高精度数字串；非法 `op` 附 `candidates` 自愈。

## 结构化错误模型（`error` 字段）

所有工具出参统一带 `success`；失败时 `error` 提供机器可读信息，便于 UI 高亮标红与 Agent 自愈：

- `code`：枚举值，至少覆盖——
  - `DIVISION_BY_ZERO`（含 `mod(...,0)`、`reciprocal` 换算输入为 0）；
  - `UNMATCHED_PARENTHESIS`（括号不匹配）；
  - `UNDEFINED_SYMBOL`（未知算子/常量/函数，如 `foo(1)`）；
  - `UNEXPECTED_TOKEN`（语法位置非法或清洗后仍无法识别，如 `1 + * 2`）；
  - `ARGUMENT_COUNT_MISMATCH`（函数元数错，如 `pow(2)`）；
  - `DIMENSION_MISMATCH`（`unit_convert` 跨量纲，或 `transform` 类型不兼容）；
  - `UNKNOWN_UNIT`（`unit_convert` / `to` 无法归一的单位，附 `candidates`）；
  - `UNEXPECTED_UNIT_IN_EXPR`（算术主链路出现裸单位参与四则运算，v1 不支持量纲代数，如 `100 km / 2 h`）；
  - `AGG_EMPTY`（聚合函数 `avg` 作用空集致分母为零，如 `avg()` 无有效数字入参）；
  - `UNDEFINED_VARIABLE`（引用不在 `context` 中的变量，或非常量/函数/关键字的未定义符号）；
  - `EXPR_TOO_LONG` / `NESTING_TOO_DEEP` / `EVAL_STEP_LIMIT`（见 DoS 防御）。
- `offset`：出错字符在 `expr`/`from`/`to` 中的**偏移量**（0 起），供前端精确标红（移动端映射为输入框下划线波浪线 / 光标定位）；单值工具场景下即为字符串内下标。
- `message`：人类可读说明（可含上下文片段）。
- `suggestion`：**纠错建议**字符串（如「是否想使用 'mph'？」「将 '5 + * 2' 改为 '5 * 2'」），供 Agent 下一轮直接修正。
- `candidates`：**近邻合法候选**数组（单位别名、合法算子、近似函数名、变量名），Agent 与 UI 联想下拉框均可直接消费。
- 顶层可选 `warning`：非致命语义提示（如 `A + B%` 歧义诊断），出现时 `success` 仍为 `true`。

## 实现要点

- **安全求值**：禁止 `eval` / `Function.apply` / `dart:mirrors`；词法 → Shunting-yard（或递归下降）→ AST → 在 Decimal 上求值；**白名单**放行算子/函数/常量，未列即 `UNDEFINED_SYMBOL`，防注入。
- **精度内核**：引入 `decimal` 包（实现期加入 `pubspec`）；`double` 仅用于超越函数的内部计算后转回，**不得**进入四则主链路中间值。
- **Sanitizer 前置管道**：在核心解析前执行双模输入清洗（全角→半角、安全千分位逗号规约、剔除币种/空白噪声），仅无损改写，有歧义即交语法报错，不静默吞错。
- **双轨渲染**：求值后同时产出 `result`（展示串）与 `numericValue`（数值），`numericValue` 超 JSON 数值范围时退化为 string，避免 Agent 二次解析。
- **无会话状态（Stateless 内核）**：`calc_eval` / `unit_convert` 均为**无状态纯函数**，单次调用独立完成求值/换算，不维护跨调用的变量作用域或依赖图；Agent 连续计算通过 `calc_eval` 的 `context` 自行注入上一轮结果闭环。此约束彻底规避拓扑排序、`CYCLIC_REFERENCE` 判环、Dirty Propagation、`stale` 缓存等状态机负担，契合「轻量移动端 App + 纯粹 MCP 服务」定位（对齐 arch-guard R4 无头要求）。
- **单位注册表（模型驱动 + 多模型分派）**：`Map<dimension, {baseUnit, units: [{id, transform, factor, offset?, reciprocalK?, aliases, symbols}]}>`；`transform ∈ {linear, affine, reciprocal, iec_si}`（v1 复合单位以预计算 `factor` 的具体条目入库，符号量纲代数 `composite` 留待 v2）。引擎按 `transform` 分派纯函数换算，未知单位/跨量纲返回 `UNKNOWN_UNIT` / `DIMENSION_MISMATCH`；新增类型才改引擎。参考实现骨架见文末附录。
- **别名归一化器**：统一 `toLowerCase + 去空格/符号` 后查表，结果同时服务 `unit_convert`/`to` 与自省 `unit_list`，单一真相源；未知单位时基于归一化表做近邻匹配产出 `candidates`。
- **渐进式自省**：`unit_list` 无参返回量纲名列表，带 `dimension`/`search` 才展开单位明细，控制 Token 开销。
- **DoS / 资源耗尽防御（硬性阈值）**：受控解析器仍面临栈溢出与计算爆炸，实现期强制以下阈值（超限即返回 `EXPR_TOO_LONG` / `NESTING_TOO_DEEP` / `EVAL_STEP_LIMIT`，**不**抛未捕获异常）：
  - 表达式最大字符长度：`expr.length <= 1000`（可配置常量）。
  - 括号最大嵌套深度：`depth <= 50`。
  - 单次求值最大步数/递归深度 + 软超时（如 `steps <= 100000` 或 `elapsed <= 500ms`），防死循环与 `9^9^9^9` 类内存打爆。
  - 指数/参数大小上限（如 `|exponent| <= 10000`），避免 `pow` 触发不可控展开。
- **纯 Dart、确定性、无平台依赖**：便于 `test/smoke_test.dart` 全链路验证；表达式与换算均为纯函数，相同入参恒定出参。
- **接口演进纪律**：新增算子/函数/量纲/换算模型只扩白名单、注册表与 `transform` 分派，不改求值主链路与现有出参形状（向后兼容）。

## 移动端计算器 UI（Vertical Stream，未来 `lib/ui` 落地的形态基线）

> 当前工程为无头壳，**尚无 `lib/ui` 层**；本节为 UI 落地时的形态与架构约束基线，非现状实现。定位为**移动端 App（竖屏单手）**，不做重型桌面双栏分栏草稿纸。内核依旧为纯 Dart 算式求值（`calc_eval`）与单位换算（`unit_convert`），不引入任何 Flutter UI 依赖。

- **布局（纵向堆叠流 Vertical Stream）**：`历史计算流（可滚动/回填）` → `当前输入与实时预览（核心操作区）` → `软键盘上方 Accessory 符号条`，自上而下纵向堆叠，**无左右分栏**：
```text
┌────────────────────────────────────────────────────────┐
│  goodTools · 计算器                     [🕒 历史] [⚙️]  │
├────────────────────────────────────────────────────────┤
│ 历史计算流 (可上下滚动查看与点击回填)                    │
│   (1200 + 350) * 0.85                                  │
│   = 1,317.50                                           │
│   ──────────────────────────────────────────────────   │
│   100 km/h to m/s                                      │
│   = 27.78 m/s (formula: 100 / 3.6)                     │
├────────────────────────────────────────────────────────┤
│ 当前输入与实时预览 (核心操作区)                         │
│  🔍 (14999 * 0.9 + 4999) * 1.13 to usd_               │
│  ≈ 2,935.12 USD                         [点击一键复制] │
│  (原值: 20,902.74 CNY · 实时求值中)                    │
├────────────────────────────────────────────────────────┤
│ 快捷符号辅助栏 (Accessory Bar，随系统软键盘联动)        │
│ [ ( ]  [ ) ]  [ ^ ]  [ % ]  [ to ]  [ sqrt ]  [ pi ]   │
└────────────────────────────────────────────────────────┘
```
- **关键交互**：
  1. **即敲即得（无需等号）**：单行/多行自动微撑高输入框，用户打字即触发 `calc_eval` 实时求值，结果以大字号直接呈现于输入框下方；语法未完成（如仅输入 `(` 或 `1 +`）时下方淡灰显示「等待输入」，不弹红、不打断。
  2. **虚拟键盘辅键条（Input Accessory Bar）**：系统软键盘上方固定一条横向滑动快捷栏，点击在光标处插入字符，免去在输入法内反复切换符号页；分组含常用算子 `( ) ^ % to`、科学函数 `sqrt abs sin cos`、快捷单位宏 `km/h m/s kg ℃`。
  3. **历史记录轻量流（History Stream）**：软键盘「完成/换行」后当前公式归档推入上方可滚动列表；点击历史卡片将旧公式或数值一键回填当前输入框。
  4. **单手手势**：点按结果大字 → 触觉震动 + 一键复制；右滑输入框 → 清空当前输入；下拉历史列表 → 收起键盘并展开更多历史。
  5. **实时行内错误定位**：`error.offset` 映射为输入框下划线波浪线（或错误 `TextSpan` 高亮），并弹出简短 Toast/气泡展示 `error.suggestion`，不打断输入、不整屏飘红。
  6. **实时求值与防抖**：用户每次输入即触发 `calc_eval` 实时求值，配合输入防抖（debounce）避免高频求值卡顿；仅当前输入框公式参与计算，无多行依赖传播。
  7. **轻量容错呈现**：当前输入若含未完成/非法语法，仅以淡灰「等待输入」或波浪线提示，不整屏飘红；历史卡片彼此独立渲染，互不影响。
- **Flutter 实现要点（须守架构红线）**：
  - **无头内核**：求值、单位换算均置于无头核心层，**不得** `import` Flutter material/widgets；UI 仅消费结构化结果（对齐 arch-guard R4）。
  - **Accessory Bar**：基于 `TextField` 辅助视图，点击经 `TextEditingController` 在光标处 `insertText`（不单独维护符号面板状态），随软键盘联动显隐。
  - **历史流**：`calc_eval` 结果追加至本地历史仓储（走 Repository，R5），卡片回填仅写回 `TextField` 控制器，UI 不直连 `Db.instance`。
  - **错误呈现**：`error.offset` → 利用 `InputDecoration` 下划线波浪或自定义 `TextSpan` 高亮；`error.suggestion` → 轻量 Toast / SnackBar，避免侵入式对话框。
  - **导出**：一键导出干净 Markdown / 文本报告（核心层产出字符串，R2），便于粘贴进聊天/笔记。
  - **arch-guard 红线绑定**（见 `AGENTS.md`）：
    - **R4（硬约束，当前即生效）**：求值、单位换算均置于**无头核心层**，**不得** `import` Flutter material/widgets；UI 仅消费核心输出的结构化结果。
    - **R1**：UI 写操作（如保存草稿、写设置）须经 `CommandHandler`，不得直连 repo。
    - **R2**：UI 不得内联 JSON 编解码，委托数据/命令层（导出 Markdown 由核心层产出字符串）。
    - **R3**：平台分支收敛接口/工厂，不在 UI 散落 `Platform.isX`。
    - **R5**：数据访问走 Repository，UI 不直连 `Db.instance`。

## 附录 A：单位换算核心实现骨架（参考）

> 无头纯 Dart 核心层参考实现；具体目录落点以 `docs/project/index.md` 为准（当前仓库尚无 `lib/core`，勿臆造路径）。

```dart
enum TransformType { linear, affine, reciprocal, iecSi }

class UnitDefinition {
  final String id;
  final String dimension;
  final TransformType transform;
  final double factor;        // linear / iecSi：相对基准单位的系数
  final double offset;        // affine：原点平移（如 K = C + 273.15）
  final double reciprocalK;   // reciprocal：基准能效=1 时的单位值
  final List<String> aliases;
  final List<String> symbols;
  const UnitDefinition({
    required this.id, required this.dimension, this.transform = TransformType.linear,
    this.factor = 1.0, this.offset = 0.0, this.reciprocalK = 0.0,
    this.aliases = const [], this.symbols = const [],
  });
}

class ConvertResult {
  final bool success;
  final double? value;
  final String? fromUnit, toUnit, formula, code, message;
  final List<String>? candidates;
  const ConvertResult.success({this.value, this.fromUnit, this.toUnit, this.formula})
      : success = true, code = null, message = null, candidates = null;
  const ConvertResult.failure({this.code, this.message, this.candidates})
      : success = false, value = null, fromUnit = null, toUnit = null, formula = null;
}

class UnitConverter {
  final Map<String, UnitDefinition> _aliasMap = {}; // alias/symbol -> def

  String normalizeUnit(String raw) {
    final cleaned = raw.trim().toLowerCase()
        .replaceAll('℃', 'celsius').replaceAll('°c', 'celsius')
        .replaceAll('℉', 'fahrenheit').replaceAll('°f', 'fahrenheit')
        .replaceAll('²', '2').replaceAll('sq ft', 'ft2');
    return _aliasMap[cleaned]?.id ?? cleaned;
  }

  ConvertResult convert(double value, String fromRaw, String toRaw, {int? precision}) {
    final fromDef = _aliasMap[normalizeUnit(fromRaw)];
    final toDef = _aliasMap[normalizeUnit(toRaw)];
    if (fromDef == null) return ConvertResult.failure(code: 'UNKNOWN_UNIT', candidates: _findSimilar(fromRaw));
    if (toDef == null) return ConvertResult.failure(code: 'UNKNOWN_UNIT', candidates: _findSimilar(toRaw));
    if (fromDef.dimension != toDef.dimension) {
      return ConvertResult.failure(code: 'DIMENSION_MISMATCH',
          message: '无法在 ${fromDef.dimension} 与 ${toDef.dimension} 之间换算');
    }

    // 油耗/能效：消耗制(l/100km) 与 里程制(mpg, km/L, mpg_uk) 混合模型
    if (fromDef.dimension == 'fuel_economy') {
      if (value <= 0) return ConvertResult.failure(code: 'DIVISION_BY_ZERO', message: '油耗换算输入必须大于 0');
      final isFromConsumption = fromDef.id == 'l/100km';
      final isToConsumption = toDef.id == 'l/100km';
      final double out;
      if (isFromConsumption ^ isToConsumption) {
        // 跨制：严格反比例倒数
        out = (fromDef.reciprocalK * toDef.reciprocalK) / value;
      } else {
        // 同制（均里程制，或均为 l/100km）：正比例线性
        out = value * (toDef.reciprocalK / fromDef.reciprocalK);
      }
      return ConvertResult.success(value: out, fromUnit: fromDef.id, toUnit: toDef.id,
          formula: '$value ➔ $out ${toDef.id}');
    }
    // 仿射变换（温度）：先归一到基准 K，再转目标
    if (fromDef.transform == TransformType.affine) {
      // affine 模型：base = in × a_from + b_from（offset 作用于 factor 之后），out = (base − b_to) / a_to
      final baseK = value * fromDef.factor + fromDef.offset;
      final out = (baseK - toDef.offset) / toDef.factor;
      return ConvertResult.success(value: out, fromUnit: fromDef.id, toUnit: toDef.id,
          formula: '(($value × ${fromDef.factor} + ${fromDef.offset}) - ${toDef.offset}) / ${toDef.factor}');
    }
    // 默认线性 / iecSi（均以 factor 相对基准）
    final out = value * fromDef.factor / toDef.factor;
    return ConvertResult.success(value: out, fromUnit: fromDef.id, toUnit: toDef.id,
        formula: '$value × (${fromDef.factor} / ${toDef.factor})');
  }

  List<String> _findSimilar(String input) =>
      _aliasMap.keys.where((k) => k.contains(input.toLowerCase())).take(3).toList();
}
```

**实现要点补充**：油耗/能效按 `dimension == 'fuel_economy'` 分派，**消耗制 `l/100km` 与里程制 `mpg`/`km/L` 跨制走严格反比 `out = (reciprocalK_from × reciprocalK_to) / in`**（如 `l/100km → mpg` = `235.215 / in`），同制走正比——彻底替代原骨架错误的 `in × reciprocalK_to / reciprocalK_from` 正比例退化；`iec_si` 复用线性分支（`factor` 已按 SI 1000ⁿ / IEC 1024ⁿ 预置）；`precision` 收口在 `ConvertResult` 归并层按 `roundingMode` 处理（与四则主链路一致）。

## 落地验证 Checklist

- [ ] **移动端 UI 链路**：输入 `（2580 + 120）* 0.8` 能否被 Sanitizer 预清洗并正确求值，即敲即得、无需等号；错误输入时 `offset` 映射为输入框下划线波浪线、`suggestion` 经 Toast/气泡提示，不整屏飘红。
- [ ] **Agent 链路**：调用 `calc_eval` 返回的 `numericValue` 能否免字符串解析直接用于下一步工具调用。
- [ ] **单位容错**：输入中文「公里每小时」或「℃」能否正确命中别名库并给出规范的 `formula` 说明。
- [ ] **自愈链路**：传入 `Unknown unit 'miles per hour'` 时，返回是否带 `suggestion` + `candidates` 且 Agent 能据此下一轮修正。
- [ ] **Token 控制**：`unit_list` 无参是否仅返回量纲概览，带 `search:"mile"` 才展开明细。
- [ ] **歧义诊断**：`100 + 10%` 是否 `success:true` 且带 `warning` 提示增幅写法。
- [ ] **移动端交互适配**：软键盘上方 Accessory 辅键条（`( ) ^ % to` / `sqrt abs sin cos` / 单位宏）点击在光标处插入；历史卡片点击回填输入框；点按结果大字触发复制 + 震动；右滑输入框清空。
- [ ] **严格性纪律**：`calc_eval` / `unit_convert` 始终严格，不剥离词、不忽略注释；`context` 注入变量供 Agent 链式计算，引用缺失返回 `UNDEFINED_VARIABLE`。
- [ ] **v1 量纲边界**：`100 km / 2 h` 报 `UNEXPECTED_UNIT_IN_EXPR`；仅 `<值> <单位> to <单位>` 闭环可用，主链路不推断量纲代数。
- [ ] **无状态内核**：`calc_eval` / `unit_convert` 单次调用独立完成，不维护跨调用变量作用域/依赖图；连续计算经 `context` 注入闭环，无拓扑排序与 `stale` 缓存。
- [ ] **单位换算模型**：`linear`/`affine`/`reciprocal`/`iec_si` 四类均按纯函数正确换算；温度仿射与油耗倒数（输入 0 报 `DIVISION_BY_ZERO`）验证通过。
- [ ] **reciprocal 跨制反比**：`l/100km → mpg`（= `235.215 / in`）、`l/100km → km/L`（= `100 / in`）走严格反比；同制 `mpg ↔ km/L` 走正比，均用各自 `reciprocalK` 正确换算（非原骨架错误的正比例 `in × K_to/K_from`）。
- [ ] **SI / IEC 边界**：`MB`(10⁶) 与 `MiB`(2²⁰) 为不同单位、互不串；`standard` 仅作校验。
- [ ] **别名/自省**：中文「千米每小时」「℃」「亩」命中别名；`unit_list({})` 返回 `dimensions`，带 `dimension`/`search` 展开 `units` 元数据。
- [ ] **聚合函数**：`sum(rent, food, utilities)` / `avg(10, 20, 30)` / `count(1, 2, 3)` 多参正确聚合；空集 `avg()` 返回 `AGG_EMPTY`，`sum()`/`count()` 返回 `0`（不再支持 `lineN..lineM` 行区间切片）。

- [ ] **context 数值类型**：`context` 同时接受 `num` 与纯数字 `String`，统一解析为 `Decimal`，类型异常返回 `UNDEFINED_VARIABLE` 而非静默兜底。
- [ ] **聚合 flatten**：`sum(1,2,3)` 与 `sum(expenses)`（`expenses:[10,20,30]`）及嵌套数组均正确摊平聚合。
- [ ] **开发顺序门禁**：`test/smoke_test.dart` 按 UnitConverter → Lexer → Parser → Evaluator/MCP 分层单测闭环，`flutter analyze` 0 issue 为交付线。

## 编码前落地边界（Execution Boundaries）

进入开发前需锁定的执行细节，避免实现期歧义：

- **`context` 注入变量的数值类型（统一 Decimal）**：`calc_eval` 反序列化 `context` 时，入参值须同时接受 `num`（`int`/`double`）与纯数字 `String`（如 `"2064.00"`、`"1.5e3"`）；统一解析为 `Decimal` 存入临时作用域再进入求值。缺失或非数字值按 `UNDEFINED_VARIABLE` 处理，避免类型转换异常——绝不静默吞错或兜底默认值（存疑实现标 `// UNCERTAIN:`）。
- **多参聚合函数 `sum`/`avg`/`count` 的扁平化（Flatten）**：求值器解析参数列表时增加一步 `flatten()`，既支持 `sum(1, 2, 3)` 的展开参数，也支持参数为数组变量（如 `context` 传入 `expenses: [10, 20, 30]` 后写出 `sum(expenses)`）；嵌套数组（`sum([1, 2], [3, 4])`）同样摊平后再聚合，提升移动单行与 Agent 调用的容错率。空集语义不变（`sum`/`count` 返回 `0`，`avg` 返回 `AGG_EMPTY`）。
- **验收门禁与开发顺序（`test/smoke_test.dart`）**：严格遵循「先纯静态、后组合」的四大能力分层，单测闭环顺序为：
  1. `UnitConverter`（纯静态注册表 + 纯函数换算，最易先跑通；Appendix A 补齐全量换算用例：linear/affine/reciprocal/iec_si 四类 + reciprocal 跨制反比）；
  2. **词法分析器 `Lexer`**（验证 Sanitizer 预清洗、全角→半角、千分位剥离、币种符规整、`to` 关键字分割、隐式乘法边界）；
  3. **语法分析器 `Parser`**（Shunting-yard 结合性、`^` 右结合、一元负号、隐式乘法插入、括号嵌套深度）；
  4. **Decimal 求值器 `Evaluator`**（AST 求值 + 运算栈 + 超越函数精度边界）+ **MCP Tool 适配层**（`calc_eval`/`unit_convert`/`unit_list` 入出参与错误模型对齐）。
  - 门禁基线：裸跑 `flutter analyze` 0 issue + 全量 `flutter test` 通过，方可交付。

## 相关文档

- 产品概述：[overview.md](overview.md)
- UI 开发规范：[../project/ui-design.md](../project/ui-design.md)
- MCP 内核工具面端口：`lib/mcp/tool_face.dart`
- 架构红线：项目根 `AGENTS.md`（arch-guard R1–R6）
