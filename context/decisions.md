---
dev-loop: decisions
format: v1
epic: global
total-merged: 0
last-merge: none
---

# decisions

## misc

### [2026-10-20] 领域网关工具（分类嵌入模式）准入裁定 (src: 用户)

**场景/痛点** —— 四大能力若按原子粒度各自注册 MCP 工具，`tools/list` 每次全量注入 schema，工具数膨胀至 60+：Token 线性上涨，且模型在长清单里易幻觉指令名。`docs/project/domain_gateway.md`（draft）提出「1 域 = 1 工具 + `action` 枚举」方案，但其能力矩阵抄自通用 Kotlin 工具集，与 4 份 `docs/product/*.md` 已定义的 **26 个**原子动作严重不符——漏 20（正向/逆向地理编码、POI、路径规划、静态图、测距；日历 13 项含标记增删改、月网格、日期消歧、工作日透视、时区投影）、多 6（`create_calendar_event` / `set_alarm` / `web_search` / `fetch_webpage_content` / `get_step_counter` / `get_battery_thermal`），其中 `create_calendar_event` 直接违反 `calendar.md`「不做独立会议 / 日程管理」定位红线。

**可选方案** ——
- **A 结构性引入**（三层 `SubAction`/`CategoryTool`/`CategoryToolFace`）——**已选**；
- **B 原子工具平铺 + `switch(name)` 膨胀**——否决：每加一能力重复「schema + 分支 + 参数解析 + 错误前缀」四件套，边际成本递增（命中否决信号 #2）；
- **C 混合**（读走网关、写走原子）——否决：同一能力两条调用路径，命中否决信号 #3（双路分支）。

**最终决定** —— 判 **S2 结构性引入**，放行。网关对内核零侵入（`McpToolFace` 接缝语义不变），唯一内核配合是 `call` 返回演进为完整 result 且 `isError` 由结果派生。附带硬约束：
1. **能力矩阵 1:1 对齐**：分类 = 四大能力域 `geo`/`system_pim`/`math_utility`/`weather`，`action` 名原样沿用 product 文档原子名，**禁止改名、禁止自造**；合计 26 个。
2. **删除通用能力**：`create_calendar_event` / `set_alarm`（守 calendar.md 定位红线）、`web_search` / `fetch_webpage_content` / `get_step_counter` / `get_battery_thermal`（杜绝通用工具箱蔓延）。网关是能力聚合方式，不是能力来源；能力唯一来源 = `docs/product/*.md`。
3. **写门禁机械拦截**：`SubAction.isWrite` 默认 `false`；W 档子操作只实现 `buildCommand(params) → Command`，由 `CategoryTool.call` 入口前置 `admits` 校验 + 统一 `dispatch`。子操作禁自行鉴权、禁自行派发。
4. **`isError` 唯一派生**：`toMcpResult()` 内硬绑定 `isError = !success`；`mcp_server.dart:118` 硬编码 `false` 同轮拆除；演进不设兼容分支。

**AI 洞察** —— 网关的真实价值不在「少注册几个工具」：`tools/list` 仍要列出全部 action 名，Token 收益有上限。价值在于把「错误前缀生成 / 参数签名生成 / 写门禁」三件原本会被重复 N 次的事收口到派发层做一次——若子操作仍手写前缀或自己 `dispatch`，只是把重复搬了个家，判定应回退为补丁。另：`action` 名沿用 product 文档原子名（不改名），使「文档表格第一列 vs 各分类 `register()` 的 name 列表」成为可机械对账的断言，根除文档与实现双轨。

**收敛条件** —— ① 第 3 次在某子操作内出现手写 `${category}.${action}` 前缀 ⇒ 强制回网关层统一注入；② 第 2 次为兼容旧返回形状出现 `if (result is Map)` 类双路分支 ⇒ 一次性收口，禁止分期演进；③ 任一 `lib/tools/*_tool.dart` 出现 `.dispatch(` / `.admits(` ⇒ CI 阻断（待 arch-guard 补扫描模式）。

> 约束型：已同步落 `context/epics/misc/memory.md` 契约行，约束后续网关落地实现。

### [2026-10-21] 计算器子页面切换 Soulver 草稿计算台（手写/键盘面退役）准入裁定 (src: 用户)

**场景/痛点** —— 手机上找算子（× ÷ ^ 括号）体验差：手写方案（ML Kit Digital Ink + KaTeX）虽已交付，但引入平台插件依赖（APK 增量数 MB~十几 MB）、首跑需联网下 20MB 模型、符号识别率不稳；点按键盘面键位繁琐。用户偶发算复合账目 / 工程比价，Soulver 式「多行草稿 + 行内解析 + 右侧等宽结果列」以全键盘直输 + 宽容归一解决算子痛点，且复用现有 `ExpressionEvaluator` / `UnitConverter` 纯内核。

**可选方案** ——
- **A Soulver 草稿台（行内文本解析）**——**已选**；
- **B 保留手写板 + 键盘 + Soulver 三输入共存**——否决：三套输入面同页维护成本高，且手写引擎体积与识别率问题不因共存消失；
- **C 传统单行计算器 + 九宫格**——否决：算子输入体验是原始痛点本身。

**最终决定** —— 判**结构性替换**（六条否决信号零命中，非补丁），放行。实施口径：
1. 行内解析调度器落 `lib/ui_ports/calculator_port.dart` 的 `evalLine`（纯 Dart，headless 可测）——调度器禁写进 Widget State；
2. 宽容归一（全角/中文符号、`85%` 后缀）在调度器层完成，内核词法面不感知；
3. `ans` 引用上一**成功**行数值（大小写不敏感），引用失败带机器码 `ANS_UNAVAILABLE` 不静默；
4. 手写三件（`handwriting_pad` / `handwriting_port` / `handwriting_recognizer`）+ 点按键盘 + `math_tex` 整体退役，`google_mlkit_digital_ink_recognition` 与 `flutter_math_fork` 依赖卸载；
5. 结果列走遥测轨等宽（`telemetry` 档），行高与算式侧同源推导（strut 钉死），零魔法值。

**AI 洞察** —— Soulver 模式与无头架构是同构关系：内核本就是「字符串进、类型化对象出」的无状态函数，新交互面只是换了一种**组串策略**，计算真相源零改动——这类「交互面重构、内核不动」的替换是本架构收益的直接证据。另外先交付再退役（手写面只活了半天）看似浪费，实则其探索为本次裁定提供了体积/识别率的一手依据，Spike 期权费没白花。

**收敛条件** —— ① 行解析第 3 次为新增语法（函数/变量绑定/百分号中间位）在 `evalLine` 加特判 ⇒ 强制下沉为独立纯 Dart 行解析器文件；② 行间引用若需超越 `ans`（命名变量、区间引用）⇒ 评估内核侧新增绑定求值器，禁在调度器里用正则糊；③ 右列与左侧行高错位类 bug 第 2 次出现 ⇒ 放弃双栏对齐改单栏内联渲染。

### [2026-10-22] 地图画布从 amap_flutter_map 切换 flutter_map + 高德瓦片源（原生 3D SDK 退役）准入裁定 (src: 用户)

**场景/痛点** —— `amap_flutter_map 3.0.0`（高德官方插件，2021 年后停更）在 AGP 9.1 / Gradle 9.3 / Flutter 3.47 工具链下连环爆雷：jcenter() 已删、缺 namespace、compileSdk 29 过低、Dart 侧 hashValues 移除、Java 侧 v1 embedding（Registrar/FlutterMain）已删——当日为出包在 `~/.pub-cache` 打了 6 处补丁才恢复构建，而 pub-cache 补丁在 `pub cache repair`/换机后失效即复现爆雷。老插件绑死高德闭源 Native 3D SDK，升级无望，补丁债必复发。

**可选方案** ——
- **A flutter_map（纯 Dart 渲染）+ 高德瓦片源 + 现有 REST 内核**——**已选**；
- **B 续用 pub-cache 补丁维护 amap_flutter_map**——否决：每次工具链升级重打 6 处补丁，同一位置第 3 次即触发 ascan 强制重构阈值，且 fork 维护成本与 A 重写成本相当而收益为负；
- **C maplibre_gl**——否决：引入新的原生依赖面（C++/Vulkan），与「零原生地图依赖」目标背道而驰，且本场景无 3D 倾斜/离线瓦片需求。

**最终决定** —— 判**结构性替换**（六条否决信号零命中，非补丁），放行。实施口径：
1. **画布层单文件替换**：`lib/ui/geo_page.dart` 画布区 AMapWidget→FlutterMap（onTap/Marker/Polyline 全有纯 Dart 等价物，实测无 `onPoiTouched` 等原生特有 API 使用，功能零损失）；
2. **定位/坐标系零新增依赖**：定位走现有 sensor 端口（不引 geolocator），坐标转换用现有 `lib/geo/coord_convert.dart`（不引 coordtransform）——用户提案中这两项依赖为多余改动面，砍掉；
3. **`amap_flutter_map`/`amap_flutter_base` 依赖整体退役**：`amap_android_key` 从 settings_keys（userWritable/credentialKeys）、`nativeKeyReader` 装配线、Manifest Native SDK 权限同步清除——SHA1 申领 Native Key 的治理负担一并消失；
4. **REST/静态图/GeoLbsPort 内核与工具面零改动**：MCP geo 8 action 不受影响；
5. **夜间模式**：高德无暗色瓦片，采用深色底 + style=8 路网叠加或滤镜方案，实施轮验证视觉效果；
6. 文档 SSOT 修订：geo.md §地图渲染 / ui-console.md 域表 / index.md 落点表同轮更新。

**AI 洞察** —— 本次切换的本质是把「地图渲染」从**高德专有客户端**降维为「标准 XYZ 瓦片 + 高德 Web 服务」组合：工程真正的高德耦合点从来只在 REST API 与瓦片源两处协议，而非 Native SDK——插件化的 Native 绑定是当初引入时多付的一层。替换后 UI 层不再有任何原生纹理依赖，R4 红线（无头约束）的实现面更干净：删掉 lib/ui 后构建链路不再含任何地图原生插件。另：评估时逐一核对了 geo_page 的实际 API 使用面（onTap/Marker/Polyline/MapType.night 四项），「功能损失」的恐惧来自想象而非实证——先实证使用面再谈成本，是本次评估快的关键。

**收敛条件** —— ① 瓦片源（`wprd*.is.autonavi.com/appmaptile`，非官方承诺接口）加鉴权/变更不可用时 ⇒ 退回 `GeoMapPort` 静态图降级预览（现有 fail-closed 路径接住），不引入备用瓦片源的 if-else 分支；② 若日后需要 POI 点选（onPoiTouched 类）能力 ⇒ 评估地图 SDK 换型而非给 flutter_map 打「伪 POI」补丁（用 REST 反查冒充 POI 点击属双路分支，禁）；③ 瓦片加载相关 bug 第 3 次在同处修补 ⇒ 强制评估 maplibre_gl 换型。

> 约束型：已同步 lessons.md build-android 条目（pub-cache 补丁为过渡态，由本替换根治）。
