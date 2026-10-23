library;

import 'package:flutter/material.dart';

import '../service/mcp_controller.dart';
import 'components/app_components.dart';

/// MCP HTTP 调试服务控制页（**隐藏入口**：设置页「关于」卡片长按进入）。
///
/// 产品口径（2026-10-20）：MCP HTTP 服务仅调试用，**不随启动自启**；开启后也只
/// 做桌面 **adb 直连**（本机回环 127.0.0.1 + `adb reverse tcp:8765 tcp:8765`），
/// 不做 Wi-Fi / LAN 暴露（mDNS 广播已随 2026-10-15 暴露面拍板退役）。
/// 生产通道走 Binder 引擎（mcp_binder_entrypoint.dart），与本页无关。
///
/// 写路径沿用既有口径：服务启停是运行时控制（非数据仓写），经 [McpController]，
/// 与原设置页「MCP 服务」卡一致（R1 的数据写纪律不适用于运行时服务开关）。
class McpServicePage extends StatefulWidget {
  const McpServicePage({super.key, required this.controller});

  final McpController controller;

  @override
  State<McpServicePage> createState() => _McpServicePageState();
}

class _McpServicePageState extends State<McpServicePage> {
  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final service = widget.controller;
    return Scaffold(
      appBar: AppBar(title: const Text('MCP 调试服务')),
      body: ListView(
        padding: EdgeInsets.all(t.metrics.space16),
        children: <Widget>[
          SectionCard(
            title: 'MCP 服务',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '仅调试用，不随 app 启动自启；开启后桌面端经 adb 直连，不做 Wi-Fi 连接。',
                  style: t.typeScale.compact
                      .copyWith(color: t.palette.textMuted),
                ),
                SizedBox(height: t.metrics.space8),
                Wrap(
                  spacing: t.metrics.space8,
                  runSpacing: t.metrics.space8,
                  children: <Widget>[
                    TelemetryText(
                        service.running ? '运行中' : '已停止',
                        color: service.running
                            ? t.palette.l1Ok
                            : t.palette.terminalMuted),
                    TelemetryText('端口 ${service.port}'),
                    TelemetryText(service.endpoint),
                  ],
                ),
                SizedBox(height: t.metrics.space8),
                Wrap(
                  spacing: t.metrics.space8,
                  children: <Widget>[
                    FilledButton(
                      onPressed: service.running
                          ? null
                          : () async {
                              await service.enable();
                              if (mounted) setState(() {});
                            },
                      child: const Text('启动'),
                    ),
                    OutlinedButton(
                      onPressed: service.running
                          ? () async {
                              await service.disable();
                              if (mounted) setState(() {});
                            }
                          : null,
                      child: const Text('停止'),
                    ),
                    OutlinedButton(
                      onPressed: () async {
                        await service.regenerateToken();
                        if (mounted) setState(() {});
                      },
                      child: const Text('重生成令牌'),
                    ),
                  ],
                ),
                if (service.lastError != null) ...<Widget>[
                  SizedBox(height: t.metrics.space8),
                  Text(
                    '上次错误：${service.lastError}',
                    style:
                        t.typeScale.compact.copyWith(color: t.palette.danger),
                  ),
                ],
              ],
            ),
          ),
          SizedBox(height: t.metrics.space16),
          SectionCard(
            title: '桌面直连步骤',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('① 本页点「启动」', style: t.typeScale.compact),
                SizedBox(height: t.metrics.space4),
                TelemetryText('adb reverse tcp:8765 tcp:8765'),
                SizedBox(height: t.metrics.space4),
                Text('② 桌面 Agent 连', style: t.typeScale.compact),
                SizedBox(height: t.metrics.space4),
                TelemetryText(service.endpoint),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
