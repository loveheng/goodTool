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

  /// 底部导航显隐（滚动下滑隐藏、上滑/触顶/切 Tab 显现）。
  bool _navVisible = true;

  /// 上次滚动位置（位移阈值判定方向，避免引入未导出的渲染库枚举）。
  double _lastScrollPixels = 0;

  void _openSettings() => _selectTab(2);

  void _selectTab(int i) {
    if (i == _index && _navVisible) return;
    setState(() {
      _index = i;
      _navVisible = true;
      _lastScrollPixels = 0;
    });
  }

  /// 滚动位移 → 底部导航显隐：下滑（pixels 增）隐藏，上滑（减）显现；
  /// 触顶（pixels≤min）强制显现，保证随时可切 Tab；阈值 4dp 滤抖动。
  bool _onScroll(ScrollNotification n) {
    if (n is ScrollUpdateNotification) {
      final p = n.metrics.pixels;
      if (p <= n.metrics.minScrollExtent) {
        if (!_navVisible) setState(() => _navVisible = true);
      } else {
        final delta = p - _lastScrollPixels;
        if (delta > 4 && _navVisible) {
          setState(() => _navVisible = false);
        } else if (delta < -4 && !_navVisible) {
          setState(() => _navVisible = true);
        }
      }
      _lastScrollPixels = p;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final pages = <Widget>[
      widget.dashboard,
      widget.capabilities,
      widget.settings,
    ];
    // 移除顶部标题栏（不再以 AppBar 占用顶部面积），内容自行避让状态栏。
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final navHeight = 80.0 + bottomInset;
    return ShellNav(
      onOpenSettings: _openSettings,
      child: Scaffold(
        body: SafeArea(
          // 顶部避让状态栏；底部避让系统手势条，防止末项被遮挡。
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: t.metrics.contentMaxWidth),
              child: NotificationListener<ScrollNotification>(
                onNotification: _onScroll,
                child: pages[_index],
              ),
            ),
          ),
        ),
        bottomNavigationBar: ClipRect(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeInOut,
            height: _navVisible ? navHeight : 0,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                NavigationBar(
                  selectedIndex: _index,
                  onDestinationSelected: _selectTab,
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}
