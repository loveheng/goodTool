---
status: active
updated: 2026-10-24
---

# goodTemplate · 模板抽取与同步

> goodTools 与 goodhub 生态新 app 起底关系的 SSOT：**goodTemplate = 受控快照脚手架，goodTools = 内核唯一事实源**。共享包依赖形态已评估不采用（决策过程见 context 决策档案）。

## 1. 定位与两仓分工

| 仓 | 角色 | 演化方向 |
|---|---|---|
| `goodTools`（本仓） | 内核 SSOT + 样板实现（MCP 内核、命令层、服务层在此真实演化） | 内核改动先落本仓 |
| `goodTemplate`（`~/app/goodTemplate`） | 起底脚手架：Android 常驻壳 + 内嵌 MCP 内核最小骨架 + init-app 一键改名 | 经同步协议单向跟版本仓 |

新 app 起底 = 复制 goodTemplate → `init-app` 改名 → 换真实存储/工具面 → goodhub 实机 bind 联调。

## 2. 抽取边界（原则；文件级清单唯一物理副本 = sync-kernel.sh）

- **入模板**：MCP 内核（jsonrpc / mcp_server / tool_face / category_tool_face / settings_kv / secret_store / pii_mask）、命令网关、双通道服务件（前台保活 / HTTP 传输 / mcp_controller / persistent_kv / 凭证双实现）、R2 自更新四件、装配样板、Android 桥接（SDK 化 Binder 服务 + SecretStoreChannel + 双引擎注册）、toolbox 脚本面、mcp-bridge 调试件、**元组件闭包**（app_tokens / app_components 纯件 / block_canvas 底座 / bracket_pair_formatter / readiness 元类型 + 组件壳——**元组件口径：只收不可再分的积木，能用积木拼装的成品不收**；组件视觉值经 AppTokens 主题扩展由**宿主注册**，宿主可自定义 token 实例换观感）、**内核配套页**（mcp_service_page——MCP HTTP 调试服务的控制页，属调试设施本身：只吃 McpController + 元组件，宿主注入 controller）。
- **不入模板**（各 app 自长）：`settings_keys` 业务键收口、域工具面（math / geo / weather / pim）、**主题骨架（theme / app_theme_data / main 主题接线——不约束新 app 页面设计）**、**业务拼装成品**（calendar_grid 月视图 / home_shell 布局壳 / 域页面等）、`ui_ports` 适配层与域 UI、域依赖（timezone / lunar / flutter_map 等）、`context/` 记忆体系（per-project，走 dev-init 接入）。
- **同步分两档**：内核件逐字同步；装配样板 / main / binder 入口属结构对齐件（架构级变化人工对齐，不进机械清单）。

## 3. 同步协议（防漂移）

1. goodTemplate 仓根跑 `toolbox run sync-kernel --from ../goodTools`：`--dry-run` 出 diff 预览 → 执行同步 → 自动 `flutter analyze` + `flutter test` 验收。
2. 严格单向：goodTools → goodTemplate，goodTools 侧全程零改动。
3. 清单维护纪律：goodTools 内核新增/删除公共件时**同轮**改 sync-kernel.sh 清单（脚本对「源仓有、清单无」做对账告警）。

## 4. 起底流程（init-app）

- `bash scripts/agent-tools/init-app.sh --name <snake> --org <com.yourco> [--title ...] [--with-agents]`：机械替换全部散落点（pubspec / gradle / Kotlin 包路径 / 通道名 / manifest meta / dart 导入前缀）。首跑用 bash 直调（新仓无 .git，`toolbox run` 解析不到项目池；init-app 收尾自建 git 首提交）。
- **契约护门**：AIDL 包名 `com.zzh.goodhub.mcp` 与签名权限 `com.zzh.goodhub.permission.MCP_SERVER` 不可变。SDK 化后契约物理副本在 goodhub-mcp-sdk 仓，护门查 gradle 依赖坐标与 manifest 权限声明（不再查仓内 AIDL 文件）。
- 起底后三步：换掉 InMemoryKv（持久化 + 凭证分流）→ 写真实工具面（参照装配样板单点收口）→ goodhub 实机 bind 联调（同签名出包）。

## 5. 构建通路（Android SDK 依赖）

- 模板与派生 app 消费 `com.zzh.goodhub.mcp:goodhub-mcp-plugin-core`（契约经 `goodhub-mcp-contract` 传递），`minSdk` 基线 **34**。
- 解析通路 = `mavenLocal()` + 离线分发件目录；**SDK 升版后须先在 goodhub-mcp-sdk 仓跑 `scripts/dist.sh`**，否则依赖解析直接 FAILED。

## 6. 红线随模板走

- `arch-guard.sh` 随清单同步（R1–R7 全集）；模板无 UI 层，R1/R2/R5 天然满足。
- 装配纪律与 goodTools 同构：工具面单点收口 `tool_face_assembly.dart`，HTTP 调试通道与 Binder 生产通道**共用同一份装配**。
