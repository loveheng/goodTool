---
dev-loop: devlog
format: v1
epic: ui-console
total-merged: 1
last-merge: 2026-10-20
---
- [2026-10-20] [变更]: 打通交付门禁的**既存构建阻塞项**：`android/app/build.gradle.kts` 增 `buildFeatures { aidl = true }`——AGP 9.1 下 AIDL 编译器默认关闭，仓内已提交的 .aidl（IMcpChannel/IMcpCallback）不生成类，致 McpBinderService.kt 8 处 Unresolved（calendar 阶段已记为存量问题）。修后 APK 编译通过——这是**仓内配置缺陷**，非本次改动引入
- [2026-10-20] [验证]: toolbox run build-apk → OK debug 包 154M 全架构（sha256 8b2ff235…）；analyze 0 issue；flutter test 411 全绿
