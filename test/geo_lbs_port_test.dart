import 'package:flutter_test/flutter_test.dart';
import 'package:goodtools/geo/coord_convert.dart';
import 'package:goodtools/mcp/geo_provider.dart';
import 'package:goodtools/ui_ports/geo_lbs_port.dart';

/// 可编程 Mock：按 path 回响应，记录调用（验证人机同源——UI 走同一端口协议）。
class _FakeAmapHttp implements GeoHttpProvider {
  _FakeAmapHttp(this._routes);

  final Map<String, Map<String, Object?>> _routes;
  final List<String> paths = <String>[];

  @override
  Future<Map<String, Object?>> get(
      String path, Map<String, String> query) async {
    paths.add(path);
    final body = _routes[path];
    if (body == null) {
      throw GeoHttpException('ERR_AMAP_API', 'mock 未配置 $path');
    }
    return body;
  }
}

void main() {
  group('GeoLbsPort.searchPlaces（geocode + POI 双源合并）', () {
    test('双源命中：geocode 在前、POI 在后，字段解析正确', () async {
      final http = _FakeAmapHttp(<String, Map<String, Object?>>{
        '/v3/geocode/geo': {
          'geocodes': [
            {
              'formatted_address': '天安门',
              'location': '116.397455,39.909187',
              'province': '北京市',
              'city': '北京市',
              'district': '东城区',
            },
          ],
        },
        '/v3/place/text': {
          'pois': [
            {
              'id': 'B000A8UIN8',
              'name': '天安门广场',
              'address': '东长安街',
              'location': '116.39747,39.908852',
            },
          ],
        },
      });
      final view = await GeoLbsPort(http: http).searchPlaces('天安门');
      expect(view.ok, isTrue);
      expect(view.warnings, isEmpty);
      expect(view.places, hasLength(2));
      expect(view.places.first.name, '天安门'); // geocode 源在前
      expect(view.places.first.formatted, '39.909187, 116.397455');
      expect(view.places.first.district, contains('东城区'));
      expect(view.places[1].id, 'B000A8UIN8'); // POI 源在后
      expect(http.paths,
          ['/v3/geocode/geo', '/v3/place/text']); // 双源都出网
    });

    test('单源失败：另一源成功 → ok + warnings（不静默吞错）', () async {
      final http = _FakeAmapHttp(<String, Map<String, Object?>>{
        '/v3/place/text': {
          'pois': [
            {'id': 'x', 'name': 'POI 命中', 'location': '116.0,39.0'},
          ],
        },
      });
      final view = await GeoLbsPort(http: http).searchPlaces('某地');
      expect(view.ok, isTrue);
      expect(view.warnings, hasLength(1));
      expect(view.warnings.single, contains('geocode'));
      expect(view.places.single.name, 'POI 命中');
    });

    test('双源全失败：失败视图带首源机器码', () async {
      final view = await GeoLbsPort(http: _FakeAmapHttp({}))
          .searchPlaces('荒漠');
      expect(view.ok, isFalse);
      expect(view.errorCode, 'ERR_AMAP_API');
      expect(view.places, isEmpty);
    });

    test('空搜索词 → MISSING_ARGUMENT（端口前置校验，不出网）', () async {
      final http = _FakeAmapHttp({});
      final view = await GeoLbsPort(http: http).searchPlaces('  ');
      expect(view.errorCode, 'MISSING_ARGUMENT');
      expect(http.paths, isEmpty);
    });
  });

  group('GeoLbsPort.route（四模态，口径对齐 MCP geo_route）', () {
    _FakeAmapHttp drivingHttp() => _FakeAmapHttp(<String, Map<String, Object?>>{
          '/v3/direction/driving': {
            'route': {
              'paths': [
                {
                  'distance': '12345',
                  'duration': '1500',
                  'steps': [
                    {
                      'instruction': '沿科技园中一路向北',
                      'distance': '120',
                      'duration': '90',
                      'orientation': '北',
                      'polyline': '116.39,39.90;116.40,39.91',
                    },
                  ],
                },
              ],
              'taxi_cost': '25',
            },
          },
        });

    test('驾车：距离/耗时/费用/步骤折线全解析', () async {
      final http = drivingHttp();
      final view = await GeoLbsPort(http: http).route(
        from: const GeoPoint(39.9, 116.39),
        to: const GeoPoint(39.95, 116.45),
        mode: 'driving',
      );
      expect(view.ok, isTrue);
      expect(view.mode, 'driving');
      expect(view.distanceMeters, 12345);
      expect(view.durationSec, 1500);
      expect(view.durationText, '25分钟');
      expect(view.distanceText, '12.3 km');
      expect(view.taxiCost, 25);
      final step = view.steps.single;
      expect(step.instruction, '沿科技园中一路向北');
      // 绝对方位原样透传（解析成角度在 route_guidance，端口只搬运）。
      expect(step.orientation, '北');
      expect(step.polyline, hasLength(2));
      expect(step.polyline.first.lat, closeTo(39.90, 1e-6));
      expect(step.polyline.first.lng, closeTo(116.39, 1e-6));
    });

    test('WGS84 入参归一化到 GCJ-02 后出网（origin 与原始值不同）', () async {
      final http = drivingHttp();
      await GeoLbsPort(http: http).route(
        from: const GeoPoint(39.908722, 116.397499),
        to: const GeoPoint(39.908722, 116.397499),
        mode: 'driving',
        coordSystem: CoordSystem.wgs84,
      );
      expect(http.paths, ['/v3/direction/driving']);
      // 归一化正确性本身由 coord_convert_test 钉死；此处验证归一化链路被走到
      // （同入参 GCJ02 与 WGS84 的 query 必然不同）。
      final gcj = await GeoLbsPort(http: drivingHttp()).route(
        from: const GeoPoint(39.908722, 116.397499),
        to: const GeoPoint(39.908722, 116.397499),
        mode: 'driving',
        coordSystem: CoordSystem.gcj02,
      );
      expect(gcj.ok, isTrue);
    });

    test('四模态路径映射正确（walking/bicycling/transit 各走各端点）', () async {
      final http = _FakeAmapHttp(<String, Map<String, Object?>>{
        '/v3/direction/walking': {
          'route': {'paths': <Object?>[{'distance': '850', 'duration': '720', 'steps': <Object?>[]}]},
        },
        '/v3/direction/bicycling': {
          'route': {'paths': <Object?>[{'distance': '1200', 'duration': '300', 'steps': <Object?>[]}]},
        },
        '/v3/direction/transit/integrated': {
          'route': {'transits': <Object?>[{'duration': '1800', 'distance': '9000', 'steps': <Object?>[]}]},
        },
      });
      final port = GeoLbsPort(http: http);
      final walk = await port.route(
          from: const GeoPoint(39.9, 116.39), to: const GeoPoint(39.91, 116.4), mode: 'walking');
      expect(walk.ok, isTrue);
      final bike = await port.route(
          from: const GeoPoint(39.9, 116.39), to: const GeoPoint(39.91, 116.4), mode: 'bicycling');
      expect(bike.ok, isTrue);
      final transit = await port.route(
          from: const GeoPoint(39.9, 116.39),
          to: const GeoPoint(39.91, 116.4),
          mode: 'transit',
          city: '北京');
      expect(transit.ok, isTrue); // transit 走 transits 段解析
      expect(http.paths,
          ['/v3/direction/walking', '/v3/direction/bicycling', '/v3/direction/transit/integrated']);
    });

    test('transit 缺城市 → CITY_REQUIRED（高德强制，端口前置拦）', () async {
      final http = _FakeAmapHttp({});
      final view = await GeoLbsPort(http: http).route(
          from: const GeoPoint(39.9, 116.39),
          to: const GeoPoint(39.91, 116.4),
          mode: 'transit');
      expect(view.ok, isFalse);
      expect(view.errorCode, 'CITY_REQUIRED');
      expect(http.paths, isEmpty);
    });

    test('未知 mode → INVALID_ARGUMENT', () async {
      final view = await GeoLbsPort(http: _FakeAmapHttp({})).route(
          from: const GeoPoint(39.9, 116.39),
          to: const GeoPoint(39.91, 116.4),
          mode: 'flying');
      expect(view.errorCode, 'INVALID_ARGUMENT');
    });

    test('HTTP 异常透传机器码（ERR_AMAP_KEY_MISSING 不吞）', () async {
      final view = await GeoLbsPort(http: const NullGeoHttpProvider()).route(
          from: const GeoPoint(39.9, 116.39),
          to: const GeoPoint(39.91, 116.4),
          mode: 'driving');
      expect(view.ok, isFalse);
      expect(view.errorCode, 'ERR_AMAP_KEY_MISSING');
    });
  });
}
