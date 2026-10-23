library;

import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../action/command_gateway.dart';
import '../action/geo_commands.dart';
import '../geo/coord_convert.dart';
import '../geo/route_guidance.dart';
import '../mcp/geo_provider.dart';
import '../repository/favorite_repository.dart';
// LatLng 与 geo_lbs_port 的同名类型解耦——本页坐标一律用 latlong2 的 LatLng，
// 端口视图的 RouteStepView.polyline（端口侧 LatLng）仅取字段不取构造。
import '../ui_ports/geo_lbs_port.dart' hide LatLng;
import '../ui_ports/geo_last_location_port.dart';
import '../ui_ports/geo_port.dart';
import 'components/app_components.dart';
import 'tokens/app_tokens.dart';

/// 地图子页面：交互地图画布（FlutterMap + 高德 XYZ 瓦片源）+ 功能面板
/// （搜索选点 / 四模态路线 / 测距 / 收藏 marker）+ 坐标纠偏（三系同屏）。
///
/// 人机同源：LBS 能力经 [GeoLbsPort] 与 MCP 工具面并列共享同一内核与
/// `GeoHttpProvider`；收藏写经 CommandGateway 用户侧注册表（R1）。
/// 画布零原生依赖：纯 Dart 渲染（decisions.md 2026-10-22 结构性替换）。
class GeoPage extends StatefulWidget {
  const GeoPage({
    super.key,
    required this.lbsPort,
    required this.favorites,
    required this.gateway,
    required this.locationSensor,
    required this.lastLocation,
  });

  final GeoLbsPort lbsPort;

  /// 定位源（系统定位；端口出 WGS-84，画布前归一化 GCJ-02）。
  final LocationSensorProvider locationSensor;

  /// 上次定位点（读/写经 Port → Repository/网关；进场先恢复再刷新定位）。
  final GeoLastLocationPort lastLocation;

  final FavoriteRepository favorites;
  final CommandGateway gateway;

  @override
  State<GeoPage> createState() => _GeoPageState();
}

class _GeoPageState extends State<GeoPage> {
  static const GeoPort _port = GeoPort();

  /// 面板数据 → 地图相机映射（路线/测距完成后 fit bounds）。
  final _mapController = MapController();

  /// 底部面板控制器：搜索框上滑/下滑手势、选点激活时自动收起。
  final _sheetController = DraggableScrollableController();

  /// 搜索框上滑/下滑手势的起点（指针按下时的 y）。
  double? _searchFlickStartY;

  /// 搜索框焦点：聚焦时（选择文本/输入场景）禁用上滑展开手势。
  final _searchFocus = FocusNode();

  /// 路线段表单错误（缺起终点等）——面板内展示，不用 SnackBar 糊面板。
  String? _routeFormError;

  /// 收藏段错误（添加/删除失败）——同上，面板内展示。
  String? _favError;

  // ---- 定位 ----
  /// 「我的位置」蓝点（GCJ-02，与瓦片同系）。
  LatLng? _myLocation;

  /// 定位水平精度（米）——画半透明精度圈（CircleLayer，米为半径）。
  double? _myAccuracy;

  /// 定位进行中 / 失败提示（顶部胶囊展示）。
  bool _locating = false;
  String? _locHint;

  // ---- 地图观仪（指北针 / 比例尺数据源） ----
  /// 当前地图旋转角（度）——非 0 时显示指北针。
  double _mapRotation = 0;

  /// 当前相机（中心/缩放）——比例尺换算数据源。
  LatLng _mapCenter = const LatLng(39.908722, 116.397499);
  double _mapZoom = 12;

  final _lat = TextEditingController(text: '39.908722');
  final _lng = TextEditingController(text: '116.397499');
  final _lat2 = TextEditingController(text: '31.230416');
  final _lng2 = TextEditingController(text: '121.473701');
  final _favName = TextEditingController();
  final _favFolder = TextEditingController();
  final _favLat = TextEditingController();
  final _favLng = TextEditingController();
  final _searchCtrl = TextEditingController();
  final _transitCityCtrl = TextEditingController();

  GeoView? _geoView;

  List<FavoritePlaceView> _favorites = const <FavoritePlaceView>[];
  bool _favBusy = false;

  // ---- 地图画布状态 ----
  /// 起点 / 终点（收藏、搜索结果或地图选点，均为 GCJ-02）。
  _PickedPlace? _origin;
  _PickedPlace? _destination;

  /// 地图点击用途：设起点 / 设终点 / 测距打点。
  _PickMode _pickMode = _PickMode.none;
  final List<LatLng> _measurePoints = <LatLng>[];
  GeoView? _measureView;

  /// 面板当前功能分段（一次只展示一个功能的完整面）。
  _GeoPanelTab _panelTab = _GeoPanelTab.route;

  // ---- 搜索与路线 ----
  GeoSearchView? _searchView;
  bool _searching = false;
  RouteView? _routeView;
  bool _routing = false;

  @override
  void initState() {
    super.initState();
    // 进场即尝试定位当前位置（胶囊先显「定位中…」），定位成功即把相机 fit 到真实位置。
    // 首帧用占位中心（北京）——`MapOptions.initialCenter` 必须有值，定位成功后立即覆盖；
    // 定位失败则给可重试提示（不静默停在占位起点）。
    // 必须在首帧后调用：_locateMe 会驱动 MapController，首帧前 controller 未挂载。
    _locating = true;
    _reloadFavorites();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      // 先恢复上次定位点（有则立即把相机带过去，不回占位原点），再刷新定位。
      // 恢复读数只动相机不置蓝点——蓝点语义是「系统定位确认的位置」。
      final last = await widget.lastLocation.read();
      if (!mounted) return;
      if (last != null && _myLocation == null) {
        _mapController.move(LatLng(last.lat, last.lng), 16);
      }
      await _locateMe();
    });
  }

  @override
  void dispose() {
    for (final c in <TextEditingController>[
      _lat, _lng, _lat2, _lng2,
      _favName, _favFolder, _favLat, _favLng, _searchCtrl, _transitCityCtrl,
    ]) {
      c.dispose();
    }
    _mapController.dispose();
    _sheetController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> _reloadFavorites() async {
    final places = await widget.favorites.list();
    if (!mounted) return;
    setState(() {
      _favorites = FavoritePlaceView.listFrom(places);
      // 起终点引用的收藏被删后落回未选态（按 id 失配清空，不悬挂旧引用）。
      final ids = _favorites.map((p) => p.id).toSet();
      if (_origin?.favId != null && !ids.contains(_origin!.favId)) {
        _origin = null;
      }
      if (_destination?.favId != null && !ids.contains(_destination!.favId)) {
        _destination = null;
      }
    });
  }

  double? _parse(String raw) => double.tryParse(raw.trim());

  /// 已有收藏夹名（去重、非空；快捷 chips 数据源）。
  List<String> get _existingFolders => <String>{
        for (final p in _favorites)
          if (p.folder.isNotEmpty) p.folder,
      }.toList();

  void _runConvert() {
    final lat = _parse(_lat.text);
    final lng = _parse(_lng.text);
    setState(() {
      _geoView = (lat == null || lng == null)
          ? const GeoView(
              ok: false,
              errorCode: 'INVALID_ARGUMENT',
              message: '经纬度须为数字',
            )
          : _port.convertPoint(lat, lng);
    });
  }

  // ---- 地图交互 ----

  void _setPickMode(_PickMode m) => setState(() {
        _pickMode = _pickMode == m ? _PickMode.none : m;
        if (_pickMode == _PickMode.measure) _measurePoints.clear();
        // 选点激活 → 面板自动收起，让地图全屏可点（收起是让位手势，不是 UX 强加）。
        if (_pickMode != _PickMode.none) {
          _sheetController.animateTo(_sheetMinSize(),
              duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
        }
      });

  /// 面板最小高度：横屏下抬高，保证地图至少 65% 可视。
  double _sheetMinSize() =>
      MediaQuery.of(context).orientation == Orientation.landscape ? 0.35 : 0.22;

  /// 面板最大高度：横屏压到 0.75（地图保 25% 可视）；竖屏 0.95 近顶留呼吸位。
  double _sheetMaxSize() =>
      MediaQuery.of(context).orientation == Orientation.landscape ? 0.75 : 0.95;

  void _onMapTap(LatLng point) {
    switch (_pickMode) {
      case _PickMode.origin:
        _applyOrigin(_PickedPlace(
            name: '地图选点', lat: point.latitude, lng: point.longitude));
        _pickMode = _PickMode.none;
      case _PickMode.destination:
        _applyDestination(_PickedPlace(
            name: '地图选点', lat: point.latitude, lng: point.longitude));
        _pickMode = _PickMode.none;
      case _PickMode.measure:
        setState(() {
          if (_measurePoints.length >= 2) _measurePoints.clear();
          _measurePoints.add(point);
          _measureView = _measurePoints.length == 2
              ? _port.distance(
                  _measurePoints[0].latitude,
                  _measurePoints[0].longitude,
                  _measurePoints[1].latitude,
                  _measurePoints[1].longitude,
                )
              : null;
        });
        // 两点齐活 → 测距线段完整入画。
        if (_measurePoints.length == 2) {
          _fitTo(List<LatLng>.of(_measurePoints));
        }
      case _PickMode.none:
        break;
    }
  }

  /// 设起点：落 Marker 并 fit 到该点——选点后地图必有可见反馈
  /// （marker 不落在面板遮挡区，解决"点了没反应"）。
  void _applyOrigin(_PickedPlace p) {
    setState(() => _origin = p);
    _fitTo(<LatLng>[LatLng(p.lat, p.lng)]);
  }

  /// 设终点：同上。
  void _applyDestination(_PickedPlace p) {
    setState(() => _destination = p);
    _fitTo(<LatLng>[LatLng(p.lat, p.lng)]);
  }

  void _clearOrigin() => setState(() => _origin = null);
  void _clearDestination() => setState(() => _destination = null);

  Future<void> _runSearch() async {
    // 先收键盘：键盘占 ~40% 高度，与 0.95 推顶面板同时占满会把结果区挤没。
    FocusScope.of(context).unfocus();
    setState(() => _searching = true);
    final view = await widget.lbsPort.searchPlaces(_searchCtrl.text);
    if (!mounted) return;
    setState(() {
      _searchView = view;
      _searching = false;
      // 搜索有结果 → 面板自动切到「搜索」分段，结果直接可点（设起点/终点）。
      _panelTab = _GeoPanelTab.search;
    });
    // 面板落到中等高度：结果列表完整可见，又不全遮地图。
    _sheetController.animateTo(0.6,
        duration: const Duration(milliseconds: 240), curve: Curves.easeOut);
  }

  /// 当前位置（WGS-84 → GCJ-02 归一）作为已选地点；拿不到返 null。
  ///
  /// 纵深防御：定位源按端口契约失败返 null 不抛，但 UI 不把「定位中」状态的
  /// 收尾押在它身上——异常同样落回可重试的失败态（否则胶囊永远显示「定位中…」）。
  Future<_PickedPlace?> _currentPlace() async {
    final reading = await _readLocation();
    if (reading == null) return null;
    final p = CoordConvert.normalize(GeoPoint(reading.lat, reading.lng),
        CoordSystem.wgs84, CoordSystem.gcj02);
    return _PickedPlace(name: '我的位置', lat: p.lat, lng: p.lng);
  }

  /// 读一次定位读数：**任何异常都收敛为 null**（不外泄）。
  ///
  /// 定位源按端口契约失败返 null 不抛，但 UI 不把「定位中」状态的收尾押在它
  /// 身上——异常若冒泡，`await` 抛出后 `setState` 不执行，「定位中…」永久挂起、
  /// 相机停在初始中心（2026-10-23 用户报「进地图定位原始起点」）。
  Future<LocationReading?> _readLocation() async {
    try {
      return await widget.locationSensor.current();
    } on Exception catch (e) {
      debugPrint('[LOC] 定位源异常（已按失败态收敛）: $e');
      return null;
    }
  }

  /// 「当前位置」快捷入口：把定位结果设为起点（路线段选点条）。
  Future<void> _setCurrentAsOrigin() async {
    setState(() => _locating = true);
    final place = await _currentPlace();
    if (!mounted) return;
    if (place == null) {
      setState(() {
        _locating = false;
        _routeFormError = '无法获取当前位置（检查定位权限与系统定位开关）';
      });
      return;
    }
    setState(() => _locating = false);
    _applyOrigin(place);
  }

  Future<void> _runRoute(String mode) async {
    var o = _origin;
    // 起点缺省兜底：路线规划的默认起点就是用户当前位置（定位可用时）。
    if (o == null) {
      final place = await _currentPlace();
      if (!mounted) return;
      if (place == null) {
        setState(() => _routeFormError =
            '起点未设，且无法获取当前位置（检查定位权限与开关，或手动设起点）');
        return;
      }
      o = place;
      setState(() => _origin = place);
    }
    final d = _destination;
    if (d == null) {
      // 面板内展示（SnackBar 会糊在底部面板上遮挡数秒）。
      setState(() => _routeFormError = '请设定终点（搜索 / 收藏 / 地图选点）');
      return;
    }
    setState(() {
      _routing = true;
      _routeFormError = null;
    });
    final view = await widget.lbsPort.route(
      from: GeoPoint(o.lat, o.lng),
      to: GeoPoint(d.lat, d.lng),
      mode: mode,
      city: mode == 'transit' ? _transitCityCtrl.text : null,
    );
    if (!mounted) return;
    setState(() {
      _routeView = view;
      _routing = false;
      // 结果落在路线分段，防止用户中途切走看不到。
      _panelTab = _GeoPanelTab.route;
    });
    // 面板数据 → 地图映射：路线折线完整入画（fit bounds）。
    if (view.ok && view.steps.isNotEmpty) {
      _fitTo(<LatLng>[
        for (final s in view.steps) for (final p in s.polyline) LatLng(p.lat, p.lng),
      ]);
    }
  }

  // ---- 收藏（用户侧命令族写，AI 不可触达） ----

  Future<void> _addFavorite() async {
    final lat = _parse(_favLat.text);
    final lng = _parse(_favLng.text);
    setState(() => _favBusy = true);
    final result = await widget.gateway
        .dispatchUser(UserGeoFavoriteAddCommand(<String, Object?>{
      'name': _favName.text,
      'lat': lat,
      'lng': lng,
      'folder': _favFolder.text,
    }));
    if (!mounted) return;
    setState(() => _favBusy = false);
    if (result.ok) {
      // 清名称/坐标，**保留收藏夹**——连续录入同一夹是常见操作。
      _favName.clear();
      _favLat.clear();
      _favLng.clear();
      _favError = null;
    } else {
      setState(() =>
          _favError = '收藏失败：${result.message ?? result.errorCode}');
    }
    await _reloadFavorites();
  }

  Future<void> _deleteFavorite(FavoritePlaceView p) async {
    final result = await widget.gateway
        .dispatchUser(UserGeoFavoriteDeleteCommand(<String, Object?>{'id': p.id}));
    if (!mounted) return;
    if (!result.ok) {
      setState(() =>
          _favError = '删除失败：${result.message ?? result.errorCode}');
    }
    await _reloadFavorites();
  }

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: Stack(
        children: <Widget>[
          // 全屏地图（铺满页面；搜索框/面板为浮层，上滑面板即功能面）。
          _buildMapCanvas(t),
          // 顶部胶囊：标题 / 选点模式提示（轻量，不挡手势）。
          _buildTopBar(t),
          // 右侧浮动按钮列：单手持机缩放 / 定位。
          _buildMapControls(t),
          // 指北针（旋转时出现）与比例尺（地图专业观仪）。
          _buildCompass(t),
          _buildScaleBar(t),
          // 底部上滑面板：把手 + 搜索框（常驻）+ 功能按钮与数据。
          _buildBottomSheet(t),
        ],
      ),
    );
  }

  // ---- 全屏地图画布 ----

  /// 交互画布（decisions.md 2026-10-22）：纯 Dart 渲染 + 高德 XYZ 瓦片源
  /// （GCJ-02 坐标系，画布数据与瓦片同系，无偏移）；零原生依赖、零 Key。
  ///
  /// 瓦片源为非官方承诺接口，失效时的静态图降级路径（GeoMapPort）与
  /// 夜间模式视觉方案留实施验证轮（见 geo devlog 登记）。
  Widget _buildMapCanvas(AppTokens t) {
    final bg = Theme.of(context).colorScheme.surface;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: const LatLng(39.908722, 116.397499),
        initialZoom: 12,
        backgroundColor: bg,
        // 手势面显式声明（Android 手机场景）：单指拖拽 / 惯性 / 双指缩放平移 /
        // 双击放大 / 双指旋转全开；scrollWheelZoom 关（无鼠标滚轮设备，防误缩放）。
        interactionOptions: InteractionOptions(
          flags: InteractiveFlag.drag |
              InteractiveFlag.flingAnimation |
              InteractiveFlag.pinchMove |
              InteractiveFlag.pinchZoom |
              InteractiveFlag.doubleTapZoom |
              InteractiveFlag.rotate,
        ),
        // 8.x 签名：(TapPosition, LatLng)——本页只取坐标点。
        onTap: (_, point) => _onMapTap(point),
        // 相机变化 → 指北针（rotation）与比例尺（zoom/center）数据源。
        onPositionChanged: (camera, _) {
          final rotation = camera.rotation;
          final zoom = camera.zoom;
          final center = camera.center;
          final changed = rotation != _mapRotation ||
              zoom != _mapZoom ||
              center.latitude != _mapCenter.latitude ||
              center.longitude != _mapCenter.longitude;
          if (!changed) return;
          setState(() {
            _mapRotation = rotation;
            _mapZoom = zoom;
            _mapCenter = center;
          });
        },
      ),
      children: <Widget>[
        TileLayer(
          // 高德标准矢量瓦片（style=7）；scl=1 + size=1 取普通清晰度档。
          urlTemplate:
              'https://wprd0{s}.is.autonavi.com/appmaptile?x={x}&y={y}&z={z}&lang=zh_cn&size=1&scl=1&style=7',
          subdomains: const <String>['1', '2', '3', '4'],
          userAgentPackageName: 'com.zzh.goodhub',
        ),
        // 暗色模式：高德无暗色瓦片，用压暗遮罩柔化亮瓦片（markers/线在上层，
        // 不受影响）。视觉方案待真机验证（geo.md 域内待办）。
        if (dark)
          const ColoredBox(color: Color(0x59000000)),
        if (_myLocation != null) CircleLayer(circles: _buildAccuracyCircles()),
        MarkerLayer(markers: _buildMarkers(t)),
        PolylineLayer(polylines: _buildPolylines(t)),
      ],
    );
  }

  /// 定位精度圈（半透明蓝 + 蓝边；米为半径，随缩放自然缩放）。
  List<CircleMarker> _buildAccuracyCircles() {
    final me = _myLocation;
    final acc = _myAccuracy;
    if (me == null || acc == null || acc <= 0) return const <CircleMarker>[];
    return <CircleMarker>[
      CircleMarker(
        point: me,
        radius: acc,
        color: Colors.blue.withValues(alpha: 0.12),
        borderColor: Colors.blue.withValues(alpha: 0.25),
        borderStrokeWidth: 1,
      ),
    ];
  }

  /// 面板数据 → 地图相机映射：单点 move，多点 fit bounds。
  ///
  /// padding 下留 320 是为底部上滑面板（min 0.22 + 把手/搜索框常驻）留出
  /// 可视区——fit 目标落在面板上方，不被遮挡。
  void _fitTo(List<LatLng> points, {double singleZoom = 15}) {
    if (points.isEmpty) return;
    if (points.length == 1) {
      _mapController.move(points.first, singleZoom);
      return;
    }
    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: LatLngBounds.fromPoints(points),
        padding: const EdgeInsets.fromLTRB(48, 120, 48, 320),
      ),
    );
  }

  // ---- 顶部胶囊 ----

  Widget _buildTopBar(AppTokens t) {
    final scheme = Theme.of(context).colorScheme;
    final String pickLabel = switch (_pickMode) {
      _PickMode.origin => '点击地图设起点',
      _PickMode.destination => '点击地图设终点',
      _PickMode.measure => '点击地图打点测距',
      _PickMode.none => '地图',
    };
    // 定位中 / 定位失败提示优先于选点提示（用户在等反馈）。
    final String label;
    final IconData icon;
    if (_locating) {
      label = '定位中…';
      icon = Icons.my_location;
    } else if (_locHint != null) {
      label = _locHint!;
      icon = Icons.location_disabled;
    } else if (_pickMode != _PickMode.none) {
      label = pickLabel;
      icon = Icons.touch_app_outlined;
    } else {
      label = pickLabel;
      icon = Icons.map_outlined;
    }
    // 注：外层 CapabilitiesPage 已包 SafeArea（状态栏/手势条 inset），此处不重复避让。
    return Positioned(
      top: t.metrics.space8,
      left: t.metrics.space16,
      right: t.metrics.space16,
      child: Center(
        // 毛玻璃：模糊地图底 + 半透明面（比纯半透明更有层次）。
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
            child: Container(
              padding: EdgeInsets.symmetric(
                  horizontal: t.metrics.space12, vertical: t.metrics.space8),
              decoration: BoxDecoration(
                color: scheme.surface.withValues(alpha: 0.72),
                borderRadius: BorderRadius.circular(20),
                boxShadow: const <BoxShadow>[
                  BoxShadow(blurRadius: 6, color: Colors.black12),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(icon, size: 18),
                  SizedBox(width: t.metrics.space8),
                  Text(label, style: t.typeScale.compact),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ---- 地图浮动控件（我的位置 / 缩放 / 指北针 / 比例尺） ----

  /// 右侧浮动按钮列：我的位置 / 放大 / 缩小。
  ///
  /// 双指手势之外的单手入口。指北由顶部指北针承担（见 [_buildCompass]）。
  /// 按钮为毛玻璃圆钮（模糊地图底，比纯半透明有层次）。
  Widget _buildMapControls(AppTokens t) {
    final scheme = Theme.of(context).colorScheme;
    Widget btn(IconData icon, VoidCallback onPressed, String tip, {bool primary = false}) {
      final color = primary ? scheme.onPrimaryContainer : scheme.onSurface;
      return Tooltip(
        message: tip,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onPressed,
            child: ClipOval(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: (primary
                            ? scheme.primaryContainer
                            : scheme.surface)
                        .withValues(alpha: 0.78),
                    shape: BoxShape.circle,
                    boxShadow: const <BoxShadow>[
                      BoxShadow(blurRadius: 6, color: Colors.black26),
                    ],
                  ),
                  child: Center(child: Icon(icon, size: 20, color: color)),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Positioned(
      right: t.metrics.space12,
      top: 0,
      bottom: 0,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            btn(Icons.my_location, _locateMe, '我的位置', primary: true),
            SizedBox(height: t.metrics.space8),
            btn(Icons.add, _zoomIn, '放大'),
            SizedBox(height: t.metrics.space8),
            btn(Icons.remove, _zoomOut, '缩小'),
          ],
        ),
      ),
    );
  }

  /// 指北针：地图被旋转（rotation≠0）时出现在右上，箭头随旋转反向偏转，
  /// 点击复位正北。不旋转时隐藏（不添静态噪点）。
  Widget _buildCompass(AppTokens t) {
    if (_mapRotation.abs() < 0.5) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Positioned(
      right: t.metrics.space12,
      top: t.metrics.space8 + 40 + t.metrics.space8,
      child: Tooltip(
        message: '指北重置',
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: _resetNorth,
            child: ClipOval(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: scheme.surface.withValues(alpha: 0.78),
                    shape: BoxShape.circle,
                    boxShadow: const <BoxShadow>[
                      BoxShadow(blurRadius: 6, color: Colors.black26),
                    ],
                  ),
                  child: Center(
                    // 箭头随地图旋转反向偏转，红针恒指北。
                    child: Transform.rotate(
                      angle: -_mapRotation * math.pi / 180,
                      child: const Icon(Icons.north, size: 20, color: Colors.red),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 比例尺（左下，贴面板上方）：随 zoom/纬度换算「80px ≈ xx m」。
  Widget _buildScaleBar(AppTokens t) {
    final scheme = Theme.of(context).colorScheme;
    return Positioned(
      left: t.metrics.space12,
      bottom: MediaQuery.of(context).size.height * _sheetMinSize() + t.metrics.space12,
      child: IgnorePointer(
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: t.metrics.space8, vertical: 2),
          decoration: BoxDecoration(
            color: scheme.surface.withValues(alpha: 0.75),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            children: <Widget>[
              Container(
                width: 40,
                height: 3,
                decoration: BoxDecoration(
                  color: scheme.onSurface.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              SizedBox(width: t.metrics.space4),
              Text(_scaleLabel(), style: t.typeScale.compact.copyWith(fontSize: 10)),
            ],
          ),
        ),
      ),
    );
  }

  /// 比例尺文字：resolution = 156543.03·cos(lat)/2^zoom 米/像素，取整到
  /// 1/2/5×10^n 的友好数（标准 Web 墨卡托公式）。
  String _scaleLabel() {
    const base = 156543.03392;
    final metersPerPx =
        base * math.cos(_mapCenter.latitude * math.pi / 180) / math.pow(2, _mapZoom);
    final meters = metersPerPx * 80;
    final pow10 = math.pow(10, (math.log(meters) / math.ln10).floor()).toDouble();
    final n = meters / pow10;
    final nice = n >= 5 ? 5 * pow10 : n >= 2 ? 2 * pow10 : pow10;
    if (nice >= 1000) {
      return '${(nice / 1000).toStringAsFixed(nice >= 10000 ? 0 : 1)} km';
    }
    return '${nice.toStringAsFixed(0)} m';
  }

  void _zoomBy(double delta) {
    final cam = _mapController.camera;
    final next = (cam.zoom + delta).clamp(3.0, 18.0);
    _mapController.move(cam.center, next);
  }

  void _zoomIn() => _zoomBy(1);

  void _zoomOut() => _zoomBy(-1);

  void _resetNorth() => _mapController.rotate(0);

  /// 「我的位置」：系统定位（WGS-84）→ GCJ-02 归一化 → 蓝点 + fit。
  ///
  /// 端口出参是 GPS 原生 WGS-84，画布与瓦片是 GCJ-02——不转换即百米漂移
  /// （geo.md 坐标系红线）。无权限/超时 → null → 胶囊给检查指引（fail-closed）。
  Future<void> _locateMe() async {
    setState(() {
      _locating = true;
      _locHint = null;
    });
    // 纵深防御：定位源失败返 null（端口契约），异常也必须在此收敛——否则
    // `await` 抛出后 `setState` 不执行，「定位中…」永久挂起、相机停在初始中心
    // （2026-10-23 用户报「进地图定位原始起点」）。
    final reading = await _readLocation();
    if (!mounted) return;
    if (reading == null) {
      setState(() {
        _locating = false;
        _locHint = '定位不可用：请检查定位权限与系统定位开关（可点右侧「我的位置」重试）';
      });
      return;
    }
    final p = CoordConvert.normalize(
        GeoPoint(reading.lat, reading.lng), CoordSystem.wgs84, CoordSystem.gcj02);
    setState(() {
      _locating = false;
      _myLocation = LatLng(p.lat, p.lng);
      _myAccuracy = reading.accuracy > 0 ? reading.accuracy : null;
    });
    _fitTo(<LatLng>[_myLocation!], singleZoom: 16);
    // 记住本次定位点（GCJ-02），下次进场先恢复到这里再刷新（不回占位原点）。
    // 写失败不影响本页使用（记忆只是体验优化），但留存结构化日志可观测。
    final saved = await widget.lastLocation.save(p.lat, p.lng);
    if (!saved.ok) {
      debugPrint('[LOC] 上次定位点记忆写入失败: ${saved.errorCode}');
    }
  }

  // ---- 底部上滑面板（搜索框常驻 + 功能面） ----

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
            borderRadius:
                BorderRadius.vertical(top: Radius.circular(t.metrics.radiusLg)),
            boxShadow: const <BoxShadow>[
              BoxShadow(blurRadius: 16, color: Colors.black26),
            ],
          ),
          child: Padding(
            // 键盘弹起时面板整体上移，搜索框不被输入法遮挡。
            // 注：底部系统手势条 inset 由外层 SafeArea 处理，此处不重复。
            padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
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
                _buildSearchBox(t),
                Expanded(
                  child: ListView(
                    controller: scrollController,
                    padding: EdgeInsets.fromLTRB(
                        t.metrics.space16, 0, t.metrics.space16, t.metrics.space16),
                    children: <Widget>[
                      // 功能分段按钮：替代旧的多功能纵向堆叠，一次只看一个功能的完整面。
                      _buildTabBar(t),
                      SizedBox(height: t.metrics.space8),
                      _buildPanelBody(t),
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

  // ---- 功能分段（按钮替代堆叠：一次一个功能的完整面） ----

  /// 分段按钮行。搜索分段仅在有过搜索行为时出现（有结果可回看）。
  Widget _buildTabBar(AppTokens t) {
    final tabs = <(_GeoPanelTab, String, IconData)>[
      if (_searching || _searchView != null)
        (_GeoPanelTab.search, '搜索', Icons.search),
      (_GeoPanelTab.route, '路线', Icons.directions),
      (_GeoPanelTab.favorite, '收藏', Icons.star_border),
      (_GeoPanelTab.measure, '测距', Icons.straighten),
      (_GeoPanelTab.convert, '纠偏', Icons.swap_horiz),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: <Widget>[
          for (final (tab, label, icon) in tabs)
            Padding(
              padding: EdgeInsets.only(right: t.metrics.space8),
              child: ChoiceChip(
                label: Text(label),
                avatar: Icon(icon, size: 18),
                selected: _panelTab == tab,
                onSelected: (_) => setState(() => _panelTab = tab),
              ),
            ),
        ],
      ),
    );
  }

  /// 当前分段的完整功能面。
  Widget _buildPanelBody(AppTokens t) => switch (_panelTab) {
        _GeoPanelTab.search => _buildSearchResults(t),
        _GeoPanelTab.route => _buildRouteTab(t),
        _GeoPanelTab.favorite => _buildFavoritesSection(t),
        _GeoPanelTab.measure => _buildMeasureTab(t),
        _GeoPanelTab.convert => _buildConvertSection(t),
      };

  /// 路线分段：起终点状态 + 选点工具条（含「当前位置」快捷）+ 四模态路线 + 步骤。
  Widget _buildRouteTab(AppTokens t) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _buildEndpointsBar(t),
          SizedBox(height: t.metrics.space8),
          _buildPickBar(t),
          SizedBox(height: t.metrics.space8),
          _buildRouteSection(t),
        ],
      );

  /// 起终点当前状态（未选时给出来源指引；已选可清除——误点可撤销）。
  Widget _buildEndpointsBar(AppTokens t) => Row(
        children: <Widget>[
          Expanded(
            child: Row(
              children: <Widget>[
                Flexible(
                  child: Text('起点：${_origin?.name ?? '未选（搜索/收藏/地图）'}',
                      style: t.typeScale.compact, overflow: TextOverflow.ellipsis),
                ),
                if (_origin != null)
                  IconButton(
                    tooltip: '清除起点',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.close, size: 16),
                    onPressed: _clearOrigin,
                  ),
              ],
            ),
          ),
          Expanded(
            child: Row(
              children: <Widget>[
                Flexible(
                  child: Text('终点：${_destination?.name ?? '未选（搜索/收藏/地图）'}',
                      style: t.typeScale.compact, overflow: TextOverflow.ellipsis),
                ),
                if (_destination != null)
                  IconButton(
                    tooltip: '清除终点',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.close, size: 16),
                    onPressed: _clearDestination,
                  ),
              ],
            ),
          ),
        ],
      );

  /// 测距分段：打点模式 + 打点进度 + 直线距离 + 清除。
  Widget _buildMeasureTab(AppTokens t) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Wrap(
            spacing: t.metrics.space8,
            runSpacing: t.metrics.space8,
            children: <Widget>[
              _pickChip(t, '测距打点', _PickMode.measure,
                  _measurePoints.isEmpty ? null : '${_measurePoints.length}/2'),
            ],
          ),
          SizedBox(height: t.metrics.space8),
          if (_measurePoints.length < 2)
            Text('激活后点击地图打点（面板自动收起让位地图）',
                style: t.typeScale.compact),
          if (_measureView != null) ...<Widget>[
            if (_measureView!.ok)
              TelemetryText('直线距离 ${_measureView!.distanceText}')
            else
              ErrorLine(
                  code: _measureView!.errorCode,
                  message: _measureView!.message),
          ],
          if (_measurePoints.isNotEmpty)
            TextButton.icon(
              onPressed: () => setState(() {
                _measurePoints.clear();
                _measureView = null;
              }),
              icon: const Icon(Icons.clear, size: 18),
              label: const Text('清除打点'),
            ),
        ],
      );

  /// 搜索框（常驻面板顶部；上滑面板展开后仍可见）。
  ///
  /// 手势：在搜索框区域上滑 → 面板展开（出功能按钮）；下滑 → 收起（让位地图）。
  /// 用 [Listener] 指针事件而非 GestureDetector——避免与 TextField 自身的
  /// 竖直拖拽（文本选择/光标移动）在手势竞技场里竞争。
  Widget _buildSearchBox(AppTokens t) => Padding(
        padding: EdgeInsets.symmetric(horizontal: t.metrics.space16),
        child: Listener(
          onPointerDown: (e) => _searchFlickStartY = e.position.dy,
          onPointerUp: (_) => _searchFlickStartY = null,
          onPointerCancel: (_) => _searchFlickStartY = null,
          onPointerMove: (e) {
            // 聚焦输入框时竖直拖动=选择文本，禁用展开/收齐手势（避免误触）。
            if (_searchFocus.hasFocus) return;
            final start = _searchFlickStartY;
            if (start == null) return;
            final dy = e.position.dy - start;
            if (dy < -60) {
              // 上滑逾阈值 → 展开功能面（一次性触发，抬手才允许再次触发）。
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
          child: Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  focusNode: _searchFocus,
                  decoration: InputDecoration(
                    hintText: '搜索地点 / 地址',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    isDense: true,
                    border: const OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _runSearch(),
                ),
              ),
              SizedBox(width: t.metrics.space8),
              IconButton(
                tooltip: '搜索',
                onPressed: _searching ? null : _runSearch,
                icon: const Icon(Icons.arrow_forward),
              ),
            ],
          ),
        ),
      );

  /// 搜索结果（面板数据 → 地图映射：设起点/终点即落 Marker）。
  Widget _buildSearchResults(AppTokens t) {
    if (_searching) return const LinearProgressIndicator();
    final v = _searchView!;
    if (!v.ok) return ErrorLine(code: v.errorCode, message: v.message);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (v.warnings.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('部分源失败：${v.warnings.join('；')}',
                style: t.typeScale.compact),
          ),
        for (final p in v.places.take(10))
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.place_outlined, size: 20),
            title: Text(p.name, style: t.typeScale.body),
            subtitle: Text(p.district ?? p.address ?? p.formatted,
                style: t.typeScale.compact),
            trailing: TextButton(
              onPressed: () => _applyDestination(
                  _PickedPlace(name: p.name, lat: p.lat, lng: p.lng)),
              child: const Text('设终点'),
            ),
            onTap: () =>
                _applyOrigin(_PickedPlace(name: p.name, lat: p.lat, lng: p.lng)),
          ),
      ],
    );
  }

  /// 图钉统一语言：白底圆 + 彩心 + 投影（暗色/亮瓦片下都清晰）；
  /// 触摸区 46（>48 推荐值下限），图标 18——小屏手指可点中。
  Widget _pin({required Color color, required Widget icon, String? tip}) {
    return Tooltip(
      message: tip ?? '',
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          border: Border.all(color: color, width: 2.5),
          boxShadow: const <BoxShadow>[
            BoxShadow(color: Color(0x33000000), blurRadius: 4, offset: Offset(0, 2)),
          ],
        ),
        child: Center(child: icon),
      ),
    );
  }

  List<Marker> _buildMarkers(AppTokens t) {
    final markers = <Marker>[];
    final accent = t.palette.l2Accent;
    for (final p in _favorites) {
      markers.add(Marker(
        point: LatLng(p.lat, p.lng),
        width: 46,
        height: 46,
        alignment: Alignment.topCenter,
        child: GestureDetector(
          onTap: () => _applyDestination(
              _PickedPlace(favId: p.id, name: p.name, lat: p.lat, lng: p.lng)),
          child: _pin(
            color: accent,
            tip: p.folder.isEmpty ? p.name : '${p.folder} · ${p.name}',
            icon: Icon(Icons.star, color: accent, size: 17),
          ),
        ),
      ));
    }
    final o = _origin;
    if (o != null) {
      markers.add(Marker(
        point: LatLng(o.lat, o.lng),
        width: 46,
        height: 46,
        alignment: Alignment.topCenter,
        child: _pin(
          color: Colors.green.shade700,
          tip: '起点',
          icon: Icon(Icons.trip_origin, color: Colors.green.shade700, size: 17),
        ),
      ));
    }
    final d = _destination;
    if (d != null) {
      markers.add(Marker(
        point: LatLng(d.lat, d.lng),
        width: 46,
        height: 46,
        alignment: Alignment.topCenter,
        child: _pin(
          color: Colors.red.shade600,
          tip: '终点',
          icon: Icon(Icons.location_on, color: Colors.red.shade600, size: 17),
        ),
      ));
    }
    for (final pt in _measurePoints) {
      markers.add(Marker(
        point: pt,
        width: 46,
        height: 46,
        child: _pin(
          color: accent,
          tip: '测距点',
          icon: Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
          ),
        ),
      ));
    }
    // 「我的位置」蓝点（GCJ-02；白边实心点，精度圈见 CircleLayer）。
    final me = _myLocation;
    if (me != null) {
      markers.add(Marker(
        point: me,
        width: 46,
        height: 46,
        child: const Center(
          child: _MyLocationDot(),
        ),
      ));
    }
    // 路线步骤转向节点（**地图上示意**：每步折线起点一枚小转向标，
    // 与面板步骤列表的徽章同图标语义——面板看详情，地图看格局）。
    final route = _routeView;
    if (route?.ok == true) {
      final steps = route!.steps;
      for (var i = 0; i < steps.length && i < 12; i++) {
        final poly = steps[i].polyline;
        if (poly.isEmpty) continue;
        final turn = turnKindOf(steps[i].instruction);
        markers.add(Marker(
          // 端口侧 LatLng → 画布 latlong2 LatLng（本页坐标口径）。
          point: LatLng(poly.first.lat, poly.first.lng),
          width: 26,
          height: 26,
          child: Center(
            child: Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.92),
                shape: BoxShape.circle,
                border: Border.all(color: accent, width: 1.5),
              ),
              child: Center(
                child: Icon(_turnIcon(turn), size: 12, color: accent),
              ),
            ),
          ),
        ));
      }
    }
    return markers;
  }

  List<Polyline> _buildPolylines(AppTokens t) {
    final polylines = <Polyline>[];
    final routeColor = t.palette.l2Accent;
    // 路线折线：各步骤 polyline 顺序拼接（GCJ-02，画布与瓦片同系直用）；
    // 端口侧 LatLng 仅取 lat/lng 字段，构造回本页（latlong2）LatLng。
    // 白描边（borderStrokeWidth）让彩线在花底图上不糊——高德路线观感。
    if (_routeView?.ok == true) {
      final pts = <LatLng>[
        for (final s in _routeView!.steps)
          for (final p in s.polyline) LatLng(p.lat, p.lng),
      ];
      if (pts.length >= 2) {
        polylines.add(Polyline(
          points: pts,
          strokeWidth: 5,
          color: routeColor,
          borderStrokeWidth: 2.5,
          borderColor: Colors.white,
        ));
      }
    }
    if (_measurePoints.length == 2) {
      polylines.add(Polyline(
        points: List<LatLng>.of(_measurePoints),
        strokeWidth: 3.5,
        color: routeColor,
        borderStrokeWidth: 1.5,
        borderColor: Colors.white,
      ));
    }
    return polylines;
  }

  // ---- 选点工具条（路线页：起点/终点；测距打点移至测距分段） ----

  Widget _buildPickBar(AppTokens t) => Wrap(
        spacing: t.metrics.space8,
        runSpacing: t.metrics.space8,
        children: <Widget>[
          _pickChip(t, '设起点', _PickMode.origin, _origin?.name),
          _pickChip(t, '设终点', _PickMode.destination, _destination?.name),
          // 「当前位置」：一键把定位设为起点（默认起点语义的显式入口）。
          ActionChip(
            avatar: _locating
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.my_location, size: 18),
            label: Text(_origin?.name == '我的位置' ? '起点=当前位置' : '当前位置'),
            onPressed: _locating ? null : _setCurrentAsOrigin,
          ),
        ],
      );

  Widget _pickChip(AppTokens t, String label, _PickMode mode, String? value) =>
      ChoiceChip(
        label: Text(value == null ? label : '$label: $value'),
        selected: _pickMode == mode,
        onSelected: (_) => _setPickMode(mode),
      );

  // ---- 路线规划（四模态） ----

  Widget _buildRouteSection(AppTokens t) => SectionCard(
        title: '路线规划',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (_routeFormError != null) ...<Widget>[
              ErrorLine(code: 'MISSING_ARGUMENT', message: _routeFormError!),
              SizedBox(height: t.metrics.space8),
            ],
            Text('起点/终点来自收藏点、搜索结果或地图选点（工具条）',
                style: t.typeScale.compact),
            SizedBox(height: t.metrics.space8),
            Wrap(
              spacing: t.metrics.space8,
              runSpacing: t.metrics.space8,
              children: <Widget>[
                for (final m in const <(String, String)>[
                  ('walking', '🚶 步行'),
                  ('bicycling', '🚴 骑行'),
                  ('driving', '🚗 驾车'),
                  ('transit', '🚌 公交'),
                ])
                  OutlinedButton(
                    onPressed: _routing ? null : () => _runRoute(m.$1),
                    child: Text(m.$2),
                  ),
              ],
            ),
            // 公交规划高德强制城市（CITY_REQUIRED 前置校验在端口）。
            TextField(
              controller: _transitCityCtrl,
              decoration: const InputDecoration(
                  labelText: '公交城市（选公交时必填）', isDense: true),
            ),
            if (_routing) const Padding(padding: EdgeInsets.only(top: 8), child: LinearProgressIndicator()),
            if (_routeView != null) ...<Widget>[
              SizedBox(height: t.metrics.space8),
              if (_routeView!.ok) ...<Widget>[
                TelemetryText(
                    '${_routeView!.mode} · ${_routeView!.durationText} · ${_routeView!.distanceText}'
                    '${_routeView!.taxiCost != null ? ' · 打车约¥${_routeView!.taxiCost!.toStringAsFixed(0)}' : ''}'),
                SizedBox(height: t.metrics.space8),
                _buildRouteSteps(t, _routeView!.steps),
              ] else
                ErrorLine(code: _routeView!.errorCode, message: _routeView!.message),
            ],
          ],
        ),
      );

  // ---- 路线步骤（公共区块化 + 转向/方位图标） ----

  /// 路线步骤列表（公共区块语言：徽章 + 正文 + 遥测轨距离 + 绝对方位）。
  ///
  /// - **相对方向**：`route_guidance.turnKindOf` 解析 instruction → 转向图标；
  /// - **绝对方位**：高德 `step.orientation` 归一成角度 → 旋向箭头 + 八方位名；
  /// - 末步徽章 = 到达旗；无法识别转向 → 序号（不猜方向）。
  Widget _buildRouteSteps(AppTokens t, List<RouteStepView> steps) {
    final shown = steps.take(12).toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (var i = 0; i < shown.length; i++)
          _buildRouteStepTile(t, i, shown[i], shown.length),
      ],
    );
  }

  Widget _buildRouteStepTile(
      AppTokens t, int idx, RouteStepView s, int total) {
    final turn = turnKindOf(s.instruction);
    final bearing = absoluteBearingOf(s.orientation);
    final isLast = idx == total - 1;
    return Padding(
      padding: EdgeInsets.only(top: t.metrics.space4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // 徽章：相对转向图标（末步=到达旗；未识别=序号）。
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: t.palette.l2Accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(t.metrics.radiusBadge),
            ),
            child: Center(
              child: isLast
                  ? Icon(Icons.flag_outlined, size: 15, color: t.palette.l2Accent)
                  : turn == TurnKind.unknown
                      ? Text('${idx + 1}',
                          style: t.typeScale.micro
                              .copyWith(color: t.palette.l2Accent))
                      : Icon(_turnIcon(turn),
                          size: 16, color: t.palette.l2Accent),
            ),
          ),
          SizedBox(width: t.metrics.space8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(s.instruction, style: t.typeScale.compact),
                if (s.distanceMeters != null || bearing != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Row(
                      children: <Widget>[
                        // 距离走遥测轨（ui-design §2：数值禁阅读轨）。
                        if (s.distanceMeters != null)
                          TelemetryText('${s.distanceMeters!.toStringAsFixed(0)} m'),
                        if (bearing != null) ...<Widget>[
                          SizedBox(width: t.metrics.space4),
                          // 绝对方位：旋向箭头（0=北）+ 八方位名。
                          Transform.rotate(
                            angle: bearing * math.pi / 180,
                            child: Icon(Icons.navigation,
                                size: 12, color: t.palette.textMuted),
                          ),
                          SizedBox(width: t.metrics.space4 / 2),
                          Text(bearingDirectionName(bearing),
                              style: t.typeScale.micro
                                  .copyWith(color: t.palette.textMuted)),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 相对转向 → Material 转向图标（turn_left/turn_right/u_turn/roundabout/
  /// straight 均为 Flutter 内置，零图标资源）。
  IconData _turnIcon(TurnKind k) => switch (k) {
        TurnKind.left => Icons.turn_left,
        TurnKind.right => Icons.turn_right,
        TurnKind.slightLeft => Icons.turn_left,
        TurnKind.slightRight => Icons.turn_right,
        TurnKind.uturn => Icons.u_turn_left,
        TurnKind.roundabout => Icons.roundabout_left,
        TurnKind.straight => Icons.straight,
        TurnKind.start => Icons.trip_origin,
        TurnKind.end => Icons.flag_outlined,
        TurnKind.unknown => Icons.arrow_upward,
      };

  // ---- 收藏（读经 Repository，写经用户侧命令族） ----

  Widget _buildFavoritesSection(AppTokens t) => SectionCard(
        title: '收藏地点',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (_favError != null) ...<Widget>[
              ErrorLine(code: 'FAVORITE_WRITE_FAILED', message: _favError!),
              SizedBox(height: t.metrics.space8),
            ],
            if (_favorites.isEmpty)
              Text('暂无收藏——下方表单添加，画布将显示 Marker',
                  style: t.typeScale.compact)
            else
              // 收藏夹分组呈现（派生分组：夹名来自收藏 folder 字段）。
              for (final group in groupFavoritesByFolder(_favorites)) ...<Widget>[
                Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 2),
                  child: Row(
                    children: <Widget>[
                      Icon(
                        group.folder.isEmpty ? Icons.inbox_outlined : Icons.folder_outlined,
                        size: 14,
                      ),
                      SizedBox(width: t.metrics.space4),
                      Text(
                        '${group.folder.isEmpty ? '未分类' : group.folder}'
                        '（${group.places.length}）',
                        style: t.typeScale.compact
                            .copyWith(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
                for (final p in group.places)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.place, size: 20),
                    title: Text(p.name, style: t.typeScale.body),
                    subtitle: Text(
                        p.address?.isNotEmpty == true ? p.address! : p.formatted,
                        style: t.typeScale.compact),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        TextButton(
                          onPressed: () => _applyOrigin(_PickedPlace(
                              favId: p.id, name: p.name, lat: p.lat, lng: p.lng)),
                          child: const Text('设起点'),
                        ),
                        TextButton(
                          onPressed: () => _applyDestination(_PickedPlace(
                              favId: p.id, name: p.name, lat: p.lat, lng: p.lng)),
                          child: const Text('设终点'),
                        ),
                        IconButton(
                          tooltip: '删除收藏',
                          icon: const Icon(Icons.delete_outline, size: 20),
                          onPressed:
                              _favBusy ? null : () => _deleteFavorite(p),
                        ),
                      ],
                    ),
                    onTap: () => _applyDestination(_PickedPlace(
                        favId: p.id, name: p.name, lat: p.lat, lng: p.lng)),
                  ),
              ],
            SizedBox(height: t.metrics.space8),
            TextField(
              controller: _favName,
              decoration: const InputDecoration(labelText: '收藏名称（必填）'),
            ),
            SizedBox(height: t.metrics.space8),
            TextField(
              controller: _favFolder,
              decoration: const InputDecoration(
                labelText: '收藏夹（留空 = 未分类，≤20 字符）',
                isDense: true,
              ),
            ),
            // 已有收藏夹快捷填入（派生夹名，点击即填，免手打）。
            if (_existingFolders.isNotEmpty) ...<Widget>[
              SizedBox(height: t.metrics.space4),
              Wrap(
                spacing: t.metrics.space8,
                runSpacing: t.metrics.space4,
                children: <Widget>[
                  for (final f in _existingFolders)
                    ActionChip(
                      label: Text(f),
                      visualDensity: VisualDensity.compact,
                      onPressed: () =>
                          setState(() => _favFolder.text = f),
                    ),
                ],
              ),
            ],
            SizedBox(height: t.metrics.space8),
            Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    controller: _favLat,
                    decoration: const InputDecoration(labelText: '纬度（GCJ-02）'),
                  ),
                ),
                SizedBox(width: t.metrics.space8),
                Expanded(
                  child: TextField(
                    controller: _favLng,
                    decoration: const InputDecoration(labelText: '经度（GCJ-02）'),
                  ),
                ),
              ],
            ),
            SizedBox(height: t.metrics.space8),
            FilledButton.icon(
              onPressed: _favBusy ? null : _addFavorite,
              icon: const Icon(Icons.star_border),
              label: const Text('添加收藏'),
            ),
          ],
        ),
      );

  // ---- 坐标纠偏（纯内核，零依赖恒可用） ----

  Widget _buildConvertSection(AppTokens t) => SectionCard(
        title: '坐标纠偏',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('输入 WGS-84 坐标，同屏查看三坐标系结果（无需 Key 与权限）',
                style: t.typeScale.compact),
            SizedBox(height: t.metrics.space8),
            Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    controller: _lat,
                    decoration: const InputDecoration(labelText: '纬度'),
                  ),
                ),
                SizedBox(width: t.metrics.space8),
                Expanded(
                  child: TextField(
                    controller: _lng,
                    decoration: const InputDecoration(labelText: '经度'),
                  ),
                ),
              ],
            ),
            SizedBox(height: t.metrics.space8),
            FilledButton(onPressed: _runConvert, child: const Text('换算')),
            if (_geoView != null) ...<Widget>[
              SizedBox(height: t.metrics.space8),
              if (_geoView!.ok)
                for (final p in _geoView!.points)
                  Padding(
                    padding: EdgeInsets.only(top: t.metrics.space4),
                    child: Row(
                      children: <Widget>[
                        SizedBox(
                          width: 72,
                          child: Text(p.label, style: t.typeScale.compact),
                        ),
                        TelemetryText(p.formatted),
                      ],
                    ),
                  )
              else
                ErrorLine(
                  code: _geoView!.errorCode,
                  message: _geoView!.message,
                ),
            ],
          ],
        ),
      );
}

/// 起点/终点/测距点的地图选点模式。
enum _PickMode { none, origin, destination, measure }

/// 面板功能分段（按钮切换，一次展示一个功能的完整面）。
enum _GeoPanelTab { search, route, favorite, measure, convert }

/// 「我的位置」蓝点：白边实心点 + 呼吸光圈（原生地图小蓝点观感）。
class _MyLocationDot extends StatefulWidget {
  const _MyLocationDot();

  @override
  State<_MyLocationDot> createState() => _MyLocationDotState();
}

class _MyLocationDotState extends State<_MyLocationDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat(reverse: true);
  late final Animation<double> _pulse =
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 46,
      height: 46,
      child: Center(
        child: AnimatedBuilder(
          animation: _pulse,
          builder: (context, _) => Stack(
            alignment: Alignment.center,
            children: <Widget>[
              // 呼吸光圈：透明度与尺寸随脉冲收敛。
              Opacity(
                opacity: 0.35 * (1 - _pulse.value),
                child: Transform.scale(
                  scale: 0.6 + 0.8 * _pulse.value,
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: Colors.blue.withValues(alpha: 0.45),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
              Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: Colors.blue,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 3),
                  boxShadow: const <BoxShadow>[
                    BoxShadow(color: Color(0x40000000), blurRadius: 3, offset: Offset(0, 1)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 已选地点（收藏点带 favId 便于删除后清引用）。
class _PickedPlace {
  const _PickedPlace({
    this.favId,
    required this.name,
    required this.lat,
    required this.lng,
  });

  final String? favId;
  final String name;
  final double lat;
  final double lng;
}
