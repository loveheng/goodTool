library;

/// BracketPairFormatter 单测：括号配对三件套（补全 / 跳过 / 配对删除）纯逻辑。
///
/// 直接测 `applyBracketPair` 纯函数（formatter 是薄壳）；以「旧值 + 模拟
/// 击键产生的新值」为输入，断言修正后的新值与光标。

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goodtools/ui/components/bracket_pair_formatter.dart';

TextEditingValue _val(String text, int cursor) => TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: cursor),
    );

/// 模拟在 [cursor] 处击键 [key]（插入字符串）产生的「未修正新值」。
TextEditingValue _typed(String text, int cursor, String key) => TextEditingValue(
      text: '${text.substring(0, cursor)}$key${text.substring(cursor)}',
      selection: TextSelection.collapsed(offset: cursor + key.length),
    );

/// 模拟光标 [cursor] 处 Backspace（删光标前字符）产生的「未修正新值」。
TextEditingValue _backspaced(String text, int cursor) => TextEditingValue(
      text: '${text.substring(0, cursor - 1)}${text.substring(cursor)}',
      selection: TextSelection.collapsed(offset: cursor - 1),
    );

void main() {
  group('括号补全：输入 ( 成对插入，光标居中', () {
    test('空行输入 (', () {
      final out = applyBracketPair(_val('', 0), _typed('', 0, '('));
      expect(out.text, '()');
      expect(out.selection.baseOffset, 1);
    });

    test('行中输入 (（s(qrt 场景）', () {
      final out = applyBracketPair(_val('2+3', 1), _typed('2+3', 1, '('));
      expect(out.text, '2()+3');
      expect(out.selection.baseOffset, 2);
    });

    test('非括号字符不干预', () {
      final out = applyBracketPair(_val('12', 2), _typed('12', 2, '3'));
      expect(out.text, '123');
      expect(out.selection.baseOffset, 3);
    });

    test('输入 ) 无配对可跳过时正常插入', () {
      final out = applyBracketPair(_val('(1', 2), _typed('(1', 2, ')'));
      expect(out.text, '(1)');
      expect(out.selection.baseOffset, 3);
    });
  });

  group('括号跳过：光标前是 ) 再输入 ) 只右移', () {
    test('行尾 (1|) 输入 )', () {
      final out = applyBracketPair(_val('(1)', 2), _typed('(1)', 2, ')'));
      expect(out.text, '(1)'); // 文本不变——未重复插入
      expect(out.selection.baseOffset, 3); // 光标右移
    });

    test('行中 (1|)+2 输入 )', () {
      final out =
          applyBracketPair(_val('(1)+2', 2), _typed('(1)+2', 2, ')'));
      expect(out.text, '(1)+2');
      expect(out.selection.baseOffset, 3);
    });
  });

  group('配对删除：删 () 的 ( 连 ) 一起删', () {
    test('空括号对 (|) Backspace', () {
      final out = applyBracketPair(_val('()', 1), _backspaced('()', 1));
      expect(out.text, '');
      expect(out.selection.baseOffset, 0);
    });

    test('行中 2+()−3 括号对 Backspace', () {
      final out = applyBracketPair(
          _val('2+()-3', 3), _backspaced('2+()-3', 3));
      expect(out.text, '2+-3');
      expect(out.selection.baseOffset, 2);
    });

    test('括号内有内容时只删一个字符（不误删）', () {
      final out = applyBracketPair(_val('(1)', 2), _backspaced('(1)', 2));
      expect(out.text, '()');
      expect(out.selection.baseOffset, 1);
    });
  });

  group('边界：不干预的编辑一律放行', () {
    test('非折叠选区（选中替换）不干预', () {
      final old = TextEditingValue(
        text: '(ab)',
        selection: const TextSelection(baseOffset: 1, extentOffset: 3),
      );
      final newV = const TextEditingValue(text: '(d)')
          .copyWith(selection: const TextSelection.collapsed(offset: 2));
      expect(applyBracketPair(old, newV), newV);
    });

    test('多字符粘贴（长度 +>1）不干预', () {
      final out = applyBracketPair(_val('1', 1), _typed('1', 1, '()'));
      expect(out.text, '1()');
      expect(out.selection.baseOffset, 3);
    });

    test('IME 组合中不干预', () {
      final old = _val('', 0).copyWith(
        composing: const TextRange(start: 0, end: 1),
      );
      final newV = TextEditingValue(
        text: '(',
        selection: const TextSelection.collapsed(offset: 1),
        composing: const TextRange(start: 0, end: 1),
      );
      expect(applyBracketPair(old, newV), newV);
    });
  });
}
