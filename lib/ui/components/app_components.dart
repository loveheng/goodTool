library;

import 'package:flutter/material.dart';

import '../tokens/app_tokens.dart';

/// 取当前主题的 token（唯一出处 `lib/ui/tokens/`；组件内禁散落魔法值）。
AppTokens tokensOf(BuildContext context) =>
    Theme.of(context).extension<AppTokens>()!;

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

/// 结构化错误行：机器码 + 说明 + 自愈建议（不吞错、不静默）。
///
/// 各域子页面共用（计算器 / 地图 / 日历 / 天气的失败态同形状）。
class ErrorLine extends StatelessWidget {
  const ErrorLine({super.key, this.code, this.message, this.suggestion});

  final String? code;
  final String? message;
  final String? suggestion;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          code == null ? (message ?? '') : '$code：${message ?? ''}',
          style: t.typeScale.compact.copyWith(color: t.palette.danger),
        ),
        if (suggestion != null)
          Padding(
            padding: EdgeInsets.only(top: t.metrics.space4),
            child: Text(
              suggestion!,
              style: t.typeScale.micro.copyWith(color: t.palette.textMuted),
            ),
          ),
      ],
    );
  }
}

/// 引导卡（L2 警告色）：缺依赖（权限 / Key）时给可操作下一步（ui-design §3.4）。
class GuidanceCard extends StatelessWidget {
  const GuidanceCard({
    super.key,
    required this.message,
    required this.actionLabel,
    required this.onAction,
    this.detail,
  });

  final String message;
  final String? detail;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(t.metrics.space12),
      decoration: BoxDecoration(
        color: t.palette.l2Warn.withValues(alpha: 0.12),
        border: Border.all(
          color: t.palette.l2Warn,
          width: t.metrics.borderWidth,
        ),
        borderRadius: BorderRadius.circular(t.metrics.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            message,
            style: t.typeScale.compact.copyWith(color: t.palette.l2Warn),
          ),
          if (detail != null) ...<Widget>[
            SizedBox(height: t.metrics.space4),
            Text(
              detail!,
              style: t.typeScale.micro.copyWith(color: t.palette.textMuted),
            ),
          ],
          SizedBox(height: t.metrics.space8),
          FilledButton(onPressed: onAction, child: Text(actionLabel)),
        ],
      ),
    );
  }
}
