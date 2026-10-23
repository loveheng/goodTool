import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goodtools/ui/calculator_page.dart';
import 'package:goodtools/ui/components/block_canvas.dart';
import 'package:goodtools/ui/theme.dart';

/// 计算器区块页验收测试（calculator-blocks.md §7 的可机械断言部分）。
///
/// 真机手动项（软键盘闪烁 / 沉降视觉 / 密度）不在本文件覆盖。
void main() {
  Future<void> pumpPage(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(brightness: Brightness.light),
        home: const Scaffold(body: CalculatorPage()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('首帧可构建：初始草稿四块均带结果', (tester) async {
    await pumpPage(tester);
    expect(find.byType(CalculatorPage), findsOneWidget);
    // 初始草稿：1200 * 85% → 1020；10 km to mi → 6.213...；ans + 50 → 1070；
    // 0.1 + 0.2 → 0.3（Decimal 主链路精确）。最终 ans（0.3）同时出现在汇总条。
    expect(find.text('1020'), findsOneWidget);
    expect(find.text('0.3'), findsNWidgets(2));
    expect(find.byType(TextField), findsNWidgets(5)); // 4 实块 + 1 ghost
  });

  testWidgets('ans 级联：修改上游块后下游块结果级联刷新（受控单源）', (tester) async {
    await pumpPage(tester);
    // 初始：块3 = ans + 50，ans 取上一成功块（块2 换算 6.2137…）→ 56.2137…。
    expect(find.text('56.2137119223733395'), findsOneWidget);
    // 修改块1 → 仅块1 结果刷新（块3 的 ans 源是块2）。
    await tester.enterText(find.byType(TextField).first, '2000 * 85%');
    await tester.pump(const Duration(milliseconds: 160));
    await tester.pumpAndSettle();
    expect(find.text('1700'), findsOneWidget);
    expect(find.text('56.2137119223733395'), findsOneWidget);
    // 修改块2（ans 源）→ 块3 级联刷新：0 + 50 = 50。
    await tester.enterText(find.byType(TextField).at(1), '0 + 0');
    await tester.pump(const Duration(milliseconds: 160));
    await tester.pumpAndSettle();
    expect(find.text('50'), findsOneWidget);
  });

  testWidgets('上游故障可视化：上游失败且无可用结果时下游标 UPSTREAM_ERROR (Line N)',
      (tester) async {
    await pumpPage(tester);
    // 构造：块1 真故障（非法字符，非输入中瞬态）、块2 清空（ans 不可用）
    // → 块3 归因根因行 Line 1。
    await tester.enterText(find.byType(TextField).first, '1200 \$ 85%');
    await tester.enterText(find.byType(TextField).at(1), '');
    await tester.pump(const Duration(milliseconds: 160));
    await tester.pumpAndSettle();
    expect(find.textContaining('UPSTREAM_ERROR (Line 1)'), findsOneWidget);
    // 修复上游后下游级联恢复（块1 = 1700 → ans + 50 = 1750）。
    await tester.enterText(find.byType(TextField).first, '2000 * 85%');
    await tester.pump(const Duration(milliseconds: 160));
    await tester.pumpAndSettle();
    expect(find.textContaining('UPSTREAM_ERROR'), findsNothing);
    expect(find.text('1750'), findsOneWidget);
  });

  testWidgets('输入中瞬态抑制：未完成语法淡灰「输入中」不闪红，完成后出结果',
      (tester) async {
    await pumpPage(tester);
    // 中途态 `1 +` → UNEXPECTED_TOKEN 属输入中瞬态：淡灰「输入中…」，
    // 不出现红色机器码。
    await tester.enterText(find.byType(TextField).first, '1 +');
    await tester.pump(const Duration(milliseconds: 160));
    await tester.pumpAndSettle();
    expect(find.text('输入中…'), findsOneWidget);
    expect(find.text('UNEXPECTED_TOKEN'), findsNothing);
    // 半截变量名 `10 km`（单位打了一半）同样抑制为输入中。
    await tester.enterText(find.byType(TextField).first, '10 km');
    await tester.pump(const Duration(milliseconds: 160));
    await tester.pumpAndSettle();
    expect(find.text('输入中…'), findsOneWidget);
    expect(find.text('UNDEFINED_VARIABLE'), findsNothing);
    // 补全 → 出结果，输入中态消失。
    await tester.enterText(find.byType(TextField).first, '10 km to mi');
    await tester.pump(const Duration(milliseconds: 160));
    await tester.pumpAndSettle();
    expect(find.text('输入中…'), findsNothing);
    // 本行结果 + 下游 ans 级联 + 汇总条共 3 处含该值。
    expect(find.textContaining('6.2137'), findsWidgets);
  });

  testWidgets('非法字符软校验：放行不吞键 + 结果位 INVALID_CHARS', (tester) async {
    await pumpPage(tester);
    await tester.enterText(find.byType(TextField).first, '1200 \$ 85%');
    await tester.pumpAndSettle();
    // 输入放行（不吞键）：文本仍在控制器。
    final field = tester
        .widgetList<TextField>(find.byType(TextField))
        .first;
    expect(field.controller!.text, '1200 \$ 85%');
    expect(find.text('INVALID_CHARS'), findsOneWidget);
  });

  testWidgets('聚焦块光标保护：级联重算不重置当前块光标位置', (tester) async {
    await pumpPage(tester);
    final controller = tester
        .widgetList<TextField>(find.byType(TextField))
        .first
        .controller!;
    await tester.showKeyboard(find.byType(TextField).first);
    controller.value = TextEditingValue(
      text: '1200 * 85% extra',
      selection: const TextSelection.collapsed(offset: 5),
    );
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    // 级联刷新后 selection 不被回写重置（spec §5.2 光标保护硬约束）。
    expect(controller.selection, const TextSelection.collapsed(offset: 5));
  });

  testWidgets('ghost 提交：末块输入新算式即追加为新区块并出结果', (tester) async {
    await pumpPage(tester);
    await tester.enterText(find.byType(TextField).last, '2 ^ 10');
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNWidgets(6)); // 5 实块 + 1 ghost
    expect(find.text('1024'), findsNWidgets(2)); // 结果槽 + 汇总条最终 ans
  });

  testWidgets('Gutter 行号：常驻编号 + 错误行标红（微字轨）', (tester) async {
    await pumpPage(tester);
    expect(find.text('01'), findsOneWidget);
    expect(find.text('04'), findsOneWidget);
  });

  testWidgets('Telemetry 汇总条：有效行数 / 最终 ans / 累计总和实时刷新', (tester) async {
    await pumpPage(tester);
    // 初始：4 有效行，最终 ans = 0.3，累计总和 = 1020 + 6.2137 + 56.2137 + 0.3 ≈ 1082.73。
    expect(find.text('4'), findsOneWidget);
    expect(find.text('1082.73'), findsOneWidget);
    // 改块1 → 汇总实时刷新：2000*85% = 1700 → 总和 ≈ 1762.73。
    await tester.enterText(find.byType(TextField).first, '2000 * 85%');
    await tester.pump(const Duration(milliseconds: 160));
    await tester.pumpAndSettle();
    expect(find.text('1762.73'), findsOneWidget);
  });

  testWidgets('Reader Mode：切换后为纯文本层（可跨行划选），可返回编辑', (tester) async {
    await pumpPage(tester);
    await tester.tap(find.byIcon(Icons.article_outlined));
    await tester.pumpAndSettle();
    expect(find.byType(SelectableText), findsOneWidget);
    expect(find.byType(BlockCanvas), findsNothing);
    // 返回编辑：画布恢复。
    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();
    expect(find.byType(BlockCanvas), findsOneWidget);
  });

  testWidgets('纸面清空：二次确认后归零至单行', (tester) async {
    await pumpPage(tester);
    await tester.tap(find.byIcon(Icons.delete_sweep_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '清空'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNWidgets(2)); // 1 空块 + 1 ghost
  });
}
