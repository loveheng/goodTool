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
    required this.openDrawer,
  });

  /// 跳转到设置 Tab（域页面引导「去设置」用）。
  final VoidCallback onOpenSettings;

  /// 打开 ☰ 导航抽屉（Tab 页顶栏汉堡按钮调用）。
  final VoidCallback openDrawer;

  /// 可能为 null（页面被独立用于测试/预览时）。
  static ShellNav? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ShellNav>();

  @override
  bool updateShouldNotify(ShellNav oldWidget) =>
      onOpenSettings != oldWidget.onOpenSettings ||
      openDrawer != oldWidget.openDrawer;
}

/// 控制台外壳：三 Tab（仪表盘 / 能力 / 设置）走 **☰ 导航抽屉**（M3
/// NavigationDrawer）。
///
/// 只做**导航与骨架**——各页内容由各页自持，页面级状态不进外壳（views-only）。
/// 域子页面由能力 hub push 进入（带返回），不占 Tab 位。
///
/// 为什么是抽屉而非底部 NavigationBar：日历等页是全屏纵向滚动条带，底部横条
/// 恰好压在滑动热区上（上滑展开面板/滑动条带被 Tab 条吞手势）；抽屉平时不占
/// 屏，左缘滑动或 Tab 页顶栏 ☰ 呼出，纵向滑动热区完整让给内容。
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
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  int _index = 0;

  void _openSettings() => _selectTab(2);

  /// ShellNav 通道切页（不经抽屉，无需收起）。
  void _selectTab(int i) {
    if (i == _index) return;
    setState(() => _index = i);
  }

  void _openDrawer() => _scaffoldKey.currentState?.openDrawer();

  /// 抽屉选 Tab：先收起抽屉，再切页（同页只收不切）。
  void _onDrawerSelect(int i) {
    Navigator.of(context).pop();
    if (i == _index) return;
    setState(() => _index = i);
  }

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
      openDrawer: _openDrawer,
      child: Scaffold(
        key: _scaffoldKey,
        drawer: NavigationDrawerTheme(
          data: NavigationDrawerThemeData(
            iconTheme: WidgetStateProperty.resolveWith<IconThemeData?>(
              (states) => IconThemeData(
                size: t.metrics.drawerIconSize,
                color: states.contains(WidgetState.selected)
                    ? t.palette.onSurface
                    : t.palette.onSurfaceVariant,
              ),
            ),
            labelTextStyle: WidgetStateProperty.resolveWith<TextStyle?>(
              (states) => (states.contains(WidgetState.selected)
                      ? t.typeScale.titleSmall
                      : t.typeScale.listItem)
                  .copyWith(
                color: states.contains(WidgetState.selected)
                    ? t.palette.onSurface
                    : t.palette.onSurfaceVariant,
              ),
            ),
          ),
          child: NavigationDrawer(
            selectedIndex: _index,
            onDestinationSelected: _onDrawerSelect,
            children: <Widget>[
              Padding(
                padding: EdgeInsets.fromLTRB(
                  t.metrics.space16,
                  t.metrics.space16,
                  t.metrics.space16,
                  t.metrics.space4,
                ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('工具', style: t.typeScale.titleMedium),
                ),
              ),
              const NavigationDrawerDestination(
                icon: Icon(Icons.dashboard_outlined),
                selectedIcon: Icon(Icons.dashboard),
                label: Text('首页'),
              ),
              const NavigationDrawerDestination(
                icon: Icon(Icons.apps_outlined),
                selectedIcon: Icon(Icons.apps),
                label: Text('能力'),
              ),
              const NavigationDrawerDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings),
                label: Text('设置'),
              ),
            ],
          ),
        ),
        body: SafeArea(
          // 顶部避让状态栏；底部避让系统手势条，防止末项被遮挡。
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: t.metrics.contentMaxWidth),
              child: pages[_index],
            ),
          ),
        ),
      ),
    );
  }
}
