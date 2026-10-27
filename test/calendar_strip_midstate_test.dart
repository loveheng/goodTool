// 日历滑动条中间态取证：慢拖半页时当前月与相邻月必须同屏渲染。
// 真机复现（PLQ110）：拖拽中途相邻月整片空白——本测试在宿主机复现判定。
// 口径：滑动条是**无限自由滚动**条（框架 Scrollable 承载）——跟手 + 惯性
// 滑行，可停在任意位置（上月尾 + 本月头同屏的中间态是合法停留态，不强
// 吸附月边界）；跨过半页松手后标题落定新月，残差由滚动位置原生保留。
//
// 手势模拟规约：必须逐步 moveBy + pump 推进（单次大步 moveBy 在测试框架
// 中不成手势——速度采样与竞技场需要时间上分离的事件序列）。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goodtools/mcp/calendar_provider.dart';
import 'package:goodtools/repository/marker_repository.dart';
import 'package:goodtools/service/marker_store.dart';
import 'package:goodtools/ui/calendar_page.dart';
import 'package:goodtools/ui/components/calendar_grid.dart';
import 'package:goodtools/ui/theme.dart';
import 'package:goodtools/ui_ports/calendar_port.dart';

/// 空事件源：走 rangeOverview 正常路径（errorCode=null、密度全 0），
/// 网格按普通日渲染——隔离「无数据」与「未渲染」两个变量。
class _EmptyFeed implements CalendarFeedProvider {
  @override
  Future<CalendarQueryResult> query({
    required String rangeStart,
    required String rangeEnd,
    String? timezone,
    List<String>? feedIds,
    bool includeSystem = true,
  }) async =>
      const CalendarQueryResult(<CalendarEvent>[]);

  @override
  Future<List<CalendarFeed>> feeds() async => const <CalendarFeed>[];

  @override
  Future<int> refresh({String? feedId}) async => 0;
}

/// 从树中取文本命中的全部纵向位置（相对页面左上角）。
List<double> _topsOf(WidgetTester tester, Finder f) {
  final out = <double>[];
  for (final w in f.evaluate()) {
    out.add(tester.getRect(find.byWidget(w.widget)).top);
  }
  return out;
}

Rect _stripRect(WidgetTester tester) {
  final viewport = find.descendant(
    of: find.byType(CalendarPage),
    matching: find.byType(Scrollable),
  );
  return tester.getRect(viewport.first);
}

/// 全树口径重查实例（含视口外预挂载缓存页——默认 finder 会漏掉它们）。
Finder _finderOf(Widget w) => find.byWidget(w, skipOffstage: false);

Future<void> _pumpPage(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(brightness: Brightness.dark),
      home: CalendarPage(
        port: CalendarPort(
          feeds: _EmptyFeed(),
          markers: MarkerRepository(store: InMemoryMarkerStore()),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('慢拖半页：相邻月与当前月同屏（中间态无空白带）', (tester) async {
    tester.view.physicalSize = const Size(1272, 2800);
    tester.view.devicePixelRatio = 3.0; // 逻辑 424x933
    addTearDown(tester.view.reset);

    await _pumpPage(tester);

    // 基线（widget 实例身份口径）：±2 预挂载窗口下树内有多页、每个月都有
    // '01'——不能按排序下标猜页序，直接记录每个 '01' 实例的静止 top。
    // 页面 widget 是缓存实例，拖拽跨帧同一实例仍可寻回。
    // 页高从滚动视口实测，不从 '01' 间距推——各月日格副行行高有差异，
    // '01' 页内偏移不恒定。
    // skipOffstage:false——±2 预挂载页在视口外属于「缓存子项」，默认
    // finder 只扫可视子树会漏掉它们，而刚性平移/跨页追踪恰恰靠这些实例。
    final viewport = find.descendant(
      of: find.byType(CalendarPage),
      matching: find.byType(Scrollable),
    );
    final pageHeight = tester.getRect(viewport.first).height;
    expect(pageHeight, greaterThan(300), reason: '页高应为一屏量级');
    final restTops = <Widget, double>{
      for (final w in find.text('01', skipOffstage: false).evaluate())
        w.widget: tester.getRect(_finderOf(w.widget)).top,
    };
    expect(restTops.length, greaterThanOrEqualTo(3),
        reason: '±2 预挂载窗口至少装配 5 页，应有多个 01 实例');
    // 下一个月的 01：±2 窗口下视口外有两页（k=+1 / +2），取近者（k=+1）。
    final nextMonth01 = restTops.entries
        .where((e) => e.value > pageHeight + 1 && e.value < 2 * pageHeight)
        .single
        .key;

    // 慢拖上滑 0.45 页：12 步 × 33px，每步 16ms 逐帧推进。
    final gesture = await tester.startGesture(const Offset(212, 600));
    await tester.pump(const Duration(milliseconds: 16));
    for (var i = 0; i < 12; i++) {
      await gesture.moveBy(const Offset(0, -33));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.pump();

    // 中间态判定：条带整体刚性上移 ≈ 拖拽行程；下月 01 进入视口——
    // 「当前月 + 下月」两月同屏，无空白带。
    for (final w in restTops.keys) {
      final now = tester.getRect(_finderOf(w)).top;
      expect(now, closeTo(restTops[w]! - 396, 1.0),
          reason: '每页应随条带刚性上移 ≈ 拖拽行程 396px');
    }
    final nextTop = tester.getRect(_finderOf(nextMonth01)).top;
    expect(nextTop, lessThan(pageHeight),
        reason: '拖拽半页后相邻月内容应进入视口（两月同屏中间态，无空白带）');

    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('慢放零速：条带停在松手位置（不回弹、不复位）', (tester) async {
    tester.view.physicalSize = const Size(1272, 2800);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await _pumpPage(tester);

    final pageHeight = _stripRect(tester).height;
    // 静止基线：视口内唯一的 '01'（锚点月首行）。各月日格布局同构，
    // 其 top 即「月边界对齐」的参照位置。
    final restTops = <Widget, double>{
      for (final w in find.text('01').evaluate())
        w.widget: tester.getRect(find.byWidget(w.widget)).top,
    };
    final anchor01 = restTops.entries
        .where((e) => e.value > 0 && e.value < pageHeight)
        .single
        .key;
    final t0 = restTops[anchor01]!;

    // 慢拖上滑 80px（8 步 × 10px），随后静置两帧再松手——速度采样归零，
    // 惯性滑行目标 = 松手位移本身，排除速度项的干扰。
    final gesture = await tester.startGesture(const Offset(212, 600));
    await tester.pump(const Duration(milliseconds: 16));
    for (var i = 0; i < 8; i++) {
      await gesture.moveBy(const Offset(0, -10));
      await tester.pump(const Duration(milliseconds: 60));
    }
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));
    await gesture.up();
    await tester.pumpAndSettle();

    // 停驻判定：位移 80px 不足半页 → 不跨月（标题不变），且条带**原样
    // 停在松手位置**（'01' 恰好上移 80px）——既不回弹到 0，也不吸附复位。
    final topAfter = tester.getRect(find.byWidget(anchor01)).top;
    expect(topAfter, closeTo(t0 - 80, 2.0),
        reason: '零速松手后条带应停在松手位置（位移 80px 原样保留）');
  });

  testWidgets('越半慢拖：停在上月尾+本月头中间态，标题落定新月', (tester) async {
    tester.view.physicalSize = const Size(1272, 2800);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await _pumpPage(tester);

    Text titleOf() => tester.widget<Text>(
          find.byWidgetPredicate((w) =>
              w is Text &&
              RegExp(r'^\d{4} 年 \d{1,2} 月$').hasMatch(w.data ?? '')),
        );
    int monthIndex(Text t) {
      final parts = t.data!.replaceAll('月', '').split(' ');
      return int.parse(parts[0]) * 12 + int.parse(parts[2]);
    }

    final pageHeight = _stripRect(tester).height;
    final restTops = <Widget, double>{
      for (final w in find.text('01', skipOffstage: false).evaluate())
        w.widget: tester.getRect(_finderOf(w.widget)).top,
    };
    // 下一个月的 '01'（k=+1 页），落定后它成为标题月页——用实例身份追踪。
    // 期望落点按「同一实例随条带平移精确换算」：各月 '01' 页内基线不等高
    // （副行行高差异），不能跨月借用锚点月基线。
    final nextMonth01 = restTops.entries
        .where((e) => e.value > pageHeight + 1 && e.value < 2 * pageHeight)
        .single
        .key;
    final nextT0 = restTops[nextMonth01]!;
    final before = monthIndex(titleOf());

    // 慢拖上滑「半页 + 20px」，静置归零速度后松手：位移越半页 → 标题
    // 推进一月；残差 = 半页 − 20px 的中间态（两月各占一部分）。
    final drag = pageHeight / 2 + 20;
    final gesture = await tester.startGesture(const Offset(212, 600));
    await tester.pump(const Duration(milliseconds: 16));
    final steps = 12;
    for (var i = 0; i < steps; i++) {
      await gesture.moveBy(Offset(0, -drag / steps));
      await tester.pump(const Duration(milliseconds: 60));
    }
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));
    await gesture.up();
    await tester.pumpAndSettle();

    // 落定判定①：标题推进一个月。
    expect(monthIndex(titleOf()), before + 1, reason: '越半页松手应落定新月');
    // 落定判定②：残差中间态精确保留——滚动位置原样保留（无重锚换算），
    // 该实例 top = 页内基线（nextT0 − 页高）+ 残差（半页 − 20px）；
    // 吸附复位会落在页内基线（少一个残差），回弹则差得更多。
    final residual = pageHeight / 2 - 20;
    final newAnchorTop = tester.getRect(_finderOf(nextMonth01)).top;
    expect(newAnchorTop, closeTo(nextT0 - pageHeight + residual, 2.0),
        reason: '落定后应保留两月同屏残差，不强吸附月边界');
    // 落定判定③：视口上部仍有前一月的日格内容（上月尾 + 本月头同屏）。
    final tailVisible = find
        .byWidgetPredicate((w) =>
            w is Text && RegExp(r'^\d{2}$').hasMatch(w.data ?? ''))
        .evaluate()
        .any((el) {
      final top = tester.getRect(find.byWidget(el.widget)).top;
      return top >= 0 && top < newAnchorTop - 5;
    });
    expect(tailVisible, true, reason: '视口上部应是前一月的月尾内容（中间态）');
  });

  testWidgets('轻快 fling：位移小速度高也前滑至少一月（惯性滑行）', (tester) async {
    tester.view.physicalSize = const Size(1272, 2800);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await _pumpPage(tester);

    Text titleOf() => tester.widget<Text>(
          find.byWidgetPredicate((w) =>
              w is Text &&
              RegExp(r'^\d{4} 年 \d{1,2} 月$').hasMatch(w.data ?? '')),
        );
    int monthIndex(Text t) {
      final parts = t.data!.replaceAll('月', '').split(' ');
      return int.parse(parts[0]) * 12 + int.parse(parts[2]);
    }

    final before = monthIndex(titleOf());

    // 轻快 fling（规范原语 flingFrom）：位移 160px + 速度 3000px/s——
    // 惯性滑行目标 = 位移 + 速度 × 0.3，自由落点；断言至少前滑一月
    // （落点由滑行投影决定，可能跨到第二个月）。
    await tester.flingFrom(const Offset(212, 600), const Offset(0, -160), 3000);
    await tester.pumpAndSettle();

    expect(monthIndex(titleOf()), greaterThanOrEqualTo(before + 1),
        reason: '小位移高速度的 fling 应惯性前滑至少一月');
  });

  testWidgets('取证：滑行落定全程逐帧连续（无跳变帧）', (tester) async {
    tester.view.physicalSize = const Size(1272, 2800);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await _pumpPage(tester);

    final pageHeight = _stripRect(tester).height;

    await tester.flingFrom(const Offset(212, 600), const Offset(0, -160), 3000);

    // 逐帧推进惯性滑行：按 widget 实例身份追踪每个 '01' 的 top——
    // 区分「整条刚性跳变」（所有实例同跳）与「单页重布局跳变」（个别实例跳），
    // 并记录新实例出现帧（换页/新建页标志）。
    // 阈值取半页：单帧位移超半页即真·跳变；合法快甩的弹簧峰速单帧仅
    // ~0.04 页，远低于此，故放行——该断言意在抓「跳一下」。
    var prev = <Widget, double>{};
    var maxJump = 0.0;
    var jumpFrame = -1;
    final appearances = <int, int>{};
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      final now = <Widget, double>{
        for (final w in find.text('01').evaluate())
          w.widget: tester.getRect(find.byWidget(w.widget)).top,
      };
      final fresh = now.keys.where((k) => !prev.containsKey(k)).length;
      if (fresh > 0) appearances[i] = fresh;
      for (final e in now.entries) {
        final p = prev[e.key];
        if (p == null) continue;
        final d = (e.value - p).abs();
        if (d > maxJump) {
          maxJump = d;
          jumpFrame = i;
        }
      }
      prev = now;
    }
    debugPrint('continuity: maxJump=${maxJump.toStringAsFixed(2)}px '
        '@frame$jumpFrame appearances=$appearances');
    expect(maxJump, lessThan(pageHeight * 0.5),
        reason: '滑行全程每个日格逐帧连续，单帧突进超半页即用户可见的「跳一下」');
  });

  testWidgets('取证：fling 后条带运动方向单调（无倒退）', (tester) async {
    tester.view.physicalSize = const Size(1272, 2800);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await _pumpPage(tester);

    // 大行程快甩：位移 900px（≈1.04 页）+ 速度 3000——释放点已越过第 1 页
    // 边界。若滑行目标取整落到身后（第 1 页），弹簧会倒退（用户感知「跳一下」）。
    await tester.flingFrom(const Offset(212, 600), const Offset(0, -900), 3000);

    // 逐帧追踪：上甩翻页过程中，所有已有实例的 top 应单调不增（容差 0.5px）。
    var prev = <Widget, double>{};
    var maxBackward = 0.0;
    var backFrame = -1;
    for (var i = 0; i < 80; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      final now = <Widget, double>{
        for (final w in find.text('01').evaluate())
          w.widget: tester.getRect(find.byWidget(w.widget)).top,
      };
      for (final e in now.entries) {
        final p = prev[e.key];
        if (p == null) continue;
        final back = e.value - p; // 正值 = 实例下移 = 条带倒退
        if (back > maxBackward) {
          maxBackward = back;
          backFrame = i;
        }
      }
      prev = now;
    }
    debugPrint('monotonic: maxBackward=${maxBackward.toStringAsFixed(2)}px '
        '@frame$backFrame');
    expect(maxBackward, lessThan(0.5),
        reason: '上甩翻页全程条带不应倒退——倒退即用户看到的「翻过去又跳回来」');
  });

  testWidgets('标题换字走过渡动画（新旧同帧共存，非直变）', (tester) async {
    tester.view.physicalSize = const Size(1272, 2800);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await _pumpPage(tester);

    Finder titleFinder() => find.byWidgetPredicate((w) =>
        w is Text && RegExp(r'^\d{4} 年 \d{1,2} 月$').hasMatch(w.data ?? ''));
    int monthIndex(Text t) {
      final parts = t.data!.replaceAll('月', '').split(' ');
      return int.parse(parts[0]) * 12 + int.parse(parts[2]);
    }

    final before = monthIndex(tester.widget<Text>(titleFinder()));

    // fling 前滑：标题随条带位置实时换字。轮询逐帧采样（上限 120 帧，
    // 覆盖弹簧滑行时长）——旧标题滑出与新标题滑入期间，两个标题 Text
    // 应同帧共存（AnimatedSwitcher 交叉过渡）；若直变（旧即刻移除），
    // 任何帧都只有一个标题。惯性滑行落点由投影决定（可能跨多月），
    // 故「已换字」判定用 > before 而非恰好 +1。
    await tester.flingFrom(const Offset(212, 600), const Offset(0, -160), 3000);
    var overlapSeen = false;
    var changed = false;
    for (var i = 0; i < 120 && !changed; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      if (titleFinder().evaluate().length >= 2) overlapSeen = true;
      final titles = titleFinder().evaluate().toList();
      if (titles.length == 1 &&
          monthIndex(tester.widget<Text>(find.byWidget(titles.single.widget))) >
              before) {
        changed = true;
      }
    }
    expect(changed, true, reason: 'fling 应完成前滑换字');
    expect(overlapSeen, true,
        reason: '标题换字应有交叉过渡窗口（新旧同帧共存），而不是直接替换');

    await tester.pumpAndSettle();
    expect(monthIndex(tester.widget<Text>(titleFinder())), greaterThan(before),
        reason: '过渡结束后标题应落在前滑后的新月份');
  });

  testWidgets('固定星期表头：全树唯一、拖拽中钉死、数据在其下滚动', (tester) async {
    tester.view.physicalSize = const Size(1272, 2800);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await _pumpPage(tester);

    // 表头全树唯一：页面级固定表头一条，数据页均为无头网格（不重复）。
    final headerFinder = find.byType(WeekdayHeader);
    expect(headerFinder.evaluate().length, 1,
        reason: '星期表头全树只能有一条（固定表头），页内不再内建');
    final fixedTop = tester.getRect(headerFinder).top;

    // 慢拖半页（逐帧推进，不松手）。
    final gesture = await tester.startGesture(const Offset(212, 600));
    await tester.pump(const Duration(milliseconds: 16));
    for (var i = 0; i < 12; i++) {
      await gesture.moveBy(const Offset(0, -33));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.pump();

    // 拖拽中表头钉在原位：rect 与静止时完全一致（不随数据滚动）。
    expect(tester.getRect(headerFinder).top, fixedTop,
        reason: '星期表头必须固定不随数据滚动');
    // 数据确实在其下滚动：'01' 日格随条带移动且相邻月内容已上移。
    final day01Now = _topsOf(tester, find.text('01'))..sort();
    expect(day01Now, isNotEmpty);
    expect(day01Now.first, lessThan(fixedTop + 900),
        reason: '拖拽中途应有月份内容滚入固定表头下方的视口区');

    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('日格 1 号标注所属月份（自由滚动多月在屏可辨分界）', (tester) async {
    tester.view.physicalSize = const Size(1272, 2800);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await _pumpPage(tester);

    // 锚点月（今天所在月）的日格 1 必须渲染「N月」月份标注。自由滚动下
    // 上月尾 + 本月头常同屏，日号连续时靠该标注区分归属月。
    final now = DateTime.now();
    expect(find.text('${now.month}月'), findsAtLeastNWidgets(1),
        reason: '锚点月的 1 号应标注所属月份（如「10月」）');
  });
}
