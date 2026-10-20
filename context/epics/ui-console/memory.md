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
- 2026-10-20 **U5 收尾落地**（清架构债 #1）：`SecretStoreChannel.kt`（AndroidKeyStore 持 AES-256-GCM 密钥、密文 Base64(IV‖密文) 落专用 SharedPreferences `goodtools_secrets`、双引擎注册、后台线程、fail-closed 转 `KEYSTORE_ERROR`）+ `KeystoreSecretStore`（Dart MethodChannel 封装，通道可注入，`SecretStoreException` 透出不吞 null）+ 装配注入 main.dart / mcp_binder_entrypoint.dart（构造形状不变，装配面未改）。**决策**：不设用户认证（常驻壳 Agent 须无解锁读凭证，威胁模型=设备物理沦陷超壳边界）；否掉 EncryptedSharedPreferences（deprecated + MasterKey 不透明不利审计）。验证：arch-guard 7/7 + analyze 0 issue + test 415 全绿（新增 4 例 headless mock）+ `compileDebugKotlin` 过。`InMemorySecretStore` 退位为单测替身；`index.md` 债 #1 结项归档，落点表补登 Kotlin 通道与新测试。
- 2026-10-20 **U12a/U12b + 域子页面拆分（用户拍板）落地**：
  - **U12b 权限入口**：`SystemCalendarChannel` 增 `requestCalendarPermission`（未授权 → `ACTION_APPLICATION_DETAILS_SETTINGS` 跳转，回 `settings_opened`，不弹假授权——后台 Binder 引擎无 Activity 可挂 requestPermissions，且授权后下次查询即生效）+ `lib/service/calendar_permission_port.dart`（端口 + MethodChannel 实现，fail-closed 转机器码）+ `CalendarPort.requestPermission`（类型化视图）；UI 落点 = 日历子页面警告卡「去授权」。**踩坑记账**：端口 switch 初版把平台回传 `settings_opened` 误写成 `settingsOpened`（驼峰）——mock 测试首跑即抓出（parseFailed），印证「mock 断言须覆盖平台字面量」。
  - **U12a 脱敏接线**：`piiMaskEnabledBy`（`'0'`=关、未设置=开——**保护性缺装**，对齐 E 拍板，未设置行为与接线前一致无回归）；ICS 路每次查询现读（改开关即时生效），系统路经 `CompositeCalendarProvider.maskPiiEnabled` 闭包注入（合并编排不持 KV，tool_face_assembly 与 main.dart 同口径注入防双通道漂移）；设置快照 maskPii 默认态改真（与内核同源）；设置页文案订正（原写「标题」也脱敏——实际只脱敏 location/description）。
  - **页面结构演进**（设计稿先行：ui-console.md §1 调和 + §3 重写 + ui-design.md §3.3 同步 + 决策日志）：三 Tab 改「仪表盘/能力/设置」，沙盒单页退役拆为 hub + 四域子页面（calculator/geo/calendar/weather，push 进入）；hub 不就绪探测（双源避免）；子页面**无写入口**（配置写只经设置页）；新增 `lib/ui_ports/weather_port.dart`（和风 provider → 类型化视图，与工具面**共用同一 QWeatherProvider 实例**，频控/缓存不分裂）；`ShellNav` InheritedWidget 供子页面回跳设置 Tab（天气缺 Key / 日历脱敏说明引导）。**踩坑记账**：capabilities_page 列表字面量误以 `};` 收尾（应为 `];`）——analyze 报错行号指向末元素而非字面量开头，靠最小复现定位。
  - 验证：arch-guard 7/7 + analyze 0 issue + test 437 全绿（新增 3 个测试文件：calendar_privacy_permission / calendar_permission_port / weather_port）+ `compileDebugKotlin` 过；`index.md` 落点表/文档落点同步，coding-standards §1 分层矩阵「沙盒」字样订正。

## 断点
- [断点] ~~U5 收尾~~ ~~U12a~~ ~~U12b~~ ~~域子页面拆分~~ **均已结项**（2026-10-20，见上方进度）。ui-console 计划内功能全部交付，剩余：① **真机侧载核对**（ui-console.md §6 视觉验收项——环境无模拟器，唯一途径，需用户配合装包走查）；② 「拾光排程师」文案残留待产品定位拍板（`domain_gateway` 域待办，不属本 epic）；③ goodhub 宿主侧私有注册问题：**已查因**——goodTools 插件端 `McpBinderService` 标 `android:permission="com.zzh.goodhub.permission.MCP_SERVER"` 却**从未声明 `<permission>`**，且宿主 `goodhub-restored` Manifest 既**未声明该权限**也**无 `<queries>` 查 `com.zzh.goodhub.action.MCP_SERVER`**（API30+ 包可见性缺失 → `queryIntentServices` 必空）。**已修**：两仓 Manifest 各补 `<permission protectionLevel="signature">` + 宿主补 `<queries>` 该 action。
  - **仍缺（更大缺口，跨工程）**：宿主 `goodhub-restored` 的 **AIDL 客户端 + 本地 Binder 发现/绑定传输层（`bindService`/`queryIntentServices`/`IMcpChannel`/`DeathRecipient`/meta-data 读取）完全不存在**——`LlmBridge.kt` 与 Dart 侧均无，且缺 `*.aidl` 文件；`thirdconnect.md` 契约文档在 goodTools 仓内也缺失（仅被引用）。即"私有注册"的**功能性**一半（宿主发现并 bind 插件）尚未实现。
  - **待澄清**：`goodhub-recovery-20261011/goodhub-restored` 是否即线上宿主、可否在其内实现该 BinderTransport（AIDL 客户端 + 发现/绑定 + Dart 调用面）；若否，需指明线上 goodhub 落点。该缺口不属本 epic 的代码范围，须跨工程授权。
