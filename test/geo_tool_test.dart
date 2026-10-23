/// geo 领域网关（S4）单测：8 个 action 派发闭环 + 坐标归一化 + 错误口径 + G5 宽容解析。
///
/// 全部走 Mock Provider，无网络、无 Key、无设备，结果 100% 确定性。
/// 动作名与 product/geo.md 表格第一列 1:1 对账（domain_gateway §落地验证 G1）。
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:goodtools/geo/coord_convert.dart';
import 'package:goodtools/mcp/category_tool_face.dart';
import 'package:goodtools/mcp/geo_provider.dart';
import 'package:goodtools/tools/geo_tool.dart';

const beijingWgs = GeoPoint(39.9042, 116.4074);

/// Mock 传感器：按构造入参返回读数（null 模拟无权限/无硬件）。
class _MockSensor implements LocationSensorProvider {
  _MockSensor({this.reading, this.compassReading});

  final LocationReading? reading;
  final CompassReading? compassReading;

  @override
  Future<LocationReading?> current() async => reading;

  @override
  Future<CompassReading?> compass() async => compassReading;
}

/// Mock 高德 HTTP：按 path 返回固化响应，并记录调用（供断言查询串）。
class _MockHttp implements GeoHttpProvider {
  _MockHttp(this._responses);

  final Map<String, Map<String, Object?>> _responses;
  final calls = <({String path, Map<String, String> query})>[];

  @override
  Future<Map<String, Object?>> get(
      String path, Map<String, String> query) async {
    calls.add((path: path, query: query));
    final r = _responses[path];
    if (r == null) {
      throw GeoHttpException('ERR_AMAP_API', '未被 mock 的路径 $path');
    }
    return r;
  }
}

LocationReading _reading() => LocationReading(
      lat: beijingWgs.lat,
      lng: beijingWgs.lng,
      accuracy: 12.5,
      coordSystem: 'WGS84',
      timestamp: 1700000000000,
      altitude: 43.0,
    );

const _drivingResponse = <String, Object?>{
  'status': '1',
  'route': <String, Object?>{
    'taxi_cost': '38.5',
    'paths': <Object?>[
      <String, Object?>{
        'distance': '12345',
        'duration': '1500',
        'steps': <Object?>[
          <String, Object?>{
            'instruction': '沿深南大道向东行驶',
            'distance': '500',
            'duration': '60',
          },
        ],
      },
    ],
  },
};

const _geocodeResponse = <String, Object?>{
  'status': '1',
  'geocodes': <Object?>[
    <String, Object?>{
      'formatted_address': '北京市朝阳区xxx大厦',
      'province': '北京市',
      'city': '北京市',
      'district': '朝阳区',
      'location': '116.407400,39.904200',
    },
  ],
};

const _regeoResponse = <String, Object?>{
  'status': '1',
  'regeocode': <String, Object?>{
    'formatted_address': '北京市朝阳区科技园中一路10号',
    'addressComponent': <String, Object?>{
      'province': '北京市',
      'city': '北京市',
      'district': '朝阳区',
      'township': 'xx街道',
    },
    'pois': <Object?>[
      <String, Object?>{'name': '腾讯大厦'},
    ],
  },
};

const _poiResponse = <String, Object?>{
  'status': '1',
  'pois': <Object?>[
    <String, Object?>{
      'id': 'B000A83:  ',
      'name': '腾讯大厦',
      'type': '商务写字楼',
      'address': '科技园中一路10号',
      'location': '116.407400,39.904200',
      'distance': '120',
    },
  ],
};

const _amapFailResponse = <String, Object?>{
  'status': '0',
  'info': 'INVALID_USER_SCODE',
  'infocode': '10001',
};

Map<String, Object?> _parse(SubActionResult r) {
  final text = r.content.first['text'] as String;
  return jsonDecode(text) as Map<String, Object?>;
}

Map<String, Object?> _errorOf(SubActionResult r) =>
    _parse(r)['error'] as Map<String, Object?>;

void main() {
  final http = _MockHttp({
    '/v3/direction/driving': _drivingResponse,
    '/v3/geocode/geo': _geocodeResponse,
    '/v3/geocode/regeo': _regeoResponse,
    '/v3/place/text': _poiResponse,
  });
  final tool = buildGeoTool(
    _MockSensor(reading: _reading(), compassReading: const CompassReading(
      heading: 324,
      accuracy: 2,
    )),
    http,
    webKeyReader: () async => 'TESTKEY',
  );

  Future<Map<String, Object?>> run(
          String action, Map<String, Object?> params) async =>
      _parse(await tool.call(action, params));

  group('能力矩阵 1:1 对账（product/geo.md）', () {
    test('geo 分类恰好注册 8 个 action，名称与能力文档一致', () {
      final schema = tool.toSchema();
      final props =
          (schema['inputSchema'] as Map)['properties'] as Map;
      final enums =
          ((props['action'] as Map)['enum'] as List).cast<String>().toList()
            ..sort();
      expect(enums, [
        'geo_compass',
        'geo_current',
        'geo_distance',
        'geo_geocode',
        'geo_reverse',
        'geo_route',
        'geo_search_poi',
        'geo_static_map',
      ]);
    });
  });

  group('geo_current', () {
    test('缺省按传感器原生坐标系输出', () async {
      final j = await run('geo_current', {});
      expect(j['success'], isTrue);
      expect(j['lat'], closeTo(beijingWgs.lat, 1e-9));
      expect(j['lng'], closeTo(beijingWgs.lng, 1e-9));
      expect(j['coordSystem'], 'WGS84');
      expect(j['accuracy'], 12.5);
      expect(j['altitude'], 43.0);
      expect(j['timestamp'], 1700000000000);
    });

    test('指定 coordSystem=GCJ02 时输出火星坐标（发生正向偏移）', () async {
      final j = await run('geo_current', {'coordSystem': 'GCJ02'});
      expect(j['coordSystem'], 'GCJ02');
      final g = CoordConvert.wgs84ToGcj02(beijingWgs);
      expect(j['lat'], closeTo(g.lat, 1e-9));
      expect(j['lng'], closeTo(g.lng, 1e-9));
    });

    test('无定位权限 → PERMISSION_DENIED（带 geo.geo_current: 前缀）', () async {
      final denied = buildGeoTool(_MockSensor(), http);
      final r = await denied.call('geo_current', {});
      expect(r.isError, isTrue);
      final err = _errorOf(r);
      expect(err['code'], startsWith('geo.geo_current:'));
      expect(err['code'], contains('PERMISSION_DENIED'));
    });
  });

  group('geo_compass', () {
    test('324° → 西北（含 accuracy）', () async {
      final j = await run('geo_compass', {});
      expect(j['success'], isTrue);
      expect(j['heading'], 324);
      expect(j['direction'], '西北');
      expect(j['accuracy'], 2);
    });

    test('无磁力计硬件 → PERMISSION_DENIED', () async {
      final denied = buildGeoTool(_MockSensor(), http);
      final err = _errorOf(await denied.call('geo_compass', {}));
      expect(err['code'] as String, contains('PERMISSION_DENIED'));
    });
  });

  group('geo_distance', () {
    test('straight 直线测距 = 内核 Haversine（不依赖网络）', () async {
      final j = await run('geo_distance', {
        'from': {'lat': 39.9, 'lng': 116.4},
        'to': {'lat': 39.91, 'lng': 116.4},
      });
      expect(j['success'], isTrue);
      final expected = CoordConvert.haversineMeters(
          const GeoPoint(39.9, 116.4), const GeoPoint(39.91, 116.4));
      expect(j['meters'], closeTo(expected, 1e-6));
      expect(j['mode'], 'straight');
    });

    test('G5 宽容解析：数字串入参亦可（与数值入参等价）', () async {
      const a = GeoPoint(39.9, 116.4);
      const b = GeoPoint(39.91, 116.4);
      final expected = CoordConvert.haversineMeters(a, b);

      final strJ = await run('geo_distance', {
        'from': {'lat': '39.9', 'lng': '116.4'},
        'to': {'lat': '39.91', 'lng': '116.4'},
      });
      final numJ = await run('geo_distance', {
        'from': {'lat': 39.9, 'lng': 116.4},
        'to': {'lat': 39.91, 'lng': 116.4},
      });
      expect(strJ['success'], isTrue);
      expect(strJ['meters'], closeTo(expected, 1e-6));
      expect(strJ['meters'], numJ['meters']);
    });

    test('road 模式取驾车距离与耗时（需 Key 的 HTTP 路径）', () async {
      final j = await run('geo_distance', {
        'from': {'lat': 39.9, 'lng': 116.4},
        'to': {'lat': 39.91, 'lng': 116.4},
        'mode': 'road',
      });
      expect(j['success'], isTrue);
      expect(j['meters'], 12345);
      expect(j['durationSec'], 1500);
      expect(j['mode'], 'road');
    });

    test('未知 mode → INVALID_ARGUMENT（不静默兜底 straight）', () async {
      final err = _errorOf(await tool.call('geo_distance', {
        'from': {'lat': 39.9, 'lng': 116.4},
        'to': {'lat': 39.91, 'lng': 116.4},
        'mode': 'fly',
      }));
      expect(err['code'] as String, contains('INVALID_ARGUMENT'));
    });

    test('缺 from/to → MISSING_ARGUMENT', () async {
      final err = _errorOf(await tool.call('geo_distance', {'mode': 'straight'}));
      expect(err['code'] as String, contains('MISSING_ARGUMENT'));
    });
  });

  group('geo_geocode', () {
    test('地址 → 坐标 + 行政区划', () async {
      final j = await run('geo_geocode', {'address': '北京市朝阳区xxx大厦'});
      expect(j['success'], isTrue);
      expect(j['count'], 1);
      final results = j['results'] as List;
      final first = results.first as Map<String, Object?>;
      expect(first['lat'], closeTo(39.9042, 1e-6));
      expect(first['lng'], closeTo(116.4074, 1e-6));
      expect(first['city'], '北京市');
    });

    test('city 附加进查询串提升命中率', () async {
      await run('geo_geocode', {'address': 'xxx大厦', 'city': '北京'});
      expect(http.calls.last.query['city'], '北京');
      expect(http.calls.last.path, '/v3/geocode/geo');
    });

    test('缺 address → MISSING_ARGUMENT', () async {
      final err = _errorOf(await tool.call('geo_geocode', {}));
      expect(err['code'] as String, contains('MISSING_ARGUMENT'));
    });

    test('高德返回失败状态 → infocode 透出为 machine code', () async {
      final failing = buildGeoTool(_MockSensor(), _MockHttp({
        '/v3/geocode/geo': _amapFailResponse,
      }));
      final err = _errorOf(
          await failing.call('geo_geocode', {'address': 'x'}));
      expect(err['code'] as String, contains('10001'));
      expect(err['message'], 'INVALID_USER_SCODE');
    });
  });

  group('geo_reverse', () {
    test('坐标 → 格式化地址与省市区镇', () async {
      final j = await run('geo_reverse', {
        'lat': beijingWgs.lat,
        'lng': beijingWgs.lng,
      });
      expect(j['success'], isTrue);
      expect(j['formattedAddress'], isA<String>());
      expect(j['city'], '北京市');
      expect(j['district'], '朝阳区');
      expect(j['town'], 'xx街道');
      expect(j['poiName'], '腾讯大厦');
    });

    test('入参按 WGS84 解释，请求前归一化到 GCJ-02', () async {
      await run('geo_reverse', {
        'lat': beijingWgs.lat,
        'lng': beijingWgs.lng,
        'coordSystem': 'WGS84',
      });
      final g = CoordConvert.wgs84ToGcj02(beijingWgs);
      expect(http.calls.last.query['location'],
          '${g.lng.toStringAsFixed(6)},${g.lat.toStringAsFixed(6)}');
      // WGS-84 坐标已被纠偏（≠ 原样透传）
      expect(http.calls.last.query['location'],
          isNot('${beijingWgs.lng.toStringAsFixed(6)},'
              '${beijingWgs.lat.toStringAsFixed(6)}'));
    });

    test('缺 lat/lng → MISSING_ARGUMENT', () async {
      final err = _errorOf(await tool.call('geo_reverse', {'lat': 39.9}));
      expect(err['code'] as String, contains('MISSING_ARGUMENT'));
    });
  });

  group('geo_search_poi', () {
    test('关键字检索返回 POI 列表', () async {
      final j = await run('geo_search_poi', {'keywords': '腾讯大厦'});
      expect(j['success'], isTrue);
      expect(j['count'], 1);
      final poi = (j['pois'] as List).first as Map<String, Object?>;
      expect(poi['name'], '腾讯大厦');
      expect(poi['lat'], closeTo(39.9042, 1e-6));
      expect(poi['distance'], 120);
    });

    test('near 周边检索：坐标归一化后写入 location', () async {
      await run('geo_search_poi', {
        'keywords': '咖啡',
        'near': {'lat': beijingWgs.lat, 'lng': beijingWgs.lng},
        'radius': 1000,
      });
      final g = CoordConvert.wgs84ToGcj02(beijingWgs);
      expect(http.calls.last.query['location'],
          '${g.lng.toStringAsFixed(6)},${g.lat.toStringAsFixed(6)}');
      expect(http.calls.last.query['radius'], '1000');
    });

    test('缺 keywords → MISSING_ARGUMENT', () async {
      final err = _errorOf(await tool.call('geo_search_poi', {}));
      expect(err['code'] as String, contains('MISSING_ARGUMENT'));
    });
  });

  group('geo_route', () {
    test('驾车：距离/耗时/步骤/打车费全链路', () async {
      final j = await run('geo_route', {
        'from': {'lat': 39.9, 'lng': 116.4},
        'to': {'lat': 39.91, 'lng': 116.4},
        'mode': 'driving',
      });
      expect(j['success'], isTrue);
      expect(j['distanceMeters'], 12345);
      expect(j['durationSec'], 1500);
      expect(j['taxiCost'], 38.5);
      final steps = j['steps'] as List;
      expect(steps.length, 1);
      expect((steps.first as Map<String, Object?>)['instruction'],
          '沿深南大道向东行驶');
      expect(j['mode'], 'driving');
      expect(http.calls.last.path, '/v3/direction/driving');
    });

    test('步行/骑行/公交各自映射到对应高德端点', () async {
      final walkingHttp = _MockHttp({
        '/v3/direction/walking': _drivingResponse,
        '/v3/direction/bicycling': _drivingResponse,
        '/v3/direction/transit/integrated': _drivingResponse,
      });
      final t = buildGeoTool(_MockSensor(), walkingHttp);
      await t.call('geo_route', {
        'from': {'lat': 39.9, 'lng': 116.4},
        'to': {'lat': 39.91, 'lng': 116.4},
        'mode': 'walking',
      });
      expect(walkingHttp.calls.last.path, '/v3/direction/walking');
      await t.call('geo_route', {
        'from': {'lat': 39.9, 'lng': 116.4},
        'to': {'lat': 39.91, 'lng': 116.4},
        'mode': 'bicycling',
      });
      expect(walkingHttp.calls.last.path, '/v3/direction/bicycling');
      await t.call('geo_route', {
        'from': {'lat': 39.9, 'lng': 116.4},
        'to': {'lat': 39.91, 'lng': 116.4},
        'mode': 'transit',
        'city': '北京',
      });
      expect(walkingHttp.calls.last.path, '/v3/direction/transit/integrated');
      expect(walkingHttp.calls.last.query['city'], '北京');
    });

    test('transit 缺 city → MISSING_ARGUMENT（给出自愈指引）', () async {
      final err = _errorOf(await tool.call('geo_route', {
        'from': {'lat': 39.9, 'lng': 116.4},
        'to': {'lat': 39.91, 'lng': 116.4},
        'mode': 'transit',
      }));
      expect(err['code'] as String, contains('MISSING_ARGUMENT'));
      expect(err['message'] as String, contains('geo_reverse'));
    });

    test('非法 mode → INVALID_ARGUMENT', () async {
      final err = _errorOf(await tool.call('geo_route', {
        'from': {'lat': 39.9, 'lng': 116.4},
        'to': {'lat': 39.91, 'lng': 116.4},
        'mode': 'teleport',
      }));
      expect(err['code'] as String, contains('INVALID_ARGUMENT'));
    });
  });

  group('geo_static_map', () {
    test('产出 HTTPS 静态图 URL（真 Render 免 SDK）', () async {
      final j = await run('geo_static_map', {
        'center': {'lat': 39.9042, 'lng': 116.4074},
        'zoom': 12,
        'size': '750*400',
      });
      expect(j['success'], isTrue);
      final url = j['url'] as String;
      expect(url, startsWith('https://restapi.amap.com/v3/staticmap?'));
      expect(Uri.parse(url).queryParameters['key'], 'TESTKEY');
      expect(Uri.parse(url).queryParameters['zoom'], '12');
      expect(Uri.parse(url).queryParameters['size'], '750*400');
    });

    test('markers / paths 编码进 URL，且路径自动 RDP 抽稀', () async {
      final longPath = List.generate(
          300, (i) => {'lat': 39.9 + i * 0.0001, 'lng': 116.4 + i * 0.0001});
      final j = await run('geo_static_map', {
        'markers': [
          {'lat': 39.9042, 'lng': 116.4074, 'label': 'A'}
        ],
        'paths': [
          {'points': longPath, 'weight': 4}
        ],
        'autoFit': true,
      });
      final uri = Uri.parse(j['url'] as String);
      expect(uri.queryParameters['markers'], contains('A'));
      expect(uri.queryParameters['paths'], contains(';'));
      // 抽稀后 URL 远低于触发 414 的 2048 上限
      expect((j['url'] as String).length, lessThan(2048));
      expect(int.parse(uri.queryParameters['zoom']!), inInclusiveRange(3, 17));
    });

    test('未配 Web Key → ERR_AMAP_KEY_MISSING', () async {
      final noKey = buildGeoTool(_MockSensor(), http);
      final err = _errorOf(await noKey.call('geo_static_map', {}));
      expect(err['code'] as String, contains('ERR_AMAP_KEY_MISSING'));
    });

    test('secret 触发数字签名（防 INVALID_USER_SCODE）', () async {
      final signed = buildGeoTool(
        _MockSensor(),
        http,
        webKeyReader: () async => 'TESTKEY',
        secretReader: () async => 'SECRET',
      );
      final j = _parse(await signed.call('geo_static_map', {
        'center': {'lat': 39.9042, 'lng': 116.4074},
      }));
      final sig = Uri.parse(j['url'] as String).queryParameters['sig']!;
      expect(sig, matches(RegExp(r'^[0-9a-f]{32}$')));
    });
  });

  group('派发门禁与错误口径', () {
    test('未知 action → UNKNOWN_ACTION（[geo.<action>: 前缀文本）', () async {
      final r = await tool.call('nope', {});
      expect(r.isError, isTrue);
      final text = r.content.first['text'] as String;
      expect(text, startsWith('[geo.nope:'));
      expect(text, contains('UNKNOWN_ACTION'));
    });

    test('错误码统一带 geo.action: 前缀，isError 与 success 同源派生', () async {
      final r = await tool.call('geo_geocode', {});
      expect(r.isError, isTrue);
      expect(r.success, isFalse);
      expect(_errorOf(r)['code'], startsWith('geo.geo_geocode:'));
      expect(r.toMcpResult()['isError'], isTrue);
    });
  });
}
