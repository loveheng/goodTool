library;

import 'package:flutter/material.dart';

import 'components/app_components.dart';

/// 外壳导航面：子页面（域页面）经此跳转设置 Tab / 获取外壳能力。
///
/// 用 InheritedWidget 而非构造函数逐层传回调——域子页面由 hub push 而来，
/// 构造链不经外壳；导航能力属「外壳环境」，不是页面数据（不涉 R1/R5）。
class ShellNav extends InheritedWidget {
  const ShellNav({
    super.key,
    required super.child,
    required this.onOpenSettings,
  });

  /// 跳转到设置 Tab（域页面引导「去设置」用）。
  final VoidCallback onOpenSettings;

  /// 可能为 null（页面被独立用于测试/预览时）。
  static ShellNav? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ShellNav>();

  @override
  bool updateShouldNotify(ShellNav oldWidget) =>
      onOpenSettings != oldWidget.onOpenSettings;
}

/// 控制台外壳：三 Tab（仪表盘 / 能力 / 设置）。
///
/// 只做**导航与骨架**——各页内容由各页自持，页面级状态不进外壳（views-only）。
/// 域子页面由能力 hub push 进入（带返回），不占 Tab 位。
class HomeShell extends StatefulWidget {
  const HomeShell({
    super.key,
    required this.dashboard,
    required this.capabilities,
    required this.settings,
  });

  final Widget dashboard;
  final Widget capabilities;
  final Widget settings;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  void _openSettings() => setState(() => _index = 2);

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final pages = <Widget>[
      widget.dashboard,
      widget.capabilities,
      widget.settings,
    ];
    return ShellNav(
      onOpenSettings: _openSettings,
      child: Scaffold(
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
              icon: Icon(Icons.apps_outlined),
              selectedIcon: Icon(Icons.apps),
              label: '能力',
            ),
            NavigationDestination(
              icon: Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings),
              label: '设置',
            ),
          ],
        ),
      ),
    );
  }
}
