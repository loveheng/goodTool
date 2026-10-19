# goodTools · 会话初始化与架构红线

Flutter（3.47.5 stable）写的 Android 常驻壳：前台服务保活 + 内嵌 MCP 服务端内核，自带 R2 自更新通道。pubspec `name: good_template`，Android `applicationId = com.goodhub.good_template`。

## 会话初始化（新窗口开场执行一次）
- 开场含「继续/开工/初始化」或首次指令时：先跑 `toolbox run-hooks bootstrap --quiet`（非 0 仅附一行 ⚠，不阻塞；无 toolbox 跳过）→ 跑 `toolbox run panel`（无 toolbox 则读 context/CURRENT → 绑定 epic 的 memory.md 断点）→ 输出会话绑定卡（域/类型/挂载/任务全景/状态）→ 按断点开工或等指令；多任务切换 `::board`（绑定纪律与恢复规约：~/.agents/skills/dev-loop/SKILL.md §3，存在时以其为准）。
- CURRENT 缺失/none → 列 context/epics/ 候选请用户选，严禁自选开工；无 context/ → 提示走 dev-init 接入；命令速查 ~/.agents/COMMANDS.md。
- 工作流命令（构建/测试/环境）唯一出处见 `.agents/skills/goodTools-workflow/SKILL.md`；功能落点见 `docs/project/index.md`；文档规范见全局 `docs-spec` skill。

## 架构红线（arch-guard 口径，改动 lib/ 后门禁）
> 无头系统：删掉整个 Flutter UI，MCP 命令面应能完整运行——故 UI 不得绕过命令层、mcp/action 层不得反向依赖 UI。白名单是**历史例外**，只许减少不许增加。机械校验见 `toolbox run arch-guard`（脚本 `scripts/agent-tools/arch-guard.sh`）。

1. **R1 UI 禁直连 repo 写**：写路径必须组装命令交 CommandHandler（唯一写入口）。
2. **R2 UI 禁内联 JSON 编解码**：委托数据/命令层（导出预览口径豁免 `lib/ui/settings_page.dart`）。
3. **R3 UI 禁平台分支**：`Platform.isX` 收敛到接口实现/工厂。
4. **R4 mcp/action 禁 import Flutter UI**（material/widgets）：无头系统硬约束，删 UI 全链路须可跑。
5. **R5 UI 禁直连 Db.instance**：数据访问一律走 Repository。
6. **R6 禁弃用 textScaleFactor**：M3 尺度走 `textTheme` + `textScaler`。
7. **R7 tools 层禁绕过网关写门禁**：`lib/tools/**` 禁 `.dispatch(` / `.admits(`，写路径唯一通道 = `CategoryTool` 网关层（子操作只 `buildCommand`）；`Command` 类型依赖仍合法。

> 本工程为无头 MCP 壳，已确认引入 `lib/ui` 用户层。arch-guard 已内置 R1~R5 扫描模式，随 `lib/ui` 建层即生效；R4（mcp/action 禁 import UI）+ R6（全 lib 禁 textScaleFactor）+ R7（tools 禁绕过网关写门禁，随 S7 启用）现已生效。白名单是历史例外，只许减少不许增加。
>
> 装配纪律：工具面由 `lib/tool_face_assembly.dart` 单点收口，HTTP 调试通道（`main.dart`）与 Binder 生产通道（`mcp_binder_entrypoint.dart`）**共用同一份装配**——新增能力只改装配工厂，禁两通道各自装配。

## 编码前必读
- 改前先查 `docs/project/index.md`（功能落点）与 `context/` 记忆；高风险模块改前检索 `context/lessons.md`。
- 提交前：裸跑 `flutter analyze`（0 issue 为交付线）与 `flutter test`；或统一走 `toolbox run build-apk`（含版本守卫 + analyze 门槛 + 产物校验）。
- 严禁在 AI 写码时静默降级（空 catch / 吞异常 / 兜底默认值）——存疑实现标 `// UNCERTAIN:`，有意降级标 `// DEGRADE:` 并打 `[DEGRADE]` 日志，首跑基线后逐条登记白名单。
