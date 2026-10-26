library;

import 'package:flutter/material.dart';

import '../ui_ports/settings_port.dart';
import 'capabilities_page.dart';
import 'components/app_components.dart';

/// 仪表盘：**首页本体 = 钉住域的二级页面**（产品决策 2026-10-26：不留快捷卡
/// 中间层，整个首页为钉住的页面服务——去掉「卡片 → 进入」一步）。
///
/// 钉选在能力页（单选图钉，默认日历）；本页只读钉住域并渲染对应子页面，
/// **与能力 hub 共用同一份子页面实例**（main.dart 单点装配）。
class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key, required this.port, required this.pages});

  final SettingsPort port;

  /// 域 → 已装配的子页面实例（与能力 hub 同一份，main.dart 共享）。
  final Map<AppDomain, Widget> pages;

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  String? _pinned;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final snapshot = await widget.port.read();
    if (!mounted) return;
    setState(() {
      _pinned = snapshot.homePinnedDomain;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      final t = tokensOf(context);
      return Center(child: Text('加载中…', style: t.typeScale.body));
    }
    // 子页面原样渲染：calendar / geo 自带 Scaffold；calculator / weather 为裸件，
    // Material 祖先由 HomeShell 的 Scaffold 提供（push 红屏问题在此不成立）；
    // 不再包标题栏——首页为这页服务。
    return widget.pages[resolvePinnedDomain(_pinned)]!;
  }
}
