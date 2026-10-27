// 年视图回归：月↔年模式切换（点标题可见通道 + 双指捏合手势通道）、
// 年页 12 迷你月渲染、点迷你月落月并滑行到目标月。
//
// 口径：年条带与月条带同构（ListView + GlidePhysics + ±2 预挂载）；
// 捏合检测走 Listener 原始指针（widget 测试可模拟双指），单指滚动不受影响。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goodtools/mcp/calendar_provider.dart';
import 'package:goodtools/repository/marker_repository.dart';
import 'package:goodtools/service/marker_store.dart';
import 'package:goodtools/ui/calendar_page.dart';
import 'package:goodtools/ui/components/calendar_grid.dart';
import 'package:goodtools/ui/theme.dart';
import 'package:goodtools/ui_ports/calendar_port.dart';

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

Finder _titleFinder() => find.byWidgetPredicate(
      (w) =>
          w is Text &&
          (RegExp(r'^\d{4} 年 \d{1,2} 月$').hasMatch(w.data ?? '') ||
              RegExp(r'^\d{4} 年$').hasMatch(w.data ?? '') ||
              RegExp(r'^\d{4} 年起$').hasMatch(w.data ?? '')),
    );

/// 当前在屏（视口内、且占满大半屏高）的 YearGrid 元素。
///
/// 年条带预挂载 ±2 页会同时建出相邻年页，但 ListView 视口同一时刻只应让
/// 居中那一页真正在屏——这是「无两页同屏错位」（itemExtent 与视口失配）的
/// 真正判据；也是点迷你月时避开相邻年页同文本（如两个「06月」）多匹配的办法。
Element _visibleYearGrid(WidgetTester tester) {
  final logical = tester.view.physicalSize / tester.view.devicePixelRatio;
  final screen = Rect.fromLTWH(0, 0, logical.width, logical.height);
  for (final e in tester.elementList(find.byType(YearGrid))) {
    final box = e.findRenderObject() as RenderBox;
    final rect = box.localToGlobal(Offset.zero) & box.size;
    if (screen.contains(rect.center)) return e;
  }
  throw StateError('未找到在屏的 YearGrid');
}

int _countVisibleYearGrid(WidgetTester tester) {
  final logical = tester.view.physicalSize / tester.view.devicePixelRatio;
  final screen = Rect.fromLTWH(0, 0, logical.width, logical.height);
  var n = 0;
  for (final e in tester.elementList(find.byType(YearGrid))) {
    final box = e.findRenderObject() as RenderBox;
    final rect = box.localToGlobal(Offset.zero) & box.size;
    if (screen.contains(rect.center)) n++;
  }
  return n;
}

void main() {
  testWidgets('点标题三级循环：月→年→年份块→月（可见控件逐级放大/缩进）', (tester) async {
    tester.view.physicalSize = const Size(1272, 2800);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await _pumpPage(tester);

    expect(tester.widget<Text>(_titleFinder()).data, matches(r'^\d{4} 年 \d{1,2} 月$'));

    // 点标题 → 年视图（第一级放大）。
    await tester.tap(_titleFinder());
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(_titleFinder()).data, matches(r'^\d{4} 年$'),
        reason: '年视图标题应为「YYYY 年」');
    expect(find.byType(YearGrid), findsOneWidget);
    // 12 个迷你月月名：1 月带年份（「YYYY年1月」），2~12 月为「0X月」。
    expect(
      find.byWidgetPredicate(
          (w) => w is Text && RegExp(r'^\d{2}月$').hasMatch(w.data ?? '')),
      findsNWidgets(11),
      reason: '年页应有 11 个「0X月」迷你月（2~12 月）',
    );
    expect(
      find.byWidgetPredicate(
          (w) => w is Text && RegExp(r'^\d{4}年1月$').hasMatch(w.data ?? '')),
      findsOneWidget,
      reason: '1 月迷你月应标注所属年份「YYYY年1月」',
    );

    // 再点标题 → 年份块视图（第二级放大：最粗层，12 年 4×3 数字阵）。
    await tester.tap(_titleFinder());
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(_titleFinder()).data, matches(r'^\d{4} 年起$'),
        reason: '年份块视图标题应为「YYYY 年起」');
    expect(find.byType(YearNumberGrid), findsWidgets,
        reason: '年份块视图应渲染 YearNumberGrid');
    expect(find.byType(YearGrid), findsNothing,
        reason: '离开年视图后 YearGrid 不应在屏');

    // 再点标题 → 回月视图（三级循环闭合：缩回最细层）。
    await tester.tap(_titleFinder());
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(_titleFinder()).data,
        matches(r'^\d{4} 年 \d{1,2} 月$'),
        reason: '回月视图标题应为「YYYY 年 M 月」');
    expect(find.byType(YearNumberGrid), findsNothing);
    expect(find.byType(YearGrid), findsNothing);
  });

  testWidgets('年视图点迷你月：落月视图且标题落定该月', (tester) async {
    tester.view.physicalSize = const Size(1272, 2800);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await _pumpPage(tester);
    final before =
        tester.widget<Text>(_titleFinder()).data!; // 「YYYY 年 M 月」

    await tester.tap(_titleFinder());
    await tester.pumpAndSettle();

    // 点一个非当前月的迷你月（取「06月」，当前 10 月落月断言更清晰）。
    await tester.tap(find.text('06月'));
    await tester.pumpAndSettle();

    final after = tester.widget<Text>(_titleFinder()).data!;
    expect(after, matches(r'^\d{4} 年 6 月$'),
        reason: '点迷你月应落月视图并滑行到该月');
    expect(after, isNot(before), reason: '落月目标月应与进入前标题月不同');
    expect(find.byType(YearGrid), findsNothing);
  });

  testWidgets('双指捏合收缩进年视图、张开回月视图（Listener 原始指针通道）', (tester) async {
    tester.view.physicalSize = const Size(1272, 2800);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await _pumpPage(tester);

    // 双指收缩：两指从相距 300px 各自向中间移动 120px（span 300→60）。
    final g1 = await tester.startGesture(const Offset(100, 500));
    final g2 = await tester.startGesture(const Offset(400, 500));
    await tester.pump(const Duration(milliseconds: 16));
    for (var i = 0; i < 8; i++) {
      await g1.moveBy(const Offset(15, 0));
      await g2.moveBy(const Offset(-15, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await g1.up();
    await g2.up();
    await tester.pumpAndSettle();

    expect(tester.widget<Text>(_titleFinder()).data, matches(r'^\d{4} 年$'),
        reason: '双指收缩应进年视图');

    // 双指张开：span 200→400（≥1.25 倍）。
    final g3 = await tester.startGesture(const Offset(200, 500));
    final g4 = await tester.startGesture(const Offset(400, 500));
    await tester.pump(const Duration(milliseconds: 16));
    for (var i = 0; i < 8; i++) {
      await g3.moveBy(const Offset(-15, 0));
      await g4.moveBy(const Offset(15, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await g3.up();
    await g4.up();
    await tester.pumpAndSettle();

    expect(tester.widget<Text>(_titleFinder()).data, matches(r'^\d{4} 年 \d{1,2} 月$'),
        reason: '年视图双指张开应回月视图');
  });

  testWidgets('年条带纵滑跨年：标题年实时换字、仅一页在屏', (tester) async {
    tester.view.physicalSize = const Size(1272, 2800);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await _pumpPage(tester);
    await tester.tap(_titleFinder());
    await tester.pumpAndSettle();
    expect(_countVisibleYearGrid(tester), 1,
        reason: '进年视图应有且仅一页在屏');

    int yearOf() => int.parse(
        RegExp(r'\d{4}').firstMatch(tester.widget<Text>(_titleFinder()).data!)!.group(0)!);
    final y0 = yearOf();

    // 向上快甩 → 进未来年份（动量投影 < 2.5 页阈值，不触发年→年份块放大）。
    final c = tester.getCenter(find.byType(YearGrid));
    await tester.flingFrom(c, const Offset(0, -2000), 4000);
    await tester.pumpAndSettle();
    final y1 = yearOf();
    expect(y1, greaterThan(y0), reason: '纵滑向上应进未来年份');
    expect(_countVisibleYearGrid(tester), 1,
        reason: '纵滑后仅一页在屏（无两页同屏错位 / itemExtent 失配）');

    // 向下快甩 → 回过去年份。
    await tester.flingFrom(c, const Offset(0, 2000), 4000);
    await tester.pumpAndSettle();
    final y2 = yearOf();
    expect(y2, lessThan(y1), reason: '纵滑向下应回过去年份');
  });

  testWidgets('年条带纵滑后点迷你月落月对位（年须为滚动后年、月须为所点月）',
      (tester) async {
    tester.view.physicalSize = const Size(1272, 2800);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await _pumpPage(tester);
    await tester.tap(_titleFinder());
    await tester.pumpAndSettle();

    // 纵滑进未来年份，使当前年 != 基准年。
    final c = tester.getCenter(find.byType(YearGrid));
    await tester.flingFrom(c, const Offset(0, -2000), 4000);
    await tester.pumpAndSettle();
    int yearOf() => int.parse(
        RegExp(r'\d{4}').firstMatch(tester.widget<Text>(_titleFinder()).data!)!.group(0)!);
    final scrolledYear = yearOf();

    // 点「在屏居中」年页内的迷你月「06月」：落月须精确对位到「滚动后年 的 6 月」。
    // 预挂载相邻年页也含「06月」，必须限定在屏年页内，否则会点错年。
    final grid = _visibleYearGrid(tester);
    await tester.tap(
      find.descendant(of: find.byWidget(grid.widget), matching: find.text('06月')),
    );
    await tester.pumpAndSettle();
    final after = tester.widget<Text>(_titleFinder()).data!;
    expect(after, '$scrolledYear 年 6 月',
        reason: '纵滑后点迷你月须落「滚动后年·所点月」，而非基准年');
    expect(find.byType(YearGrid), findsNothing);
  });
}
