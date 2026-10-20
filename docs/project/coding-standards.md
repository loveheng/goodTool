---
status: active
updated: 2026-10-20
---

# goodTools · 工程规范（Engineering Specification / Arch-Guard SSOT）

> 本文是编码 / 架构规则的**契约 SSOT**——对齐架构认知、锁定模块边界、给机械门禁（`arch-guard`）提供依据。只写规则，不写演进史；项目现状数据（架构债、直连白名单基线、超标清单）一律住 [`index.md`](index.md)，本文按节引用。
>
> 冲突裁决：`context/epics/<epic>/memory.md` 显式决策 ＞ 本文 ＞ 通用规约。
>
> 本工程为**无头 MCP 壳**：删掉整个 Flutter UI，MCP 命令面应能完整运行。故 UI 不得绕过命令层、`mcp`/`action` 层不得反向依赖 UI。此前提决定 §1 分层与 §3 端口纪律的硬边界。
>
> 章节骨架参照 goodhub `coding-standards.md`（§1~§9）以保持一致可读性；内容按 goodTools 无头现实改写，goodhub 专属段（llm/sandbox/gateway/coordinator/PII 围栏/$ref/双进程/对话态机）已剔除。

## 1. 架构拓扑与分层依赖（Dependency Rules）

拓扑 = **扁平域目录**（`lib/` 一级域：`action/` `geo/` `mcp/` `service/` `tools/` `update/` + 装配件 `main.dart` `mcp_binder_entrypoint.dart` `ports.dart`）。依赖方向**自底向上**，无文件级环。

| 域 | 角色 | 允许的域内出向（内部 import） |
|---|---|---|
| `mcp/` | MCP 内核（JSON-RPC/传输/server/工具面接口/KV/示例工具） | 纯 Dart 件可直接用；经端口引 `geo`/`service` 的接口定义（依赖倒置） |
| `action/` | 命令层（CommandGateway 唯一写入口） | `mcp`（接口）；可 import 业务域执行体 |
| `geo/` | 地理/地图内核（坐标纠偏/测距/静态图 URL/签名/抽稀/HTTP 端口） | 纯 Dart，零 Flutter 依赖；可 import 自身 |
| `service/` | 服务层（前台服务保活/HTTP 传输/MCP 控制） | `mcp`（装配）、`action` |
| `tools/` | 工具面扩展（领域网关/子操作） | `mcp`（`tool_face`）、`action`（写门禁）、注入的 provider 端口 |
| `update/` | 自更新（安装器/远程配置热更/清单/服务） | 独立叶子域，零内部出向 |
| 装配件 `main.dart`/`mcp_binder_entrypoint.dart`/`ports.dart`/`tool_face_assembly.dart` | 装配入口 | 任意域，但只持装配职责，业务逻辑不得回灌 |

### 1.0 架构红线（arch-guard 口径）

机械校验见 `toolbox run arch-guard`（`scripts/agent-tools/arch-guard.sh`）。白名单是**历史例外**，只许减少不许增加。

| 规则 | 作用域 | 约束 | 当前可扫 |
|---|---|---|---|
| **R1** 唯一写入口 | `lib/ui`（用户层·待建） | 写路径必须组装命令交 CommandHandler（唯一写入口） | lib/ui 落地即扫（arch-guard 已含扫描模式） |
| **R2** UI 禁内联 JSON | `lib/ui`（用户层·待建） | 编解码委托数据/命令层（导出预览豁免 `settings_page.dart`） | lib/ui 落地即扫 |
| **R3** UI 禁平台分支 | `lib/ui`（用户层·待建） | `Platform.isX` 收敛到接口实现/工厂 | lib/ui 落地即扫 |
| **R4** mcp/action 禁 import Flutter UI | `lib/mcp` `lib/action` | 禁 `import 'package:flutter/(material|widgets).dart'`，无头系统硬约束，删 UI 须可跑 | **可扫** |
| **R5** UI 禁直连 Db | `lib/ui`（用户层·待建） | 数据访问一律走 Repository | lib/ui 落地即扫 |
| **R6** 禁弃用 textScaleFactor | `lib` 全量 | 改 `textScaler` 并映射 M3 `textTheme` | **可扫**（全 lib） |
| **R7** tools 层禁绕过网关写门禁 | `lib/tools` | 禁 `.dispatch(` / `.admits(`，写必经 `CategoryTool` 网关层统一派发与鉴权（§2.3 / §3.3 G3）；`Command` **类型依赖合法**（W 档 `buildCommand` 返回类型） | **可扫**（S7 起启用） |

> 本工程为无头 MCP 壳，但已确认引入 `lib/ui` 用户层。arch-guard 已内置 R1~R5 扫描模式（作用域 `lib/ui`），`lib/ui` 建层后即自动覆盖；R4（mcp/action 禁 import UI）+ R6（禁 textScaleFactor）已对现有 `lib` 全量生效；R7 随 S7 启用（`sample_tool_face.dart` 已退役，无需白名单）。白名单是历史例外，只减不增。

### 1.1 无头内核纪律（R4 的本质）

- `lib/mcp/`、`lib/action/` 下的文件**严禁 import Flutter UI**（`material.dart` / `widgets.dart` / `BuildContext`）。内核须可被 headless 路径复用（无 Flutter 运行时也能 `flutter test` 跑通）。
- 机械验收：新增内核文件 grep 无 `package:flutter`（material/widgets）。
- 平台/硬件能力一律走**端口注入**（§1.2），内核只依赖纯 Dart 抽象。

### 1.2 端口与依赖反转纪律

- **内核禁直连平台 API**：子操作/内核执行体不得 `import` `dart:io` 平台 API 或 `Platform.isX`（R4 延伸）；权限/硬件读取经 Provider 端口注入，`LocationSensorProvider`（`lib/mcp/geo_provider.dart`）为范式。
- **端口实现可缺位 fail-closed**：未注入源抛带 `code` 的异常（如 `ERR_AMAP_KEY_MISSING`），由上层转 `ToolResult.Error`，不闪退、不静默降级。
- **跨域能力走最小抽象端口 + 注入**：消费方域内定义 `abstract interface class` 最小能力集，实现方 `implements`（方向合法）；对齐 `weather_provider.dart` / `geo_provider.dart` 范式。

### 1.3 新功能落点决策表

| 新功能类型 | 落点域 | 关键约束 |
|---|---|---|
| 新 MCP 传输/工具面 | `lib/mcp/` | 内核零改造，只认 `McpToolFace`（`lib/mcp/tool_face.dart`）；新工具实现 `McpToolFace` |
| 新领域网关 / 子操作 | `lib/tools/`（`library;` 文件，`_SubAction` 私有） | 公入口（`categoryName` + `action` 枚举）/ 私内部（子操作）；依赖注入 Provider，写操作转 `CommandGateway`；契约机械约束见 §3.3 G1–G6 |
| 新写类命令 | `lib/action/` | 必须走 CommandGateway 唯一写入口（R1 前瞻） |
| 新地理/地图能力 | `lib/geo/` | 纯 Dart 无头，经 `GeoHttpProvider`/`LocationSensorProvider` 端口；坐标归一 WGS-84→GCJ-02 |
| 新平台/硬件能力 | `lib/service/` + Provider 端口 | 端口实现住 service 层，内核经注入消费（§1.2） |
| 新自更新/发布能力 | `lib/update/` | 发布侧 `scripts/`（release-r2 链） |

### 1.4 新顶层域纪律

`lib/` 新增一级域须**三处同步**：① 本文 §1.0 分层矩阵（角色 + 允许出向）；② [`index.md`](index.md)（域内文件落点）；③ 若涉跨域依赖边界，`test/` 加依赖护栏。拍板前禁止新增前缀——优先落现有域子目录。

## 2. 状态、数据不可变性与生命周期（State & Lifecycle）

### 2.1 生命周期所有权表

| 资产 | 所有者 | 共享方式 | 释放/销毁纪律 |
|---|---|---|---|
| 应用级服务（`McpServer` 单例、前台服务） | 装配容器单例 | 经端口/流订阅（`McpController`、`onCall`） | 随进程存亡，禁止外部提前销毁 |
| UI 视图态（`McpController` ChangeNotifier） | UI 持有 | `AnimatedBuilder` / `StreamBuilder` 绑定 | UI `dispose` 取消订阅、解绑流 |
| 配置 / 画像值对象 | 不可变快照 | `copyWith` 演进 | 不原地改，变更经 CommandGateway 回写 |

> 领域态与视图态不得同居同一 `State`：新增会话级/配置字段一律落内核并由命令层持久化，禁止在窗口 `State` 加裸字段 + 手工 reset（漏改即静默 bug）。

### 2.2 实体不可变性

- 配置/状态模型统一 `@freezed` 或手写全 `final` 不可变类，禁止可变集合（裸 `List`/`Map` 出参）；更新一律 `copyWith`。
- **禁 `dynamic`**：网络/工具返回值解析完成后第一时间转强类型；内核管道禁止 `dynamic` 传递。
- **显式错误传递**：统一 `Result<T, McpError>` 包装或领域异常（`lib/mcp/` 错误类型），禁止随处裸抛无类型异常（详见 §5.3）。

### 2.3 写入口纪律（CommandGateway 唯一写入口）

- 一切副作用写路径经 `lib/action/command_gateway.dart` 的 `CommandGateway`（R1 前瞻：UI 引入后亦适用）。领域网关（§1.3）只做「枚举校验 + 派发」，遇写操作内部转发 `CommandGateway`，不自己直写。
- 写操作返回**变更后最新状态**（对齐读工具同形状），禁回 `void`/纯成功文案。

## 3. 并发模型与写安全（Concurrency & Write Safety）

### 3.0 单进程硬约束

Flutter UI、前台服务、`McpServer` headless 监听严格**同单 OS 进程**，禁 `:remote` 多进程——跨进程并发会使串行写队列（§3.2）与单例生命周期失效。

### 3.1 执行线程划分

- **主 Isolate**：Flutter UI、`CommandGateway` 串行写队列、状态机——只做轻量状态驱动与渲染调度，禁止大 JSON 解析、密集正则、大文件 IO。
- **Worker Isolate（CPU 密集强制离主线程）**：坐标抽稀、签名运算、>1MB 临时文件处理等。**CPU 密集任务必须带执行超时看门狗**（防正则/解密灾难回溯拖死主 Isolate）。

### 3.2 写安全（Write Safety）

- 一切写路径经 `CommandGateway` 的**串行队列**派发（链排空且无后继即惰性除名，防无界增长）；`SettingsKv` / Repository 的写均经此队列，禁止并发裸写磁盘、禁止绕过 writer 直接 `File.writeAsString`。
- **复合「读-改-写」单元同样必须接入**：只串行化底层 write 不够——两处仍会各自读到同一份旧内容、后写覆盖前写。键值写取配置键粒度串行。
- 单次失败向调用方透传异常但**不毒化队列**（续链与透传分离）。
- **网关层是写门禁的机械拦截点**：领域网关（`lib/tools/*_tool.dart`）只做「枚举校验 + 派发」；写操作由 `CategoryTool.call` 入口前置校验后转发 `CommandGateway`，子操作内部禁止自行鉴权、禁止自行 `dispatch`（§3.3 G3）。

### 3.3 领域网关契约（分类嵌入模式）

> 设计正文见 [`domain_gateway.md`](domain_gateway.md)（契约层 S1–S2 与 `math_utility`(3) / `geo`(8) 已落地 `lib/`，`system_pim` / `weather` 待排期）；本节只写**机械约束**，是网关实现的准入红线。裁定记录见 `context/decisions.md` misc 节（2026-10-20）。
>
> **装配纪律（S7）**：各 `buildXxxTool()` 由 `lib/tool_face_assembly.dart` 单点收口成 1 个 `McpToolFace`，HTTP 调试通道与 Binder 生产通道**共用同一份装配**——新增能力只改装配工厂，禁止两通道各自装配（否则出现「HTTP 有、Binder 无」的能力漂移）。

一个「业务域」= 1 个 MCP 工具，经 `action` 枚举 + 自由 `params` 对象完成精确调用。三层：`SubAction`（子操作契约）→ `CategoryTool`（领域网关，自动汇总生成 1 个 Tool）→ `CategoryToolFace`（总注册与派发，实现 `McpToolFace`）。

**G1 能力矩阵 1:1 对齐（范围蔓延红线）**

- 分类 = 四大能力域 `geo` / `system_pim` / `math_utility` / `weather`，**分类数 = 4 份能力文档**；
- `action` 名**原样沿用** `docs/product/*.md` 已定义的原子工具名，**禁止改名、禁止自造**——使「文档表格第一列」与「各分类 `register()` 的 name 列表」成为可机械对账的断言，根除文档/实现双轨；
- 合计 **26 个**原子动作（geo 8 / calendar 14 / calc 3 / weather 1）。新增 action 必须先补 product 文档，禁止先落地代码再补文档。

**G2 公共入口 / 私有内部**

抽象契约 `SubAction` / `CategoryTool` / `register()` 为 **package 内部 public**（`_` 为文件级私有，跨文件无法子类化），且**不进包的公共 barrel 导出**；具体实现类（`_CompassSub` / `_EvalSub` 等）以 `_` 前缀私有于各自分类文件。对外只暴露 `categoryName` + `action` 枚举，无法绕过网关直触实现。

**G3 写门禁机械强制（R1 防御）**

R1 不能只靠「记得走 CommandGateway」——子操作一多必然出现绕过。故写路径收口到**网关层单一物理通道**：

- `SubAction` 基类声明 `bool get isWrite => false;`；W 档子操作覆写为 `true` 并实现 `buildCommand(params) → Command`（**只构造命令，不派发**）；
- 在 `CategoryTool.call(action, params)` **入口处**前置拦截，随后由网关层统一派发：

```dart
// 拦截：子操作执行体之前，物理级无法穿透
if (sub.isWrite && !commandGateway.admits(action, params)) {
  return SubActionResult.error(
      'PERMISSION_DENIED', 'Write operation unauthorized');
}
// 派发：唯一写入口，子操作自身不得调用 dispatch
final result = sub.isWrite
    ? SubActionResult.success(
        await commandGateway.dispatch(sub.buildCommand(params)))
    : await sub.execute(params);
```

- **机械镜像（§8.1）**：`lib/tools/**` 内禁止出现 `.dispatch(` 与 `.admits(`；出现即 CI 阻断。子操作可 `import` `Command` 类型（类型依赖合法，`tools/` → `action` 方向见 §1），但不得持有或调用派发器。

**G4 `isError` 唯一派生**

- `SubActionResult.toMcpResult()` 内部硬绑定 `isError = !success`；**禁止**在 `mcp_server.dart` 或任何调用点二次赋值（现状 `mcp_server.dart:118` 硬编码 `false` 须同轮拆除）；
- 内容信封 `success` 与 MCP `isError` 由同一状态派生，杜绝「`isError:false` 而 `success:false`」的矛盾体。

**G5 参数宽容解析边界**

`params` 为自由 `object`（省 Token），参数名与类型由 `toSchema()` 自动拼进 `action` 枚举描述（`paramSignature`）。宽容解析（`parseDouble`/`parseInt`/`parseBool`）**只允许出现在子操作入参边界这一层**，一次性转强类型；缺参或不可解析一律返回带 `code` 的 error，**禁止取默认值兜底**（守 §4.2 严禁静默降级）。

**G6 W 档前置校验与 Actor 信封（P2-⑤ 新增）**

- **`buildCommand` 无法表达失败**：它只能返回 `Command`。必填缺失、URL 护栏拒绝、幂等冲突这类**可预期失败**若塞进行命令构造，只能抛异常，最终被内核兜成散文错误（破坏 D3 结构化错误口径）。故 `SubAction` 提供可选 `validate(params) → SubActionResult?`，在 `CategoryTool.call` 中按 `admits → validate → dispatch` 顺序执行：`validate` 返回非 null 即以之为最终结果，跳过派发。
- **拦截顺序固定为 `admits` 先于 `validate`**：未授权会话不得触达任何入参校验（不泄露「该缺什么参数」这类可枚举信息）。
- **Actor 输出统一为信封**：`{'success': bool, ...}` 首条 text JSON；失败附 `error: {code, message, suggestion?}`。`SubActionResult.fromActor` 据此派生 `isError = !success`——否则业务失败（如 URL 被 SSRF 护栏拒绝）对客户端表现为「调用成功」。
- **失败信封必须走 `structuredError` 构造**：`_raw` 构造的 `errorCode` 为 null，`withPrefix` 会把 `[前缀: UNKNOWN]` 文本**替换掉**原 JSON 信封，自愈字段随之丢失（P2-⑤ 实测踩坑，已有单测钉死）。
- Actor（service 层）仍须对安全关键项（URL 护栏）做**防御性复检**：装配路径若绕过子操作 `validate`，Actor 是最后一道闸。

## 4. 容错、熔断与降级（Fault Tolerance & Degradation）

### 4.1 Fail-Closed 铁律

- **无头恒拒绝**：无人值守模式下，涉及 Human-In-The-Loop 的确认逻辑立即 `approved: false` 快速拒绝，禁阻塞挂起或静默放行。
- **端口缺位恒拒绝**：未注入能力源（如缺地图 Key）抛带 `code` 异常，由上层转 `ToolResult.Error`，不闪退、不静默降级。
- **安全围栏异常/超时恒拒绝**：权限/密钥校验发生异常或超时时一律按拒绝处理，禁止静默通过。

### 4.2 降级可见性分级（数据面 / 非数据面）

`[DEGRADE]` 埋点按**数据面 / 非数据面**两档划界，禁止一切「磁盘满/权限失败静默丢数据」：

- **数据面写失败**（落盘事实、配置持久化、快照等用户资产的写路径）：失败必须**升为用户可观测**；未接回调时至少 `[DEGRADE]` 留痕；`unawaited` 只允许挂在**已接错误上报**的 future 上，裸 `discarded_futures` 即违例。
- **非数据面降级**（心跳保活、progress 瞬态帧、审计流水等：失败不丢用户数据，只损可观测性）：允许 `[DEGRADE]`/空吞留痕不阻断主链路，但**须在代码注释声明其非数据面属性**。
- **严禁静默降级**：AI 写码不得空 catch / 吞异常 / 兜底默认值；存疑实现标 `// UNCERTAIN:`，有意降级标 `// DEGRADE:` 并打 `[DEGRADE]` 日志（与 `AGENTS.md` 编码前必读一致）。

## 5. 接口契约与标识符规范（Interface Contracts）

> 约束对象 = 经 MCP 暴露的工具面（`lib/mcp/` + `lib/tools/` 领域网关）；纯内部件不受强制，但建议同口径。

### 5.1 工具描述主动引导

每个 MCP 工具的 `description` 须写「怎么用才对」，不仅「干什么」——推荐用法、适用场景、参数约束与反例。空泛描述（"获取天气"）不合格。

### 5.2 写后必回最新快照

写类工具返回**变更后的最新状态**（与对应读工具同形状），禁止回 `void`/纯成功文案——调用方（Agent）上下文必须与库内状态对齐；数据移出可见域时显式置空并说明。

### 5.3 错误契约：机器码 + `category.action` 前缀

- 拒绝统一带机器可读 `code`；可纠正分支带 `hint`（告诉调用方下一步）。
- **统一口径**：`category.action: CODE`（如 `math_utility.evaluate_expression: UNEXPECTED_TOKEN`、`device_sensors.get_compass: PERMISSION_DENIED`），便于 UI 弹配置引导卡与排障定位（源于 `docs/project/domain_gateway.md` 决策 #4）。
- 禁底层异常（IO/平台/堆栈）裸漏到 MCP 层；统一领域异常或 `Result<T, McpError>` 包装。
- **前缀由网关统一注入**：`${categoryName}.${action}: ${code}` 由 `CategoryTool.call` 在派发层自动拼接，子操作**只吐裸 `code`**，禁止手写前缀（守 §3.3 G1/G5 同类去重纪律）。

### 5.4 标识符与命名约定

- **文件命名**：小写蛇形（`geo_provider.dart` ↔ `GeoProvider`），文件名与主要暴露类型严格对应。
- **工具命名空间**：工具名 snake_case，领域网关以 `categoryName` + `action` 枚举组织；工具名内部禁止再出现双下划线分隔以外的歧义前缀。
- **数据引用前缀**：惰性句柄（如抽稀缓存键）统一 `$ref:<domain>:<unique_id>` 形式，避免裸路径拼接。

### 5.5 新增工具自查清单（任一缺失即不合格）

工具注册（含 §5.1 描述引导）→ 实现 `McpToolFace`（`schemas()` + `call()`）→ 参数 Schema（强类型，禁 `dynamic`）→ 错误契约（§5.3 `code` + `hint`）→ 契约测试（`test/`，与 §8 质量门禁同交付线）。

## 6. 安全、脱敏与隐私护栏（Security & Privacy）

### 6.1 凭证零明文留痕

密钥、Token、私有凭证（地图厂商 API Key、身份画像）严禁出现在日志输出、崩溃堆栈或未加密的本地持久化中——凭证类一律走系统安全存储抽象（`SettingsKv` / 平台安全存储，平台实现经装配注入），不落明文 `SharedPreferences`。

### 6.2 写操作经唯一网关 + 安全存储

- 任何用户触发的写（API Key、脱敏开关、身份画像）组装命令交 `CommandGateway.dispatch`，UI 不得直连 KV/Repository（R1/R5）。
- 敏感字段过滤（日程敏感字段、模糊定位模式）由命令层在落盘前应用，UI 只持开关态，不持明文凭证。

## 7. 资源释放与内存防泄漏（Release Hygiene）

### 7.1 成对生命周期（谁构造谁销毁）

每条装配链上每个 `new` / `listen` 都必须指向某个 `close` / `cancel` 调用点；注入端口「谁创建谁销毁、有无独立 dispose」写进端口文件头注释（范式：`geo_provider.dart`——provider 无独立 dispose，释放唯一入口 = owner 调 `close()`）。

### 7.2 幂等 close

一切资源句柄 `close()`/`dispose()` 幂等，防重入守卫覆盖正常 + 异常双路径：
- `McpServer` 停止显式 `close`，`onCall` 订阅在 UI `dispose` 取消；
- 前台服务 `flutter_foreground_task` 的 `stop()` 显式释放 Timer/流；
- 测试须有释放断言（注入 fake 计数验证连接全部 close）。

### 7.3 临时资源即焚

`geo` 抽稀缓存、>1MB 临时处理文件挂清理——用完即焚 + TTL 兜底 + 冷启动孤儿扫描（挂 `main.dart` 装配期），**须有断言验证**防止泄漏。

## 8. 自动化门禁与架构看门狗（CI Guardrails）

> 凡本文明确的红线，必须有机械拦截；规则正文在本文，机械实现只镜像不立法。

### 8.1 机械门禁矩阵

| 规则项 | 门禁实现 | 拦截时机 |
|---|---|---|
| 无头约束（R4 mcp/action 禁 import Flutter UI） | `scripts/agent-tools/arch-guard.sh` | pre-commit / 改动 lib/ 后 |
| 弃用 API（R6 textScaleFactor） | `arch-guard.sh` | pre-commit |
| 静态检查 | `flutter analyze` 0 issue 为交付线 | 提交前 |
| 纯 Dart 内核全链路 | `flutter test`（test/smoke_test.dart + test/geo_test.dart，无设备可跑） | 提交前 |
| 依赖环 / 跨域直连 | `arch-guard.sh` 扫描模式（lib/ui 落地即扫 R1~R5） | pre-commit |
| 网关写门禁（`lib/tools/**` 禁 dispatch / admits 调用，写必经 `CategoryTool` 网关层统一派发与鉴权） | `arch-guard.sh` **R7**（S7 起启用；`sample_tool_face.dart` 已退役，零白名单） | pre-commit |
| 装配单点收口（HTTP 与 Binder 双通道共用同一工具面） | `lib/tool_face_assembly.dart`（新增能力只改本文件）+ `flutter test`（`test/tool_face_assembly_test.dart` 断言工具数 = 域数） | 提交前 |
| 网关派发契约（枚举外 `action` → `UNKNOWN_ACTION`；未授权写 → `PERMISSION_DENIED`；`isError ⇔ !success`） | `flutter test`（`test/`，Mock Provider 走通闭环） | 提交前 |

> 架构债与白名单基线见 [`index.md`](index.md)；R1/R2/R3/R5 待 lib/ui 引入时补机械镜像（只减不增）。

### 8.2 单文件体量护栏

- **软红线 800 行**：新文件评审时超 800 行须拆分；800~1200 行的新文件须在文件头注释声明拆分计划。
- **存量超标清单（只减不增）**：登记于 [`index.md`](index.md)「存量超标清单」，任一件降到 800 以下即从清单移除。

## 9. 与 dev-loop 工程护栏的对齐

规范变更（本文任何节实质修改）须同轮：① 刷新 `updated` 字段；② 检查 arch-guard 是否需同步；③ 涉及 docs/ 归属的按 goodTools-docs 维护协议三处同步；基线数据同步 [`index.md`](index.md)；workflow skill 事实面同轮刷新。
