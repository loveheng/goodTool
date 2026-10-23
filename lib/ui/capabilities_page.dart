library;

import 'package:flutter/material.dart';

import 'components/app_components.dart';

/// 能力域枚举（hub 导航与 main.dart 装配共用）。
enum AppDomain { calculator, calendar, geo, weather }

/// 能力 hub：四张域卡——分开看到、用到各部分功能（产品决策 2026-10-20，
/// 见 `docs/project/ui-console.md` §3.2）。
///
/// hub **只做入口与说明，不就绪探测**（探测归仪表盘矩阵与各子页面自身，
/// 防双源）；点击 push 对应域子页面。
class CapabilitiesPage extends StatelessWidget {
  const CapabilitiesPage({super.key, required this.pages});

  /// 域 → 已装配的子页面实例（main.dart 注入端口后构造）。
  final Map<AppDomain, Widget> pages;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    return ListView(
      padding: EdgeInsets.all(t.metrics.space16),
      children: <Widget>[
        Text('能力', style: t.typeScale.titleMedium),
        SizedBox(height: t.metrics.space4),
        Text(
          '不依赖外部模型，自行验证内核正确性；与 Agent 侧 MCP 工具面共享同一内核。',
          style: t.typeScale.micro.copyWith(color: t.palette.textMuted),
        ),
        SizedBox(height: t.metrics.space16),
        for (final entry in _entries) ...<Widget>[
          _DomainCard(
            entry: entry,
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => pages[entry.domain]!,
            )),
          ),
          SizedBox(height: t.metrics.space12),
        ],
      ],
    );
  }
}

/// 域卡元数据（静态说明；就绪态在子页面内自呈）。
class _DomainEntry {
  const _DomainEntry({
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

const List<_DomainEntry> _entries = <_DomainEntry>[
  _DomainEntry(
    domain: AppDomain.calculator,
    title: '计算器',
    summary: '表达式求值 + 单位换算，Decimal 精确主链路',
    dependency: '无需任何依赖',
    icon: Icons.calculate_outlined,
  ),
  _DomainEntry(
    domain: AppDomain.calendar,
    title: '日历',
    summary: '某日事件与重要标记快照（只读）',
    dependency: '需日历读取权限',
    icon: Icons.event_outlined,
  ),
  _DomainEntry(
    domain: AppDomain.geo,
    title: '地图',
    summary: '坐标纠偏（三系同屏）与两点测距',
    dependency: '无需任何依赖',
    icon: Icons.map_outlined,
  ),
  _DomainEntry(
    domain: AppDomain.weather,
    title: '天气',
    summary: '实时天气 + 逐日预报 + 气象预警',
    dependency: '需和风天气 Key',
    icon: Icons.cloud_outlined,
  ),
];

class _DomainCard extends StatelessWidget {
  const _DomainCard({required this.entry, required this.onTap});

  final _DomainEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    return SectionCard(
      title: entry.title,
      trailing: const Icon(Icons.chevron_right),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(t.metrics.radiusMd),
        child: Padding(
          // 触控热区 ≥44dp（视觉不变，透明 padding 补足——ui-design §4.4）。
          padding: EdgeInsets.symmetric(vertical: t.metrics.space8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(entry.summary, style: t.typeScale.compact),
              SizedBox(height: t.metrics.space4),
              Text(
                entry.dependency,
                style: t.typeScale.micro.copyWith(color: t.palette.textMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
