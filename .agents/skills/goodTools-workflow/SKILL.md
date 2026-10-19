---
name: goodTools-workflow
description: goodTools 工作流事实源：构建/测试/运行命令唯一出处、环境硬约束（flutter 在 ~/flutter/bin 不在默认 PATH）、规范数据维护触发器。构建报错、跑测试、换机器前先读，命令勿凭记忆写；工具链踩坑查 context/lessons.md，接缝速查与落点索引查 docs/project/index.md（goodTools-index skill）。
---

# goodTools · 工作流事实源

> 项目一句话：**goodTools**——Flutter（3.47.5 stable）写的 Android 常驻壳：**前台服务保活 + 内嵌 MCP 服务端内核**，对外暴露 MCP 工具面，并自带 R2 自更新通道。无头系统：删掉整个 Flutter UI，MCP 命令面应能完整运行。

## 定位边界（三件套分工，防双源）

| 需要什么 | 查哪里 |
|---|---|
| **写码规则**：分层依赖方向 / 架构红线（arch-guard R1~R6）/ 新功能落点决策 / 质量门禁 | `docs/project/coding-standards.md`（工程规范 SSOT） |
| **改前定位**：某功能的代码落点 / 文档落点 / 架构债与违例登记 | `docs/project/index.md`（数据；登记规约 = goodTools-index skill） |
| **命令与环境**：本 skill | 构建/测试/运行/发布命令、环境硬约束（工具链踩坑规则正文查 `context/lessons.md`） |

lib/ 的分层结构与域清单**不在本表登记**——见 `docs/project/coding-standards.md` §1（分层矩阵与红线）与 `docs/project/index.md`（域内文件与功能落点）。现行 epic 与过程态查 `context/CURRENT` / `context/epics/`，本 skill 不登记。

## 读码纪律（省 token 与正确性兼得）

文档比代码省 token，但文档**有损且可能失真**——三段式读法：

| 阶段 | 动作 | 成本量级 |
|---|---|---|
| ① 文档建图 | 先读 index.md 落点 + memory.md 决策 + devlog 变更记录，拿「为什么 / 边界 / 落点」 | 几十~几百 token |
| ② 定向读码 | LSP / semantic search 只读相关符号与区域（readSymbol / 行号范围），**禁整文件通读** | 几百 token/次 |
| ③ 关键断言实证 | 文档每个「已实现」结论动手前抽查一处代码确认；行号引用须实测（会漂移） | 一次性 |

- 「文档 + 定向读码」比「通读代码」省 token；「只读文档」省的是阅读成本、付的是正确性风险（返工远超省下的 token）。

## 规范数据维护触发器（发现即维护，不当旁观者）

**判据三问**（决定要不要写）：① 是架构分流/准入规则？② 变更频率是月/季度或重大架构变更级？③ 缺了它 CI 扫描或 Review 是否失去判定依据？——三问命中即按下表维护；日常需求流水账禁写。

**本触发器只管 `coding-standards.md`**：index.md 数据与代码枚举各有专属归属（见表内路由列），本 skill 不越界维护。

| 工作中发现的信号 | standards 维护（本 skill 触发） | 同轮路由（非本 skill 维护） |
|---|---|---|
| **新功能落点域 / 新顶层域** | §1.0 分层矩阵登记（角色 + 允许出向）；§1.3 决策表追加一行 | `docs/project/index.md` 代码落点（**goodTools-index skill**）；`kGoodToolsDomains` 代码枚举（若有） |
| **mcp/action 命中红线（R4 import UI）** | 按 §1.1/§1.2 处置：先改结构（端口注入 / 类型下沉）再写 import；确属历史遗留走白名单纪律（只减不增） | 债表登记与清零记账（**goodTools-index skill** → index.md） |
| **新对外暴露 MCP 工具** | §3.1 工具描述引导 + §3.2 错误码口径核对 | 工具面实现代码中执行 |
| **端口 / 依赖反转新增** | §1.2 端口纪律登记范式 | index.md 落点（**goodTools-index skill**） |

**维护收尾两件**（standards 侧，同轮完成）：① 刷新 `updated` 字段；② 检查机械镜像（arch-guard R4/R6）是否需同步——规则正文在文档，代码只镜像不立法。

## 环境硬约束（实测取证）

- **flutter 不在默认 PATH**：实测 `which flutter` 为空；二进制在 `~/flutter/bin/flutter`（同目录含 `dart`）。所有 flutter 命令前必须先 `export PATH="$HOME/flutter/bin:$ANDROID_HOME/platform-tools:$PATH"`。仓库内 `scripts/agent-tools/*.sh` 已统一在脚本内注入该 PATH，裸跑脚本无需手动加。
- **Flutter/Dart 版本**：`flutter --version` 实测 `Flutter 3.47.5 • channel stable`（Dart 随 SDK，pubspec 约束 `sdk: ^3.13.4`）。
- **ANDROID_HOME**：默认 `~/android-sdk`；打包/安装/adb 需 Android SDK + `platform-tools`。`scripts/agent-tools` 内 `ANDROID_HOME="${ANDROID_HOME:-$HOME/android-sdk}"`。
- **release 签名**：`android/app/build.gradle.kts` 的 `release` 段当前 `signingConfig = signingConfigs.debug`（用 debug 密钥），正式发布前须配自有签名。
- **无头约束**：本工程是「无头系统」——删掉整个 Flutter UI，MCP 命令面应能完整运行（arch-guard R4 据此禁 mcp/action 反向依赖 UI）。

## 经验教训维护协议（context/lessons.md）

**数据住 `context/lessons.md`，协议住本 skill**（防双源）：本文件只定义什么时候记、按什么格式记、什么时候清零，不承载任何经验正文。

### 使用时机（三种，缺一即退化为重复排查）

| 时机 | 场景 | 动作 |
|---|---|---|
| **写前检索** | 动高风险模块前（地理 HTTP 签名 / 前台服务保活 / 自更新通道…） | 先查对应模块节，提取已知反模式，在写代码第一分钟避开暗坑 |
| **排障检索** | 构建 / 测试 / 真机联调报错时 | 取报错关键字在 lessons.md 全字匹配，先读解法再动手，禁从零排查 |
| **升维销项** | 坑解决后 | 把解法挂上回归钉子进「回归」段——只写文档不挂钉，换人照踩 |

### 录入准则（三不记 + 录入门槛）

- **不记**临时网络/环境偶发抖动（连接超时、换个镜像站即好）——无复现价值。
- **不记**情绪与破案流水账——人名、时间、排查历程一律抹除，只留技术因果。
- **不记**无法落地的泛泛建议（"注意并发安全"、"多写单测"类）。
- **录入门槛**：排查耗时 >15min 的确定性故障（机理清楚、可复现、有复现价值），**同轮沉淀**，不当旁观者。

### 录入格式（四段式 · 单行落盘 · 显式标签）

新条目在 `context/lessons.md` 底部 `## 待归并（<模块>）` 区追加：

```
- [<模块>] 现象: <报错关键字/堆栈特征，确保 grep 精准命中> | 根因: <语言/运行时/平台机制本质> | 处置: <解法/命令/代码修改点> | 回归: <回归钉路径或机械规则编号> (Ref: <epic>)
```

- 归并后移入对应 `## <模块>` 节并去掉 `[<模块>]` 前缀，补上回归段。
- 正文区行禁 `- [` 开头（该前缀专属底部追加区）。

### 闭环清零纪律（Inbox → 正文）

- 新坑先落 Inbox（`## 待归并` 区），**禁直接插正文**——正文只收已审条目。
- **Epic 收官 / 版本发版前必须清零 Inbox**：归入模块节、消除完全重复项。
- **归并门禁**：缺「回归」段的条目，要么补回归钉子路径，要么写明机械规则编号（arch-guard R#）或明确代码约束，否则不得进正文。
- 归并后刷新文件 frontmatter 的 `total-merged` 与 `last-merge` 字段。
- lessons.md 是**全局账**（frontmatter `epic: global`）：跨 epic 复用，只归并不清空。

## 研发闭环命令（唯一出处）

所有命令显式携带 SDK 环境变量：

```bash
export PATH="$HOME/flutter/bin:$HOME/android-sdk/platform-tools:$PATH" ANDROID_HOME="$HOME/android-sdk"
flutter pub get                 # 依赖拉取（改 pubspec.yaml 后）
```

> 命令双入口：项目工具池 `toolbox run <工具>`（canonical）与裸脚本 `scripts/agent-tools/<工具>.sh` 等价；无 toolbox 环境用裸脚本。

### 1. 提交前质检流水线（PR 交付红线，按耗时从小到大）

任一步失败**禁止提交**；禁止 `--no-verify` 绕过门禁：

```bash
toolbox run arch-guard            # ag   # ① 架构红线扫描（秒级：R1~R5 lib/ui 平台隔离/写门禁/依赖方向 + R4 mcp/action 禁 import UI + R6 禁 textScaleFactor）
flutter analyze                   #      # ② 静态检查 → 0 issue 为交付线
flutter test                      #      # ③ 单测 → 全绿（test/smoke_test.dart + test/geo_test.dart，无设备可跑）
```

- lib/ 与 docs/ 混改时用聚合门禁按改动范围分派：`toolbox run pre-commit-gate`（pcg）；提交信息过 Conventional Commits 校验：`toolbox run commit-msg-gate`。
- ① 命中红灯 = 按 `docs/project/coding-standards.md` §1 修结构，**不得申请加白名单**（只减不增）。

### 2. 本地运行与真机联调（无模拟器）

```bash
flutter devices                          # 查看在线真机 ID
flutter run -d <DEVICE_ID> --debug       # 挂载真机联调
adb logcat -s flutter:*                  # 过滤 Flutter 运行时日志
toolbox run build-apk --install          # apk  # 构建 debug 包并 adb 安装（内置设备已装版本防降级守卫）
```

### 3. 打包与发布（Release Workflow）

发布链 = **升版本 → 预检 → dry-run → 发布**（release-r2 直接读 `pubspec.yaml` 的 version 行，必须先 bump）：

```bash
toolbox run bump-version --patch   # bump # ① 升版本：--patch/--minor/--major/--build 或 --set x.y.z+w
                                    #     自动探测设备已装 versionCode 防降级
toolbox run release-r2 --json      # r2   # ② 环境预检（真身存在/.env R2 凭证/node/flutter 就绪性）
toolbox run release-r2 -n          #      # ③ dry-run 预览全链步骤，不构建不上传
toolbox run release-r2 --commit    #      # ④ 正式发布：arm64 release APK → sha256 → 清单 → 上传 R2
```

- 本地调试包：`flutter build apk --debug`（或 `toolbox run build-apk`）。
- 真身 = `scripts/release-r2.sh`；R2 凭证配置见仓库根 `.env`（参考 `.env.example`）。

### 4. 构建异常自救（缓存重置急救包）

```bash
flutter clean && flutter pub get          # 基础缓存重置
cd android && ./gradlew clean && cd ..    # 深度原生构建缓存清理
toolbox run build-apk --fresh             # gradle 锁被占（Timeout waiting to lock）：先停 daemon 再构建
```
