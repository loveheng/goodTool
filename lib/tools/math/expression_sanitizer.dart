library;

/// 表达式输入防御性清洗（calculator.md「Sanitizer Pipeline」）。
///
/// 铁律：**无损 / 保守**——仅当确定无歧义时才改写，否则原样交后续语法报错
/// （`UNEXPECTED_TOKEN`），不静默吞错。
///
/// 位移回填：清洗必然改写字符串，而 `MathError.offset` 必须指向**原始输入**
/// （UI 下划线标红 / Agent 自愈定位都用它）。故本类与清洗结果同产
/// cleaned→original 的位置映射 [SanitizeResult.originMap]——
/// 清洗省下的 offset 对齐成本，会在 UI 与排障处加倍付回来。
class ExpressionSanitizer {
  const ExpressionSanitizer._();

  /// 全角 / 变宽符号 → 半角（calculator.md 显式列举的算子/括号/标点，
  /// 另补百分号、全角数字与 `×`/`÷`——均为确定性 1:1 映射，无歧义；
  /// `×`/`÷` 是中文输入法下最易敲出的乘除号，漏归一会直接变成
  /// `UNEXPECTED_TOKEN`，属可预见的输入噪声）。
  static const Map<String, String> _fullWidth = {
    '（': '(', '）': ')',
    '＋': '+', '－': '-', '＊': '*', '／': '/',
    '×': '*', '÷': '/',
    '，': ',', '：': ':', '％': '%',
    '０': '0', '１': '1', '２': '2', '３': '3', '４': '4',
    '５': '5', '６': '6', '７': '7', '８': '8', '９': '9',
  };

  /// 货币 / 噪声前置符（不可能构成合法 token，直接剔除）。
  /// 注意 `$` 须转义——非 raw 字符串里 `$` 是插值起始。
  static const List<String> _currency = ['¥', '￥', '\$', '＄'];

  /// 形如 `1,000,000` 的千分位连续段；**不**匹配 `1,2,3` 或 `1,5`
  /// （避免误伤函数参数分隔与小数）。
  static final RegExp _thousands = RegExp(r'\d{1,3}(?:,\d{3})+');

  static SanitizeResult sanitize(String raw) {
    final buf = StringBuffer();
    final originMap = <int>[];
    final notes = <String>[];

    for (var i = 0; i < raw.length; i++) {
      var ch = raw[i];

      final fw = _fullWidth[ch];
      if (fw != null) {
        ch = fw;
        notes.add('全角→半角');
      }
      if (_currency.contains(ch)) {
        notes.add('剔除货币符');
        continue; // 删除：不写 buf、不记 originMap
      }

      buf.write(ch);
      originMap.add(i);
    }

    var text = buf.toString();

    // 千分位逗号：在已清洗文本上规整，同步回填 originMap（逗号被删，索引左移）。
    if (_thousands.hasMatch(text)) {
      final sb = StringBuffer();
      final newMap = <int>[];
      var idx = 0;
      for (final m in _thousands.allMatches(text)) {
        for (; idx < m.start; idx++) {
          sb.write(text[idx]);
          newMap.add(originMap[idx]);
        }
        for (var j = m.start; j < m.end; j++) {
          if (text[j] == ',') continue; // 丢掉分隔逗号
          sb.write(text[j]);
          newMap.add(originMap[j]);
        }
        idx = m.end;
      }
      for (; idx < text.length; idx++) {
        sb.write(text[idx]);
        newMap.add(originMap[idx]);
      }
      text = sb.toString();
      originMap
        ..clear()
        ..addAll(newMap);
      notes.add('千分位逗号规整');
    }

    return SanitizeResult(
      text: text,
      originMap: originMap,
      notes: notes.toSet().toList(growable: false),
    );
  }
}

/// 清洗结果。[originMap] 长度 == [text] 长度，`originMap[i]` = 清洗后第 i 个
/// 字符在**原始串**中的下标；越界时按端点钳位。
class SanitizeResult {
  const SanitizeResult({
    required this.text,
    required this._originMap,
    required this.notes,
  });

  final String text;
  final List<int> _originMap;

  /// 本次发生的清洗动作（去重，供回显「规范化表达式」与调试）。
  final List<String> notes;

  bool get changed => notes.isNotEmpty;

  /// cleaned 偏移 → original 偏移（端点钳位，绝不错位）。
  int originalOffset(int cleanedOffset) {
    if (_originMap.isEmpty) return cleanedOffset;
    if (cleanedOffset < 0) return _originMap.first;
    if (cleanedOffset >= _originMap.length) return _originMap.last + 1;
    return _originMap[cleanedOffset];
  }
}
