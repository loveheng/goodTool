// S7 装配收口测试：验证「双通道共用的工具面」能力面完整、派发闭环、错误 fail-closed。
//
// 不依赖设备与网络：`geo_distance` 的 straight 档走本地 Haversine，
// 高德动作在未配 Key 时必须返回 `ERR_AMAP_KEY_MISSING`（禁静默兜底）。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:goodtools/mcp/geo_provider.dart';
import 'package:goodtools/mcp/settings_kv.dart';
import 'package:goodtools/mcp/tool_face.dart';
import 'package:goodtools/action/command_gateway.dart';
import 'package:goodtools/mcp/weather_provider.dart';
import 'package:goodtools/ports.dart';
import 'package:goodtools/tool_face_assembly.dart';
import 'package:goodtools/tools/calendar/holiday_table.dart';

void main() {
  late SettingsKv kv;

  setUp(() {
    kv = InMemoryKv();
  });

  McpToolFace face() => buildDefaultToolFace(kv: kv);

  /// 单条 text content → 文本。
  String textOf(Map<String, Object?> result) =>
      ((result['content'] as List).first as Map)['text'] as String;

  Map<String, Object?> jsonOf(Map<String, Object?> result) =>
      jsonDecode(textOf(result)) as Map<String, Object?>;

  /// 某工具的 action 枚举列表。
  List<String> actionsOf(String toolName) {
    final schema = face()
        .schemas()
        .firstWhere((s) => s['name'] == toolName);
    final props = (schema['inputSchema'] as Map)['properties'] as Map;
    return ((props['action'] as Map)['enum'] as List).cast<String>().toList();
  }

  group('能力面（tools/list 收敛到域数）', () {
    test('只暴露 4 个领域工具：math_utility + geo + weather + system_pim', () {
      final names = face().schemas().map((s) => s['name']).toList();
      expect(names, ['math_utility', 'geo', 'weather', 'system_pim']);
    });

    test('action 合计 33 项（math 4 + geo 9 + weather 5 + pim 15），与矩阵闭环', () {
      expect(actionsOf('math_utility'),
          ['calc_eval', 'unit_convert', 'unit_list', 'list_stats']);
      expect(actionsOf('geo').length, 9);
      expect(
        actionsOf('weather')..sort(),
        [
          'weather_air',
          'weather_astronomy',
          'weather_forecast',
          'weather_indices',
          'weather_minutely',
        ],
      );
      expect(actionsOf('system_pim'), hasLength(15));
      expect(
        actionsOf('system_pim'),
        containsAll(<String>[
          'calendar_query',
          'calendar_subscribe',
          'calendar_marker_add',
          'calendar_month_grid',
          'calendar_date_diff',
        ]),
      );
    });

    test('每个 action 描述带紧凑参数签名（消参数盲盒）', () {
      final desc =
          face().schemas().map((s) => s['description'] as String).join('\n');
      expect(desc, contains('geo_distance('));
      expect(desc, contains('calc_eval('));
    });

    test('四个聚合工具均声明 visibility=shared（宿主可收进共享面）', () {
      // SDK 0.2.0 可见性标记：本仓 tools/list 由 Dart 侧产出（Kotlin 侧全量接管
      // 路由，反射派发器扫不到 @McpTool），故 _meta.goodhub.visibility 必由本侧
      // 下发——漏发即宿主按 default-deny 把四个域工具全判为私有。
      final schemas = face().schemas();
      expect(schemas, hasLength(4));
      for (final s in schemas) {
        final goodhub = (s['_meta'] as Map)['goodhub'] as Map;
        expect(goodhub['visibility'], 'shared', reason: '${s['name']} 未标 shared');
      }
    });
  });

  group('派发闭环', () {
    test('math_utility.calc_eval 走通（纯 Dart 零依赖主线）', () async {
      final r = await face().call('math_utility', {
        'action': 'calc_eval',
        'params': {'expr': '0.1+0.2'},
      });
      expect(r['isError'], isFalse);
      final j = jsonOf(r);
      expect(j['success'], isTrue);
      expect(j['result'], '0.3');
    });

    test('geo.geo_distance straight 走本地 Haversine（不依赖网络与 Key）',
        () async {
      final r = await face().call('geo', {
        'action': 'geo_distance',
        'params': {
          'from': {'lat': 39.9, 'lng': 116.4},
          'to': {'lat': 39.91, 'lng': 116.4},
        },
      });
      expect(r['isError'], isFalse);
      expect(jsonOf(r)['mode'], 'straight');
    });

    test('注入桩 Provider 时装配面接管（端口注入纪律）', () async {
      final f = buildDefaultToolFace(
        kv: kv,
        sensor: _SensorStub(),
        http: _HttpStub(),
        weather: _WeatherStub(),
      );
      final w = await f.call('weather', {
        'action': 'weather_forecast',
        'params': {'city': '朝阳'},
      });
      expect(w['isError'], isFalse);
      expect(jsonOf(w)['city'], '北京市 朝阳区');
      final r = await f.call('geo', {
        'action': 'geo_current',
        'params': {},
      });
      expect(r['isError'], isFalse);
      expect(jsonOf(r)['lat'], 39.9);
    });
  });

  group('错误口径（fail-closed，不静默兜底）', () {
    test('未配高德 Key → 裸码带 geo.<action>: 前缀', () async {
      final r = await face().call('geo', {
        'action': 'geo_geocode',
        'params': {'address': '北京市朝阳区'},
      });
      expect(r['isError'], isTrue);
      final j = jsonOf(r);
      expect((j['error'] as Map)['code'], startsWith('geo.geo_geocode:'));
      expect((j['error'] as Map)['code'], contains('ERR_AMAP_KEY_MISSING'));
    });

    test('KV 补填 Key 后**无需重建工具面**即生效（懒读收益）', () async {
      final f = buildDefaultToolFace(kv: kv, http: _HttpStub());
      await kv.settingsSet({kAmapWebKey: 'K'});
      final r = await f.call('geo', {
        'action': 'geo_geocode',
        'params': {'address': '北京市朝阳区'},
      });
      expect(r['isError'], isFalse);
    });

    test('未配和风 Key → ERR_WEATHER_KEY_MISSING（fail-closed，不静默 null）',
        () async {
      final r = await face().call('weather', {
        'action': 'weather_forecast',
        'params': {'city': '北京'},
      });
      expect(r['isError'], isTrue);
      final code = (jsonOf(r)['error'] as Map)['code'] as String;
      expect(code, startsWith('weather.weather_forecast:'));
      expect(code, contains('ERR_WEATHER_KEY_MISSING'));
    });

    test('未注入定位实现 → PERMISSION_DENIED（不伪造坐标）', () async {
      final r = await face().call('geo', {
        'action': 'geo_current',
        'params': {},
      });
      expect(r['isError'], isTrue);
      expect((jsonOf(r)['error'] as Map)['code'],
          contains('PERMISSION_DENIED'));
    });

    test('system_pim 纯函数 R 档经装配可用（内置节假日表注入生效）', () async {
      final r = await buildDefaultToolFace(kv: kv, holidays: cnHolidayBundled)
          .call('system_pim', {
        'action': 'calendar_workdays_between',
        'params': {
          'startDate': '2026-10-01',
          'endDate': '2026-10-11',
        },
      });
      expect(r['isError'], isFalse);
      final j = jsonOf(r);
      expect(j['workdays'], 3); // 10-08、10-09、10-10（调休补班计入）
      expect(j['holidayTableVersion'], 'cn-2026.1');
    });

    test('system_pim W 档已登记 Actor：subscribe 幂等落 KV（不发网络）', () async {
      final r = await face().call('system_pim', {
        'action': 'calendar_subscribe',
        'params': {'url': 'webcal://example.com/holiday.ics'},
      });
      expect(r['isError'], isFalse);
      final j = jsonOf(r);
      expect(j['url'], 'https://example.com/holiday.ics'); // webcal 规整
      expect(j['feedId'], isNotEmpty);
    });

    test('system_pim W 档：装配件总登记 Actor，作用域错误明确（不假装成功）', () async {
      final f = buildDefaultToolFace(kv: kv, gateway: CommandGateway());
      final r = await f.call('system_pim', {
        'action': 'calendar_marker_delete',
        'params': {'markerId': 'mk_none'},
      });
      expect(r['isError'], isTrue);
      expect(((jsonOf(r)['error'] as Map)['code'] as String),
          contains('ERR_MARKER_NOT_FOUND'));
    });

    test('未知分类 → UNKNOWN_TOOL', () async {
      final r = await face().call('ping', {});
      expect(r['isError'], isTrue);
      expect(textOf(r), contains('UNKNOWN_TOOL'));
    });

    test('缺 action → MISSING_ACTION', () async {
      final r = await face().call('geo', {});
      expect(r['isError'], isTrue);
      expect(textOf(r), contains('MISSING_ACTION'));
    });

    test('枚举外 action → UNKNOWN_ACTION（不幻觉执行）', () async {
      final r = await face().call('geo', {
        'action': 'geo_teleport',
        'params': {},
      });
      expect(r['isError'], isTrue);
      expect(textOf(r), contains('UNKNOWN_ACTION'));
    });
  });
}

/// 定位桩：固定返回 WGS-84 读数。
class _SensorStub implements LocationSensorProvider {
  @override
  Future<LocationReading?> current() async => LocationReading(
        lat: 39.9,
        lng: 116.4,
        accuracy: 5,
        coordSystem: 'WGS84',
        timestamp: 0,
      );

  @override
  Future<CompassReading?> compass() async => const CompassReading(
        heading: 0,
        accuracy: 1,
      );
}

/// 天气桩：回放固定成功信封（验证装配面把 Provider 注入到 weather 分类）。
class _WeatherStub implements WeatherProvider {
  @override
  Future<WeatherResult> forecast({
    String? city,
    double? lat,
    double? lng,
    int days = 3,
  }) async =>
      const WeatherResult.success(
        city: '北京市 朝阳区',
        locationId: '101010100',
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

/// 高德 HTTP 桩：只验证「已配 Key 即放行」，不模拟真实响应体。
class _HttpStub implements GeoHttpProvider {
  @override
  Future<Map<String, Object?>> get(String path, Map<String, String> query) async =>
      <String, Object?>{'status': '1', 'info': 'OK'};
}
