---
dev-loop: lessons
format: v1
epic: global
total-merged: 3
last-merge: 2026-10-27
---

# lessons

按模块归类的避坑规则正文（正文行禁用 `- [` 开头——该前缀专属底部追加区）

## calendar（日历域 · 2026-10-20 归并自 P2-①~⑧，2026-10-27 续归 ui-console 流水）

**ICS 时间解析禁 `DateTime(...).toUtc()`** — 现象: 展开的日历实例整体漂一天（`02:00Z` 变前一天 18:00）| 根因: `toUtc()` 把 ICS 墙钟按**本机时区**偏移，而 ICS 的 `Z` 表示真 UTC、`TZID`/浮点为名义 UTC | 处置: 用 `DateTime.utc(...)` 直接构造，不经 `toUtc()` 转换 | 回归: `test/ics_parser_test.dart`

**Actor 失败信封必须走 `structuredError` 构造** — 现象: 业务失败返回散文而非 JSON 信封，`suggestion` 等自愈字段全丢 | 根因: `_raw` 构造的 `errorCode` 为 null，`withPrefix` 注入的 `[前缀: UNKNOWN]` 文本把整个 JSON 信封**替换**掉 | 处置: 失败信封一律用 `structuredError` 构造 | 回归: `test/calendar_actors_test.dart`

**跨度算法用逐月推进而非月份相减借位** — 现象: `1/31 → 3/1` 算出负数天内差（-2 天）| 根因: 借位法借的是 end **所在上月**的天数 | 处置: 从 start 逐整月推进（先年后月）至再进一月即超过 end，残余即天数 | 回归: `test/system_pim_tool_test.dart`

**RRULE 的 BYMONTHDAY 必须按 FREQ 分流** — 现象: DAILY 规则每月只触发一天 | 根因: 月日过滤被无差别套用到所有 FREQ | 处置: 仅 MONTHLY/YEARLY 应用 BYMONTHDAY、WEEKLY 应用 BYDAY；无 31 日的月份按 RFC **不触发**（不 clamp 伪造日期）| 回归: `test/ics_parser_test.dart`

**第三方农历库约定读源码钉死，禁凭记忆** — 现象: 闰月 / 角标 / 节气三项同时错 | 根因: 假设库 API——闰月用**负月份数**、`getMonthInChinese()` 返回不带「月」字、节气表 key 仅跨年表头是拼音 | 处置: 读源码取真值后归一（`Lunar.fromYmd(y,-6,d)`；角标自加「月」；节气 key 统一）| 回归: `test/lunar_math_test.dart`

**Dart null-aware 元素对 false 仍出字段** — 现象: `?'approximate'` 想「仅 true 时出参」却把 false 也输出了 | 根因: null-aware 只省 `null`、不省 `false` | 处置: 形参改可空 + 值域归 `null` 后再走 null-aware（`use_null_aware_elements` 与 `invalid_null_aware_operator` 两条 lint 互相打架，须靠可空形参化解）| 回归: `test/marker_math_test.dart`

**合并层禁直接 `addAll` 源返回的不可变列表** — 现象: `UnmodifiableListError` | 根因: 源 Provider 返回 `UnmodifiableListView` | 处置: 复制后再合并 | 回归: `test/composite_calendar_provider_test.dart`

**固定表头形态下数据页必须纯无头，禁用叠加元素模拟钉死** — 现象: 月视图固定表头首版做成「全局固定表头 + 页内对齐表头」（两表头叠 4px），静止时视觉双表头、落定帧实锤重复 | 根因: 同构表头「滚到重合」方案在任何非滚动时刻都会露出第二条表头 | 处置: 直接删页内表头（`MonthGrid.showHeader=false` 已有开关）；真机验收固定类 UI 要同时看**滚动中间帧与落定帧**（中间帧对、落定帧错正是叠加方案的破绽）| 回归: test/calendar_strip_midstate_test.dart（固定表头单表头口径 3 断言）

**跳变类问题先分层取证（动画层 vs 数据路径）** — 现象: 翻页落定后页面跳一下；宿主机逐帧连续性/方向单调性取证均 0px（动画层无缝）| 根因: 跳变不在动画层而在数据路径——翻页后 `_loadOverview` 异步更新，①新月份 warnings 有无使告警行出现/消失 → 条带高度变 → 网格重排；②页面实例缓存键不含数据版本，密度更新后滞留旧空密度（事件点不显示）且伴随重排 | 处置: ①告警行改 `Visibility(maintainSize:true)` 恒占位（月/年两处）②`_loadOverview` 逐槽位 `_densityMapsEqual` 侦测数据版本，变化即清页面实例缓存；空 feed 测试环境天然复现不了告警/密度路径，须真机双帧 sha256 取证 | 回归: test/calendar_strip_midstate_test.dart + 真机落定双帧 sha256 一致

**滑动条相邻页禁被 Stack 默认裁剪，空白区须可起拖** — 现象: 真机拖拽中途相邻月整片空白（当前月上移、下月区域纯背景色），且空白网格区起点拖不动 | 根因: 双因——Stack 默认 `Clip.hardEdge` 把 Positioned 在 Stack 边界外的相邻页整页裁掉，两月同屏中间态画不出来；GestureDetector 默认 `deferToChild`，空白网格区（格间隙）起点子链零命中则整条不响应 | 处置: 月/年滑动条 Stack 显式 `clipBehavior=Clip.none`（视口裁剪交外层 ClipRect）+ GD `behavior=HitTestBehavior.opaque`（整条可起拖）| 回归: test/calendar_strip_midstate_test.dart（实例身份刚性平移+中间态+落定断言）+ 真机中途截图两月同屏成立

**阈值常量语义不得与字面系数叠乘** — 现象: 快甩进年视图门槛公式写成 `3 * _pageHeight * _kYearFlickPages`（3×3=9 整屏），注释语义 3 整屏与公式系数叠乘，入口成死功能 | 根因: 常量本身已含「整屏倍数」语义，公式里又写了字面 3 | 处置: 公式只保留单一常量锚点（`_kYearFlickPages * _pageHeight`）| 回归: 真机快甩 3 整屏须进年视图（该入口随年视图撤除已退役，规则仍成立）

## dart（语言与门禁 · 2026-10-20 归并自 ui-console）

**空值感知元素修饰的是「值」不是「键」** — 现象: 想让 map 某项在值为 null 时整项省略，写成 `?'key': value` 被 lint 双向打架（`use_null_aware_elements` 与 `invalid_null_aware_operator` 同时报）| 根因: `?key: value` 是**键**空感知，而键是字面量永不为 null，故该写法无意义 | 处置: 正确写法是 `'key': ?value`（值空则整项省略）| 回归: `test/ui_console_test.dart`

**机械门禁「真的活着」要用反向探针验证** — 现象: arch-guard 的 R1/R2/R3/R5 作用域是 `lib/ui`，而该目录长期不存在 → 扫描**无对象**却一直报「全部通过」，绿灯是假的 | 根因: 空目录下 grep 必然零命中，门禁从未被真实触发过 | 处置: 建层后必须做**反向探针**：临时注入违规代码（`jsonDecode` / `Platform.isAndroid`）→ 期望逐条报出行号拦截 → 删除探针 → 复跑确认全绿 | 回归: `toolbox run arch-guard`（已验证 R2/R3 命中）

**机械门禁须在真实工具链上编译实证，SDK 类型收敛会打断陈旧写法** — 现象: Flutter 3.47 起 `ListView.scrollCacheExtent` 收敛为 `ScrollCacheExtent` 类，历史 double 直接赋值不编译（`argument_type_not_assignable`），构建门禁（analyze 0 issue）在打包时拦下 | 根因: SDK API 形状随版本收敛，凭记忆写的旧参数类型未跟工具链对齐 | 处置: 迁移到 `ScrollCacheExtent.pixels(...)`（rendering 库导出，`show` 限定引入）；交付线恒为 analyze 0 issue，编译错误不出现在打包阶段 | 回归: `toolbox run build-apk`（内置 analyze 门槛）

## 构建（Android 工具链 · 2026-10-20 归并自 ui-console，2026-10-24/27 续归）

**AGP 8+ 的 AIDL 编译器默认关闭** — 现象: `McpBinderService.kt` 的 `import com.zzh.goodhub.mcp.*` 全部 `Unresolved reference 'zzh'`（8 处），但仓内 `.aidl` 源**确实存在** | 根因: 自 AGP 8 起 AIDL 编译**不再默认开启**，未写 `buildFeatures { aidl = true }` 则 `.aidl` 不生成类——**文件在 ≠ 会被编译** | 处置: `android/app/build.gradle.kts` 增 `buildFeatures { aidl = true }` | 回归: `toolbox run build-apk`

> **2026-10-20 补充（坑已在本仓消失，教训保留）**：自拷 AIDL 随插件接入 SDK 拆仓一并删除，契约类改由 `com.zzh.goodhub.mcp:goodhub-mcp-contract` 坐标提供。本坑在本仓不再复现。教训仍成立：**AGP 8+ 的 `.aidl` 文件不 opt-in `aidl = true` 就不生成类**。

**SDK 升版 ≠ 本机消费路径自动跟进** — 现象: `goodhub-mcp-plugin-core` 升到 0.2.0 后 `:app:dependencies` 报 FAILED | 根因: 本仓消费路径是 `mavenLocal()` + SDK 仓 `dist/maven-repo`，两者都只在上次 publish/dist 时落件——**SDK 仓打 tag 不会回写到本机**；GitHub Packages 匿名拉为 401 | 处置: 在 goodhub-mcp-sdk 仓跑 `scripts/dist.sh` 产出离线分发件（免认证），再复验依赖解析与编译 | 回归: **今后每次 SDK 升版，先跑一次 dist.sh 再打包** (Ref: mcp-sdk-version-drift)

**后台 entrypoint 必须被某个编译根 import，否则 headless 引擎查库落空** — 现象: Binder headless 引擎报 Dart entrypoint 超时（ready 5s 未达）| 根因: 真相不是慢而是 `Dart_LookupLibrary not found`——后台 entrypoint 文件无人 import，kernel_blob 根本不含该库 | 处置: 后台 entrypoint（`mcp_binder_entrypoint.dart`）在 main.dart 编译根 import（`// ignore: unused_import` 亦可见）| 回归: U15 真机 goodhub 挂载 GoodTools 后 tools/list 非空 (Ref: binder-entrypoint-kernel)

**老插件落后工具链三代时，打补丁只是延迟付重写的账** — 现象: `flutter build apk` 报 `Could not find method jcenter()`（:amap_flutter_map）等 6 处不兼容 | 根因: amap 3.0.0 落后 Flutter/AGP/Gradle 三代——jcenter 在 Gradle 9 已删、无 namespace、compileSdk 29 过低、弃用 API 全爆，真根因在老插件 | 处置: **2026-10-23 根治**——amap 随 flutter_map 结构性替换整体退役（decisions.md 2026-10-22），pub-cache 补丁债清零，本坑不再复现 | 回归: toolbox run build-apk 全绿 (Ref: geo)

**原生插件选型看「近 6 个月有发版」维护信号，引入当日构建实证** — 现象: 无（预防性实证）| 根因: 引入原生类第三方插件前无法预判其 AGP/Gradle 兼容性 | 处置: 2026-10-22 引入 geolocator 14.1.2 后立即跑 `flutter build apk --debug` 实证——42s 零补丁通过 | 回归: **引入后当日构建实证，不留到出包日才爆雷** (Ref: geo)

**release 包启动 NoSuchMethodError 先查联邦插件 R8/JNI 雷** — 现象: release 包启动卡装配失败页 `PlatformException NoSuchMethodError SharedPreferencesApiRegistrar.getAll(...Lkotlin/coroutines/Continuation;)`，debug/profile 正常 | 根因: shared_preferences_android 2.5.0 起 Pigeon JNI 直调按名查找 kotlin.coroutines.Continuation 等六类，release R8 混淆改类名致 JNI 描述符失配（flutter/flutter#194649），2.5.0/2.5.1 无 consumer-rules，2.5.2 起自带修复；clean 重建无用因错在 R8 与源码组合 | 处置: release 冷启 NoSuchMethodError 先 `grep Continuation pubspec.lock` 查联邦插件版本，升级到修复版（≥2.5.2）并 `flutter clean` 重生成 GeneratedPluginRegistrant | 回归: release 包冷启 logcat grep NoSuchMethodError=0 (Ref: shared-prefs-r8-jni)

## weather（天气域 · 2026-10-24 归并）

**403 Security Restriction 是独立真因，须从笼统鉴权失败拆出** — 现象: 真机配置 Key+Host 后仍报「鉴权失败403」| 根因: 和风控制台安全限制（IP 白名单/访问限制）返回 403 JSON:API title=Security Restriction——Key/Host 本身有效；`_isHostProblem` 只认 Invalid Host/服务不可访问，落入笼统鉴权失败文案 | 处置: `lib/service/weather.dart` 新增 `_isSecurityRestriction` 优先识别，文案改「和风安全限制拦截」并指向控制台安全设置 | 回归: test/qweather_provider_test.dart『403 Security Restriction → 安全限制文案』 (Ref: weather)

**和风公共域名全线停用，错误体必须读出再翻译** — 现象: 和风请求 403（响应体 `{"error":{"title":"Invalid Host"}}`）或 404 空体；应用侧只显示笼统「鉴权失败」/「查无此城」| 根因: ① 公共域名自 2024 起全线停用，必须账号专属 Host；② 和风把真实原因放在**错误体**里（JSON:API `error.title/detail`），4xx 直接 `drain` 丢体 → 用户拿不到可自愈真因；③ 用户粘贴控制台 URL 会拼出畸形 URI | 处置: 公共域名不再兜底；错误体读出再翻译并新增 `ERR_WEATHER_HOST_INVALID`；HTTP 200 + `error` 段也拦截（消除假成功）；Host 值归一化；Key 缺失优先于 Host 缺失上报 | 回归: test/qweather_provider_test.dart 7 例 (Ref: weather)

## geo（地理域 · 2026-10-24 归并）

**定位源任何异常 fail-closed 返 null，UI 状态收尾不押「端口不抛」** — 现象: 进地图页停在硬编码起点（相机不动）且顶部胶囊「定位中…」永久不结束，无异常栈 | 根因: geolocator 在系统定位开关关闭时抛 `LocationServiceDisabledException`、权限流程异常抛 `PermissionDeniedException`——旧实现只 catch `TimeoutException`，异常冒泡出端口后 UI 侧 `await` 抛出、`setState` 不执行，失败态永不落地 | 处置: 定位源任何失败一律 catch 并 fail-closed 返 null（打 `[LOC]` 日志留原因，不静默吞）；UI 侧再兜一层 try/catch（纵深防御）；分档回退 高精度→低精度→上次已知位置（仅采信新鲜读数） | 回归: test/system_location_sensor_test.dart 13 例 (Ref: geo)

## ui（用户层 · 2026-10-24 归并自 ui-console/calculator，2026-10-27 续归）

**push 路由须有 Material/Scaffold 祖先（Flutter 3.47+ 路由不再代包）** — 现象: 页面 push 后整页红屏 No Material widget found | 根因: Flutter 3.47 起 `MaterialRouteTransitionMixin.buildPage` 只包 Semantics 不再包 Material，无 Scaffold 的页面直接 push 缺 Material 祖先 | 处置: capabilities_page.dart 域卡 push 处 `Scaffold(body: pages[domain])` 收口 | 回归: U15 真机点击四域卡进子页 (Ref: push-route-no-material)

**release 包 InkWell 失效须查 Material 祖先** — 现象: release 真机点域卡无反应、无水纹 | 根因: InkWell 要求 Material 祖先做 hit-test，SectionCard 是纯 Container+BoxDecoration，release 包 assert 剥离后静默失效 | 处置: capabilities_page.dart _DomainCard 给 InkWell 包 MaterialType.transparency | 回归: U15 真机点击四域卡进子页（待补 widget 测试钉子）(Ref: hub-inkwell-material)

**maxLines:1 的 TextField 被框架强插 singleLineFormatter，粘贴拦截须走入口层** — 现象: Flutter TextField(maxLines:1) 粘贴多行文本换行被静默剥掉，TextInputFormatter 的 formatEditUpdate 收不到含换行的值，粘贴裂变拦截全链失效 | 根因: EditableText 构造器在 maxLines==1 时无条件把 `FilteringTextInputFormatter.singleLineFormatter` 前插到用户格式器之前（editable_text.dart），框架级过滤先于一切用户代码 | 处置: 放弃 formatter 路线，改在粘贴动作入口拦截——contextMenuBuilder 替换粘贴按钮，先 Clipboard.getData 判多行走裂变事务、单行放行 state.pasteText；控制器监听层兜底程序化直写 | 回归: test/block_canvas_test.dart 粘贴入口拦截+直写兜底两用例 (Ref: calculator)

**横向滚动视口禁给 infinity 内容宽** — 现象: 进入计算器页整页空白，日志 BoxConstraints forces an infinite width（RenderCustomPaint, w=Infinity）| 根因: 横向 SingleChildScrollView 的内容 SizedBox 在未落笔时给 double.infinity 宽——横向滚动视口禁无限宽约束，performLayout 断言炸掉整帧 | 处置: 内容宽度用 LayoutBuilder 取视口 maxWidth 做有限初值；凡横向书写带/画布类组件禁给 infinity 内容宽 | 回归: test/calculator_page_test.dart（页首帧可构建 widget 测试）(Ref: ui-console)

**widget 测试断言预挂载/缓存子项必须 skipOffstage:false** — 现象: 断言「±2 预挂载窗口至少装配 N 页」恒失败，`find` 只见可视页；`getRect(find.byWidget(w))` 对缓存实例报 Found 0 widgets | 根因: flutter_test finder 默认 `skipOffstage:true`，ListView/CustomScrollView 的 cacheExtent 预挂载子项在视口外被 finder 漏扫——sliver 实际**已挂载**（SliverConstraints.cacheOrigin/remainingCacheExtent 正常、`indexOf(firstChild/lastChild)` 覆盖缓存窗口），纯属查询口径问题 | 处置: 涉预挂载/缓存子项的断言与重查一律 `find.text(..., skipOffstage: false)` / `find.byWidget(w, skipOffstage: false)`；取证手段：SliverLayoutBuilder 打印 SliverConstraints + 首末子下标、skipOffstage 双口径对照计数（6/10 钉死根因）| 回归: test/calendar_strip_midstate_test.dart（`_finderOf` 助手）(Ref: ui-console)

**widget 测试点日格定位须按「整格完整落在页矩形内」筛候选，只看中心点会脱靶** — 现象: `tester.tap(find.text('28'))` 报 derived an Offset that would not hit test（偏移落在页顶 y≈15），点后面板未展开、后续 `find.text('重新读取')` 报 Found 0 widgets | 根因: 相邻缓存月页只露几像素在条带视口顶部，该日格中心点虽落在页矩形内，但可见部分已被视口裁剪 + 固定 WeekdayHeader 覆盖，命中测试必脱靶；`evaluate()` 顺序先返回缓存页实例 | 处置: 候选筛选判据由 `screen.contains(r.center)` 收紧为 `screen.contains(r.topLeft) && screen.contains(r.bottomRight)`；取证：遍历 `find.text(...).evaluate()` 逐个打印 `getRect` 与命中判据，对照两份候选矩形定位被遮者 | 回归: test/calendar_fab_fullscreen_test.dart（今日格候选筛选）(Ref: ui-console)

## 待归并（inbox）

- [面板动画] 现象: 点全屏 FAB 后面板塌成细条、满屏黄黑溢出条纹（测试 272 异常） ➔ 根因: Flutter 双机制——AnimationController 默认 lowerBound/upperBound=0..1，animateWith 弹簧值在 px 量级（数百）被钳到 1，必须 AnimationController.unbounded；RenderFlex 固定子件在 flex 兄弟被挤到 0 高时必溢出（fixed 子件不随 flex 收缩），极端挤压布局需 LayoutBuilder 阈值让位 + FittedBox(scaleDown) 兜底，且挤压目标档位应留非退化余量（呼吸条） ➔ 规则: 驱动 px 量级值的 AnimationController 一律 unbounded；可被挤压到 0 的 flex 区域内禁放固定尺寸子件（LayoutBuilder 阈值隐藏或 FittedBox）；挤压式全屏档留 ≥48px 呼吸条（回归钉: test/calendar_fab_fullscreen_test.dart）(Ref: FAB全屏溢出2026-10-27) (Ref: ui-console)

- [日历页] 现象: 进日历页整屏空白，测试报 dependOnInheritedWidgetOfExactType<MediaQuery>() called before initState() completed（14 例挂） ➔ 根因: Flutter 机制双坑——AnimationController 默认 value=0，驱动 FadeTransition 时起点全透明（首帧渲染透明→视觉空白）；State 的 late final 字段初始化器读 MediaQuery/inherited widget，首触若发生在 initState 内即在 initState 期间建立依赖（框架断言禁止） ➔ 规则: initState 里把过渡动画置完成态（value=1.0），入场过渡只在切模式时 forward(from:0) 重播；动画控制器时长写死常量，reduced-motion 等 MediaQuery 依赖判断收敛到 build 期调用点；机械规则=initState/字段初始化器禁读 MediaQuery/Theme 等 inherited widget（回归钉: test/calendar_strip_midstate_test.dart 全组）(Ref: 日历空白屏2026-10-27) (Ref: ui-console)

- [ui] 现象: AppBar 标题槽位（centerTitle 的 title widget）内 InkWell onTap 真机（PLQ110/ColorOS）点不响应，同 AppBar 的 TextButton 正常；widget 测试 tester.tap 一切正常 | 根因: InkWell 的 tap 竞技场在 AppBar 标题槽位真机环境不稳（Impeller/平台手势细节，宿主机无法复现），命中域也偏窄（仅文本+padding） | 处置: 标题类点击直接用 GestureDetector(behavior: HitTestBehavior.opaque)——不依赖 Material 水纹、命中域整个 Padding 区域；不要在 AppBar title 槽放裸 InkWell 承载关键导航 | 回归: test/calendar_year_view_test.dart（点标题进/出年视图两用例）+ 真机点标题切换实测 (Ref: ui-console)
