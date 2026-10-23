/// BracketPairFormatter —— 括号自动配对输入格式器（IDE 惯例三件套）。
///
/// 纯函数逻辑（`applyBracketPair` 可 headless 单测），formatter 只是薄壳。
/// 只处理半角 `()`；全角 `（）` 交归一化链路（`evalLine` 统一替换），不在此
/// 扩面。规则：
///
/// 1. **补全**：输入 `(`（光标折叠）→ 插入 `()`，光标落括号对中间；
/// 2. **跳过**：光标前恰好是 `)` 时再输入 `)` → 光标右移一位，不重复插入；
/// 3. **配对删除**：删除完整 `()` 的 `(` → 连 `)` 一起删（否则留孤儿括号）；
///
/// 任意非折叠选区、IME 组合中、长度变化非 ±1 的编辑（粘贴/裂变等）一律
/// 放行不干预——格式器只做「单字符击键级」的增强，不吞编辑能力。
library;

import 'package:flutter/services.dart';

/// 纯逻辑：按三件套规则计算输入后的新值；不命中任何规则返回 [newValue]。
TextEditingValue applyBracketPair(
  TextEditingValue oldValue,
  TextEditingValue newValue,
) {
  // IME 组合中不干预（拼音/联想期间改文本会打断组合）。
  if (oldValue.composing.isValid || newValue.composing.isValid) {
    return newValue;
  }
  final oldText = oldValue.text;
  final sel = oldValue.selection;
  // 无有效光标或非折叠选区（选中替换）不干预。
  if (!sel.isValid || !sel.isCollapsed) return newValue;
  final cursor = sel.baseOffset;

  final oldLen = oldText.length;
  final newLen = newValue.text.length;

  // —— 插入（+1）：击键级自动补全 / 跳过 ——
  if (newLen == oldLen + 1) {
    // 击键插入的字符位于新文本的旧光标处。
    final inserted = newValue.text[cursor];
    // 跳过：光标前已有 `)`，再输入 `)` 只右移。
    if (inserted == ')' && cursor < oldLen && oldText[cursor] == ')') {
      return newValue.copyWith(
        text: oldText,
        selection: TextSelection.collapsed(offset: cursor + 1),
      );
    }
    // 补全：输入 `(` → 成对插入，光标居中。
    if (inserted == '(') {
      return newValue.copyWith(
        text: '${newValue.text.substring(0, cursor)}()'
            '${newValue.text.substring(cursor + 1)}',
        selection: TextSelection.collapsed(offset: cursor + 1),
      );
    }
    return newValue;
  }

  // —— 删除（-1）：配对删除 ——
  // Backspace 删掉的是光标**前**一个字符 oldText[cursor-1]；若它是 '(' 且
  // 右邻恰是 ')'（即完整括号对），连 ')' 一起删，光标留在删除点。
  if (newLen == oldLen - 1 &&
      cursor > 0 &&
      oldText[cursor - 1] == '(' &&
      cursor < oldLen &&
      oldText[cursor] == ')') {
    final text =
        '${oldText.substring(0, cursor - 1)}${oldText.substring(cursor + 1)}';
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: cursor - 1),
    );
  }

  return newValue;
}

/// formatter 薄壳：把 [applyBracketPair] 挂进 TextField 的输入管线。
class BracketPairFormatter extends TextInputFormatter {
  const BracketPairFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) =>
      applyBracketPair(oldValue, newValue);
}
