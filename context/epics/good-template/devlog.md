---
dev-loop: devlog
format: v1
epic: good-template
total-merged: 0
last-merge: none
---

（开发过程日志按行追加：[变更]/[验证]/[note]/[SSOT 修正]；≥5 条自动归并进 memory.md——dev-loop §2）
- [2026-10-24] [变更]: goodTemplate 受控快照落地：① sync-kernel.sh 入池（SYNC 31 件逐字/STRUCT 6 件结构对齐/IGNORE 域件豁免 + 源仓对账告警 + analyze/test 收尾验收）并实跑换血——内核补缺（category_tool_face 契约/secret_store/pii_mask/in_memory_secret_store/mcp_server 事件流/command_gateway 用户侧注册表/arch-guard R6R7/android 根 gradle mavenLocal+dist 通路）；② Android SDK 化——minSdk 34 + goodhub-mcp-plugin-core 0.2.0、McpBinderService 换 GoodHubPluginService 基类版（删自拷 AIDL）、SecretStoreChannel+MainActivity 双引擎注册、init-app 契约护门改查 SDK 坐标+签名权限（AIDL 已不存在）；③ 装配样板单点收口（tool_face_assembly 双通道共用）+ 修模板 main 缺 binder entrypoint 编译根 import（kernel_blob 不含库→真机 Dart entrypoint 超时）；④ sample 去反模式——删旧 weather_provider（forecast3→Map? 静默 null 已判反模式），新 sample_provider 不可空信封 + CategoryTool 模式示例域（R 端口信封/W 档 buildCommand→网关派发→G6 isError 派生）；⑤ smoke_test 扩至 7 例（凭证分流/装配 schema/private 可见性/前缀注入）
- [2026-10-24] [验证]: 模板仓 analyze 0 issue + test 7 全绿 + arch-guard 7 条全过 + sync-kernel 终态实跑 rc=0 + init-app/self-test 双金丝雀过；起底演练 app（demo_probe）改名零残留、test 7 绿、assembleDebug 81s 成功（SDK 经 sibling dist 真实解析），跑完即删；goodTools 侧零代码改动
- [2026-10-24] [变更]: UI 设计基座切分并迁入 goodTemplate（第一步/档 A）：① goodTools 侧切分——app_components.dart 修正上轮误判（实有 ui_ports 域耦合）：StatusDot+_TrianglePainter+ReadinessPill 挪新件 readiness_components.dart（域感知件，ReadinessState/ReadinessItem 来自 status_port），删 CalcResultCard（CalcView 域件且全仓零消费=死代码），纯基座剩五件（tokensOf/SectionCard/TelemetryText/EmptyState/ErrorLine/GuidanceCard）零域 import，settings_page/dashboard_page 消费方 import 更新，测试零引用无写保护障碍；② 模板侧——sync-kernel 清单扩 5 件（theme/tokens×2/app_components/block_canvas）实跑落库，main 接 buildAppTheme（暗色优先示范设计语言），新增 ui_smoke_test 5 例（双亮度主题/AppTokens 主题扩展可达/四组件渲染/GuidanceCard 回调/BlockCanvas 受控输入——自带滚动视口宿主不包 SingleChildScrollView）
- [2026-10-24] [验证]: goodTools：analyze 0 issue + test 611 全绿（切分零行为变化）；模板：analyze 0 + test 12 全绿（内核 7 + UI 基座 5）+ arch-guard 7 条全过（UI 层落库后 R1/R2/R5/R6 扫描实际生效）
- [2026-10-24] [SSOT 修正]: 旧 UI 设计基座五件（含主题骨架 theme/app_theme_data + main 接线）随模板起底 ➔ 新 **功能组件闭包三件**入模板（app_tokens / app_components / block_canvas），主题骨架不入——用户拍板：模板不约束新 app 页面设计；组件视觉值经 AppTokens 主题扩展归宿主注册（宿主可自定义实例换观感）
- [2026-10-24] [变更]: 模板组件基座按新口径重落：sync-kernel 清单收三件组件闭包（theme/app_theme_data 出清单），main 保持无主题接线，ui_smoke_test 4 例改「宿主 inline 注册 AppTokens」最小示范（组件零主题依赖）；goodTools 侧切分维持（app_components 纯基座零域耦合 + readiness_components 域件 + 删死代码 CalcResultCard——被中断的回滚已对齐回切分态）
- [2026-10-24] [验证]: 模板 analyze 0 + test 11 全绿（内核 7 + 组件 4）+ arch-guard 7 条全过；goodTools analyze 0 + test 611 全绿
- [2026-10-24] [变更]: 元组件口径落定并扩容组件闭包：用户拍板「只要元组件，拼装成品不收」——mcp_service_page（页面）/ calendar_grid（月视图成品）/ home_shell（布局骨架）不迁；新增迁移 bracket_pair_formatter（纯逻辑 formatter，applyBracketPair 可 headless 测）+ readiness 双件（StatusDot/ReadinessPill 元组件 + ReadinessState/ReadinessItem 元类型上移中性件 lib/ui_ports/readiness.dart——纯 Dart 无 Flutter，status_port 经 import+export 保持原路径兼容，readiness_components 改直引 readiness.dart 以便模板闭包自洽）。模板 ui_smoke_test 增 2 例（formatter 三件套补全/跳过/配对删除 + ReadinessPill 双通道渲染）
- [2026-10-24] [验证]: goodTools analyze 0 + test 611 全绿；模板 analyze 0 + test 13 全绿（内核 7 + 元组件 6）+ arch-guard 7 条全过；sync-kernel 对账干净（6 件组件闭包全在清单）
- [2026-10-24] [变更]: mcp_service_page 迁入模板（内核配套页归类）：用户拍板「MCP 服务本身是内部调试设施，每个 app 都有」——该页只吃 McpController + 元组件（tokensOf/SectionCard/TelemetryText），宿主注入 controller，不携带视觉范式，从「拼装成品不迁」清单移入「内核配套页随内核走」类；模板 ui_smoke_test 增 1 例（调试页渲染：不随启动自启/端口/endpoint 双现/重生成令牌——宿主注入 InMemoryKv controller，不真启 HTTP）
- [2026-10-24] [验证]: 模板 analyze 0 + test 14 全绿（内核 7 + 元组件/配套页 7）+ arch-guard 7 条全过；goodTools 本轮零改动（页面源文件未动）
