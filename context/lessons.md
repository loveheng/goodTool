---
dev-loop: lessons
format: v1
epic: global
total-merged: 2
last-merge: 2026-10-24
---

# lessons

按模块归类的避坑规则正文（正文行禁用 `- [` 开头——该前缀专属底部追加区）

## calendar（日历域 · 2026-10-20 归并自 P2-①~⑧）

**ICS 时间解析禁 `DateTime(...).toUtc()`** — 现象: 展开的日历实例整体漂一天（`02:00Z` 变前一天 18:00）| 根因: `toUtc()` 把 ICS 墙钟按**本机时区**偏移，而 ICS 的 `Z` 表示真 UTC、`TZID`/浮点为名义 UTC | 处置: 用 `DateTime.utc(...)` 直接构造，不经 `toUtc()` 转换 | 回归: `test/ics_parser_test.dart`

**Actor 失败信封必须走 `structuredError` 构造** — 现象: 业务失败返回散文而非 JSON 信封，`suggestion` 等自愈字段全丢 | 根因: `_raw` 构造的 `errorCode` 为 null，`withPrefix` 注入的 `[前缀: UNKNOWN]` 文本把整个 JSON 信封**替换**掉 | 处置: 失败信封一律用 `structuredError` 构造 | 回归: `test/calendar_actors_test.dart`

**跨度算法用逐月推进而非月份相减借位** — 现象: `1/31 → 3/1` 算出负数天内差（-2 天）| 根因: 借位法借的是 end **所在上月**的天数 | 处置: 从 start 逐整月推进（先年后月）至再进一月即超过 end，残余即天数 | 回归: `test/system_pim_tool_test.dart`

**RRULE 的 BYMONTHDAY 必须按 FREQ 分流** — 现象: DAILY 规则每月只触发一天 | 根因: 月日过滤被无差别套用到所有 FREQ | 处置: 仅 MONTHLY/YEARLY 应用 BYMONTHDAY、WEEKLY 应用 BYDAY；无 31 日的月份按 RFC **不触发**（不 clamp 伪造日期）| 回归: `test/ics_parser_test.dart`

**第三方农历库约定读源码钉死，禁凭记忆** — 现象: 闰月 / 角标 / 节气三项同时错 | 根因: 假设库 API——闰月用**负月份数**、`getMonthInChinese()` 返回不带「月」字、节气表 key 仅跨年表头是拼音 | 处置: 读源码取真值后归一（`Lunar.fromYmd(y,-6,d)`；角标自加「月」；节气 key 统一）| 回归: `test/lunar_math_test.dart`

**Dart null-aware 元素对 false 仍出字段** — 现象: `?'approximate'` 想「仅 true 时出参」却把 false 也输出了 | 根因: null-aware 只省 `null`、不省 `false` | 处置: 形参改可空 + 值域归 `null` 后再走 null-aware（`use_null_aware_elements` 与 `invalid_null_aware_operator` 两条 lint 互相打架，须靠可空形参化解）| 回归: `test/marker_math_test.dart`

**合并层禁直接 `addAll` 源返回的不可变列表** — 现象: `UnmodifiableListError` | 根因: 源 Provider 返回 `UnmodifiableListView` | 处置: 复制后再合并 | 回归: `test/composite_calendar_provider_test.dart`

## dart（语言与门禁 · 2026-10-20 归并自 ui-console）

**空值感知元素修饰的是「值」不是「键」** — 现象: 想让 map 某项在值为 null 时整项省略，写成 `?'key': value` 被 lint 双向打架（`use_null_aware_elements` 与 `invalid_null_aware_operator` 同时报）| 根因: `?key: value` 是**键**空感知，而键是字面量永不为 null，故该写法无意义 | 处置: 正确写法是 `'key': ?value`（值空则整项省略）| 回归: `test/ui_console_test.dart`

**机械门禁「真的活着」要用反向探针验证** — 现象: arch-guard 的 R1/R2/R3/R5 作用域是 `lib/ui`，而该目录长期不存在 → 扫描**无对象**却一直报「全部通过」，绿灯是假的 | 根因: 空目录下 grep 必然零命中，门禁从未被真实触发过 | 处置: 建层后必须做**反向探针**：临时注入违规代码（`jsonDecode` / `Platform.isAndroid`）→ 期望逐条报出行号拦截 → 删除探针 → 复跑确认全绿 | 回归: `toolbox run arch-guard`（本次已验证 R2/R3 命中）

## 构建（Android 工具链 · 2026-10-20 归并自 ui-console，2026-10-24 续归 geo/ui-console 流水）

**AGP 8+ 的 AIDL 编译器默认关闭** — 现象: `McpBinderService.kt` 的 `import com.zzh.goodhub.mcp.*` 全部 `Unresolved reference 'zzh'`（8 处），但仓内 `src/main/aidl/com/zzh/goodhub/mcp/` 的 `.aidl` 源**确实存在** | 根因: 自 AGP 8 起 AIDL 编译**不再默认开启**，未写 `buildFeatures { aidl = true }` 则 `.aidl` 不生成类，import 全部落空——**文件在 ≠ 会被编译** | 处置: `android/app/build.gradle.kts` 增 `buildFeatures { aidl = true }` | 回归: `toolbox run build-apk`（修后 APK 编译通过，154M debug 全架构）

> **2026-10-20 补充（坑已在本仓消失，教训保留）**：自拷 AIDL（`android/app/src/main/aidl/com/zzh/goodhub/mcp/`）随插件接入 SDK 拆仓一并删除，`buildFeatures { aidl = true }` 同步移除——契约类改由 `com.zzh.goodhub.mcp:goodhub-mcp-contract` 坐标提供（唯一物理副本在 goodhub-mcp-sdk 仓 `:contract` 模块）。本坑在本仓不再复现。教训仍成立：**AGP 8+ 的 `.aidl` 文件不 opt-in `aidl = true` 就不生成类，文件在 ≠ 会被编译**。

**SDK 升版 ≠ 本机消费路径自动跟进** — 现象: `android/app/build.gradle.kts` 把 `goodhub-mcp-plugin-core` 升到 0.2.0 后 `:app:dependencies` 报 `goodhub-mcp-plugin-core:0.2.0 FAILED` | 根因: 本仓消费路径是 `mavenLocal()` + SDK 仓 `dist/maven-repo`（`android/build.gradle.kts`），两者都只在上次 `publishToMavenLocal` / `scripts/dist.sh` 时落件——**SDK 仓打 tag（v0.2.0）不会回写到本机**；GitHub Packages 匿名拉为 401（公开包也强制 token） | 处置: 在 goodhub-mcp-sdk 仓跑 `scripts/dist.sh` 产出 0.2.0 离线分发件（免认证），再复验 `:app:dependencies` + `:app:compileReleaseKotlin` | 回归: 依赖解析出 `plugin-core 0.2.0 → contract 0.2.0`；**今后每次 SDK 升版，先跑一次 dist.sh 再打包** (Ref: mcp-sdk-version-drift)

**后台 entrypoint 必须被某个编译根 import，否则 headless 引擎查库落空** — 现象: Binder headless 引擎报 Dart entrypoint 超时（ready 5s 未达）| 根因: 真相不是慢而是 `Dart_LookupLibrary not found`——后台 entrypoint 文件无人 import，kernel_blob 根本不含该库，`executeDartEntrypoint` 查库落空 isolate 起不来 | 处置: 后台 entrypoint（`mcp_binder_entrypoint.dart`）在 main.dart 编译根 import（`// ignore: unused_import` 亦可见）| 回归: U15 真机 goodhub 挂载 GoodTools 后 tools/list 非空 (Ref: binder-entrypoint-kernel)

**老插件落后工具链三代时，打补丁只是延迟付重写的账** — 现象: `flutter build apk` 报 `Could not find method jcenter()`（:amap_flutter_map）等 6 处不兼容 | 根因: amap 3.0.0 落后 Flutter/AGP/Gradle 三代——jcenter 在 Gradle 9 已删、无 namespace、compileSdk 29 过低、hashValues/Registrar/FlutterMain 等弃用 API 全爆，Flutter Fix 框只提示 newDsl，真根因在老插件 | 处置: 曾打 pub-cache 补丁续命；**2026-10-23 根治**——`amap_flutter_map`/`amap_flutter_base` 随 flutter_map 结构性替换整体退役（decisions.md 2026-10-22），pub-cache 补丁债清零，本坑不再复现 | 回归: toolbox run build-apk 全绿 (Ref: geo)

**原生插件选型看「近 6 个月有发版」维护信号，引入当日构建实证** — 现象: 无（预防性实证）| 根因: 引入原生类第三方插件前无法预判其 AGP/Gradle 兼容性，停更插件在本工具链需 6 处 pub-cache 补丁 | 处置: 2026-10-22 引入 geolocator 14.1.2（geolocator_android 5.2.1）后立即跑 `flutter build apk --debug` 实证——42s 零补丁通过（仅 Java 弃用警告）| 回归: 活维护插件（近月有发版 + federated 架构）在本工具链开箱即用；**结论：引入后当日构建实证，不留到出包日才爆雷** (Ref: geo)

## weather（天气域 · 2026-10-24 归并）

**403 Security Restriction 是独立真因，须从笼统鉴权失败拆出** — 现象: 真机配置 Key+Host 后仍报「鉴权失败403」| 根因: 和风控制台安全限制（IP 白名单/访问限制）返回 403 JSON:API title=Security Restriction——Key/Host 本身有效；`_isHostProblem` 只认 Invalid Host/服务不可访问，落入笼统鉴权失败文案 | 处置: `lib/service/weather.dart` 新增 `_isSecurityRestriction` 优先识别，文案改「和风安全限制拦截」并指向控制台安全设置 | 回归: test/qweather_provider_test.dart『403 Security Restriction → 安全限制文案』 (Ref: weather)

**和风公共域名全线停用，错误体必须读出再翻译** — 现象: 和风请求 403（响应体 `{"error":{"title":"Invalid Host"}}`）或 404 空体；应用侧只显示笼统「鉴权失败」/「查无此城」| 根因: ① 公共域名自 2024 起全线停用（`devapi`/`api` → 403 Invalid Host，`geoapi` → 404 空体），必须账号专属 Host（系统按账号分配，不能猜）；② 和风把真实原因放在**错误体**里（JSON:API `error.title/detail`，未开通场景中文「服务不可访问」），4xx 直接 `drain` 丢体 → 用户拿不到可自愈真因；③ 用户粘贴控制台 URL 会拼出畸形 URI | 处置: 公共域名不再兜底（兜底只会把 404 空体误报成「查无此城」）；错误体读出再翻译并新增 `ERR_WEATHER_HOST_INVALID`；HTTP 200 + `error` 段也拦截（消除「成功但 now 为空」假成功）；Host 值归一化（去协议/斜杠/路径段）；Key 缺失优先于 Host 缺失上报 | 回归: test/qweather_provider_test.dart 7 例（归一化/账号 Host 的 /geo 路径/未配 Host 零请求/403/404 中文文案/200 内 error 段） (Ref: weather)

## geo（地理域 · 2026-10-24 归并）

**定位源任何异常 fail-closed 返 null，UI 状态收尾不押「端口不抛」** — 现象: 进地图页停在硬编码起点（相机不动）且顶部胶囊「定位中…」永久不结束，无异常栈 | 根因: geolocator 在系统定位开关关闭时抛 `LocationServiceDisabledException`、权限流程异常抛 `PermissionDeniedException`——旧实现只 catch `TimeoutException`，异常冒泡出端口后 UI 侧 `await` 抛出、`setState` 不执行，失败态永不落地 | 处置: 定位源任何失败一律 catch 并 fail-closed 返 null（打 `[LOC]` 日志留原因，不静默吞）；UI 侧再兜一层 try/catch（纵深防御）；分档回退 高精度→低精度→上次已知位置（仅采信新鲜读数） | 回归: test/system_location_sensor_test.dart 13 例（权限/开关/异常收敛/分档顺序/过期拒收） (Ref: geo)

## ui（用户层 · 2026-10-24 归并自 ui-console/calculator）

**push 路由须有 Material/Scaffold 祖先（Flutter 3.47+ 路由不再代包）** — 现象: 页面 push 后整页红屏 No Material widget found | 根因: Flutter 3.47 起 `MaterialRouteTransitionMixin.buildPage` 只包 Semantics 不再包 Material（旧版包 Material），无 Scaffold 的页面直接 push 缺 Material 祖先 | 处置: capabilities_page.dart 域卡 push 处 `Scaffold(body: pages[domain])` 收口 | 回归: U15 真机点击四域卡进子页 (Ref: push-route-no-material)

**release 包 InkWell 失效须查 Material 祖先** — 现象: release 真机点域卡无反应、无水纹 | 根因: InkWell 要求 Material 祖先做 hit-test，SectionCard 是纯 Container+BoxDecoration，release 包 assert 剥离后静默失效 | 处置: capabilities_page.dart _DomainCard 给 InkWell 包 MaterialType.transparency | 回归: U15 真机点击四域卡进子页（待补 widget 测试钉子）(Ref: hub-inkwell-material)

**maxLines:1 的 TextField 被框架强插 singleLineFormatter，粘贴拦截须走入口层** — 现象: Flutter TextField(maxLines:1) 粘贴多行文本换行被静默剥掉，TextInputFormatter 的 formatEditUpdate 收不到含换行的值，粘贴裂变拦截全链失效 | 根因: EditableText 构造器在 maxLines==1 时无条件把 `FilteringTextInputFormatter.singleLineFormatter` 前插到用户格式器之前（editable_text.dart），框架级过滤先于一切用户代码 | 处置: 放弃 formatter 路线，改在粘贴动作入口拦截——contextMenuBuilder 替换粘贴按钮，先 Clipboard.getData 判多行走裂变事务、单行放行 state.pasteText；控制器监听层兜底程序化直写 | 回归: test/block_canvas_test.dart 粘贴入口拦截+直写兜底两用例 (Ref: calculator)

**横向滚动视口禁给 infinity 内容宽** — 现象: 进入计算器页整页空白，日志 BoxConstraints forces an infinite width（RenderCustomPaint, w=Infinity）| 根因: 横向 SingleChildScrollView 的内容 SizedBox 在未落笔时给 double.infinity 宽——横向滚动视口禁无限宽约束，performLayout 断言炸掉整帧 | 处置: 内容宽度用 LayoutBuilder 取视口 maxWidth 做有限初值；凡横向书写带/画布类组件禁给 infinity 内容宽 | 回归: test/calculator_page_test.dart（页首帧可构建 widget 测试）(Ref: ui-console)
