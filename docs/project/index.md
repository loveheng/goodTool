---
status: active
updated: 2026-10-20
---

# goodTools · 功能 → 代码落点索引

> 域级锚点表，禁止一次性铺满：随实现长出来。落点精确到仓库相对路径；改前先查本表，跨域改动先登记再动手。机制与登记纪律见项目索引 skill（`.agents/skills/goodTools-index/SKILL.md`）。

## 1. 代码落点

| 域 | 功能 | 代码落点 | 备注（定位必读） |
|----|------|----------|------------------|
| 启动/入口 | App 入口与 MCP 绑定启动 | `lib/main.dart`、`lib/mcp_binder_entrypoint.dart`、`lib/ports.dart` | 端口/绑定参数集中在 `lib/ports.dart` |
| MCP 内核 | JSON-RPC 传输、MCP server、工具面接口、KV 持久化、示例工具、领域网关契约 | `lib/mcp/jsonrpc.dart`、`lib/mcp/mcp_server.dart`、`lib/mcp/tool_face.dart`、`lib/mcp/settings_kv.dart`、`lib/mcp/weather_provider.dart`、`lib/mcp/category_tool_face.dart` | `mcp_server.dart` 是核心；`tool_face.dart` 定义工具注册接口（`call` 返回完整 result `{content,isError}`，内核只透传）；`category_tool_face.dart` = 领域网关契约层（工程规范 §3.3 G1–G5，**不进 barrel 导出**） |
| 命令层（唯一写入口） | CommandGateway 分发，写必走 CommandHandler | `lib/action/command_gateway.dart` | 工程规范 §2：R1 前瞻——UI 引入后写路径须组装命令交 CommandHandler |
| 服务层 | Android 前台服务保活、HTTP 传输、MCP 控制 | `lib/service/foreground_task_init.dart`、`lib/service/http_transport.dart`、`lib/service/mcp_controller.dart` | 无头系统：删 UI 后此层须能独立跑通 |
| 工具面扩展 | 工具面样例（新工具照此注册）/ 领域网关 | `lib/tools/sample_tool_face.dart` | 新 MCP 工具以此为实现模板；领域网关模式见 `domain_gateway.md` |
| 自更新 | 安装器、远程配置热更、更新清单、更新服务 | `lib/update/installer.dart`、`lib/update/remote_config_store.dart`、`lib/update/update_manifest.dart`、`lib/update/update_service.dart` | 发布链路见 workflow skill 的 `release-r2` |
| 地理/地图内核 | 坐标纠偏（WGS-84↔GCJ-02↔BD-09）、Haversine 测距 | `lib/geo/coord_convert.dart` | 纯 Dart 无头，arch-guard R4；WGS-84→GCJ-02 自动归一 |
| 地理/地图内核 | 高德静态图 URL 构建器（免 Native 3D SDK 轻量渲染） | `lib/geo/static_map_url.dart` | 入参可声明任意坐标系，内部归一化到 GCJ-02；集成 sig 签名 / RDP 抽稀 / Auto-bounding 视口自适应 |
| 地理/地图内核 | 高德数字签名（Sig/MD5） | `lib/geo/amap_sign.dart` | 参数升序拼接 + secret → MD5，防 INVALID_USER_SCODE |
| 地理/地图内核 | 轨迹抽稀（RDP） | `lib/geo/rdp.dart` | 道格拉斯-普克，折线硬性≤80 点，防 URL 超 2048 触发 414 |
| 地理/地图内核 | 高德 HTTP / 位置传感器端口（依赖反转接缝） | `lib/mcp/geo_provider.dart` | 对齐 `weather_provider.dart`；未注入源抛 `ERR_AMAP_KEY_MISSING`（工程规范 §1.2） |
| 测试 | 纯 Dart 内核全链路测试（无设备可跑） | `test/smoke_test.dart`、`test/geo_test.dart`、`test/category_gateway_test.dart` | 覆盖 InMemoryKv / CommandGateway / McpServer / 坐标互转闭环 / 静态图 URL / 八方位 / 网关派发契约（枚举外拦截、写门禁拦截、错误前缀注入、isError 唯一派生） |

## 2. 文档落点

| 主题 | 文档路径 | 状态 |
|------|----------|------|
| 工程规范 SSOT（架构红线 / 分层 / 工具面契约） | `docs/project/coding-standards.md` | active |
| 领域网关工具设计（分类嵌入模式） | `docs/project/domain_gateway.md` | draft（矩阵已按 4 份 product 文档 26 个原子动作 1:1 对账，待落地 `lib/`） |
| 产品概述（能力/架构/信任模型） | `docs/product/overview.md` | active |
| 日历能力 | `docs/product/calendar.md` | active |
| 计算器能力 | `docs/product/calculator.md` | active |
| 地理能力 | `docs/product/geo.md` | active |
| 天气能力 | `docs/product/weather.md` | active |
| UI 开发规范（用户层） | `docs/project/ui-design.md` | active |

> 三处同步纪律：本表 + `docs/README.md` + goodTools-docs 域表（goodTools-docs 维护协议）。

## 3. 架构债与依赖违例登记

> 活跃表只留未结项；清零时结项归档（压缩为「#N 摘要 → 落点 → 结项日期」，细节归 Git log / epic devlog）。散修须先登记再动手（goodTools-index §3）。

| # | 债 | 落点 | 状态 |
|---|----|------|------|
| （空） | 暂无登记项 | — | — |

<!-- 归档区（结项后移入，压缩为一行）：
- #N 摘要 → 落点 → 结项日期
-->

## 4. 工程基线数据

> standards 各条款引用的项目基线数据；变化时同轮更新。

### 4.1 直连白名单基线（arch-guard，只减不增）

当前 `scripts/agent-tools/arch-guard.sh` 白名单（历史例外）：

| 规则 | 白名单条目 | 原因 |
|------|-----------|------|
| R2（UI 内联 JSON） | `lib/ui/settings_page.dart` | 导出预览口径豁免（前瞻：暂无效） |

> R1/R3/R5 白名单为空（无 lib/ui）；R4/R6 无白名单。新增任何白名单边须显式注明原因，且只减不增。

### 4.2 超标清单（只减不增）

| 文件 | 治理策略 |
|------|----------|
| （空） | 软红线 800 行；超标即登记，降到阈值下即移出 |
