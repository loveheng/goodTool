library;

import 'package:flutter/material.dart';

import 'components/app_components.dart';

/// 控制台外壳：三 Tab（仪表盘 / 沙盒 / 设置）。
///
/// 只做**导航与骨架**——各页内容由各页自持，页面级状态不进外壳（views-only）。
class HomeShell extends StatefulWidget {
  const HomeShell({
    super.key,
    required this.dashboard,
    required this.sandbox,
    required this.settings,
  });

  final Widget dashboard;
  final Widget sandbox;
  final Widget settings;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final pages = <Widget>[
      widget.dashboard,
      widget.sandbox,
      widget.settings,
    ];
    return Scaffold(
      appBar: AppBar(
        title: const Text('goodTools'),
        titleTextStyle: t.typeScale.titleMedium,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: t.metrics.contentMaxWidth),
          child: pages[_index],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const <NavigationDestination>[
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: '仪表盘',
          ),
          NavigationDestination(
            icon: Icon(Icons.science_outlined),
            selectedIcon: Icon(Icons.science),
            label: '沙盒',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: '设置',
          ),
        ],
      ),
    );
  }
}
