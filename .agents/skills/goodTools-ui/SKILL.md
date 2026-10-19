---
name: goodTools-ui
description: goodTools UI（用户层）开发与规范落点：Material 3 工业控制台视觉纪律、无头架构红线指针与验收要求。建 lib/ui、改页面、加组件前必读；规范正文 SSOT = docs/project/ui-design.md。
---

# goodTools-ui · UI（用户层）规范与开发纪律

> **规范正文 SSOT**：[`docs/project/ui-design.md`](../../../docs/project/ui-design.md)（Material 3 工业控制台风格；无头架构约束已对齐 arch-guard R1–R6）。本 Skill 只负责**代码落地纪律与防腐化门禁**，不复制设计正文；工程规则正文（分层/平台边界/门禁）在 `docs/project/coding-standards.md`，命令唯一出处 = goodTools-workflow skill——三者均只留指针，防双源。

## 1. 查阅指引（按改动范围定向查阅）

| 准备修改的内容 | 规范正文查阅位置 | 核心实现/落点 |
|---|---|---|
| 架构红线（R1 写门禁 / R2 内联 JSON / R3 平台分支 / R4 内核禁 UI / R5 直连 Db / R6 textScaleFactor） | `coding-standards.md` §1.0 | `lib/ui/`（建层后）；红线 SSOT = `docs/project/coding-standards.md` §1.0 |
| 数据流（只读订阅 ChangeNotifier/Stream，写必经 CommandGateway） | `ui-design.md` §3.2（实时调用流） | `lib/service/mcp_controller.dart` + `lib/action/command_gateway.dart` |
| 视觉规范（M3 动态取色 / 等宽数值区 / textScaler / 暗色优先） | `ui-design.md` §1/§2/§4/§5（色彩/排印/交互/布局） | `lib/ui/` 主题与 `TextTheme` 注入（色彩/字号/圆角/动效时长经 token，禁裸写） |
| 页面结构（仪表盘/沙盒/设置 三 Tab） | `ui-design.md` §3（界面模块规格） | `lib/ui/` 各页 + `lib/ui/components/`、`lib/ui/sections/` |
| 反模式清单 | `ui-design.md` §7 | — |

> UI 为**低频打开、高频后台、面向外部 Agent 调用**的基础设施工具：约束优先级 = 架构红线 > 视觉偏好。

## 2. 编码纪律与高压红线

### A. 零魔法值（本 skill 专属执行细则）

- **尺度无条件 `textScaler`**（R6）：禁 `textScaleFactor:`，M3 尺度走 `textTheme` + `textScaler`。
- **等宽数值区**：时间戳、经纬度、计算器结果、JSON 预览走等宽字体，经 `TextTheme` 注入，不靠 widget 内硬编码。
- **色彩/字号/圆角/动效时长**：统一走主题 token（`Theme.of(context)` 取 `TextTheme` / `ColorScheme`），禁裸写 `Color(0xFF...)`、内联 `TextStyle(...)`、硬编码数值边框/圆角/时长。

### B. 架构红线（指针——规则正文在 coding-standards.md，本 skill 不复制）

- **平台隔离（R3）**：`lib/ui/` 禁 `import 'dart:io'`、禁 `Platform.isX`、禁 `MethodChannel(` 直连；特权能力一律抽象接口 + 装配期注入——规则与处置 = `docs/project/coding-standards.md` §1.2，机械闸 = `arch-guard` R3，**红灯修结构，不申请白名单**。
- **写门禁（R1）**：UI 禁直连 repo/Repository 写，写路径组装命令交 `CommandGateway`（唯写入口，`lib/action/command_gateway.dart`）。
- **内联 JSON（R2）**：UI 禁 `jsonDecode/jsonEncode`，编解码委托数据/命令层（导出预览口径豁免见 coding-standards 白名单基线）。
- **内核禁反向依赖（R4）**：`mcp`/`action` 层禁 import Flutter UI——无头系统硬约束，删 UI 全链路须可跑。
- **数据访问（R5）**：UI 禁直连 `Db.instance`，经 Repository。
- **视图态与领域态解耦**：UI 仅持临时交互态，禁就地持有领域核心态/共享单例；跨窗口状态走既有装配口径（注入位范式查 coding-standards §1.2）。
- **长列表保活**：设置页有状态段必须混 `AutomaticKeepAliveClientMixin`（防 ListView 滚动复用丢态）。

### C. 组件登记（指针——登记规约在 goodTools-index skill）

- 新增通用业务组件（`lib/ui/components/`）**同轮**登记 `docs/project/index.md` 代码落点表；表结构与登记纪律见 goodTools-index skill，不在本 skill 重复。

## 3. UI 验收闭环（顺序要求；命令行唯一出处 = goodTools-workflow skill）

改 UI 后按序三重自证，**命令原文（含 SDK 环境变量前缀）以 workflow §1 质检流水线为准**，本 skill 只锁顺序与口径：

1. **架构护栏**：`arch-guard` 秒过（R1~R5 平台隔离 + 写门禁 + 依赖方向 + R6 尺度）——红灯即修结构。
2. **静态与闸门**：`flutter analyze` 0 issue。
3. **视觉验证**：环境无可用模拟器，唯一途径 = 真机侧载（命令与装机纪律查 workflow §2；工具链踩坑查 `context/lessons.md`）。

## 4. 维护与扩展纪律（程序归本 skill，规范正文不自带管理程序）

`ui-design.md` 是**即成规范**（现行规则的终态陈述），自身不承载维护/扩展程序——一切「怎么扩、冲突听谁的」在本节执行，原则 **规范先行**：

| 场景 | 程序 |
|---|---|
| 新增界面 / 组件 | 先归入 `ui-design.md` §3 既有模式；无先例形态**先扩 §1/§4/§5 再实现** |
| 新增状态 / 语义 / 尺寸 / 字号 / 时长 | 先扩对应阶梯并同步主题 token，禁直取任意色值/裸数值 |
| 规范与实现冲突 | 以 `ui-design.md` 为准改实现；确需突破（新形态 / 新档位）先修订规范——禁实现单方面领先规范 |
| 功能清单 | 页面级「有哪些件 / 做什么」不入规范——归各功能设计稿与 `docs/project/index.md` 代码落点表 |

- **零外引**：`ui-design.md` 是终态规范，正文不挂钩任何外部文档；映射关系由本 skill 侧登记。
- **规范移动/改名**：按 docs-spec §5 三处同步（`docs/README.md` + `docs/project/index.md` 文档落点表 + goodTools-docs 域表），并全仓 grep 文件名修引用。
