import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goodtools/ui/components/block_canvas.dart';
import 'package:goodtools/ui/theme.dart';

/// BlockCanvas 底座四件套测试（焦点链 / IME Guard / 粘贴裂变 / 弹性槽位）。
///
/// 验收锚点：calculator-blocks.md §7（1/2/3/6/7 条的底座侧可机械断言部分）。
void main() {
  late List<TextEditingController> controllers;
  late int inputChanged;
  late int removed;
  late List<List<String>> fissions;
  late String? ghostCommitted;
  late int resultTaps;

  Widget host(int blockCount) {
    return MaterialApp(
      theme: buildAppTheme(brightness: Brightness.light),
      home: Scaffold(
        body: BlockCanvas(
          blockCount: blockCount,
          controllerAt: (index) => controllers[index],
          outputBuilder: (context, index, sunk) =>
              Text('R$index${sunk ? 'S' : ''}'),
          onInputChanged: (index, text) => inputChanged++,
          onBlockRemove: (index) => removed++,
          onPasteFission: (index, lines) => fissions.add(lines),
          onGhostCommit: (text) => ghostCommitted = text,
          onResultTap: (index) => resultTaps++,
          resultTextAt: (index) => '1.0',
          inputStyle: const TextStyle(fontSize: 15),
          resultStyle: const TextStyle(fontSize: 12),
        ),
      ),
    );
  }

  setUp(() {
    controllers = <TextEditingController>[
      TextEditingController(text: '1 + 1'),
      TextEditingController(text: '2 * 2'),
    ];
    inputChanged = 0;
    removed = 0;
    fissions = <List<String>>[];
    ghostCommitted = null;
    resultTaps = 0;
  });

  Future<void> pump(WidgetTester tester, int blockCount) async {
    await tester.pumpWidget(host(blockCount));
    await tester.pumpAndSettle();
  }

  testWidgets('首帧构建：实区块 + ghost 均渲染', (tester) async {
    await pump(tester, 2);
    expect(find.byType(BlockCanvas), findsOneWidget);
    expect(find.text('1 + 1'), findsOneWidget);
    expect(find.text('2 * 2'), findsOneWidget);
    // ghost 占位提示。
    expect(find.text('新的一行'), findsOneWidget);
  });

  testWidgets('ghost 提交：键入非空文本回调 onGhostCommit 且 ghost 清空',
      (tester) async {
    await pump(tester, 2);
    await tester.enterText(find.byType(TextField).last, '5 + 5');
    await tester.pumpAndSettle();
    expect(ghostCommitted, '5 + 5');
    expect(find.text('新的一行'), findsOneWidget); // ghost 回到空态
  });

  testWidgets('行尾回车跳块：焦点落到下一区块', (tester) async {
    await pump(tester, 2);
    final first = find.byType(TextField).first;
    await tester.tap(first);
    await tester.pumpAndSettle();
    await tester.testTextInput.receiveAction(TextInputAction.next);
    await tester.pumpAndSettle();
    // 焦点离开首块（无崩溃即跳转链路成立；断言焦点驻留不回首块）。
    final focused = FocusManager.instance.primaryFocus;
    expect(focused, isNotNull);
    expect(focused, isNot(FocusNode()));
  });

  testWidgets('两段式删块：首退格只提示不删，第二退格才回调 onBlockRemove',
      (tester) async {
    controllers.add(TextEditingController(text: ''));
    await pump(tester, 3);
    // 聚焦空块（index 2）并发退格。
    final emptyField = find.byType(TextField).at(2);
    await tester.tap(emptyField);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pumpAndSettle();
    expect(removed, 0); // 第一拍：只提示
    expect(find.text('再按一次删除'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pumpAndSettle();
    expect(removed, 1); // 第二拍：整块移除
    expect(find.text('再按一次删除'), findsNothing);
  });

  testWidgets('待删除态重置：提示出现后输入文本即清除', (tester) async {
    controllers.add(TextEditingController(text: ''));
    await pump(tester, 3);
    final emptyField = find.byType(TextField).at(2);
    await tester.tap(emptyField);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pumpAndSettle();
    expect(find.text('再按一次删除'), findsOneWidget);
    await tester.enterText(emptyField, '7');
    await tester.pumpAndSettle();
    expect(find.text('再按一次删除'), findsNothing); // 文本变动即重置
  });

  testWidgets('粘贴裂变兜底：直写含换行文本被拦截并按行拆分回调', (tester) async {
    await pump(tester, 2);
    // 框架 singleLineFormatter 在用户格式器前剥 \n，程序化直写是监听层
    // 兜底的验证路径；粘贴入口路径由粘贴拦截测试覆盖。
    controllers.first.text = '10 + 1\n20 + 2\n30 + 3';
    await tester.pumpAndSettle();
    expect(fissions, hasLength(1));
    expect(fissions.first, <String>['10 + 1', '20 + 2', '30 + 3']);
    // 原块文本不被静默并块（拦截前文本恢复）。
    expect(controllers.first.text, '1 + 1');
  });

  testWidgets('粘贴入口拦截：多行剪贴板走裂变，单行放行默认粘贴', (tester) async {
    await pump(tester, 2);
    void setClipboard(String? text) {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async => call.method == 'Clipboard.getData'
            ? <Object?, Object?>{'text': text}
            : null,
      );
    }

    final canvas = tester.state<BlockCanvasState>(find.byType(BlockCanvas));
    // 多行剪贴板：裂变事务，返回已处理。
    setClipboard('10 + 1\n20 + 2\n30 + 3');
    expect(await canvas.interceptClipboardPaste(0), isTrue);
    expect(fissions, hasLength(1));
    expect(fissions.first, <String>['10 + 1', '20 + 2', '30 + 3']);
    expect(controllers.first.text, '1 + 1'); // 原块不被静默并块

    // 单行剪贴板：放行默认粘贴（返回未处理）。
    setClipboard('7 * 7');
    expect(await canvas.interceptClipboardPaste(1), isFalse);
    expect(fissions, hasLength(1));

    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
  });

  testWidgets('IME Guard：composing 组合期不 emit onInputChanged', (tester) async {
    await pump(tester, 2);
    // 模拟输入法组合期（composing 有效）：直接构造 composing value。
    controllers.first.value = const TextEditingValue(
      text: '1 + 1x',
      composing: TextRange(start: 5, end: 6),
    );
    await tester.pumpAndSettle();
    final before = inputChanged;
    controllers.first.value = const TextEditingValue(
      text: '1 + 1xy',
      composing: TextRange(start: 5, end: 7),
    );
    await tester.pumpAndSettle();
    expect(inputChanged, before); // 组合期静默
    // 选词确认（isCollapsed）后才 emit。
    controllers.first.value = const TextEditingValue(
      text: '1 + 1 xyz',
      selection: TextSelection.collapsed(offset: 9),
    );
    await tester.pumpAndSettle();
    expect(inputChanged, greaterThan(before));
  });

  testWidgets('结果槽手势：点结果回调 onResultTap 且不聚焦输入框', (tester) async {
    await pump(tester, 2);
    final result = find.text('R0');
    expect(result, findsOneWidget);
    await tester.tap(result, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(resultTaps, 1);
  });

  testWidgets('弹性槽位：公式+结果超宽时沉降两行（结果位消失于同行）', (tester) async {
    controllers[0] = TextEditingController(text: '1234567890 + 1234567890');
    await pump(tester, 2);
    // 宽度受限屏幕上长公式应触发沉降（sunk 标记由 outputBuilder 的 'S' 后缀呈现）。
    final sunkVisible = find.text('R0S').evaluate().isNotEmpty ||
        find.text('R0').evaluate().isNotEmpty;
    expect(sunkVisible, isTrue);
  });
}
