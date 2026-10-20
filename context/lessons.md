---
dev-loop: lessons
format: v1
epic: global
total-merged: 1
last-merge: 2026-10-20
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

## 构建（Android 工具链 · 2026-10-20 归并自 ui-console）

**AGP 8+ 的 AIDL 编译器默认关闭** — 现象: `McpBinderService.kt` 的 `import com.zzh.goodhub.mcp.*` 全部 `Unresolved reference 'zzh'`（8 处），但仓内 `src/main/aidl/com/zzh/goodhub/mcp/` 的 `.aidl` 源**确实存在** | 根因: 自 AGP 8 起 AIDL 编译**不再默认开启**，未写 `buildFeatures { aidl = true }` 则 `.aidl` 不生成类，import 全部落空——**文件在 ≠ 会被编译** | 处置: `android/app/build.gradle.kts` 增 `buildFeatures { aidl = true }` | 回归: `toolbox run build-apk`（修后 APK 编译通过，154M debug 全架构）
