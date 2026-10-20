library;

import 'package:flutter/material.dart';

import '../mcp/calendar_provider.dart';
import '../ui_ports/calendar_port.dart';
import 'components/app_components.dart';
import 'home_shell.dart';

/// 日历子页面：某日事件 + 重要标记**只读快照** + 运行时权限申请入口（U12b）。
///
/// 定位红线（ui-console.md §1）：**不做日程管理**——本页不提供事件/标记增删改，
/// 写归系统日历本身与 Agent 侧 W 档命令；UI 只读。
class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key, required this.port});

  final CalendarPort port;

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  final _date = TextEditingController();
  CalendarSnapshotView? _snapshot;
  bool _loading = false;

  /// 权限申请反馈（人话；透出机器码）。
  String? _permissionHint;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    _date.text = '${now.year}-${two(now.month)}-${two(now.day)}';
  }

  @override
  void dispose() {
    _date.dispose();
    super.dispose();
  }

  Future<void> _loadSnapshot() async {
    setState(() => _loading = true);
    final view = await widget.port.snapshot(date: _date.text.trim());
    if (!mounted) return;
    setState(() {
      _snapshot = view;
      _loading = false;
    });
  }

  /// U12b：未授权 → 引导卡按钮 → 平台通道申请（跳转系统设置）。
  Future<void> _requestPermission() async {
    final view = await widget.port.requestPermission();
    if (!mounted) return;
    setState(() {
      if (!view.ok) {
        _permissionHint = '${view.errorCode}：${view.message ?? ''}';
      } else if (view.granted) {
        _permissionHint = '日历权限已授予，重新读取即可';
      } else {
        _permissionHint = '已打开系统设置，授予日历权限后返回点「读取」';
      }
    });
    if (view.ok && view.granted) await _loadSnapshot();
  }

  /// 快照是否因权限/源不可用而需要引导。
  bool get _needsGuidance {
    final s = _snapshot;
    if (s == null) return false;
    return s.errorCode == CalendarErr.permissionDenied ||
        s.errorCode == CalendarErr.sourceUnavailable ||
        s.warnings.any((w) => w.startsWith(CalendarErr.permissionDenied));
  }

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final shell = ShellNav.maybeOf(context);
    return ListView(
      padding: EdgeInsets.all(t.metrics.space16),
      children: <Widget>[
        SectionCard(
          title: '日历快照',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      controller: _date,
                      decoration: const InputDecoration(
                          labelText: '日期 YYYY-MM-DD'),
                    ),
                  ),
                  SizedBox(width: t.metrics.space8),
                  FilledButton(
                    onPressed: _loading ? null : _loadSnapshot,
                    child: const Text('读取'),
                  ),
                ],
              ),
              SizedBox(height: t.metrics.space8),
              if (_needsGuidance) ...<Widget>[
                GuidanceCard(
                  message: '无法读取系统日历：未授予日历权限',
                  detail: '日历快照需要系统日历读取权限；授予后即可查看当天事件',
                  actionLabel: '去授权',
                  onAction: _requestPermission,
                ),
                SizedBox(height: t.metrics.space8),
              ],
              if (_permissionHint != null) ...<Widget>[
                Text(
                  _permissionHint!,
                  style: t.typeScale.micro.copyWith(color: t.palette.textMuted),
                ),
                SizedBox(height: t.metrics.space8),
              ],
              if (_loading)
                Text('读取中…', style: t.typeScale.body)
              else if (_snapshot != null)
                _SnapshotView(view: _snapshot!)
              else
                const EmptyState(message: '选择日期后读取当天事件与重要标记'),
            ],
          ),
        ),
        SizedBox(height: t.metrics.space16),
        // 脱敏开关联动提示（U12a）：开关态在设置页维护，此处只读展示。
        SectionCard(
          title: '脱敏说明',
          child: Text(
            '日程地点与描述中的电话、邮箱按设置页「日程敏感字段过滤」开关处理（默认开）。',
            style: t.typeScale.compact,
          ),
        ),
        if (shell != null) ...[
          SizedBox(height: t.metrics.space8),
          TextButton(
            onPressed: shell.onOpenSettings,
            child: const Text('去设置页调整'),
          ),
        ],
      ],
    );
  }
}

/// 日历快照展示（事件 + 标记 + 子源告警）。
class _SnapshotView extends StatelessWidget {
  const _SnapshotView({required this.view});

  final CalendarSnapshotView view;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    if (view.errorCode != null) {
      return ErrorLine(code: view.errorCode, message: view.message);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (view.warnings.isNotEmpty)
          for (final w in view.warnings)
            Padding(
              padding: EdgeInsets.only(bottom: t.metrics.space4),
              child: Text(
                w,
                style: t.typeScale.micro.copyWith(color: t.palette.l2Warn),
              ),
            ),
        if (view.events.isEmpty && view.markers.isEmpty)
          const EmptyState(message: '当天没有事件与重要标记')
        else ...<Widget>[
          for (final e in view.events)
            Padding(
              padding: EdgeInsets.only(bottom: t.metrics.space4),
              child: Row(
                children: <Widget>[
                  SizedBox(
                    width: 56,
                    child: Text(e.timeText, style: t.typeScale.telemetry),
                  ),
                  Expanded(
                    child: Text(e.title, style: t.typeScale.listItem),
                  ),
                ],
              ),
            ),
          for (final m in view.markers)
            Padding(
              padding: EdgeInsets.only(bottom: t.metrics.space4),
              child: Row(
                children: <Widget>[
                  SizedBox(
                    width: 56,
                    child: Text('标记', style: t.typeScale.telemetry),
                  ),
                  Expanded(
                    child: Text(
                      '${m.title}（${m.originalDate}）',
                      style: t.typeScale.listItem,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }
}
