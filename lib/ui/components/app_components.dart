library;

import 'package:flutter/material.dart';

import '../../ui_ports/status_port.dart';
import '../tokens/app_tokens.dart';

/// 取当前主题的 token（唯一出处 `lib/ui/tokens/`；组件内禁散落魔法值）。
AppTokens tokensOf(BuildContext context) =>
    Theme.of(context).extension<AppTokens>()!;

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

/// 细边框卡（1dp hairline；禁大范围弥散投影）。
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.title,
    required this.child,
    this.trailing,
  });

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(t.metrics.space16),
      decoration: BoxDecoration(
        color: t.palette.surfaceRaised,
        border: Border.all(color: t.palette.hairline, width: t.metrics.borderWidth),
        borderRadius: BorderRadius.circular(t.metrics.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(child: Text(title, style: t.typeScale.titleMedium)),
              ?trailing,
            ],
          ),
          SizedBox(height: t.metrics.space12),
          child,
        ],
      ),
    );
  }
}

/// 遥测轨文本：等宽字体 + 微弱底色容器（ui-design §2 双轨排印）。
///
/// 遥测内容（时间戳 / 经纬度 / 计算结果 / 端口号 / JSON 预览）**必须**走本组件——
/// 不得用阅读轨字体呈现数值。
class TelemetryText extends StatelessWidget {
  const TelemetryText(
    this.text, {
    super.key,
    this.color,
  });

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: t.metrics.space8,
        vertical: t.metrics.space4,
      ),
      decoration: BoxDecoration(
        color: t.palette.codeBg,
        borderRadius: BorderRadius.circular(t.metrics.radiusBadge),
      ),
      child: Text(
        text,
        style: color == null
            ? t.typeScale.telemetry
            : t.typeScale.telemetry.copyWith(color: color),
      ),
    );
  }
}

/// 空态占位：居中人话提示（限宽与页面同轴；禁高亮扫光）。
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.message, this.detail});

  final String message;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: t.metrics.emptyStateMaxWidth),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              message,
              textAlign: TextAlign.center,
              style: t.typeScale.body,
            ),
            if (detail != null) ...<Widget>[
              SizedBox(height: t.metrics.space4),
              Text(
                detail!,
                textAlign: TextAlign.center,
                style: t.typeScale.micro.copyWith(color: t.palette.textMuted),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
