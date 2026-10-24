// 天气页 widget 冒烟：手风琴卡片（点卡就地展开详情）+ 左滑删除（Dismissible +
// 撤销 SnackBar）。真机手动项（拖拽手感 / 快甩 / 键盘遮挡）不在本文件覆盖。
//
// 写路径走**真实链路**：InMemoryWeatherCityStore + WeatherCityActors 经网关派发
//（与生产同构，验证 R1 组装命令口径），仅天气取数用假端口。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goodtools/action/command_gateway.dart';
import 'package:goodtools/mcp/weather_provider.dart';
import 'package:goodtools/repository/weather_city_repository.dart';
import 'package:goodtools/service/weather_city_actors.dart';
import 'package:goodtools/service/weather_city_store.dart';
import 'package:goodtools/ui/theme.dart';
import 'package:goodtools/ui/weather_page.dart';
import 'package:goodtools/ui_ports/weather_port.dart';

/// 假天气端口：forecast 回放固定成功视图（temp/现象/一日预报）。
class _FakeProvider implements WeatherProvider {
  @override
  Future<WeatherResult> forecast({
    String? city,
    double? lat,
    double? lng,
    int days = 3,
  }) async =>
      WeatherResult.success(
        city: '北京市 朝阳区',
        updateTime: '2026-10-24T12:00+08:00',
        now: const <String, Object?>{
          'text': '多云',
          'temp': '18',
          'humidity': '45',
          'windDir': '东北风',
          'windScale': '2',
        },
        forecast: const <Map<String, Object?>>[
          <String, Object?>{
            'fxDate': '2026-10-24',
            'textDay': '晴',
            'tempMax': '20',
            'tempMin': '10',
          },
        ],
      );

  @override
  Future<CitySearchResult> searchCity(String query) async =>
      const CitySearchResult.success(<QCityOption>[]);

  @override
  Future<CitySearchResult> lookupCityByCoords({
    required double lat,
    required double lng,
  }) async =>
      const CitySearchResult.success(<QCityOption>[]);

  @override
  Future<WeatherResult> air({String? city, double? lat, double? lng}) async =>
      const WeatherResult.failure(WeatherError(WeatherErr.keyMissing, '桩'));

  @override
  Future<WeatherResult> indices({
    String? city,
    double? lat,
    double? lng,
    int days = 1,
    String? type,
  }) async =>
      const WeatherResult.failure(WeatherError(WeatherErr.keyMissing, '桩'));

  @override
  Future<WeatherResult> astronomy({
    String? city,
    double? lat,
    double? lng,
    String? date,
  }) async =>
      const WeatherResult.failure(WeatherError(WeatherErr.keyMissing, '桩'));

  @override
  Future<WeatherResult> minutely({String? city, double? lat, double? lng}) async =>
      const WeatherResult.failure(WeatherError(WeatherErr.keyMissing, '桩'));
}

void main() {
  late InMemoryWeatherCityStore store;
  late CommandGateway gateway;

  setUp(() {
    store = InMemoryWeatherCityStore();
    gateway = CommandGateway();
    WeatherCityActors(store: store, writer: store).register(gateway);
  });

  Future<void> pumpPage(
    WidgetTester tester, {
    List<WeatherCity> seed = const <WeatherCity>[],
  }) async {
    for (final c in seed) {
      await store.addCity(c);
    }
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(brightness: Brightness.light),
        home: Scaffold(
          body: WeatherPage(
            port: WeatherPort(_FakeProvider()),
            cities: WeatherCityRepository(store: store),
            gateway: gateway,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  WeatherCity city(String id, String name) => WeatherCity(
        id: id,
        name: name,
        lat: 39.92,
        lng: 116.43,
      );

  testWidgets('首帧：城市卡摘要 + 手势说明行（无删除按钮）', (tester) async {
    await pumpPage(tester, seed: [city('a1', '北京市 朝阳区')]);
    expect(find.text('北京市 朝阳区'), findsOneWidget);
    expect(find.text('左滑删除 · 点卡片展开/收起详情'), findsOneWidget);
    // 手势代替按钮：页面上没有删除 IconButton。
    expect(find.byIcon(Icons.delete_outline), findsNothing);
    expect(find.byIcon(Icons.arrow_forward), findsNothing);
  });

  testWidgets('手风琴：点卡片就地展开详情，再点收起（详情不另起区块）', (tester) async {
    await pumpPage(tester, seed: [city('a1', '北京市 朝阳区')]);
    // 展开前无详情内容。
    expect(find.text('10 ~ 20℃'), findsNothing);
    await tester.tap(find.text('点击展开'));
    await tester.pumpAndSettle();
    // 详情内联在卡片里：now + 逐日 + 更新时间同屏。
    expect(find.text('点击收起'), findsOneWidget);
    expect(find.text('多云'), findsWidgets);
    expect(find.text('10 ~ 20℃'), findsOneWidget);
    expect(find.textContaining('更新时间 2026-10-24'), findsOneWidget);
    // 再点收起。
    await tester.tap(find.text('点击收起'));
    await tester.pumpAndSettle();
    expect(find.text('点击展开'), findsOneWidget);
    expect(find.text('10 ~ 20℃'), findsNothing);
  });

  testWidgets('左滑删除：条目离场 + SnackBar 撤销恢复', (tester) async {
    await pumpPage(tester, seed: [city('a1', '北京市 朝阳区')]);
    await tester.drag(find.text('北京市 朝阳区'), const Offset(-500, 0));
    await tester.pumpAndSettle();
    // 乐观移除 + 真实命令派发：store 已空，SnackBar 出撤销。
    expect(await store.list(), isEmpty);
    expect(find.text('已删除 北京市 朝阳区'), findsOneWidget);
    await tester.tap(find.text('撤销'));
    await tester.pumpAndSettle();
    final restored = await store.list();
    expect(restored, hasLength(1));
    expect(restored.single.name, '北京市 朝阳区');
  });

  testWidgets('多城渲染：各城摘要独立（逐城聚合），展开互斥', (tester) async {
    await pumpPage(tester,
        seed: [city('a1', '北京市 朝阳区'), city('b2', '上海市 浦东新区')]);
    expect(find.text('18℃'), findsNWidgets(2)); // 两城摘要均聚合完成
    await tester.tap(find.text('点击展开').first);
    await tester.pumpAndSettle();
    expect(find.text('点击收起'), findsOneWidget);
  });
}
