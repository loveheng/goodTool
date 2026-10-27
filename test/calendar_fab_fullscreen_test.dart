// FAB 全屏切换复现取证：点日格开面板 → 点 FAB 全屏 → 再点退出。
// 复现真机反馈「事件的全屏按钮点击之后就能复现 bug」——本测试在宿主机
// 驱动完整链路，异常由 testWidgets 自动捕获（RenderFlex overflow /
// framework assert 均判失败）。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goodtools/mcp/calendar_provider.dart';
import 'package:goodtools/repository/marker_repository.dart';
import 'package:goodtools/service/marker_store.dart';
import 'package:goodtools/ui/calendar_page.dart';
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
  tester.view.physicalSize = const Size(1272, 2800);
  tester.view.devicePixelRatio = 3.0; // 逻辑 424x933
  addTearDown(tester.view.reset);
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
  testWidgets('FAB 全屏切换链路：开面板 → 全屏 → 退出全屏 → 关面板', (tester) async {
    await _pumpPage(tester);

    // 1. 点日格开面板（选中今天，默认半屏）。±2 预挂载缓存页不是 Offstage
    // （只是位于视口外），finder 照样找得到、命中测试必脱靶——按屏幕矩形
    // 过滤，只点真正在屏内的今日格。
    final today = find.text(DateTime.now().day.toString().padLeft(2, '0'));
    expect(today, findsWidgets);
    final screen = tester.getRect(find.byType(CalendarPage));
    // 收紧为「整格完整落在页矩形内」：相邻缓存月页可能只露几像素在条带视口
    // 顶部（中心点仍在页矩形内，但被视口裁剪/固定 WeekdayHeader 遮住，tap 必脱靶）。
    final onScreen = today.evaluate().map((e) => e.widget).where((w) {
      final r = tester.getRect(find.byWidget(w));
      return screen.contains(r.topLeft) && screen.contains(r.bottomRight);
    }).toList();
    expect(onScreen, isNotEmpty, reason: '今日格应在屏内');
    final cell = find.ancestor(
      of: find.byWidget(onScreen.first),
      matching: find.byType(InkWell),
    );
    expect(cell, findsOneWidget, reason: '今日格应有 InkWell 热区');
    await tester.tap(cell);
    await tester.pumpAndSettle();
    expect(find.text('重新读取'), findsOneWidget, reason: '面板应已展开（空态+重试）');

    // 2. 点 FAB → 全屏。
    final fab = find.byTooltip('日程全屏');
    expect(fab, findsOneWidget, reason: '面板打开+FAB 可见');
    await tester.tap(fab);
    await tester.pumpAndSettle();

    // 3. FAB 图标/tooltip 应翻转为「退出全屏」。
    expect(find.byTooltip('退出全屏'), findsOneWidget,
        reason: '全屏后 FAB tooltip 应翻转');

    // 4. 再点 FAB → 退回半屏。
    await tester.tap(find.byTooltip('退出全屏'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('日程全屏'), findsOneWidget, reason: '退出后应翻回');

    // 5. 点把手关闭面板（日期行即关闭热区；「重新读取」是重试按钮不是关闭）。
    await tester.tap(find.textContaining('周').first, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.byTooltip('日程全屏'), findsNothing, reason: '面板关闭后 FAB 应消失');
  });
}
