library;

import 'package:flutter/material.dart';

import '../action/command_gateway.dart';
import '../action/weather_commands.dart';
import '../mcp/weather_provider.dart';
import '../repository/weather_city_repository.dart';
import '../service/weather_city_store.dart';
import '../ui_ports/weather_port.dart';
import 'components/app_components.dart';
import 'home_shell.dart';
import 'tokens/app_tokens.dart';

/// 天气子页面：已添加城市列表（手风琴卡片：点卡片就地展开实时天气详情）+
/// 底部胶囊搜索条（上滑半屏/全屏面板搜索、添加城市）。
///
/// 手势即操作（无按钮）：**左滑卡片删除**（Dismissible，撤销走 SnackBar）、
/// 点卡片展开/收起、搜索提交走键盘搜索键（suffix 仅搜索中的进度指示）。
/// 面板交互范式对齐地图页（geo_page `DraggableScrollableSheet`：snap 档位、
/// 把手、搜索框 Listener 快甩 + FocusNode 守卫、`viewInsets` 防键盘遮挡）。
/// 与 MCP 工具面共享同一 `WeatherProvider` 实例（装配期注入）——UI 与 Agent
/// 同源，频控与缓存不分裂；本页不消费文本信封（守 R2）。
class WeatherPage extends StatefulWidget {
  const WeatherPage({
    super.key,
    required this.port,
    required this.cities,
    required this.gateway,
  });

  final WeatherPort port;
  final WeatherCityRepository cities;
  final CommandGateway gateway;

  @override
  State<WeatherPage> createState() => _WeatherPageState();
}

class _WeatherPageState extends State<WeatherPage> {
  final _sheetController = DraggableScrollableController();
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();

  /// 搜索框指针事件起点（快甩展开/收齐面板；聚焦输入时禁用防误触）。
  double? _searchFlickStartY;

  List<WeatherCity> _cities = const <WeatherCity>[];

  /// 手风琴展开的城市 id（单开；null = 全收起）。
  String? _expandedId;
  WeatherView? _view;
  bool _loading = false;
  bool _searching = false;
  CitySearchView? _searchResult;

  /// 逐城天气摘要（城市列表行内展示；key = city.id）。
  ///
  /// 摘要与「点城市取数」详情**共用 provider 的逐城 TTL 缓存**（30min，同一
  /// `location#days` 键）——摘要先行预热，点进详情直接命中缓存；删除城市即剪枝。
  final Map<String, WeatherView> _summaries = <String, WeatherView>{};

  /// 聚合进行中的城市 id（防并发重复取数；逐城串行补数护频控）。
  final Set<String> _summarizing = <String>{};

  double _sheetMinSize() =>
      MediaQuery.of(context).orientation == Orientation.landscape ? 0.35 : 0.22;

  double _sheetMaxSize() =>
      MediaQuery.of(context).orientation == Orientation.landscape ? 0.75 : 0.95;

  @override
  void initState() {
    super.initState();
    _refreshCities();
  }

  @override
  void dispose() {
    _sheetController.dispose();
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> _refreshCities() async {
    final list = await widget.cities.list();
    if (!mounted) return;
    setState(() => _cities = list);
    _aggregateSummaries();
  }

  /// 逐城聚合列表摘要：命中 provider 缓存的城市零出网，未命中的**逐城串行**
  /// 补数（开发版和风配额低，避免 10 城并发取数触发频控）。
  ///
  /// `days` 用缺省 3——与「点城市取数」同键，摘要先行预热后点详情直接回放缓存。
  Future<void> _aggregateSummaries() async {
    final ids = _cities.map((c) => c.id).toSet();
    _summaries.removeWhere((id, _) => !ids.contains(id));
    for (final city in _cities) {
      if (_summaries.containsKey(city.id) || !_summarizing.add(city.id)) {
        continue;
      }
      final view = await widget.port.forecast(lat: city.lat, lng: city.lng);
      if (!mounted) return;
      setState(() {
        _summarizing.remove(city.id);
        // 列表中途变化（删除/重挂）则丢弃过期摘要，不留悬挂条目。
        if (_cities.any((c) => c.id == city.id)) {
          _summaries[city.id] = view;
        }
      });
    }
  }

  Future<void> _addCity(WeatherCityOptionView option) async {
    final result = await widget.gateway
        .dispatchUser(UserWeatherCityAddCommand(<String, Object?>{
      'name': option.name,
      'lat': option.lat,
      'lng': option.lng,
      if (option.locationId != null) 'locationId': option.locationId,
    }));
    if (!mounted) return;
    if (result.ok) {
      _searchController.clear();
      setState(() => _searchResult = null);
      await _refreshCities();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(result.message ?? '添加失败'),
      ));
    }
  }

  /// 左滑删除（Dismissible onDismissed）：**乐观移除**先行——Dismissible 要求
  /// 条目同步离场，命令派发失败则经 store 重读回滚 + SnackBar 提示；
  /// 成功给「撤销」动作（同名重添加，新 id，配额校验在 Actor 侧照常生效）。
  Future<void> _dismissCity(WeatherCity city) async {
    setState(() {
      _cities = _cities.where((c) => c.id != city.id).toList(growable: false);
      _summaries.remove(city.id);
      if (_expandedId == city.id) {
        _expandedId = null;
        _view = null;
      }
    });
    final result = await widget.gateway
        .dispatchUser(UserWeatherCityDeleteCommand(<String, Object?>{
      'id': city.id,
    }));
    if (!mounted) return;
    if (!result.ok) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('删除失败：${result.message ?? result.errorCode}'),
      ));
      await _refreshCities();
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('已删除 ${city.name}'),
      action: SnackBarAction(
        label: '撤销',
        onPressed: () async {
          final reAdd = await widget.gateway
              .dispatchUser(UserWeatherCityAddCommand(<String, Object?>{
            'name': city.name,
            'lat': city.lat,
            'lng': city.lng,
            if (city.locationId != null) 'locationId': city.locationId,
          }));
          if (!mounted) return;
          if (!reAdd.ok) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('撤销失败：${reAdd.message ?? reAdd.errorCode}'),
            ));
          }
          await _refreshCities();
        },
      ),
    ));
    await _refreshCities();
  }

  /// 手风琴切换：点已展开卡片收起；点收起卡片展开并按坐标取数
  /// （provider 逐城 TTL 缓存——摘要预热后点开直接回放缓存）。
  Future<void> _toggleCity(WeatherCity city) async {
    if (_expandedId == city.id) {
      setState(() {
        _expandedId = null;
        _view = null;
      });
      return;
    }
    setState(() {
      _expandedId = city.id;
      _loading = true;
    });
    final view = await widget.port.forecast(lat: city.lat, lng: city.lng);
    if (!mounted) return;
    setState(() {
      _view = view;
      _loading = false;
      // 详情与摘要同键取数：最新结果同步回列表行，行内摘要不滞留旧值。
      if (_cities.any((c) => c.id == city.id)) {
        _summaries[city.id] = view;
      }
    });
  }

  Future<void> _search() async {
    final q = _searchController.text.trim();
    if (q.isEmpty) return;
    setState(() => _searching = true);
    final r = await widget.port.searchCity(q);
    if (!mounted) return;
    setState(() {
      _searchResult = r;
      _searching = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    return Stack(
      children: <Widget>[
        // 城市列表与天气详情（铺满整页；搜索条/面板为浮层，上滑面板即功能面）。
        Positioned.fill(
          bottom: MediaQuery.of(context).size.height * _sheetMinSize(),
          child: _buildCityArea(t),
        ),
        _buildBottomSheet(t),
      ],
    );
  }

  // ---- 城市区（手风琴卡片：摘要行 + 就地展开详情；左滑删除） ----

  Widget _buildCityArea(AppTokens t) {
    return ListView(
      padding: EdgeInsets.all(t.metrics.space16),
      children: <Widget>[
        if (_cities.isEmpty)
          Padding(
            padding: EdgeInsets.symmetric(vertical: t.metrics.space16),
            child: Center(
              child: Text(
                '还没有城市，从下方搜索添加',
                style: t.typeScale.body.copyWith(color: t.palette.textMuted),
              ),
            ),
          )
        else
          for (final city in _cities)
            Padding(
              padding: EdgeInsets.only(bottom: t.metrics.space8),
              child: _buildCityCard(t, city),
            ),
        // 手势说明（唯一说明行；操作面全走手势，无按钮）。
        Padding(
          padding: EdgeInsets.only(top: t.metrics.space4),
          child: Center(
            child: Text(
              '左滑删除 · 点卡片展开/收起详情',
              style: t.typeScale.micro.copyWith(color: t.palette.textMuted),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCityCard(AppTokens t, WeatherCity city) {
    final expanded = _expandedId == city.id;
    return Dismissible(
      key: ValueKey('weather_city_${city.id}'),
      direction: DismissDirection.endToStart,
      // 手势代替按钮（用户验收反馈）：左滑整条露出删除底色，松手即删——
      // 不设二次确认弹窗，SnackBar「撤销」兜底（误滑可一键恢复）。
      background: Container(
        alignment: Alignment.centerRight,
        padding: EdgeInsets.only(right: t.metrics.space16),
        decoration: BoxDecoration(
          color: t.palette.danger,
          borderRadius: BorderRadius.circular(t.metrics.radiusMd),
        ),
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      onDismissed: (_) => _dismissCity(city),
      child: SectionCard(
        title: city.name,
        // 被动状态指示（非按钮）：展开时箭头翻转。
        trailing: AnimatedRotation(
          turns: expanded ? 0.5 : 0,
          duration: const Duration(milliseconds: 200),
          child:
              Icon(Icons.expand_more, size: 20, color: t.palette.textMuted),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            InkWell(
              onTap: () => _toggleCity(city),
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: t.metrics.space4),
                child: Row(
                  children: <Widget>[
                    Icon(
                      expanded ? Icons.thermostat : Icons.cloud_outlined,
                      size: 16,
                      color: expanded
                          ? t.palette.l2Accent
                          : t.palette.textMuted,
                    ),
                    SizedBox(width: t.metrics.space8),
                    Expanded(child: _buildSummaryLine(t, city)),
                    SizedBox(width: t.metrics.space8),
                    Text(
                      expanded ? '点击收起' : '点击展开',
                      style: t.typeScale.micro
                          .copyWith(color: t.palette.textMuted),
                    ),
                  ],
                ),
              ),
            ),
            if (expanded) ...<Widget>[
              SizedBox(height: t.metrics.space4),
              if (_loading)
                Padding(
                  padding: EdgeInsets.symmetric(vertical: t.metrics.space12),
                  child: Center(
                    child: Text('读取中…',
                        style: t.typeScale.body
                            .copyWith(color: t.palette.textMuted)),
                  ),
                )
              else if (_view != null)
                _buildForecastBody(t, _view!),
            ],
          ],
        ),
      ),
    );
  }

  /// 行内逐城摘要：实时温况（temp 走遥测轨）+ 缓存标记；失败/无数据给人话，
  /// 结构化原因展开卡片看详情——行内不吞失败也不摆机器码。
  Widget _buildSummaryLine(AppTokens t, WeatherCity city) {
    final summary = _summaries[city.id];
    final muted = t.typeScale.compact.copyWith(color: t.palette.textMuted);
    if (summary == null) {
      return Text(_summarizing.contains(city.id) ? '读取中…' : '点击查看天气',
          style: muted);
    }
    if (!summary.ok) {
      return Text('取数失败 · 点击展开看原因', style: muted);
    }
    final now = summary.now;
    if (now == null) {
      return Text('暂无实时数据', style: muted);
    }
    return Row(
      children: <Widget>[
        TelemetryText('${now.temp ?? '--'}℃'),
        SizedBox(width: t.metrics.space8),
        Flexible(
          child: Text(now.text,
              style: t.typeScale.compact, overflow: TextOverflow.ellipsis),
        ),
        if (summary.isCached) ...<Widget>[
          SizedBox(width: t.metrics.space8),
          Text('缓存回放', style: t.typeScale.micro.copyWith(
              color: t.palette.textMuted)),
        ],
      ],
    );
  }

  /// 展开卡内的详情体（无独立 SectionCard 容器——城市卡即容器）：
  /// 依赖门引导卡 / 结构化错误 / now + 逐日 + 预警 + 更新时间。
  Widget _buildForecastBody(AppTokens t, WeatherView view) {
    final shell = ShellNav.maybeOf(context);
    final configIncomplete = !view.ok &&
        (view.errorCode == WeatherErr.keyMissing ||
            view.errorCode == WeatherErr.hostMissing ||
            view.errorCode == WeatherErr.hostInvalid);
    if (configIncomplete && shell != null) {
      return GuidanceCard(
        message: '和风天气未正确配置',
        detail: view.errorCode == WeatherErr.hostMissing
            ? '在设置页填入账号专属 API Host（形如 xxxx.re.qweatherapi.com）后即可查询'
            : '在设置页填入 Key 后即可查询天气',
        actionLabel: '去设置',
        onAction: shell.onOpenSettings,
      );
    }
    if (!view.ok) {
      return ErrorLine(
        code: view.errorCode,
        message: view.message,
        suggestion: view.suggestion,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (view.now != null) ...<Widget>[
          Row(
            children: <Widget>[
              Text(view.now!.text, style: t.typeScale.listItem),
              SizedBox(width: t.metrics.space8),
              TelemetryText('${view.now!.temp ?? '--'}℃'),
              if (view.now!.feelsLike != null) ...<Widget>[
                SizedBox(width: t.metrics.space8),
                TelemetryText('体感 ${view.now!.feelsLike}℃'),
              ],
            ],
          ),
          SizedBox(height: t.metrics.space4),
          Text(
            '湿度 ${view.now!.humidity ?? '--'}% · '
            '${view.now!.windDir ?? '--'} ${view.now!.windScale ?? '--'} 级',
            style: t.typeScale.micro.copyWith(color: t.palette.textMuted),
          ),
          SizedBox(height: t.metrics.space12),
        ],
        for (final d in view.days)
          Padding(
            padding: EdgeInsets.only(bottom: t.metrics.space4),
            child: Row(
              children: <Widget>[
                SizedBox(
                  width: 96,
                  child: Text(d.date, style: t.typeScale.telemetry),
                ),
                Expanded(
                  child: Text(d.textDay, style: t.typeScale.compact),
                ),
                TelemetryText(d.tempRange),
              ],
            ),
          ),
        for (final a in view.alerts) ...<Widget>[
          SizedBox(height: t.metrics.space8),
          Text(
            '${a.severity ?? ''}${a.title}',
            style: t.typeScale.compact.copyWith(color: t.palette.danger),
          ),
        ],
        if (view.updateTime != null || view.isCached) ...<Widget>[
          SizedBox(height: t.metrics.space8),
          Text(
            '${view.updateTime == null ? '' : '更新时间 ${view.updateTime}'}'
            '${view.updateTime != null && view.isCached ? ' · ' : ''}'
            '${view.isCached ? '缓存回放' : ''}',
            style: t.typeScale.micro.copyWith(color: t.palette.textMuted),
          ),
        ],
      ],
    );
  }

  // ---- 底部搜索面板（对齐地图页 DraggableScrollableSheet 范式） ----

  Widget _buildBottomSheet(AppTokens t) {
    return DraggableScrollableSheet(
      controller: _sheetController,
      initialChildSize: _sheetMinSize(),
      minChildSize: _sheetMinSize(),
      // 可推到近顶，但留 5% 距离（不贴死顶边，留呼吸位）；横屏压到 0.75。
      maxChildSize: _sheetMaxSize(),
      snap: true,
      builder: (context, scrollController) {
        final scheme = Theme.of(context).colorScheme;
        return DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.vertical(
                top: Radius.circular(t.metrics.radiusLg)),
            boxShadow: const <BoxShadow>[
              BoxShadow(blurRadius: 16, color: Colors.black26),
            ],
          ),
          child: Padding(
            // 键盘弹起时面板整体上移，搜索框不被输入法遮挡。
            padding:
                EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                // 把手（可上滑的视觉提示；加宽到 40 更易命中）。
                Container(
                  width: 40,
                  height: 5,
                  margin: EdgeInsets.symmetric(vertical: t.metrics.space8),
                  decoration: BoxDecoration(
                    color: scheme.onSurfaceVariant.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                _buildSearchBar(t),
                Expanded(
                  child: ListView(
                    controller: scrollController,
                    padding: EdgeInsets.fromLTRB(t.metrics.space16, 0,
                        t.metrics.space16, t.metrics.space16),
                    children: <Widget>[
                      _buildSearchBody(t),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSearchBar(AppTokens t) {
    return Padding(
      padding:
          EdgeInsets.symmetric(horizontal: t.metrics.space16),
      child: Listener(
        // 用 Listener 而非 GestureDetector：TextField 自带竖直拖拽做文本选择，
        // GestureDetector 会与其在手势竞技场竞争（地图页同款处理）。
        onPointerDown: (e) => _searchFlickStartY = e.position.dy,
        onPointerUp: (e) {
          // 聚焦输入（选择文本/输入）时禁用展开/收齐手势（避免误触）。
          if (_searchFocus.hasFocus) return;
          final start = _searchFlickStartY;
          if (start == null) return;
          final dy = e.position.dy - start;
          if (dy < -60) {
            _searchFlickStartY = null;
            _sheetController.animateTo(_sheetMaxSize(),
                duration: const Duration(milliseconds: 240),
                curve: Curves.easeOut);
          } else if (dy > 60) {
            _searchFlickStartY = null;
            _sheetController.animateTo(_sheetMinSize(),
                duration: const Duration(milliseconds: 240),
                curve: Curves.easeOut);
          }
        },
        child: TextField(
          controller: _searchController,
          focusNode: _searchFocus,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _search(),
          decoration: InputDecoration(
            hintText: '搜索城市，添加到天气列表',
            prefixIcon: const Icon(Icons.search),
            // 手势代替按钮：提交走键盘搜索键；suffix 仅搜索中的被动进度指示。
            suffixIcon: _searching
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : null,
          ),
        ),
      ),
    );
  }

  Widget _buildSearchBody(AppTokens t) {
    final r = _searchResult;
    if (r == null) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: t.metrics.space16),
        child: Center(
          child: Text(
            '输入城市名搜索，点结果即添加（上限 $weatherCityLimit 个）',
            style: t.typeScale.compact.copyWith(color: t.palette.textMuted),
          ),
        ),
      );
    }
    if (!r.ok) {
      final shell = ShellNav.maybeOf(context);
      final configIncomplete = r.errorCode == WeatherErr.keyMissing ||
          r.errorCode == WeatherErr.hostMissing ||
          r.errorCode == WeatherErr.hostInvalid;
      if (configIncomplete && shell != null) {
        return GuidanceCard(
          message: '和风天气未正确配置',
          detail: r.errorCode == WeatherErr.hostMissing
              ? '在设置页填入账号专属 API Host（形如 xxxx.re.qweatherapi.com）后即可搜索'
              : '在设置页填入 Key 后即可搜索城市',
          actionLabel: '去设置',
          onAction: shell.onOpenSettings,
        );
      }
      return Padding(
        padding: EdgeInsets.symmetric(vertical: t.metrics.space8),
        child: ErrorLine(
          code: r.errorCode,
          message: r.message,
          suggestion: r.suggestion,
        ),
      );
    }
    if (r.options.isEmpty) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: t.metrics.space16),
        child: Center(
          child: Text(
            '查无此城，换个写法试试（支持行政区，如「朝阳区」）',
            style: t.typeScale.compact.copyWith(color: t.palette.textMuted),
          ),
        ),
      );
    }
    return Column(
      children: <Widget>[
        for (final option in r.options)
          ListTile(
            dense: true,
            title: Text(option.name, style: t.typeScale.compact),
            trailing: TextButton(
              onPressed: () => _addCity(option),
              child: const Text('添加'),
            ),
            onTap: () => _addCity(option),
          ),
      ],
    );
  }
}
