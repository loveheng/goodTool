/// 计算器子页面——区块草稿台（Soulver 行模型的区块化演进）。
///
/// 设计稿：`docs/project/calculator-blocks.md`（§2 交互 / §5 架构落点）。
///
/// - **页面只做领域装配**：`BlockCanvas` 底座（焦点链 / IME Guard / 粘贴裂变 /
///   弹性槽位四件套）+ `CalculatorPort.evalLine` 行内解析调度注入；
/// - **受控列表单源**：Page 级 `List<_LineRecord>`（行文本 + CalcView）统一
///   记账，结果不落区块本地 State——级联刷新经单次 setState 整齐传导；
/// - **聚焦块光标保护**：数据流单向，重算只写 `LineRecord` 的结果字段，
///   永不回写聚焦块 `controller.text`（光标不被暴力重置）；
/// - **ans DAG 归页面侧**：`ans` 指向上一成功区块；上游故障行下游标
///   `UPSTREAM_ERROR (Line N)` 指明根因行（禁下游整串爆红看不出根因）；
/// - 内核与 MCP 工具面零改动（R1/R2/R5 无写路径，纯只读）。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ui_ports/calculator_port.dart';
import '../ui_ports/draft_port.dart';
import 'components/app_components.dart';
import 'components/block_canvas.dart';
import 'components/bracket_pair_formatter.dart';
import 'tokens/app_tokens.dart';

/// 单行记录：区块的领域侧单源（文本控制器 + 求值视图 + 软校验态）。
class _LineRecord {
  _LineRecord(String text) : controller = TextEditingController(text: text);

  final TextEditingController controller;

  /// 求值结果（null = 空行不参与结果位）。
  CalcView? view;

  /// 非法字符软校验命中（输入放行不吞键，仅高亮 + INVALID_CHARS）。
  bool invalid = false;

  /// 输入中瞬态错误（未完成语法/半截变量名）：渲染淡灰「输入中」而非红色
  /// 机器码（calculator.md「轻量容错呈现」）。
  bool pending = false;
}

class CalculatorPage extends StatefulWidget {
  const CalculatorPage({super.key, this.port});

  /// 草稿持久化端口（读经 Repository / 写经用户侧网关）。null = 纯内存
  /// 会话态（headless 测试 / 未注入），维持旧「每次挂载播种示例」行为。
  final DraftPort? port;

  @override
  State<CalculatorPage> createState() => _CalculatorPageState();
}

class _CalculatorPageState extends State<CalculatorPage> {
  static const CalculatorPort _port = CalculatorPort();

  static const String _initialDraft = '1200 * 85%\n10 km to mi\nans + 50\n0.1 + 0.2';

  /// 合法字符面（软校验，不硬拦）：数字 / 字母（单位与 ans）/ 运算符 /
  /// 百分号 / 括号 / 常用全角变体 / 度·微·欧。
  static final RegExp _allowedChars = RegExp(
    r"^[0-9A-Za-z°μΩ+\-*/().,%^\s×÷＋－（）]+$",
  );

  List<_LineRecord> _records = <_LineRecord>[];
  Timer? _debounce;
  Timer? _saveDebounce;
  bool _readerMode = false;

  /// 挂载后用户是否已动过纸面：恢复流是异步的，动过就不再覆盖（防竞态）。
  bool _userEdited = false;
  final GlobalKey<BlockCanvasState> _canvasKey = GlobalKey<BlockCanvasState>();

  @override
  void initState() {
    super.initState();
    _records = _initialDraft
        .split('\n')
        .map(_LineRecord.new)
        .toList(growable: true);
    _recalculate();
    _restoreDraft();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _saveDebounce?.cancel();
    for (final record in _records) {
      record.controller.dispose();
    }
    super.dispose();
  }

  /// 草稿恢复：读持久化内容覆盖示例（`\n` 拆块）。从未保存过（null）= 首启，
  /// 保持示例不落盘；已保存过空串 = 用户清空过，恢复为单空行——示例不再复活。
  Future<void> _restoreDraft() async {
    final port = widget.port;
    if (port == null) return;
    final saved = await port.read();
    if (!mounted || _userEdited) return;
    if (saved == null) return;
    final lines = saved.isEmpty ? <String>[''] : saved.split('\n');
    setState(() => _replaceRecords(lines));
    _recalculate();
  }

  /// 草稿自动保存（防抖 600ms，全量覆盖式）。失败不打断输入流，仅留痕。
  // DEGRADE: 草稿保存失败不弹窗不打断（输入流优先），[DEGRADE] 日志留痕。
  void _scheduleSave() {
    _userEdited = true;
    final port = widget.port;
    if (port == null) return;
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 600), () {
      if (!mounted) return;
      final content = _records.map((r) => r.controller.text).join('\n');
      unawaited(port.save(content).then((result) {
        if (!result.ok) {
          debugPrint('[DEGRADE] 草稿保存失败: ${result.errorCode}');
        }
      }));
    });
  }

  /// 整表替换（恢复/回滚共用）：释放旧控制器，重建记录。
  void _replaceRecords(List<String> lines) {
    for (final record in _records) {
      record.controller.dispose();
    }
    _records = lines.map(_LineRecord.new).toList(growable: true);
  }

  // ---------------- Canvas 回调（增删流事务统一记账） ----------------

  void _onInputChanged(int index, String text) {
    _scheduleSave();
    _scheduleRecalculate();
  }

  /// ghost 提交：追加新区块（ghost 由底座清空并保持焦点）。
  void _onGhostCommit(String text) {
    setState(() => _records.add(_LineRecord(text)));
    _scheduleSave();
    _scheduleRecalculate();
  }

  /// 两段式删块确认：整块移除（焦点由底座落上一区块）。
  void _onBlockRemove(int index) {
    setState(() {
      final removed = _records.removeAt(index);
      removed.controller.dispose();
    });
    _scheduleSave();
    _scheduleRecalculate();
  }

  /// 粘贴裂变（复合事务）：目标块取首行，其余行依次插入其后；焦点收敛到最后
  /// 一个新块行尾 + 平滑滚入；提供单次撤销整体回滚（多 TextField 割裂了系统
  /// Undo，应用层自建）。
  void _onPasteFission(int index, List<String> lines) {
    final isGhost = index >= _records.length;
    final snapshot = _records.map((r) => r.controller.text).toList();

    setState(() {
      if (isGhost) {
        for (final line in lines) {
          _records.add(_LineRecord(line));
        }
      } else {
        _records[index].controller.text = lines.first;
        var cursor = index + 1;
        for (final line in lines.skip(1)) {
          _records.insert(cursor++, _LineRecord(line));
        }
      }
    });

    final lastIndex = isGhost ? _records.length - 1 : index + lines.length - 1;
    _canvasKey.currentState?.focusBlock(lastIndex);
    _scheduleSave();
    _recalculate();

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('已裂变为 ${lines.length} 个计算块'),
          action: SnackBarAction(
            label: '撤销',
            onPressed: () => _restoreSnapshot(snapshot),
          ),
        ),
      );
  }

  /// 裂变回滚：整事务恢复快照（单次撤销语义）。
  void _restoreSnapshot(List<String> snapshot) {
    setState(() => _replaceRecords(snapshot));
    _scheduleSave();
    _recalculate();
  }

  /// >30 行裂变确认（spec §3）。
  Future<bool> _confirmFission(int index, int lineCount) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('批量创建计算块'),
        content: Text('检测到 $lineCount 行文本，是否批量创建为 $lineCount 个计算块？'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('创建'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  // ---------------- 纸面级全局动作（spec §一.4） ----------------

  /// 全纸文本：`[公式] = [结果]` 逐行拼接（导出/复制/Reader 共用）。
  String _paperText() {
    return _records.map((record) {
      final text = record.controller.text;
      if (text.isEmpty) {
        return '';
      }
      final view = record.view;
      final result = view == null
          ? ''
          : (view.ok ? (view.numeric ?? view.text ?? '') : (view.errorCode ?? ''));
      return result.isEmpty ? text : '$text = $result';
    }).join('\n');
  }

  /// 一键全纸复制（Markdown/纯文本口径）。
  void _copyAllPaper() {
    Clipboard.setData(ClipboardData(text: _paperText()));
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('整张草稿已复制')));
  }

  /// 纸面清空：二次确认后整张草稿归零，恢复至仅剩一行光标。
  Future<void> _clearPaper() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清空草稿'),
        content: const Text('整张草稿将归零，此操作不可撤销。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (confirmed ?? false) {
      setState(() {
        for (final record in _records) {
          record.controller.dispose();
        }
        _records = <_LineRecord>[_LineRecord('')];
      });
      _scheduleSave();
      _recalculate();
    }
  }

  /// 结果槽单击：成功 → 复制无损值 + 气泡；上游故障 → 平滑滚动并聚焦
  /// 根因行（spec §二：点击 UPSTREAM_ERROR 提示直达故障源）。
  void _onResultTap(int index) {
    final view = _records[index].view;
    if (view == null) {
      return;
    }
    if (!view.ok) {
      final match =
          RegExp(r'Line (\d+)').firstMatch(view.errorCode ?? '');
      if (match != null) {
        final sourceLine = int.parse(match.group(1)!) - 1;
        if (sourceLine >= 0 && sourceLine < _records.length) {
          _canvasKey.currentState?.focusBlock(sourceLine);
        }
        return;
      }
      return;
    }
    final numeric = view.numeric;
    if (numeric == null || numeric.isEmpty) {
      return;
    }
    Clipboard.setData(ClipboardData(text: numeric));
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('结果已复制')));
  }

  /// 结果槽长按：操作菜单（复制格式化串 / 在下一行插入该值）。
  void _onResultLongPress(int index) {
    final view = _records[index].view;
    final numeric = view?.numeric;
    if (numeric == null || numeric.isEmpty) {
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.copy_outlined),
              title: const Text('复制格式化串'),
              subtitle: Text(view!.text ?? numeric),
              onTap: () {
                Navigator.of(context).pop();
                Clipboard.setData(ClipboardData(text: view.text ?? numeric));
                ScaffoldMessenger.of(this.context)
                  ..hideCurrentSnackBar()
                  ..showSnackBar(const SnackBar(content: Text('已复制格式化串')));
              },
            ),
            ListTile(
              leading: const Icon(Icons.playlist_add),
              title: const Text('在下一行插入该值'),
              onTap: () {
                Navigator.of(context).pop();
                setState(() => _records.insert(
                      index + 1,
                      _LineRecord(numeric),
                    ));
                _canvasKey.currentState?.focusBlock(index + 1);
                _recalculate();
              },
            ),
          ],
        ),
      ),
    );
  }

  // ---------------- 求值调度（ans DAG + 级联） ----------------

  /// 输入中瞬态错误码：未完成语法（`1 +`、`(` 未闭合）与打了一半的
  /// 变量/单位名（`10 km`）——纯击键中间态，完成前不构成真错误。
  bool _isInProgress(String? code) =>
      code == 'UNEXPECTED_TOKEN' || code == 'UNDEFINED_VARIABLE';

  void _scheduleRecalculate() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 150), _recalculate);
  }

  /// 全量重算：按块调度，`ans` 串接上一**成功**块的数值；上游故障块的下游
  /// `ans` 行标 `UPSTREAM_ERROR (Line N)`。只写结果字段，不回写文本（光标
  /// 保护硬约束，spec §5.2）。
  void _recalculate() {
    String? ans;
    int? lastFailedLine;
    var lastFailedPending = false;
    for (var i = 0; i < _records.length; i++) {
      final record = _records[i];
      final text = record.controller.text.trim();

      if (text.isEmpty) {
        record
          ..view = null
          ..invalid = false
          ..pending = false;
        continue;
      }

      // 软校验：非法字符放行不吞键，结果位 INVALID_CHARS（spec §2.2）。
      final invalid = !_allowedChars.hasMatch(text);
      record.invalid = invalid;
      if (invalid) {
        record.view = const CalcView(
          ok: false,
          errorCode: 'INVALID_CHARS',
          message: '含不支持的字符',
        );
        lastFailedLine = i;
        lastFailedPending = false;
        continue;
      }

      final evalView = _port.evalLine(text, ans: ans);
      var view = evalView ??
          const CalcView(ok: false, errorCode: 'EMPTY_LINE', message: '空行');
      // 输入中瞬态：未完成语法 / 打了一半的变量名（如 `1 +`、`10 km`）——
      // 淡灰「输入中」而非红色机器码（calculator.md「轻量容错呈现」）。
      var pending = !view.ok && _isInProgress(view.errorCode);
      // ans 不可用时优先归因上游故障行（可操作，禁静默）；上游只是输入中
      // 时，下游同步转输入中态（级联不闪红）。
      if (!view.ok &&
          view.errorCode == 'ANS_UNAVAILABLE' &&
          lastFailedLine != null) {
        pending = lastFailedPending;
        view = CalcView(
          ok: false,
          errorCode: 'UPSTREAM_ERROR (Line ${lastFailedLine + 1})',
          message: pending
              ? '第 ${lastFailedLine + 1} 行输入中，完成后自动恢复'
              : '第 ${lastFailedLine + 1} 行计算失败，修复后本行自动恢复',
        );
      }
      record.view = view;
      record.pending = pending;
      if (view.ok) {
        ans = view.numeric;
      } else {
        lastFailedLine = i;
        lastFailedPending = pending;
      }
    }
    if (mounted) {
      setState(() {});
    }
  }

  // ---------------- 结果槽渲染（业务语义） ----------------

  String? _resultTextAt(int index) {
    final view = _records[index].view;
    if (view == null) {
      return null;
    }
    return view.ok ? view.numeric : view.errorCode;
  }

  InputDecoration? _decorationAt(int index) {
    if (index >= _records.length) {
      return null; // ghost 行：底座默认 collapsed 提示。
    }
    if (!_records[index].invalid) {
      return null;
    }
    final t = tokensOf(context);
    final danger = BorderSide(color: t.palette.danger);
    return InputDecoration(
      isDense: true,
      border: UnderlineInputBorder(borderSide: danger),
      enabledBorder: UnderlineInputBorder(borderSide: danger),
      focusedBorder: UnderlineInputBorder(borderSide: danger),
    );
  }

  Widget? _buildOutput(BuildContext context, int index, bool sunk) {
    final record = _records[index];
    final view = record.view;
    if (view == null) {
      return null;
    }
    final t = tokensOf(context);
    if (view.ok) {
      // 遥测轨等宽 + tabularFigures（多行数位整齐）；两行模式加 `= ` 前缀
      // 弱化箭头感（spec §2.4）。排版可截断，复制取底层无损值。
      final value = view.numeric ?? view.text ?? '';
      final text = sunk ? '= $value' : value;
      return Text(
        text,
        style: t.typeScale.telemetry.copyWith(
          color: t.palette.l1Ok,
          fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }
    // 输入中瞬态：淡灰「输入中…」（calculator.md「轻量容错呈现」——打字
    // 中途不闪红、不打断），完成后自动出结果。
    if (record.pending) {
      return Text(
        '输入中…',
        style: t.typeScale.micro.copyWith(color: t.palette.textMuted),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.right,
      );
    }
    // 失败：机器码 + 人话（danger），错误圈定在出错区块内。
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          view.errorCode ?? 'ERR',
          style: t.typeScale.micro.copyWith(color: t.palette.danger),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.right,
        ),
        Text(
          view.message ?? '',
          style: t.typeScale.micro.copyWith(color: t.palette.textMuted),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.right,
        ),
      ],
    );
  }

  // ---------------- 构建 ----------------

  /// Gutter 行号（spec §一.2）：弱化 `NN` 编号，错误行标红，点击聚焦该行
  /// （多选/拖拽锚点归 v2）。ghost 行不占位。
  Widget? _buildGutter(BuildContext context, int index) {
    if (index >= _records.length) {
      return null;
    }
    final t = tokensOf(context);
    final record = _records[index];
    final hasError = record.view != null && !record.view!.ok;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _canvasKey.currentState?.focusBlock(index),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          '${index + 1}'.padLeft(2, '0'),
          style: t.typeScale.micro.copyWith(
            color: hasError ? t.palette.danger : t.palette.textMuted,
          ),
        ),
      ),
    );
  }

  /// Telemetry 汇总条读数（spec §一.3）：有效行数 / 最终 ans / 累计总和。
  ({int validCount, String? finalAns, String totalSum}) _summary() {
    var validCount = 0;
    String? finalAns;
    double total = 0;
    for (final record in _records) {
      final view = record.view;
      if (view == null || !view.ok) {
        continue;
      }
      validCount++;
      finalAns = view.numeric;
      total += double.tryParse(view.numeric ?? '') ?? 0;
    }
    return (
      validCount: validCount,
      finalAns: finalAns,
      totalSum: _formatNumber(total),
    );
  }

  /// 数值展示格式：整数不带小数点，小数保留有效位（避免长浮点尾巴）。
  String _formatNumber(double value) {
    if (value == value.roundToDouble()) {
      return value.round().toString();
    }
    return value.toStringAsFixed(2);
  }

  Widget _buildSummaryBar(AppTokens t) {
    final summary = _summary();
    Widget readout(String label, String value) {
      return Expanded(
        child: InkWell(
          onTap: () {
            Clipboard.setData(ClipboardData(text: value));
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(SnackBar(content: Text('已复制 $label')));
          },
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: t.metrics.space8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  label,
                  style:
                      t.typeScale.micro.copyWith(color: t.palette.textMuted),
                ),
                SizedBox(height: t.metrics.space4),
                Text(
                  value,
                  style: t.typeScale.telemetry.copyWith(
                    color: t.palette.l1Ok,
                    fontFeatures: const <FontFeature>[
                      FontFeature.tabularFigures(),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: t.palette.hairline)),
      ),
      padding: EdgeInsets.symmetric(horizontal: t.metrics.space8),
      child: Row(
        children: <Widget>[
          readout('有效行', '${summary.validCount}'),
          readout('最终 ans', summary.finalAns ?? '—'),
          readout('累计总和', summary.totalSum),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final actions = <Widget>[
      IconButton(
        // 一键全纸复制（spec §一.4）。
        icon: const Icon(Icons.copy_all_outlined),
        tooltip: '全纸复制',
        onPressed: _copyAllPaper,
      ),
      IconButton(
        // 纸面清空（二次确认）。
        icon: const Icon(Icons.delete_sweep_outlined),
        tooltip: '清空草稿',
        onPressed: _clearPaper,
      ),
      IconButton(
        // Reader Mode：纯文本渲染层，可跨行划选（补跨块选择缺失）。
        icon: Icon(_readerMode ? Icons.edit_outlined : Icons.article_outlined),
        tooltip: _readerMode ? '返回编辑' : '只读视图',
        onPressed: () => setState(() => _readerMode = !_readerMode),
      ),
    ];

    // 子页面由 capabilities_page 以 Scaffold(body: ...) 直包（无 appBar），
    // 内容须自带 SafeArea，否则顶进系统状态栏。
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.all(t.metrics.space16),
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text('草稿计算台', style: t.typeScale.titleMedium),
              ),
              ...actions,
            ],
          ),
          SizedBox(height: t.metrics.space4),
          Text(
            '逐块输入算式即出结果：1200 * 85% · 10 km to mi · ans + 50（引用上一成功块）',
            style: t.typeScale.micro.copyWith(color: t.palette.textMuted),
          ),
          SizedBox(height: t.metrics.space12),
          Expanded(
            child: _readerMode
                ? SingleChildScrollView(
                    child: SelectableText(
                      _paperText(),
                      style: t.typeScale.body,
                    ),
                  )
                : BlockCanvas(
                    key: _canvasKey,
                    blockCount: _records.length,
                    controllerAt: (index) => _records[index].controller,
                    outputBuilder: _buildOutput,
                    onInputChanged: _onInputChanged,
                    onBlockRemove: _onBlockRemove,
                    onPasteFission: _onPasteFission,
                    onGhostCommit: _onGhostCommit,
                    inputFormatters: const <TextInputFormatter>[
                      BracketPairFormatter(),
                    ],
                    onResultTap: _onResultTap,
                    onResultLongPress: _onResultLongPress,
                    decorationAt: _decorationAt,
                    resultTextAt: _resultTextAt,
                    inputStyle: t.typeScale.body,
                    resultStyle: t.typeScale.telemetry,
                    focusRailColor: t.palette.l1Info,
                    gutterBuilder: _buildGutter,
                    ghostHint: '// 输入公式或单位换算…',
                    confirmFission: _confirmFission,
                  ),
          ),
          _buildSummaryBar(t),
        ],
        ),
      ),
    );
  }
}
