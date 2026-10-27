---
dev-loop: memory
format: v1
epic: ui-console
total-merged: 2
last-merge: 2026-10-27
---

# ui-console

- [挂载] docs/project/ui-console.md

## 进度

- 2026-10-20 **epic 开启**（承接前序 P0 收口）：底子文档 `docs/project/ui-console.md` 立稿（人前端页面级功能与接缝设计，与 `ui-design.md` 分工：后者为视觉终态规范 SSOT）。三 Tab 骨架：仪表盘 / 能力 / 设置。
- 2026-10-20 **前序收口**：calendar epic 归并（决策进 `docs/product/calendar.md`、通用坑进 `context/lessons.md` §calendar）；文档漂移回写（overview / domain_gateway draft→active、index.md 补登 + 架构债 #1 登记，债已随 U5 结项）。
- **架构决定**（Ref: `docs/project/ui-console.md` §4 与 ## 决策日志）：UI 写路径用**用户命令族**（`user_*`）登记 `CommandGateway` **用户侧注册表**——与 AI 侧物理分离（AI 不可达、用户本人不被 forbiddenKeys 误伤），是信任模型的机制化而非绕过。
- 2026-10-20 **人前端落地（U1~U4 / U6~U13 完成）**：接缝三层 `lib/ui_ports/`（纯 Dart port）+ `lib/repository/`（读聚合）+ `lib/ui/`（页面+组件+token），UI 只吃**类型化视图模型**、全程不消费 MCP 文本信封。U1 用户写入口返回类型化对象（否则 UI 必 jsonDecode 触 R2）；U2 内核事件流（`McpCallEvent` + `McpController` 稳定代理）；U5 凭证零明文 AndroidKeyStore（`SecretStoreChannel.kt` AES-256-GCM，不设用户认证——威胁模型=设备物理沦陷超壳边界）；U8~U11 三页装配（日历合并源与工具面**共用同一实例**防频控/缓存分裂）；U12a 脱敏接线（`piiMaskEnabledBy` 保护性缺装）+ U12b 权限入口（`settings_opened` 不弹假授权）；页面结构演进 = 能力 hub + 四域子页面（决策 Ref: ui-console.md 决策日志 [页面结构]）。
- 2026-10-20~21 **Binder/交付链收束**（决策 Ref: 决策日志 [Binder接入] / [产品决策] / [交接]）：goodhub-mcp-sdk 拆仓接入（McpBinderService 继承 GoodHubPluginService、minSdk 34）；MCP HTTP 改手动开启（隐藏服务页）；UI 修复组（SectionCard Material 祖先 / 二级页 push 红屏 / AIDL buildFeatures / Binder entrypoint kernel 闭包）。
- 2026-10-26 **首页快捷/首页内嵌**（决策 Ref: 决策日志 [仪表盘现态] / [首页快捷] / [首页内嵌二级页]）：新用户侧命令 `user_set_home_pinned_domain` + 设置键 `home_pinned_domain`；仪表盘**直接内嵌**钉住域子页为首页本体（无快捷卡中间层），hub 与仪表盘共享同一子页实例（main.dart 单点装配）。
- 2026-10-26~27 **日历手势全链改造 → 无限自由滚动定稿**（决策 Ref: 决策日志 [日历信息层] / [日历外壳] / [日历外壳·年视图撤除] / [日历外壳·自由滚动定稿] / [自由滚动打磨]）：纵滑连续滚动流（动态视窗 + 临界阻尼弹簧 + rubber-band + 落位 haptic）、年视图撤除、告警行恒占位 + 密度版本侦测（落定跳变修复，跳变在数据路径非动画层）、单条固定 WeekdayHeader、标题实时推导 + 方向感知克制过渡、日格 1 号月份标注；性能组：页面实例缓存、单页 RepaintBoundary、±2 预挂载、`_loadOverview` 增量加载 + 按槽位精准失效；中间态双因修复（Stack Clip.none + GD HitTestBehavior.opaque）。
- 2026-10-26 **发布链**：v0.1.2(36) 发布 R2 → shared_preferences_android R8/JNI 雷（flutter/flutter#194649，≥2.5.2 自带修复）升 2.5.3 → v0.1.3(37) 覆盖坏包（教训见 lessons.md §构建）。
- 2026-10-27 **WIP 修复**：`scrollCacheExtent` 类型收敛（Flutter 3.47 起 `ScrollCacheExtent` 类，double 不再合法）；中间态回归 finder 口径修正（**skipOffstage:false 才能扫到预挂载缓存页**，教训见 lessons.md §ui）；test 基线 629。
- 2026-10-27 **真机手感过关 + 年视图恢复**（SSOT 修正 Ref: ui-console.md 决策日志 2026-10-27 [SSOT 修正]）：自由滚动手感真机过关；年条带以月条带同构无限滚动条回归（纵滑跨年惯性 + ±2 预挂载），入口双通道 = 双指捏合（Listener 原始指针检测，不进手势竞技场）+ 点标题；点迷你月落月；**Stack+Offstage 双条带常驻**（AnimatedSwitcher 重挂载子树会丢条带位置 + glide 撞未挂载 controller）；**年条带独立 _yearPageHeight**（年/月视口高不同，共用页高致两页同屏）；test 基线 **632**。

## 断点
- [断点] 下一步：v0.1.4(38) 已发版（commit ef90ac5 → release-r2 上传 R2，清单 app-38.apk 线上已校验 200；旧 app-37.apk 已清理）；FAB 全屏三层修复已落地（unbounded 控制器 + LayoutBuilder 极端挤压让位 + FittedBox 兜底 + 48px 呼吸条），analyze/test 635/arch-guard 全过；**U15 真机 e2e 仍挂**——待真机装包复验全屏交互、四域子页面、权限/天气引导、Keystore 凭证持久化与 Binder 通道
- **U15 真机侧载核对**（ui-console.md §6 视觉验收项 + Binder e2e）：环境无模拟器，需用户装包走查四域子页面 / 权限引导 / 天气引导 / Keystore 凭证持久化（重启不丢 + Binder 通道可见）+ 宿主 Binder 联调（GLM 系待 goodhub 注入 tool_stream 后复验，step-3.7-flash 可先验）。
- 「拾光排程师」文案残留：待产品定位拍板（`domain_gateway` 域待办，不属本 epic）。
- `thirdconnect.md` 契约文档在 goodTools 仓内仍缺失（仅被引用），待补回或登记避免信息丢失。
