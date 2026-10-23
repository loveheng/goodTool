/// BlockCanvas —— 区块草稿画布底座（系统共用组件，计算器只是首个消费者）。
///
/// 设计稿：`docs/project/calculator-blocks.md` §5.1（四进三出抽取边界）。
///
/// 底座持有（无领域语义，可复用）：
///   - 焦点链管线：FocusNode 池 / 焦点防跳变 / 末尾 ghost 块 / 空白命中聚焦 /
///     行尾回车跳块 / 空块两段式退格删块 / 删块后焦点落上一区块；
///   - IME Guard：`composing` 组合期绝对静默（不 emit / 不校验），选词确认
///     （`composing.isCollapsed`）后才对外通知；
///   - 粘贴裂变协议：多行粘贴拦截（按 `\n` 裂变 N 块），>30 行经上层确认，
///     事务记账归上层；
///   - 弹性槽位引擎：`TextPainter` 测量 + 95%/75% 迟滞沉降（同行 → 两行），
///     结果槽独立手势（阻断穿透到输入框）。
///
/// 留业务层（回调/槽位注入）：求值引擎（`onInputChanged` 注入）、结果语义渲染
/// （`outputBuilder` 槽位）、依赖图（`ans` DAG 归页面侧）。
///
/// API 纪律（v1 最小面）：非泛型——输入 String、输出经 `outputBuilder` 直接产
/// Widget；底座只认一维区块列表，增删流事务由上层统一记账（底座无领域状态）。
/// 业务需要键盘流/裂变行为时先扩底座再消费，禁绕过底座自持焦点/粘贴逻辑。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_components.dart';
import '../tokens/app_tokens.dart';

/// 区块状态三态（底座不持语义色：成功/失败的业务渲染归 `outputBuilder`）。
enum BlockStatus { idle, busy, done }

/// 区块画布：受控一维区块列表 + 末尾常驻 ghost 块。
class BlockCanvas extends StatefulWidget {
  const BlockCanvas({
    super.key,
    required this.blockCount,
    required this.controllerAt,
    required this.outputBuilder,
    required this.onInputChanged,
    required this.onBlockRemove,
    required this.onPasteFission,
    this.onGhostCommit,
    this.onResultTap,
    this.onResultLongPress,
    this.decorationAt,
    this.resultTextAt,
    this.inputStyle,
    this.resultStyle,
    this.focusRailColor,
    this.gutterBuilder,
    this.ghostHint = '新的一行',
    this.inputFormatters,
    this.confirmFission,
    this.resultGap = 12,
  });

  /// 实区块数量（ghost 不计入；ghost 输入经 [onGhostCommit] 提交为新区块）。
  final int blockCount;

  /// 区块文本控制器（上层持有 = 受控单源；底座不缓存文本）。
  final TextEditingController Function(int index) controllerAt;

  /// 结果槽渲染：`sunk` = 当前区块处于两行沉降模式（业务可据此加 `= ` 前缀 /
  /// 右对齐 / 截断样式）。返回 null 的区块（如无结果）不渲染结果位。
  final Widget? Function(BuildContext context, int index, bool sunk)
      outputBuilder;

  /// 文本变更（IME Guard 后 emit；`composing` 组合期绝不触发）。
  final void Function(int index, String text) onInputChanged;

  /// 整块移除（两段式退格第二次确认后触发；上层记账删块）。
  final void Function(int index) onBlockRemove;

  /// 粘贴裂变：粘贴内容含 `\n` 被拦截后按行拆分交上层记账
  /// （上层负责快照 / 撤销 / 后续焦点收敛）。
  final void Function(int index, List<String> lines) onPasteFission;

  /// ghost 块提交：ghost 内键入非空文本后触发（上层追加新区块；底座随后清空
  /// ghost）。空即丢弃。
  final ValueChanged<String>? onGhostCommit;

  /// 结果槽单击（业务语义：复制无损值 + 气泡；底座保证不聚焦输入框）。
  final void Function(int index)? onResultTap;

  /// 结果槽长按（业务语义：操作菜单）。
  final void Function(int index)? onResultLongPress;

  /// 输入框装饰（业务软校验通道：非法字符高亮下划线等；null = 无装饰）。
  final InputDecoration? Function(int index)? decorationAt;

  /// 结果槽测量文本（弹性槽位引擎用；与 [resultStyle] 配对测量宽度）。
  final String? Function(int index)? resultTextAt;

  /// 公式输入样式（测量与渲染同源，零魔法值）。
  final TextStyle? inputStyle;

  /// 结果样式（测量用；渲染仍归 `outputBuilder`）。
  final TextStyle? resultStyle;

  /// 聚焦轨强调色（左缘竖条；业务传入语义色，底座不持语义色）。
  final Color? focusRailColor;

  /// 行槽左缘的 Gutter 槽位（业务渲染行号/状态标记；底座只管摆放位置，
  /// 两段式删块待删除态由底座覆盖为删除图标）。返回 null 不占位。
  final Widget? Function(BuildContext context, int index)? gutterBuilder;

  /// ghost 占位提示。
  final String ghostHint;

  /// 输入格式器（逐块透传给 TextField；消费方按自身语义挂——计算器挂
  /// 括号配对三件套）。null = 无增强。
  final List<TextInputFormatter>? inputFormatters;

  /// 裂变确认（>30 行时弹确认；返回 false 放弃裂变）。
  final Future<bool> Function(int index, int lineCount)? confirmFission;

  /// 公式与结果的同行最小间距。
  final double resultGap;

  @override
  State<BlockCanvas> createState() => BlockCanvasState();
}

class BlockCanvasState extends State<BlockCanvas> {
  final ScrollController _scroll = ScrollController();

  /// 焦点节点池：实区块 0..blockCount-1，ghost = blockCount。
  final Map<int, FocusNode> _nodes = <int, FocusNode>{};

  /// 已挂监听：index → (controller, listener)。随块增删对齐解绑。
  final Map<int, TextEditingController> _boundControllers =
      <int, TextEditingController>{};
  final Map<int, VoidCallback> _boundListeners = <int, VoidCallback>{};

  /// 两段式删块的待删除态（空块首退格只提示）。
  final Set<int> _pendingDelete = <int>{};

  /// ghost 控制器（底座自有；提交后清空）。
  late final TextEditingController _ghostController;

  /// 沉降态按块记录（迟滞判断需要跨帧记忆）。
  final Map<int, bool> _sunk = <int, bool>{};

  /// 各块最近一次确认后的文本（裂变拦截时恢复用）。
  final Map<int, String> _lastCommitted = <int, String>{};

  /// 裂变恢复期间的回环抑制标志。
  bool _restoring = false;

  @override
  void initState() {
    super.initState();
    _ghostController = TextEditingController();
    _ghostController.addListener(_onGhostChanged);
    _syncControllers();
  }

  @override
  void didUpdateWidget(covariant BlockCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncControllers();
    if (widget.blockCount < oldWidget.blockCount) {
      // 删块后焦点落上一区块（spec §2.3；底座职责，无需上层关心）。
      final target = (widget.blockCount - 1).clamp(0, widget.blockCount);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          focusBlock(target);
        }
      });
    }
  }

  @override
  void dispose() {
    for (final entry in _boundListeners.entries) {
      _boundControllers[entry.key]?.removeListener(entry.value);
    }
    _boundListeners.clear();
    _boundControllers.clear();
    _ghostController.removeListener(_onGhostChanged);
    _ghostController.dispose();
    for (final node in _nodes.values) {
      node.dispose();
    }
    _nodes.clear();
    _scroll.dispose();
    super.dispose();
  }

  // ---------------- 焦点链管线 ----------------

  FocusNode _nodeFor(int index) {
    return _nodes.putIfAbsent(index, () {
      final node = FocusNode();
      node.addListener(() {
        if (!node.hasFocus && mounted && _pendingDelete.remove(index)) {
          setState(() {});
        }
      });
      return node;
    });
  }

  FocusNode get _ghostNode => _nodeFor(widget.blockCount);

  /// 外部聚焦目标区块（光标落到文本末尾）并平滑滚入可视区（~200ms Ease-Out）。
  void focusBlock(int index, {bool atEnd = true}) {
    if (index < 0 || index >= widget.blockCount) {
      return;
    }
    final node = _nodeFor(index);
    final controller = widget.controllerAt(index);
    if (atEnd) {
      controller.selection = TextSelection.collapsed(
        offset: controller.text.length,
      );
    }
    // 焦点防跳变：先聚焦新目标，再撤销旧焦点（软键盘不闪退，spec §2.3）。
    node.requestFocus();
    final ctx = node.context;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  void _moveFocus(int from, int to) {
    if (to >= 0 && to < widget.blockCount) {
      _nodeFor(to).requestFocus();
    } else {
      _ghostNode.requestFocus();
    }
    if (from >= 0 && from < widget.blockCount && from != to) {
      _nodeFor(from).unfocus();
    }
  }

  // ---------------- IME Guard + 输入事件 ----------------

  VoidCallback _listenerFor(int index) {
    return () {
      final controller = widget.controllerAt(index);
      // Composing 隔离铁律：选词/注音进行中绝对静默（spec §2.2）。
      if (controller.value.composing.isValid || _restoring) {
        return;
      }
      final text = controller.text;
      // 粘贴裂变兜底：formatter 拦不住的直写路径（部分 IME/程序化写入）
      // 在监听层二次检测 `\n`，恢复拦截前文本后走裂变事务（禁静默并块）。
      if (text.contains('\n')) {
        final lines = text.split('\n');
        final restore = _lastCommitted[index] ?? '';
        _restoring = true;
        controller.value = TextEditingValue(
          text: restore,
          selection: TextSelection.collapsed(offset: restore.length),
        );
        _restoring = false;
        scheduleMicrotask(() => _handleFission(index, lines));
        return;
      }
      _lastCommitted[index] = text;
      // 两段式待删除态重置：任何文本变动立即清除（spec §2.3）。
      if (text.isNotEmpty && _pendingDelete.remove(index)) {
        setState(() {});
      }
      widget.onInputChanged(index, text);
    };
  }

  void _onGhostChanged() {
    final value = _ghostController.value;
    if (value.composing.isValid || _restoring) {
      return;
    }
    final text = value.text;
    if (text.contains('\n')) {
      _restoring = true;
      _ghostController.clear();
      _restoring = false;
      scheduleMicrotask(() => _handleFission(widget.blockCount, text.split('\n')));
      return;
    }
    if (text.isEmpty) {
      return;
    }
    widget.onGhostCommit?.call(text);
    _ghostController.clear();
  }

  /// 块数/控制器变化时对齐监听（新增 attach / 移除或换控制器 detach）。
  void _syncControllers() {
    for (var i = 0; i < widget.blockCount; i++) {
      final controller = widget.controllerAt(i);
      if (!identical(_boundControllers[i], controller)) {
        final old = _boundControllers[i];
        final oldListener = _boundListeners[i];
        if (old != null && oldListener != null) {
          old.removeListener(oldListener);
        }
        final listener = _listenerFor(i);
        controller.addListener(listener);
        _boundControllers[i] = controller;
        _boundListeners[i] = listener;
        // 播种最近确认文本（初始值不走监听，裂变恢复需以此为基线）。
        _lastCommitted[i] = controller.text;
      }
    }
    // 越界或失联的旧绑定解绑。
    final stale = _boundControllers.keys
        .where((i) => i >= widget.blockCount)
        .toList(growable: false);
    for (final i in stale) {
      _boundControllers[i]?.removeListener(_boundListeners[i]!);
      _boundControllers.remove(i);
      _boundListeners.remove(i);
    }
  }

  // ---------------- 两段式删块（空块退格） ----------------

  KeyEventResult _onKeyEvent(int index, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey != LogicalKeyboardKey.backspace) {
      return KeyEventResult.ignored;
    }
    final isGhost = index >= widget.blockCount;
    final controller = isGhost ? _ghostController : widget.controllerAt(index);
    if (controller.text.isNotEmpty || controller.value.composing.isValid) {
      return KeyEventResult.ignored;
    }
    if (isGhost) {
      return KeyEventResult.ignored; // ghost 常驻，空块退格不删。
    }
    // 两段式：首退格仅出提示，第二次才整块移除（确定性两拍，不依赖计时竞态）。
    if (!_pendingDelete.contains(index)) {
      setState(() => _pendingDelete.add(index));
      return KeyEventResult.handled;
    }
    _pendingDelete.remove(index);
    final previous = index > 0 ? index - 1 : 0;
    setState(() {}); // 立即撤提示；块删除由上层经 didUpdateWidget 收敛。
    widget.onBlockRemove(index);
    // 焦点在 didUpdateWidget 删块分支统一落上一区块（防跳变口径）。
    if (previous == index) {
      _moveFocus(index, 0);
    }
    return KeyEventResult.handled;
  }

  /// 侧滑删块收敛：与退格第二拍同口径——清待删态、焦点经 didUpdateWidget
  /// 删块分支统一落上一区块（防跳变）。
  void _onSwipeDelete(int index) {
    _pendingDelete.remove(index);
    setState(() {});
    widget.onBlockRemove(index);
  }

  /// 行尾回车跳块（P1 口径；中段拆块为 P2）。
  void _onSubmitted(int index) {
    _moveFocus(index, index + 1);
  }

  // ---------------- 粘贴裂变 ----------------

  Future<void> _handleFission(int index, List<String> lines) async {
    if (lines.length > 30 && widget.confirmFission != null) {
      final confirmed = await widget.confirmFission!(index, lines.length);
      if (!confirmed || !mounted) {
        return;
      }
    }
    widget.onPasteFission(index, lines);
  }

  // ---------------- 构建区 ----------------

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    return GestureDetector(
      // 空白区命中：点列表剩余空白 = 聚焦 ghost 并拉起键盘（spec §2.3）。
      behavior: HitTestBehavior.translucent,
      onTap: () => _ghostNode.requestFocus(),
      child: ListView.builder(
        controller: _scroll,
        // 无尽纸卷：顶底各 16dp，软键盘弹起不挤变形（spec §三.2）。
        padding: EdgeInsets.symmetric(vertical: t.metrics.space16),
        itemCount: widget.blockCount + 1,
        itemBuilder: (context, index) {
          final isGhost = index == widget.blockCount;
          return _BlockRow(
            key: ValueKey<int>(index),
            index: index,
            isGhost: isGhost,
            controller:
                isGhost ? _ghostController : widget.controllerAt(index),
            focusNode: _nodeFor(index),
            canvas: this,
          );
        },
      ),
    );
  }
}

// ======================= 区块行（私有） =======================

class _BlockRow extends StatefulWidget {
  const _BlockRow({
    super.key,
    required this.index,
    required this.isGhost,
    required this.controller,
    required this.focusNode,
    required this.canvas,
  });

  final int index;
  final bool isGhost;
  final TextEditingController controller;
  final FocusNode focusNode;
  final BlockCanvasState canvas;

  @override
  State<_BlockRow> createState() => _BlockRowState();
}

class _BlockRowState extends State<_BlockRow> {
  /// 当前是否两行沉降（含尺寸迟滞，跨帧记忆在 [BlockCanvasState._sunk]）。
  bool get _sunk => widget.canvas._sunk[widget.index] ?? false;

  set _sunk(bool value) => widget.canvas._sunk[widget.index] = value;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final canvas = widget.canvas.widget;
    final index = widget.index;

    final hasFocus = widget.focusNode.hasFocus;
    final resultWidget =
        widget.isGhost ? null : canvas.outputBuilder(context, index, _sunk);

    // 草稿纸模型（calculator-blocks.md §4 修订）：块体透明，无底色无圆角——
    // 纸面是连续书写表面，分块是逻辑/交互概念而非视觉容器。聚焦行 = IDE 式
    // 行光标带（surfaceRaised 整行高亮，token 全值零魔法）+ 左缘强调条。
    // 侧滑删除：非 ghost 块右滑（endToStart）直达删除——与空块退格两段式
    // 并存（键盘用户走退格，触屏用户走侧滑）；焦点收敛同走 didUpdateWidget
    // 删块分支（落上一区块，防跳变口径）。ghost 常驻不可删，不包。
    final block = AnimatedContainer(
      duration: t.motion.durationSlow,
      curve: t.motion.curveEaseOut,
      color: hasFocus ? t.palette.surfaceRaised : Colors.transparent,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          // 左缘 2dp 强调竖条（双通道：色 + 位置标记，不单靠颜色）。
          AnimatedContainer(
            duration: t.motion.durationSlow,
            curve: t.motion.curveEaseOut,
            width: t.metrics.borderWidth * 2,
            color: hasFocus
                ? (canvas.focusRailColor ?? t.palette.l1Info)
                : Colors.transparent,
          ),
          Expanded(
            child: Focus(
              onKeyEvent: (node, event) =>
                  widget.canvas._onKeyEvent(widget.index, event),
              child: AnimatedBuilder(
                animation: widget.focusNode,
                builder: (context, _) => LayoutBuilder(
                  builder: (context, constraints) =>
                      _buildContent(context, constraints, t, resultWidget),
                ),
              ),
            ),
          ),
        ],
      ),
    );
    if (widget.isGhost) {
      return block;
    }
    return Dismissible(
      key: ValueKey<int>(widget.index),
      direction: DismissDirection.endToStart,
      background: ColoredBox(
        color: t.palette.danger,
        child: Align(
          alignment: AlignmentDirectional.centerEnd,
          child: Padding(
            padding: EdgeInsets.only(right: t.metrics.space16),
            child: Icon(Icons.delete_outline, color: Colors.white),
          ),
        ),
      ),
      onDismissed: (_) => widget.canvas._onSwipeDelete(widget.index),
      child: block,
    );
  }

  Widget _buildContent(
    BuildContext context,
    BoxConstraints constraints,
    AppTokens t,
    Widget? resultWidget,
  ) {
    final canvas = widget.canvas.widget;
    final index = widget.index;
    final inputStyle = canvas.inputStyle ?? t.typeScale.body;
    final resultStyle = canvas.resultStyle ?? t.typeScale.telemetry;
    final horizontalPad = t.metrics.space8;
    final available = constraints.maxWidth - horizontalPad * 2;

    // ---- 弹性槽位：测量 + 迟滞沉降（spec §2.4）----
    // 公式测量宽无条件计算（聚焦引线 Leader Dots 起点也要用）。
    final formulaWidth = _measureText(
      widget.controller.text.isEmpty && widget.isGhost
          ? canvas.ghostHint
          : widget.controller.text,
      inputStyle,
    );
    var shouldSunk = _sunk;
    if (resultWidget != null) {
      final resultWidth =
          _measureText(canvas.resultTextAt?.call(index) ?? '', resultStyle);
      final need = formulaWidth + canvas.resultGap + resultWidth;
      // 迟滞：进入两行 ≥95% 可用宽、退回单行 ≤75%（防边界抖动）。
      if (!_sunk && need > available * 0.95) {
        shouldSunk = true;
      } else if (_sunk && need <= available * 0.75) {
        shouldSunk = false;
      }
      if (shouldSunk != _sunk) {
        _sunk = shouldSunk;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() {});
          }
        });
      }
    }

    final decoration = canvas.decorationAt?.call(index);
    // Gutter 槽位：业务渲染行号；两段式删块待删除态由底座覆盖为删除图标。
    final gutter = widget.canvas._pendingDelete.contains(index)
        ? Icon(
            Icons.delete_outline,
            size: t.typeScale.micro.fontSize,
            color: t.palette.danger,
          )
        : canvas.gutterBuilder?.call(context, index);
    final field = TextField(
      controller: widget.controller,
      focusNode: widget.focusNode,
      // 自适应换行：长公式自动折行撑高块体（calculator.md「单行/多行自动
      // 微撑高」），不再横向滚动。`\n` 由 _NoNewlineFormatter 拦截——块内容
      // 恒单行文本（粘贴裂变按行拆块的依赖），换行只是视觉折行。
      minLines: 1,
      maxLines: null,
      keyboardType: TextInputType.text,
      textInputAction: TextInputAction.next,
      inputFormatters: <TextInputFormatter>[
        ...?canvas.inputFormatters,
        const _NoNewlineFormatter(),
      ],
      style: inputStyle,
      onSubmitted: (_) => widget.canvas._onSubmitted(index),
      // 粘贴裂变：粘贴入口先读剪贴板，多行走裂变事务（禁静默并块）。
      // // UNCERTAIN: 部分 IME 剪贴板芯片可绕过菜单直插文本——该路径被框架
      // singleLineFormatter 静默过滤，框架侧无拦截点；Android 触屏主流路径
      // （长按菜单粘贴）已覆盖，监听层兜底再挡程序化直写。
      contextMenuBuilder: (context, editableState) =>
          widget.canvas.fissionMenu(context, editableState, widget.index),
      decoration: decoration ??
          InputDecoration.collapsed(
            hintText: widget.isGhost ? canvas.ghostHint : null,
          ),
    );

    // 聚焦引线（Leader Dots）：聚焦行的公式末尾到输入区右缘之间铺点阵，
    // 视线在长留白中穿透（spec §一.1）。画在 TextField 之下——文字底下
    // 透明，点阵只在文本右侧空区可见。
    final hasFocus = widget.focusNode.hasFocus;
    final showDots = hasFocus && !shouldSunk && !widget.isGhost;
    final input = Padding(
      padding: EdgeInsets.symmetric(horizontal: horizontalPad),
      child: LayoutBuilder(
        builder: (context, inputConstraints) => Stack(
          children: <Widget>[
            if (showDots)
              Positioned.fill(
                child: CustomPaint(
                  painter: _LeaderDotsPainter(
                    x0: formulaWidth + t.metrics.space8,
                    spacing: t.metrics.grid * 2,
                    radius: t.metrics.borderWidth,
                    color: t.palette.hairline,
                  ),
                ),
              ),
            field,
          ],
        ),
      ),
    );

    // 行槽 = [Gutter] + [输入（Flexible）] [结果]。
    final row = <Widget>[
      ?gutter,
      Expanded(child: input),
    ];

    final pendingHint = widget.canvas._pendingDelete.contains(index)
        ? Padding(
            padding: EdgeInsets.only(
              left: horizontalPad,
              bottom: t.metrics.space4,
            ),
            child: Text(
              '再按一次删除',
              style: t.typeScale.micro.copyWith(color: t.palette.textMuted),
            ),
          )
        : null;

    if (resultWidget == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(height: t.metrics.space6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: row,
          ),
          ?pendingHint,
          SizedBox(height: t.metrics.space6),
        ],
      );
    }

    // 结果槽：独立手势域（阻断穿透——点结果绝不聚焦输入框拉起键盘）。
    final resultSlot = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => canvas.onResultTap?.call(index),
      onLongPress: () => canvas.onResultLongPress?.call(index),
      child: ConstrainedBox(
        // 两行模式下限宽兜底：排版可截断（ellipsis），数据无损归业务。
        constraints: BoxConstraints(maxWidth: available),
        child: resultWidget,
      ),
    );

    if (!shouldSunk) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(height: t.metrics.space6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              ...row,
              SizedBox(width: canvas.resultGap),
              resultSlot,
              SizedBox(width: horizontalPad),
            ],
          ),
          ?pendingHint,
          SizedBox(height: t.metrics.space6),
        ],
      );
    }

    // 两行模式：公式占第一行全宽，第二行右对齐渲染结果。
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(height: t.metrics.space6),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: row,
        ),
        ?pendingHint,
        SizedBox(height: t.metrics.space4),
        Align(alignment: Alignment.centerRight, child: resultSlot),
        SizedBox(height: t.metrics.space6),
      ],
    );
  }

  double _measureText(String text, TextStyle style) {
    if (text.isEmpty) {
      return 0;
    }
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }
}

// ======================= 粘贴裂变（入口拦截） =======================

extension _FissionPaste on BlockCanvasState {
  /// 裂变感知的右键/长按菜单：复用默认按钮项，仅把「粘贴」替换为先读剪贴板
  /// 的裂变感知版本。
  ///
  /// 为什么在粘贴入口拦截而非 TextInputFormatter：EditableText 在
  /// `maxLines == 1` 时框架自带 `FilteringTextInputFormatter.singleLineFormatter`
  /// 且排在用户格式器**之前**（flutter/widgets/editable_text.dart），`\n` 在
  /// 到达任何用户格式器前已被剥掉——formatter 路线天然失效，只有粘贴动作入口
  /// 能在过滤发生前读到剪贴板原文。
  Widget fissionMenu(
    BuildContext context,
    EditableTextState state,
    int index,
  ) {
    final items = <ContextMenuButtonItem>[];
    for (final item in state.contextMenuButtonItems) {
      if (item.type == ContextMenuButtonType.paste) {
        items.add(
          ContextMenuButtonItem(
            label: item.label,
            onPressed: () => pasteWithFission(state, index),
          ),
        );
      } else {
        items.add(item);
      }
    }
    return AdaptiveTextSelectionToolbar.buttonItems(
      anchors: state.contextMenuAnchors,
      buttonItems: items,
    );
  }

  /// 粘贴执行：多行剪贴板走裂变事务（不经 TextField 默认粘贴——其会静默
  /// 过滤换行并块）；单行放行默认粘贴行为。
  Future<void> pasteWithFission(EditableTextState state, int index) async {
    if (await interceptClipboardPaste(index)) {
      return;
    }
    await state.pasteText(SelectionChangedCause.toolbar);
  }
}

/// 粘贴裂变决策（公开可测缝）：读剪贴板——多行 → 执行裂变事务并返回 true
/// （已拦截处理）；单行/空 → 返回 false（调用方放行默认粘贴）。
extension BlockCanvasPasteFission on BlockCanvasState {
  Future<bool> interceptClipboardPaste(int index) async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || !text.contains('\n')) {
      return false;
    }
    await _handleFission(index, text.split('\n'));
    return true;
  }
}

// ======================= 单行不变式守卫 =======================

/// 拦截 `\n` 进块：输入框改自适应换行后（`maxLines: null`），框架不再自动
/// 过滤换行——由本 formatter 接管「块内容恒单行文本」不变式（`evalLine`
/// 单行口径与粘贴裂变按行拆块的共同依赖）。硬件回车等直插 `\n` 的路径
/// 一律拦截（软件回车走 `textInputAction.next` 的 onSubmitted，不经此处）。
class _NoNewlineFormatter extends TextInputFormatter {
  const _NoNewlineFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) =>
      newValue.text.contains('\n') ? oldValue : newValue;
}

// ======================= 聚焦引线（Leader Dots） =======================

/// 隐形参考线：从公式末尾向输入区右缘铺点阵，视线在长留白中自然穿透到
/// 行尾结果（spec §一.1）。画在 TextField 之下的空区，不参与命中。
class _LeaderDotsPainter extends CustomPainter {
  _LeaderDotsPainter({
    required this.x0,
    required this.spacing,
    required this.radius,
    required this.color,
  }) : assert(spacing > 0);

  /// 点阵起始 x（公式测量宽 + 8dp 间距）；输入区右缘为终止。
  final double x0;

  /// 点间距（grid × 2）。
  final double spacing;

  /// 点半径（borderWidth 1dp）。
  final double radius;

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // 留白不足一个间距时不画（公式已写满该行）。
    if (size.width - x0 < spacing * 2) {
      return;
    }
    final paint = Paint()..color = color;
    final y = size.height / 2;
    for (var x = x0; x <= size.width - spacing; x += spacing) {
      canvas.drawCircle(Offset(x, y), radius, paint);
    }
  }

  @override
  bool shouldRepaint(_LeaderDotsPainter oldDelegate) =>
      oldDelegate.x0 != x0 ||
      oldDelegate.spacing != spacing ||
      oldDelegate.radius != radius ||
      oldDelegate.color != color;
}
