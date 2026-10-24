library;

import 'package:flutter/material.dart';

import '../ui_ports/status_port.dart';
import 'components/app_components.dart';
import 'components/readiness_components.dart';

/// 仪表盘：服务状态 + 权限就绪矩阵 + 实时调用流水。
///
/// 数据全部来自**类型化**适配层（`lib/ui_ports`）——本页不 import `lib/mcp/**`
/// 的传输类型、不消费 `{content,isError}` 文本信封（守 R2 / R4）。
class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key, required this.port});

  final StatusPort port;

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  late Future<List<ReadinessItem>> _readiness;

  /// 累积后的调用流水（**建一次**——若在 build 里新建流，每次重建都重订阅、
  /// 累积缓冲被清空，列表只剩最后一条）。
  late final Stream<List<CallEventView>> _events;

  @override
  void initState() {
    super.initState();
    _readiness = widget.port.readiness();
    _events = _accumulate(widget.port.callEvents);
  }

  /// 把逐条事件累积成「最近 N 条」列表。
  static Stream<List<CallEventView>> _accumulate(
    Stream<CallEventView> source,
  ) {
    final buffer = <CallEventView>[];
    return source.map((e) {
      buffer.add(e);
      if (buffer.length > 50) buffer.removeAt(0);
      return List<CallEventView>.unmodifiable(buffer);
    });
  }

  Future<void> _refresh() async {
    final next = widget.port.readiness();
    setState(() => _readiness = next);
  }

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    return ListView(
      padding: EdgeInsets.all(t.metrics.space16),
      children: <Widget>[
        SectionCard(
          title: '权限与配置',
          trailing: IconButton(
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
            tooltip: '重新检测',
          ),
          child: FutureBuilder<List<ReadinessItem>>(
            future: _readiness,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return Text('检测中…', style: t.typeScale.body);
              }
              if (snapshot.hasError) {
                return Text(
                  '检测失败：${snapshot.error}',
                  style: t.typeScale.body.copyWith(color: t.palette.danger),
                );
              }
              final items = snapshot.data ?? const <ReadinessItem>[];
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Wrap(
                    spacing: t.metrics.space8,
                    runSpacing: t.metrics.space8,
                    children: <Widget>[
                      for (final item in items) ReadinessPill(item: item),
                    ],
                  ),
                  SizedBox(height: t.metrics.space8),
                  for (final item in items)
                    if (item.detail != null)
                      Padding(
                        padding: EdgeInsets.only(top: t.metrics.space4),
                        child: Text(
                          '${item.label}：${item.detail}',
                          style: t.typeScale.micro
                              .copyWith(color: t.palette.textMuted),
                        ),
                      ),
                ],
              );
            },
          ),
        ),
        SizedBox(height: t.metrics.space16),
        SectionCard(
          title: '实时调用流水',
          child: SizedBox(
            height: 260,
            child: StreamBuilder<List<CallEventView>>(
              stream: _events,
              builder: (context, snapshot) {
                final events = snapshot.data ?? const <CallEventView>[];
                if (events.isEmpty) {
                  return const EmptyState(
                    message: '暂无调用记录',
                    detail: '外部 Agent 经 MCP 调用工具时，调用流水会实时出现在这里',
                  );
                }
                final rows = events.reversed.take(50).toList(growable: false);
                return ListView.separated(
                  itemCount: rows.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 4),
                  itemBuilder: (context, index) {
                    final e = rows[index];
                    return Row(
                      children: <Widget>[
                        SizedBox(
                          width: 72,
                          child: Text(e.timeText, style: t.typeScale.telemetry),
                        ),
                        Expanded(
                          child: Text(
                            e.name,
                            style: t.typeScale.telemetry,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        SizedBox(width: t.metrics.space8),
                        Text(
                          '${e.elapsedMs}ms',
                          style: t.typeScale.telemetry.copyWith(
                            color: e.ok ? t.palette.l1Ok : t.palette.danger,
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}


