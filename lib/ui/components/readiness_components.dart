library;

/// 就绪状态组件（StatusDot / ReadinessPill）：**域感知件**——状态类型
/// `ReadinessState` / `ReadinessItem` 来自 `ui_ports/status_port.dart`，
/// 不属零域耦合的组件基座（模板基座只收 `app_components.dart` 纯件）。
import 'package:flutter/material.dart';

import '../../ui_ports/readiness.dart';
import 'app_components.dart';

/// 状态点：**色相 + 形状双通道**（ui-design §6 无障碍红线——禁仅以颜色传达状态）。
///
/// 形状约定：正常 = 圆、缺失 = 方形、被拒 = 三角。色弱与强光下仅凭第二通道可判态。
class StatusDot extends StatelessWidget {
  const StatusDot({super.key, required this.state});

  final ReadinessState state;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final p = t.palette;
    final size = t.metrics.statusDotSize;
    final color = switch (state) {
      ReadinessState.ready => p.l1Ok,
      ReadinessState.missing => p.terminalMuted,
      ReadinessState.denied => p.danger,
    };
    return SizedBox(
      width: size,
      height: size,
      child: switch (state) {
        ReadinessState.ready => DecoratedBox(
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
        ReadinessState.missing => DecoratedBox(
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(t.metrics.radiusBadge),
            ),
          ),
        ReadinessState.denied => CustomPaint(
            painter: _TrianglePainter(color),
          ),
      },
    );
  }
}

/// 被拒态三角（形状通道的第二判据）。
class _TrianglePainter extends CustomPainter {
  _TrianglePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(size.width / 2, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_TrianglePainter oldDelegate) => oldDelegate.color != color;
}

/// 就绪药丸：状态点 + 文字标签（**禁仅以绿点示意**）。
class ReadinessPill extends StatelessWidget {
  const ReadinessPill({super.key, required this.item});

  final ReadinessItem item;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final p = t.palette;
    final label = switch (item.state) {
      ReadinessState.ready => '就绪',
      ReadinessState.missing => '未就绪',
      ReadinessState.denied => '被拒',
    };
    final stateColor = switch (item.state) {
      ReadinessState.ready => p.l1Ok,
      ReadinessState.missing => p.terminalMuted,
      ReadinessState.denied => p.danger,
    };
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: t.metrics.space8,
        vertical: t.metrics.space4,
      ),
      decoration: BoxDecoration(
        border: Border.all(color: p.hairline, width: t.metrics.borderWidth),
        borderRadius: BorderRadius.circular(t.metrics.radiusBadge),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          StatusDot(state: item.state),
          SizedBox(width: t.metrics.space4),
          Text(item.label, style: t.typeScale.compact),
          SizedBox(width: t.metrics.space4),
          Text(
            label,
            style: t.typeScale.compact.copyWith(color: stateColor),
          ),
        ],
      ),
    );
  }
}
