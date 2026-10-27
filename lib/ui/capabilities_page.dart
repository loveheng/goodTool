library;

import 'package:flutter/material.dart';

import '../ui_ports/settings_port.dart';
import 'components/app_components.dart';
import 'home_shell.dart';

/// 能力域枚举（hub 导航 / 首页快捷 / main.dart 装配共用）。
enum AppDomain { calculator, calendar, geo, weather }

/// 首页快捷默认域（用户拍板 2026-10-26：日历）——未设置时的渲染层口径。
const AppDomain kHomePinnedDefault = AppDomain.calendar;

/// 域卡元数据（hub 与首页快捷共用）。
class DomainEntry {
  const DomainEntry({
    required this.domain,
    required this.title,
    required this.summary,
    required this.dependency,
    required this.icon,
  });

  final AppDomain domain;
  final String title;
  final String summary;

  /// 依赖说明（无需依赖 / 需权限 / 需 Key）。
  final String dependency;
  final IconData icon;
}

const List<DomainEntry> kDomainEntries = <DomainEntry>[
  DomainEntry(
    domain: AppDomain.calculator,
    title: '计算器',
    summary: '表达式求值 + 单位换算，Decimal 精确主链路',
    dependency: '无需任何依赖',
    icon: Icons.calculate_outlined,
  ),
  DomainEntry(
    domain: AppDomain.calendar,
    title: '日历',
    summary: '某日事件与重要标记快照（只读）',
    dependency: '需日历读取权限',
    icon: Icons.event_outlined,
  ),
  DomainEntry(
    domain: AppDomain.geo,
    title: '地图',
    summary: '搜索选点 · 四模态路线 · 测距 · 收藏 · 坐标纠偏',
    dependency: '无需任何依赖',
    icon: Icons.map_outlined,
  ),
  DomainEntry(
    domain: AppDomain.weather,
    title: '天气',
    summary: '实时天气 + 逐日预报 + 气象预警',
    dependency: '需和风天气 Key',
    icon: Icons.cloud_outlined,
  ),
];

/// 取域的元数据。
DomainEntry domainEntryOf(AppDomain domain) {
  for (final e in kDomainEntries) {
    if (e.domain == domain) return e;
  }
  return kDomainEntries.first;
}

/// 解析首页快捷的钉选原始值：未设置 / 非法值回落默认域 [kHomePinnedDefault]
/// （写侧 Actor 已校取值域，非法值只可能来自陈旧 KV 或人工改动）。
AppDomain resolvePinnedDomain(String? raw) {
  final v = raw?.trim();
  if (v == null || v.isEmpty) return kHomePinnedDefault;
  for (final d in AppDomain.values) {
    if (d.name == v) return d;
  }
  return kHomePinnedDefault;
}

/// push 打开域子页面（能力 hub 与首页快捷共用）。
///
/// **不再叠标题栏**：各域子页自带身份与顶部 UI（日历区间条 / 地图胶囊 /
/// 天气搜索面板 / 计算器标题行），外层标题属冗余且挤占显示面积；返回走系统
/// 返回手势（Android 边缘回滑 / 系统返回键），MaterialPageRoute 默认支持。
/// 外层仍包 Scaffold 以作为 SnackBar 的祖先（calculator / weather 用到）。
void openDomainPage(
  BuildContext context,
  Map<AppDomain, Widget> pages,
  DomainEntry entry,
) {
  Navigator.of(context).push(MaterialPageRoute<void>(
    builder: (_) => Scaffold(
      appBar: null,
      body: SafeArea(child: pages[entry.domain]!),
    ),
  ));
}

/// 能力 hub：四张域卡——分开看到、用到各部分功能（产品决策 2026-10-20，
/// 见 `docs/project/ui-console.md` §3.2）。
///
/// hub **只做入口与说明，不就绪探测**（探测归仪表盘矩阵与各子页面自身，
/// 防双源）；点击 push 对应域子页面；图钉设首页快捷（写经 [SettingsPort]
/// 用户侧命令，AI 不可触达）。
class CapabilitiesPage extends StatefulWidget {
  const CapabilitiesPage({
    super.key,
    required this.pages,
    required this.port,
  });

  /// 域 → 已装配的子页面实例（main.dart 注入端口后构造）。
  final Map<AppDomain, Widget> pages;

  /// 设置端口（读钉选快照 + 钉选写，写经用户侧注册表）。
  final SettingsPort port;

  @override
  State<CapabilitiesPage> createState() => _CapabilitiesPageState();
}

class _CapabilitiesPageState extends State<CapabilitiesPage> {
  /// 当前钉在首页的域名（null = 未设置，渲染回落默认域）。
  String? _pinned;
  bool _pinning = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final snapshot = await widget.port.read();
    if (!mounted) return;
    setState(() => _pinned = snapshot.homePinnedDomain);
  }

  Future<void> _pin(AppDomain domain) async {
    if (_pinning || _pinned == domain.name) return;
    setState(() => _pinning = true);
    final result = await widget.port.setHomePinnedDomain(domain.name);
    if (!mounted) return;
    setState(() => _pinning = false);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            result.ok
                ? '已将「${domainEntryOf(domain).title}」钉到首页'
                : '${result.errorCode}：${result.message ?? ''}',
          ),
        ),
      );
    if (result.ok) _pinned = domain.name;
  }

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final nav = ShellNav.maybeOf(context);
    return ListView(
      padding: EdgeInsets.all(t.metrics.space16),
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (nav != null)
              IconButton(
                onPressed: nav.openDrawer,
                icon: const Icon(Icons.menu),
                tooltip: '导航',
              ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('能力', style: t.typeScale.titleMedium),
                  SizedBox(height: t.metrics.space4),
                  Text(
                    '不依赖外部模型，自行验证内核正确性；与 Agent 侧 MCP 工具面共享同一内核。',
                    style: t.typeScale.micro.copyWith(color: t.palette.textMuted),
                  ),
                ],
              ),
            ),
          ],
        ),
        SizedBox(height: t.metrics.space16),
        for (final entry in kDomainEntries) ...<Widget>[
          DomainCard(
            entry: entry,
            pinned: _pinned == entry.domain.name,
            onOpen: () => openDomainPage(context, widget.pages, entry),
            onPin: () => _pin(entry.domain),
          ),
          SizedBox(height: t.metrics.space12),
        ],
      ],
    );
  }
}

/// 域卡：hub 与首页快捷共用。
///
/// [onPin] 为 null = 不渲染钉选控件（首页快捷卡）；[pinned] = 本卡已钉在
/// 首页——双通道（§6）：实心/轮廓图钉形状 + 「首页快捷」文字。
class DomainCard extends StatelessWidget {
  const DomainCard({
    super.key,
    required this.entry,
    required this.onOpen,
    this.onPin,
    this.pinned = false,
  });

  final DomainEntry entry;
  final VoidCallback onOpen;
  final VoidCallback? onPin;
  final bool pinned;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    return SectionCard(
      title: entry.title,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (onPin != null)
            IconButton(
              onPressed: onPin,
              icon: Icon(
                pinned ? Icons.push_pin : Icons.push_pin_outlined,
                color: pinned ? t.palette.l1Ok : t.palette.textMuted,
              ),
              tooltip: pinned ? '已钉在首页' : '钉到首页',
            ),
          const Icon(Icons.chevron_right),
        ],
      ),
      // InkWell 必须有 Material 祖先才有 hit-test（release 包 assert 被剥离
      // 后表现为点击无反应），透明 Material 不改变卡片视觉。
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onOpen,
          borderRadius: BorderRadius.circular(t.metrics.radiusMd),
          child: Padding(
            // 触控热区 ≥44dp（视觉不变，透明 padding 补足——ui-design §4.4）。
            padding: EdgeInsets.symmetric(vertical: t.metrics.space8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(entry.summary, style: t.typeScale.compact),
                SizedBox(height: t.metrics.space4),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        entry.dependency,
                        style: t.typeScale.micro
                            .copyWith(color: t.palette.textMuted),
                      ),
                    ),
                    if (pinned)
                      Text(
                        '首页快捷',
                        style: t.typeScale.micro
                            .copyWith(color: t.palette.l1Ok),
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
