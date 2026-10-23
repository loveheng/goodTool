import 'package:flutter_test/flutter_test.dart';
import 'package:goodtools/ui_ports/calculator_port.dart';

void main() {
  const port = CalculatorPort();

  group('evalLine（Soulver 行内调度器）', () {
    test('空行返回 null', () {
      expect(port.evalLine(''), isNull);
      expect(port.evalLine('   '), isNull);
    });

    test('百分号后缀归一：1200 * 85% = 1020', () {
      final view = port.evalLine('1200 * 85%');
      expect(view!.ok, isTrue);
      expect(view.numeric, '1020');
    });

    test('中文全角符号归一：（1+2）×3 = 9', () {
      final view = port.evalLine('（1+2）×3');
      expect(view!.ok, isTrue);
      expect(view.numeric, '9');
    });

    test('单位换算：10 km to mi', () {
      final view = port.evalLine('10 km to mi');
      expect(view!.ok, isTrue);
      expect(view.text, contains('mi'));
    });

    test('中文映射：10 公里 to mi 与 10 km to mi 等值', () {
      final zh = port.evalLine('10 公里 to mi');
      final en = port.evalLine('10 km to mi');
      expect(zh!.ok, isTrue);
      expect(zh.numeric, en!.numeric);
    });

    test('中文全链路：10 公里 换算 英里（连接字 + 中文单位）', () {
      final view = port.evalLine('10 公里 换算 英里');
      final en = port.evalLine('10 km to mi');
      expect(view!.ok, isTrue);
      expect(view.numeric, en!.numeric);
      // 出参回显规范单位 id（与 MCP unit_convert 同口径），不回显原文别名。
      expect(view.text, contains('mi'));
    });

    test('单位换算数值部分支持表达式：2*10 km to mi = 20km 换算值', () {
      final expr = port.evalLine('2*10 km to mi');
      final expected = port.evalLine('20 km to mi');
      expect(expr!.ok, isTrue);
      expect(expr.numeric, expected!.numeric);
    });

    test('ans 引用上一行结果：ans + 50', () {
      final view = port.evalLine('ans + 50', ans: '1020');
      expect(view!.ok, isTrue);
      expect(view.numeric, '1070');
    });

    test('ans 大小写不敏感', () {
      final view = port.evalLine('ANS + 1', ans: '9');
      expect(view!.ok, isTrue);
      expect(view.numeric, '10');
    });

    test('ans 引用失败带机器码不静默', () {
      final view = port.evalLine('ans + 50');
      expect(view!.ok, isFalse);
      expect(view.errorCode, 'ANS_UNAVAILABLE');
    });

    test('非法表达式透传内核错误码', () {
      final view = port.evalLine('1 +');
      expect(view!.ok, isFalse);
      expect(view.errorCode, isNotNull);
    });
  });
}
