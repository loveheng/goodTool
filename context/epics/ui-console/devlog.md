---
dev-loop: devlog
format: v1
epic: ui-console
total-merged: 1
last-merge: 2026-10-20
---
- [2026-10-20] [变更]: 打通交付门禁的**既存构建阻塞项**：`android/app/build.gradle.kts` 增 `buildFeatures { aidl = true }`——AGP 9.1 下 AIDL 编译器默认关闭，仓内已提交的 .aidl（IMcpChannel/IMcpCallback）不生成类，致 McpBinderService.kt 8 处 Unresolved（calendar 阶段已记为存量问题）。修后 APK 编译通过——这是**仓内配置缺陷**，非本次改动引入
- [2026-10-20] [验证]: toolbox run build-apk → OK debug 包 154M 全架构（sha256 8b2ff235…）；analyze 0 issue；flutter test 411 全绿
- [2026-10-20] [变更]: 插件接入 SDK 拆仓接入：删除自拷 AIDL（android/app/src/main/aidl/，契约唯一物理副本改在 goodhub-mcp-sdk 仓 :contract）；McpBinderService 由自写 IMcpChannel.Stub 改为继承 GoodHubPluginService + 重写 handleJsonRpc 接管路由（业务层在 Dart，SDK 反射派发器不适用）+ onHostCallback 迁 registerCallback + 终帧推送改走 SDK tryEmitEvent（保住 [DEGRADE] 可观测性）；F1（tools/call 全量 _async + onEvent 终帧切片）行为逐字保留；SystemCalendarChannel/SecretStoreChannel 双引擎注册保留；minSdk 由 flutter.minSdkVersion(24) 提到 34（SDK 两模块 minSdk=34，低于则 manifest merger 失败）；buildFeatures{aidl=true} 移除
- [2026-10-20] [验证]: android :app:compileDebugKotlin BUILD SUCCESSFUL + flutter build apk --debug BUILD SUCCESSFUL + flutter analyze No issues found + toolbox run arch-guard 7 条全通过 + merged manifest minSdkVersion=34（3 处）+ 依赖解析实测 goodhub-mcp-plugin-core:0.1.1 → 传递 goodhub-mcp-contract:0.1.1；未执行: 真机 e2e（需 goodhub 与 goodTools 同机安装 + 靶子联调）
