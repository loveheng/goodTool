---
dev-loop: memory
format: v1
epic: ui-console
total-merged: 0
last-merge: none
---

# ui-console

- [挂载] docs/project/ui-console.md

## 进度

- 2026-10-20 **epic 开启**（承接前序 P0 收口）：底子文档 `docs/project/ui-console.md` 立稿（人前端页面级功能与接缝设计，与 `ui-design.md` 分工：后者为视觉终态规范 SSOT）。三 Tab 骨架确定：仪表盘 / 沙盒 / 设置。
- 2026-10-20 **前序收口**（切域前）：① calendar epic 归并（11 条决策原文归档进 `docs/product/calendar.md` ## 决策日志，7 条通用踩坑进 `context/lessons.md` §calendar，devlog 清零、断点收敛为 1 行）；② 文档漂移回写——`overview.md` 与 `domain_gateway.md`（draft→**active**，26 action 全可用口径）、`index.md`（system_pim「未装配」矛盾行订正 + 新落点补登：`marker_math`/`lunar_math`/`resolve_expression`/`tz_math`、系统日历 MethodChannel、ICS 合并源、8 个新测试文件）+ **架构债 #1 登记**（`InMemoryKv`/`InMemoryMarkerStore` 无持久化）；③ 装配件陈旧注释同步。
- **本 epic 的架构决定**（落 `ui-console.md` §4）：UI 写路径用**用户命令族**（`user_*`）登记在 `CommandGateway` 的**用户侧注册表**——与 AI 侧物理分离，故 AI 不可达、而用户本人不被 `forbiddenKeys` 越权门误伤。这是信任模型（敏感设置仅本人自设）的机制化，不是绕过。
- **SSOT 修正**（原文归档）：`docs/project/ui-console.md` ## 决策日志。
- **通用坑点**（2 条）：`context/lessons.md` §dart —— 空值感知元素修饰的是「值」不是「键」；机械门禁须用**反向探针**验证真的活着（空目录下 grep 必零命中，绿灯是假的）。

## 进度

- 2026-10-20 **epic 开启**（承接前序 P0 收口）：底子文档 `docs/project/ui-console.md` 立稿（人前端页面级功能与接缝设计，与 `ui-design.md` 分工：后者为视觉终态规范 SSOT）。三 Tab 骨架确定：仪表盘 / 沙盒 / 设置。
- 2026-10-20 **前序收口**（切域前）：① calendar epic 归并（11 条决策原文归档进 `docs/product/calendar.md` ## 决策日志，7 条通用踩坑进 `context/lessons.md` §calendar，devlog 清零、断点收敛为 1 行）；② 文档漂移回写——`overview.md` 与 `domain_gateway.md`（draft→**active**，26 action 全可用口径）、`index.md`（system_pim「未装配」矛盾行订正 + 新落点补登）+ **架构债 #1 登记**；③ 装配件陈旧注释同步。
- 2026-10-20 **人前端落地（U1~U4 / U6~U11 / U13 完成）**：
  - **接缝三层落地**：`lib/ui_ports/`（纯 Dart 适配，5 个 port）+ `lib/repository/`（读聚合）+ `lib/ui/`（三页 + 组件 + token）。UI 只吃**类型化视图模型**，全程不消费 MCP 文本信封。
  - **用户写入口（U1）**：`CommandGateway` 增**用户侧注册表**（`registerUser`/`dispatchUser`），与 AI 侧物理分离；`user_*` 三命令 + `SettingsActors` 落 KV。**返回类型化对象**（不返文本信封）——否则 UI 必 `jsonDecode` 触 R2。
  - **内核事件流（U2）**：`McpServer.onCall` 吐 `McpCallEvent`（`ok` 由 `isError` 唯一派生），`McpController` 做稳定代理（server 重建不断流）+ 幂等 `close()`。
  - **凭证零明文（U5 部分）**：`SecretAwareKv` 把凭证键分流到 `SecretStore`（内核端口）、普通键走 SharedPreferences；当前 SecretStore 为**内存实现**（凭证不落盘，重启需重填）——**不降级为明文**。
  - **三页 + 装配（U8~U11）**：仪表盘（服务状态 / 就绪矩阵 / 实时流水）、沙盒（坐标纠偏 + 测距 + 高精计算器双轨出参 + 日历快照）、设置（MCP 服务 + API Key + 脱敏开关 + 身份画像）；`main.dart` 装配链把**日历合并源与工具面共用同一实例**（否则 UI 与 Agent 各拉一次、频控与缓存分裂）。
  - **门禁首次真生效**：R1/R2/R3/R5 的机械扫描此前因 `lib/ui` 不存在而无对象；已用**反向探针**验证——注入 `jsonDecode`/`Platform.isAndroid` 的临时文件，arch-guard 逐条报出行号拦截，删除后复跑全绿。
  - **交付门禁打通**：`android/app/build.gradle.kts` 补 `buildFeatures { aidl = true }`——AGP 9.1 下 AIDL 编译器默认关闭，仓内已提交的 `.aidl`（IMcpChannel/IMcpCallback）不生成类，致 `McpBinderService.kt` 8 处 Unresolved（**仓内既存配置缺陷**，calendar 阶段已记为阻塞项，非本次引入）。修后 `toolbox run build-apk` 通过：debug 包 154M 全架构。
  - **Binder 通道接持久化 KV**：`LazySharedPrefsKv`（同步装配、首次访问才 await SharedPreferences）→ 生产通道与 UI 主 isolate 共享同一份设置（进程级存储）；**凭证例外**（内存 SecretStore 跨不了 isolate）→ 登记架构债 #1。
  - **token 由子任务交付**：色彩/排印/几何/动效四组，深浅**语义名一致**；`danger` 按 §6 对比度红线校准（暗 Rose 400 / 浅 Rose 700），已**回写 `ui-design.md` §1**。

## 断点
- [断点] 下一步：**U5 收尾：Android Keystore 实现 `SecretStore`**——现为内存实现，故①重启凭证失位 ②**跨 isolate 不可见**（UI 写入的 Key 对 Binder 生产通道的 Agent 不可见，Agent 侧 geo/weather 仍 fail-closed 返 `ERR_*_KEY_MISSING`）；接口就位、接入不改装配面（`index.md` 架构债 #1 保持活跃）。随后 **U12b 运行时日历权限申请 UI 入口**（需 Android 运行时权限请求，走平台通道）+ **U12a 收尾：脱敏开关态接到 `maskPii` 行为**（内核目前是固定默认档，开关只落 KV 未生效）。另：`McpServer._builtinInstructions` 的「拾光排程师」文案残留仍待产品定位拍板（`domain_gateway` 域待办）。
