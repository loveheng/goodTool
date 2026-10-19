// S7 装配收口测试：验证「双通道共用的工具面」能力面完整、派发闭环、错误 fail-closed。
//
// 不依赖设备与网络：`geo_distance` 的 straight 档走本地 Haversine，
// 高德动作在未配 Key 时必须返回 `ERR_AMAP_KEY_MISSING`（禁静默兜底）。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:good_template/mcp/geo_provider.dart';
import 'package:good_template/mcp/settings_kv.dart';
import 'package:good_template/mcp/tool_face.dart';
import 'package:good_template/mcp/weather_provider.dart';
import 'package:good_template/ports.dart';
import 'package:good_template/tool_face_assembly.dart';

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
    test('只暴露 3 个领域工具：math_utility + geo + weather', () {
      final names = face().schemas().map((s) => s['name']).toList();
      expect(names, ['math_utility', 'geo', 'weather']);
    });

    test('action 合计 12 项（math 3 + geo 8 + weather 1），与能力文档 1:1', () {
      expect(actionsOf('math_utility'),
          ['calc_eval', 'unit_convert', 'unit_list']);
      expect(actionsOf('geo').length, 8);
      expect(actionsOf('weather'), ['weather_forecast']);
    });

    test('每个 action 描述带紧凑参数签名（消参数盲盒）', () {
      final desc =
          face().schemas().map((s) => s['description'] as String).join('\n');
      expect(desc, contains('geo_distance('));
      expect(desc, contains('calc_eval('));
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
}

/// 高德 HTTP 桩：只验证「已配 Key 即放行」，不模拟真实响应体。
class _HttpStub implements GeoHttpProvider {
  @override
  Future<Map<String, Object?>> get(String path, Map<String, String> query) async =>
      <String, Object?>{'status': '1', 'info': 'OK'};
}
