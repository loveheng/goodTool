---
status: active
updated: 2026-10-20
---

# goodTools · 领域网关工具（Domain Gateway Tool）设计 — 分类嵌入模式

> 状态：`active`。本文是「把零散能力聚合为少量领域工具」方案的**落地基线**。契约层 S1–S2 + 四域全部装配（`math_utility` 3 / `geo` 8 / `weather` 1 / `system_pim` 14，共 **26 action，26 个全部真实可用**）并经 `lib/tool_face_assembly.dart` 进入 HTTP 与 Binder 双通道；`CommandGateway` 写门禁随 5 个日历 W 档在生产路径闭环（arch-guard R7 为真门禁）。代码落点以 `docs/project/index.md` 的域级锚点为唯一事实源。

## 背景与动机

当前四大能力（计算/日历/地理/天气）若按原子粒度各自注册为 MCP 工具，工具面会快速膨胀：

- `calc_eval` / `unit_convert` / `unit_list` / `geo_current` / `geo_compass` / `geo_route` / `geo_static_map` / `fetch_weather` / `query_calendar_events` ……随能力增长可达数十甚至上百个。
- `tools/list` 每次把全部工具 schema 注入 LLM 上下文，Token 线性膨胀，且模型在长工具清单里更容易**幻觉拼写指令名**、注意力分散。

**目标**：把一个「业务域」内的 N 个细粒度操作压制为 **1 个 MCP 工具**，通过 `action` 枚举值 + 自由 `params` 对象完成精确调用。对 LLM 暴露的工具数量从 N 降到「域数」（本仓规划 4 个），且 `action` 用 JSON-Schema `enum` 严格圈定，杜绝指令名幻觉。

本模式对齐既有内核接缝与架构红线，是**工程装配层**的演进，不是重写内核。

## 核心模式

三层结构：

1. **`SubAction`（子操作契约）**：一个细粒度能力（如 `get_compass` / `evaluate_expression`）只实现一个微型接口，声明指令名、描述、紧凑参数签名 `paramSignature`（自动生成进 description）与执行体；执行体返回结构化的 `SubActionResult`（含 `isError` 与机器码）。
2. **`ActionCategory`（领域网关）**：把同类 `SubAction` 聚合为一个分类，由它自动汇总下属子操作并动态生成 1 个 MCP `Tool` 定义（含 `action` 枚举 + `params` 对象）。
3. **`McpCategoryServer`（总注册与派发）**：维护分类字典，`tools/list` 每个分类输出 1 个 `Tool`；`tools/call` 第一级按工具名路由到分类，第二级按 `action` 派发到具体 `SubAction`。

### 派发时序

```mermaid
flowchart LR
    A[tools/call] -->|name=geo| B[CategoryTool: geo]
    A -->|args.action=geo_current| B
    B -->|查 _subs[action]| C[SubAction.execute / buildCommand]
    C -->|依赖注入| D[GeoHttpProvider / LocationSensorProvider / WeatherProvider]
    B -->|W 档拦截 + 统一派发| E[CommandGateway 唯一写入口]
    C --> F[SubActionResult: text / error+code]
```

## 与现有架构的契合（为何改动面极小）

现有内核是**协议/传输/业务三层解耦**的纯 Dart MCP 服务，关键接缝是 `McpToolFace`：

22:22:lib/mcp/tool_face.dart
```dart
/// 演进后（见 §关键工程决策 #2）：call 返回完整 tools/call 结果（含 isError），
/// 内核透传；历史实现可包一层 {'content': list, 'isError': false} 兼容。
abstract class McpToolFace {
  List<Map<String, Object?>> schemas();
  Future<Map<String, Object?>> call(String name, Map<String, Object?> args);
}
```

它的两个方法正好就是 Kotlin 原案里 `listTools()` 与 `executeTool()` 的落点：

| Kotlin 原案 | 本仓落点 |
|---|---|
| `ActionCategory.toMcpTool()` | `CategoryTool.toSchema()` → `McpToolFace.schemas()` |
| `McpCategoryServer.listTools()` | `schemas()` 直接 `categories.map(toSchema)` |
| `McpCategoryServer.executeTool()` | `McpToolFace.call(name, args)` |

**结论：网关注册与派发层对内核零侵入**——只需在 `McpServer` 与 `McpToolFace` 之间插一层「分类注册表 + 自动派发」，现有 `SampleToolFace` 的扁平 `switch(name)`（见 `sample_tool_face.dart:45`）换成分类注册表只是把 switch 拆成「分类级路由 + 子操作级 map 查表」。**唯一需要内核配合的，是 `tools/call` 的 `isError` 合规**（见 §关键工程决策 #2 / #9）：将 `McpToolFace.call` 的返回从裸 content 列表演进为完整 result（`{content, isError}`），`McpServer._dispatch` 只透传、不再硬编码 `isError: false`。该演进**一次性完成、不设兼容分支**——`SampleToolFace` 同轮包一层 `{'content': list, 'isError': false}`，禁止内核出现 `if (result is Map)` 双路。

四个契合点：

1. **接缝零改造**：内核只认 `McpToolFace`，不感知分类概念。
2. **`library` + 不导出实现「公入口 / 私内部」**：Dart 的 `_` 下划线是**文件/库级私有**，无法跨文件子类化或调用。因此抽象契约 `SubAction`、`CategoryTool`、`register()` 须为 **package 内部 public**（不带 `_`），而**具体实现类**（`_CompassSub` / `_EvalSub`）才用 `_` 前缀私有于各自分类文件；同时 `category_tool_face.dart` 不进包的公共 barrel 导出，从而外部 package 仍不可见。最终效果与 Kotlin 匿名类方案一致且更彻底：MCP 线级只暴露 `categoryName` + `action` 枚举，内核与客户端无法绕过网关直触某个子操作实现。
3. **依赖反转正交**：子操作执行体不该碰 `dart:io`/平台 API（arch-guard R4 无头约束）。它应依赖注入已有的 `GeoHttpProvider`（`geo_provider.dart:11`）/ `LocationSensorProvider`（`geo_provider.dart:86`）/ `WeatherProvider`（`weather_provider.dart`），与现有 geo 纯 Dart 化范式一致。
4. **域网关 ≠ 写门禁，二者正交**：`CommandGateway` 是唯一写入口（`command_gateway.dart`）。域网关只做「枚举校验 + 派发」；遇到 `calendar_subscribe` / `calendar_marker_add` 这类 W 档写操作，由**网关层**在派发前鉴权 + 统一 dispatch，子操作只构造命令、不自己直写（arch-guard R1，机械约束见 coding-standards §3.3 G3）。

## 公共入口 / 私有内部（Dart 落地口径）

- **公开（package 内部 public，不进 barrel 导出）**：抽象契约 `SubAction`、分类 `CategoryTool`、公开方法 `register(SubAction)`、构造器 `buildXxxTool(providers)`、生成的 `toSchema()`。这些对 `McpServer` 与 MCP 客户端可见（但外部 package 经导出规则不可见）。
- **私有（文件级 `_`）**：具体子操作类 `_CompassSub` / `_EvalSub` 等——它们定义并仅使用于各自分类文件内，MCP 线级永远看不到；`CategoryTool._subs` 注册表为分类内部私有，仅经 `register()` 写入。

> **边界澄清**：Dart 没有「同 package 可见、跨 package 不可见」的修饰符，故抽象契约必须 public 才能被跨文件子类化。`_` 私有只能挡在文件边界内。要封住外部依赖，靠**不把 `category_tool_face.dart` 从包的公共 barrel（如 `lib/good_tools.dart`）导出**，而非靠 `_`。

这样满足诉求「入口公共、内部私有」：外部只能经由公开的分类工具名 + `action` 枚举调用，无法绕过网关直触某个子操作实现。

## 能力矩阵映射（四大能力 → 领域网关）

> **裁定（2026-10-20）**：**分类 = 四大能力域**，与 `docs/product/` 四份能力文档一一对应；`action` 名**原样沿用**各文档已定义的原子工具名，**不改名、不自造**。由此「文档表格第一列」与「各分类 `register()` 的 name 列表」成为可机械对账的断言，文档与实现天然单源。

| 领域工具（Tool Name） | action 枚举（= product 文档原子动作） | 数据源 / 实现端口 | 来源文档 |
|---|---|---|---|
| **`geo`**（地理与地图，8） | `geo_current`、`geo_geocode`、`geo_reverse`、`geo_search_poi`、`geo_route`、`geo_static_map`、`geo_compass`、`geo_distance` | `LocationSensorProvider` + `GeoHttpProvider`（`lib/mcp/geo_provider.dart`）＋纯 Dart 内核 `lib/geo/` | product/geo.md |
| **`system_pim`**（日历与标记，14） | `calendar_query`、`calendar_feeds`、`calendar_subscribe`、`calendar_unsubscribe`、`calendar_refresh`、`calendar_month_grid`、`calendar_resolve_date`、`calendar_marker_list`、`calendar_marker_add`、`calendar_marker_delete`、`calendar_date_calc`、`calendar_date_diff`、`calendar_workdays_between`、`calendar_tz_convert` | `CalendarFeedProvider`（待新增，模式对齐 `LocationSensorProvider`）+ `HolidayProvider` + `CommandGateway` | product/calendar.md |
| **`math_utility`**（计算与换算，3） | `calc_eval`、`unit_convert`、`unit_list` | 纯 Dart 求值 / 换算内核 | product/calculator.md |
| **`weather`**（天气，1） | `weather_forecast` | `WeatherProvider`（`lib/mcp/weather_provider.dart`）+ `LocationSensorProvider` | product/weather.md |

**合计 26 个 action**（geo 8 / calendar 14 / calc 3 / weather 1）。

**写操作标记**：`calendar_subscribe`、`calendar_unsubscribe`、`calendar_refresh`、`calendar_marker_add`、`calendar_marker_delete` 为 W 档（`isWrite: true`），其余为 R 档。构造分类时逐个标注，拦截由网关层统一执行（coding-standards §3.3 G3）。

### 已删除的通用能力（范围蔓延红线）

以下 6 项出自通用工具箱模板，**`docs/product/` 无任何一份能力规范登记，一律删除**：

| 已删除 action | 原属分类 | 删除理由 |
|---|---|---|
| `create_calendar_event` | system_pim | 违反 `product/calendar.md`「不做独立会议 / 日程管理」定位红线 |
| `set_alarm` | system_pim | 同上；且无能力文档定义 |
| `web_search` | network_utility | 无能力文档定义，属通用工具箱蔓延 |
| `fetch_webpage_content` | network_utility | 同上 |
| `get_step_counter` | device_sensors | 同上 |
| `get_battery_thermal` | device_sensors | 同上 |

> **纪律**：网关是**能力的聚合方式**，不是**能力的来源**。能力唯一来源 = `docs/product/*.md`；未登记进能力文档的 action 禁止进入网关矩阵。

## 关键工程决策与风险（必须正视）

1. **枚举只约束 `action`，不约束 `params`（参数盲盒）**：`params` 保持自由 `type: object` 省 Token，但 LLM（尤其轻量端侧模型）易出现参数名幻觉（`start_time`/`date`/`targetDate` 混用）、类型漂移。强类型（`oneOf`/`if-then` 内联各子操作 schema）会让 `tools/list` 膨胀、反吃 Token 收益。**决策**：保持 `params` 自由对象，但每个 `SubAction` 声明紧凑参数签名 `paramSignature`（如 `calc_eval(expr: string) [必填: expr]`），由 `toSchema()` **自动拼进 `action` 枚举的每行描述**——LLM 在看到枚举的同时即得参数名+类型，命中率接近全 Schema 而零 schema 膨胀。参数结构化校验仍交给 `SubAction.execute` 内部 + 清晰错误返回（对齐 `NullGeoHttpProvider` 抛 `ERR_AMAP_KEY_MISSING` 的机器码口径）。

2. **`isError` 合规（MCP 规范硬要求，需最小内核改动）**：现状内核 `tools/call` 把结果硬编码为 `isError: false`（`mcp_server.dart:118`），凡返回含"错误"字样的文本都被客户端当作成功，Agent 会误判任务已完成继续推进。**决策**：`isError` 是 `CallToolResult` **顶层字段**，绝不能塞进 Content 项（Content 只有 `type`/`text`）。故将 `McpToolFace.call` 返回类型从裸 `List<Map>` 演进为完整 result `{'content': [...], 'isError': bool}`；`McpServer._dispatch` 透传该 map 即可。子操作统一经 `SubActionResult`（见附录）产出 result，业务失败走 `SubActionResult.error(code, msg)`，成功走 `SubActionResult.success(content)`。该演进**一次性完成、不设兼容分支**（`SampleToolFace` 同轮包一层 `{'content': list, 'isError': false}`），详见 §决策 #9。

3. **Token 收益有上限**：60 个操作压成 4 类后，`tools/list` 里仍会出现全部 `action` 名 + 描述。真正省下的是「每个工具独立 schema 的结构开销」与「工具过多致模型注意力分散」，而非绝对字符数。优化靠 `paramSignature` 紧凑签名 + 短描述；长描述可下沉到 `action` 触发后的运行期提示，而非全部塞进 `tools/list`。

4. **权限/异常边界必须走 Provider，不碰平台 API**：原 Kotlin 示例在子操作里直接 `checkSelfPermission`，在 Dart 无头内核里违犯 R4（arch-guard R4 硬约束，删 UI 须可跑）。**决策**：权限/硬件读取一律经 `LocationSensorProvider`/`CalendarProvider` 等端口注入；端口实现（service 层）在无权限/无硬件时返回 `null` 或抛带 `code` 的异常（如 `PERMISSION_DENIED: READ_CALENDAR`），由子操作转成 `SubActionResult.error`，引导用户回 App 授权，不闪退。

5. **错误码口径须统一 + 前缀由派发层自动注入**：现有 geo 用「抛带 code 的异常」（`GeoHttpException`），而 Kotlin 示例用「返回 Error 字符串」。**决策**：统一为「裸机器码 + `category.action` 前缀」（如 `system_pim.calendar_marker_add: PERMISSION_DENIED`）。**前缀由 `CategoryTool.call` 在派发层统一拼接，子操作只吐裸 `code`，禁止手写前缀**——否则每新增一个子操作就重复一次拼接，网关退化为补丁（同 G1 去重纪律）。

6. **跨域链式调用（编排增强，非结构缺陷）**：真实诉求常跨域（如"从这到二七广场打车 8 折多少钱 + 3 点前能不能到"涉及 `geo`/`math_utility`/`system_pim`）。这**不是网关引入的缺陷**——扁平 60 工具同样要跨工具链；网关也未恶化它（分组反而降噪利于规划），LLM 原生就会多步规划。**缓解（描述级，非结构改造）**：① 各 action 描述内嵌"相关 action"提示（如 `geo_route` 注明"常配合 `math_utility.calc_eval` 算费用"）；② 输出保持自描述、可免解析链式传递（`calculator.md` 的 `numericValue` 即此意）。v2 再视需引入 composite/workflow 工具封装高频跨域配方。

7. **长任务进度需升级接缝**：原案 `context.sendProgress()` 在现内核没有对应物（`McpToolFace.call` 直接返回 content）。`geo_route` / `calendar_refresh` 等易卡顿操作若要实时进度，得给 `McpToolFace` 加 `McpToolContext`（含 `onProgress` 回调）。MCP 规范 progress 为 SHOULD 非 MUST——**决策**：v1 先按「返回即完成」实现（错误/成功均经 `SubActionResult`），确认需求后再升级接缝，避免过早改造内核。

8. **写门禁必须是机械拦截而非纪律**：`CommandGateway` 的唯一写入口语义若只靠「记得转发」，子操作一多必然出现绕过。**决策**：`SubAction` 声明 `isWrite`，`CategoryTool.call` 入口前置 `admits` 校验拦截；子操作**禁止** `import command_gateway.dart`、**禁止**出现 `.dispatch(`。写路径唯一物理通道 = 网关层。

9. **`isError` 必须唯一派生，禁止多点赋值**：现状 `mcp_server.dart:118` 硬编码 `isError: false`，凡含「错误」字样的返回都被客户端当作成功，Agent 据此误判任务已完成继续推进。**决策**：`SubActionResult.toMcpResult()` 内部硬绑定 `isError = !success`，`McpServer._dispatch` 只透传；内容信封 `success` 与 MCP `isError` 同源派生。**演进不设兼容分支**——`SampleToolFace` 同轮包一层 `{'content': list, 'isError': false}`，禁止在内核写 `if (result is Map)` 双路。

## 落地路径（最小改造）

1. **内核签名演进（一次性，不分期）**：`McpToolFace.call` 返回类型演进为完整 result（`{'content': [...], 'isError': bool}`），`McpServer._dispatch` 透传并拆除 `mcp_server.dart:118` 的硬编码 `false`；`SampleToolFace` 同轮包一层 `{'content': list, 'isError': false}`，**禁止**在内核留 `if (result is Map)` 兼容双路。新增 `lib/mcp/category_tool_face.dart` 实现 `SubAction` + `CategoryTool` + `SubActionResult` + `CategoryToolFace`（见附录骨架）。
2. 每个分类一个文件（如 `lib/tools/geo_tool.dart`），抽象 `SubAction` 跨文件子类化、具体 `_XxxSub` 实现私有，仅暴露 `buildXxxTool(providers)`；`category_tool_face.dart` 不进包 barrel 导出。
3. 子操作执行体一律依赖注入 Provider，绝不 `import` 平台/UI（守 R4）；W 档子操作只 `buildCommand`，鉴权与 `dispatch` 由网关层执行（守 R1 / §3.3 G3）。
4. 在 `McpController.toolFaceFactory`（`mcp_controller.dart:29`）收口各 `buildXxxTool()`，注入对应 Provider。
5. 错误统一经 `SubActionResult.error(code, msg)` 吐**裸机器码**，`category.action:` 前缀由派发层自动注入；`isError` 由 `toMcpResult()` 派生（`isError = !success`），不散落二次赋值；`progress` 先按「返回即完成」实现。
6. 落地后同步回写 `docs/project/index.md` 域级锚点（`action` 名沿用 product 文档原子名，无需改名）。

## 附录 A：Dart 落地骨架（参考）

> 无头纯 Dart 装配层参考；具体目录落点以 `docs/project/index.md` 为准（当前 `lib/` 尚无 `category_tool_face.dart`，勿臆造路径）。

```dart
// lib/mcp/category_tool_face.dart
// 注意：本文件不进包的公共 barrel 导出（如 lib/good_tools.dart），外部 package 不可见。

/// 子操作结构化结果：对齐 MCP CallToolResult（isError 在结果顶层，不在 Content 项）。
class SubActionResult {
  const SubActionResult.success(this.content)
      : isError = false,
        errorCode = null,
        errorMessage = null;

  /// [code] 为**裸机器码**（如 `PERMISSION_DENIED`）；
  /// `category.action:` 前缀由 [CategoryTool.call] 在派发层统一注入（G1）。
  SubActionResult.error(this.errorCode, this.errorMessage)
      : content = [
          {'type': 'text', 'text': '[$errorCode] $errorMessage'}
        ],
        isError = true;

  final List<Map<String, Object?>> content;
  final bool isError;
  final String? errorCode;
  final String? errorMessage;

  /// G4：`success` 与 MCP `isError` **同源派生**，禁止调用点二次赋值。
  bool get success => !isError;

  /// 产出完整 tools/call 结果对象（McpServer 透传给客户端）。
  Map<String, Object?> toMcpResult() => {'content': content, 'isError': isError};

  /// 派发层注入 `category.action:` 前缀；子操作只吐裸 code，不自行拼接（G1/G5）。
  SubActionResult withPrefix(String category, String action) => isError
      ? SubActionResult.error(
          '$category.$action: ${errorCode ?? 'UNKNOWN'}', errorMessage ?? '')
      : this;
}

/// 子操作契约：一个细粒度能力。package 内部 public（无 _ 前缀，供跨文件子类化）；
/// 具体实现类（_XxxSub）才用 _ 私有于各自分类文件。
abstract class SubAction {
  String get name;
  String get description;
  /// 紧凑参数签名，toSchema() 自动拼进 action 枚举描述，杜绝参数名幻觉。
  /// 例：'calc_eval(expr: string) [必填: expr]'
  String get paramSignature;

  /// G3 写标记：true ⇒ 网关层在派发前强制 `CommandGateway.admits()` 校验。
  bool get isWrite => false;

  /// R 档执行体（isWrite=false 时由网关调用）。
  Future<SubActionResult> execute(Map<String, Object?> params);

  /// W 档命令构造（isWrite=true 时由网关调用，构造后由**网关层**统一 dispatch）。
  /// 子操作只构造命令，禁止自行派发、禁止自行鉴权（G3）。
  Command buildCommand(Map<String, Object?> params) =>
      throw UnsupportedError('R 档子操作无命令构造');
}

/// 领域网关：把同类子操作聚合为 1 个公开 MCP 工具。
/// 公开面 = categoryName + action 枚举（含 paramSignature）；内部 = 子操作表（_subs）。
class CategoryTool {
  CategoryTool(this.categoryName, this.categoryDescription, this.commandGateway);
  final String categoryName;
  final String categoryDescription;

  /// 写门禁端口（唯一写入口，coding-standards §2.3）。
  final CommandGateway commandGateway;

  final Map<String, SubAction> _subs = {}; // 注册表私有，仅经 register 写入

  void register(SubAction a) => _subs[a.name] = a; // package 内部 public，跨文件可调用

  Map<String, Object?> toSchema() => {
        'name': categoryName,
        'description': '$categoryDescription\n支持操作：\n'
            '${_subs.values.map((a) => '- ${a.paramSignature}: ${a.description}').join('\n')}',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'action': {
              'type': 'string',
              'enum': _subs.keys.toList(),
              'description': '目标执行指令',
            },
            'params': {
              'type': 'object',
              'description': '该指令的具体键值参数（字段名与类型见 action 描述）'
            },
          },
          'required': ['action'],
        },
      };

  /// 二级派发：枚举校验 → 写门禁拦截 → 执行 / 统一派发 → 注入错误前缀。
  ///
  /// G1：**单一出口**——所有分支（含网关层自身的拒绝）汇入同一个 result，
  /// 再由唯一 `withPrefix` 注入 `category.action:` 前缀。新增早退分支不可能
  /// 漏掉前缀注入；子操作只吐裸 code。
  Future<SubActionResult> call(String action, Map<String, Object?> params) async {
    final SubActionResult result;
    final sub = _subs[action];
    if (sub == null) {
      result = SubActionResult.error(
          'UNKNOWN_ACTION', '分类 $categoryName 无指令 $action');
    } else if (sub.isWrite && !commandGateway.admits(action, params)) {
      // G3 写门禁：子操作执行体之前拦截，物理级无法穿透
      result = SubActionResult.error(
          'PERMISSION_DENIED', 'Write operation unauthorized');
    } else if (sub.isWrite) {
      // 唯一写入口：W 档由网关层统一 dispatch，子操作只构造命令
      result = SubActionResult.success(
          await commandGateway.dispatch(sub.buildCommand(params)));
    } else {
      result = await sub.execute(params);
    }
    // G1：错误前缀由派发层统一注入，子操作只吐裸 code
    return result.withPrefix(categoryName, action);
  }
}

/// 聚合工具面：实现演进后的 McpToolFace（call 返回完整 result，含 isError）。
class CategoryToolFace implements McpToolFace {
  CategoryToolFace(this._categories);
  final List<CategoryTool> _categories;

  @override
  List<Map<String, Object?>> schemas() => _categories.map((c) => c.toSchema()).toList();

  @override
  Future<Map<String, Object?>> call(String name, Map<String, Object?> args) async {
    final cat = _categories.where((c) => c.categoryName == name).firstOrNull;
    if (cat == null) {
      return SubActionResult.error('UNKNOWN_TOOL', '未识别的服务分类: $name').toMcpResult();
    }
    final action = args['action'];
    if (action is! String) {
      return SubActionResult.error('MISSING_ACTION', '请求缺少 action 字段').toMcpResult();
    }
    final params = args['params'] is Map<String, Object?>
        ? args['params'] as Map<String, Object?>
        : const {};
    return (await cat.call(action, params)).toMcpResult();
  }
}

/// LLM 弱类型输出宽容解析（防数字/布尔被包成字符串等漂移）。
double? parseDouble(Object? val) {
  if (val is num) return val.toDouble();
  if (val is String) return double.tryParse(val);
  return null;
}

int? parseInt(Object? val) {
  if (val is int) return val;
  if (val is double) return val.truncate();
  if (val is String) return int.tryParse(val);
  return null;
}

bool? parseBool(Object? val) {
  if (val is bool) return val;
  if (val is String) return val.toLowerCase() == 'true';
  return null;
}
```

```dart
// lib/tools/geo_tool.dart
import '../action/command_gateway.dart'; // 仅类型依赖（Command）；禁止 .dispatch(
import '../mcp/category_tool_face.dart';
import '../mcp/geo_provider.dart';

/// 公开入口：返回已注册好子操作的 CategoryTool（构造器公开，MCP 线级可见）。
CategoryTool buildGeoTool(
  LocationSensorProvider sensor,
  GeoHttpProvider http,
  CommandGateway gateway,
) {
  final cat = CategoryTool(
      'geo', '地理与地图（定位/地理编码/POI/路径规划/静态图/指南针/测距）', gateway);
  cat.register(_CompassSub(sensor)); // 具体子类私有，仅本文件可见
  cat.register(_CurrentSub(sensor));
  cat.register(_RouteSub(http));
  return cat;
}

/// 具体实现：_ 前缀 → 文件级私有，内核与 MCP 客户端均不可见。
/// G1：错误只吐**裸 code**（如 `PERMISSION_DENIED`），前缀由 CategoryTool.call 注入。
/// 子操作用 `extends SubAction`（抽象基类）——`isWrite: false` 默认被继承，
/// R 档无需逐个覆写（`implements` 不继承默认实现，会强制每个 R 档手写 isWrite/buildCommand）。
class _CompassSub extends SubAction {
  _CompassSub(this._sensor);
  final LocationSensorProvider _sensor;

  @override
  String get name => 'geo_compass';

  @override
  String get description => '获取磁力计方位角（0-359°）与八方位文字';

  @override
  String get paramSignature => 'geo_compass()';

  @override
  Future<SubActionResult> execute(Map<String, Object?> params) async {
    final reading = await _sensor.compass();
    if (reading == null) {
      return SubActionResult.error('PERMISSION_DENIED', '无传感器权限/硬件');
    }
    return SubActionResult.success([
      {
        'type': 'text',
        'text': '{"heading": ${reading.heading}, "direction": "${compassDirection(reading.heading)}"}',
      }
    ]);
  }
}

class _CurrentSub implements SubAction { /* 同构，委托 _sensor.current() */ }
class _RouteSub implements SubAction { /* 委托 GeoHttpProvider；入参经 G5 宽容解析 */ }
```

```dart
// lib/tools/system_pim_tool.dart —— W 档子操作示范
/// 写操作只构造命令，不派发；鉴权与 dispatch 均由网关层执行（G3）。
class _MarkerAddSub extends SubAction {
  @override
  String get name => 'calendar_marker_add';

  @override
  String get description => '添加重要事件标记（生日/纪念日/里程碑）';

  @override
  String get paramSignature =>
      'calendar_marker_add(originalDate: string, title: string, '
      'category: enum) [必填: originalDate, title, category]';

  @override
  bool get isWrite => true; // W 档：派发前经网关层 admits 校验

  @override
  Future<SubActionResult> execute(Map<String, Object?> params) =>
      throw UnsupportedError('W 档子操作不得直接 execute');

  @override
  Command buildCommand(Map<String, Object?> params) =>
      _CalendarMarkerAddCommand(params);
}
```

## 落地验证 Checklist

- [ ] **能力矩阵 1:1 对账**：4 份 product 文档表格第一列 = 各分类 `register()` 的 name 列表，合计 26；无自造 action、无遗漏（§3.3 G1）。
- [ ] **内核签名演进 + 工具数收敛**：`McpToolFace.call` 返回完整 result（`{content, isError}`），`McpServer._dispatch` 透传；`CategoryToolFace` 实现该接口，`tools/list` 仅返回 4 个领域工具；无兼容双路分支。
- [ ] **写门禁机械拦截**：W 档 action 未授权时返回 `PERMISSION_DENIED` 且子操作执行体未被触达；`lib/tools/**` 无 `.dispatch(`、无 `import command_gateway.dart`（§3.3 G3）。
- [ ] **isError 唯一派生**：`toMcpResult()` 内 `isError = !success`，二者同源；不存在「`isError:false` 而 `success:false`」的返回（§3.3 G4）。
- [ ] **枚举约束**：`tools/list` 输出的 `action` 字段含 `enum`，且 LLM 传入未在枚举内的 `action` 时返回 `UNKNOWN_ACTION` 错误（不幻觉执行）。
- [ ] **紧凑签名消盲盒**：`action` 枚举每行含 `paramSignature`（参数名+类型+必填），非全 Schema 膨胀。
- [ ] **公入口/私内部**：抽象 `SubAction` 与 `register` 为 package 内部 public 且不进 barrel；具体 `_XxxSub` 为文件级私有；内核与 MCP 客户端无法绕过网关直触实现。
- [ ] **依赖反转**：子操作执行体经 Provider 注入，无 `dart:io`/平台 API import（arch-guard R4）。
- [ ] **写门禁**：`calendar_subscribe` / `calendar_marker_add` 等 W 档写操作由网关层前置 `admits` 校验 + 统一 `dispatch`；子操作只 `buildCommand`，无 `.dispatch(` / `.admits(` 调用（arch-guard R1 / §3.3 G3）。
- [ ] **错误口径**：统一带机器码 + `category.action` 前缀；缺权限返回 `PERMISSION_DENIED:*`，不闪退。
- [ ] **宽容解析**：`parseDouble/parseInt/parseBool` 兜底 LLM 弱类型漂移（数字/布尔被包成字符串）。
- [ ] **Token 控制**：`tools/list` 工具数 = 域数（4），`action` 明细紧凑，长描述不下沉进清单。
- [ ] **纯 Dart 单测**：`test/` 用 Mock Provider 走通各 `action` 派发闭环，`flutter analyze` 0 issue 为交付线。

## 相关文档

- 产品概述（四大能力范围）：[../product/overview.md](../product/overview.md)
- 计算器能力（math_utility 内部语义）：[../product/calculator.md](../product/calculator.md)
- 地理能力（device_sensors 内部语义）：[../product/geo.md](../product/geo.md)
- 天气能力（network_utility 内部语义）：[../product/weather.md](../product/weather.md)
- 日历能力（system_pim 内部语义）：[../product/calendar.md](../product/calendar.md)
- MCP 内核工具面端口：`lib/mcp/tool_face.dart`
- 唯一写入口：`lib/action/command_gateway.dart`
- 架构红线：项目根 `AGENTS.md`（arch-guard R1/R4）
- 功能落点索引：[index.md](index.md)
