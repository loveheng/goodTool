// S5c 和风真实源测试：起本地 HttpServer 走通**真实请求链路**（非 Mock HttpClient），
// 逐条断言 product/weather.md 的硬性约束：两阶段查询、五级回退链、200 内业务码拦截、
// unit=m、lng,lat 顺序、预警弱依赖、TTL 缓存、429 频控回退。
//
// 仅单测注入 host/port/scheme/clock（生产恒 HTTPS + KV 配置），故本文件允许
// `dart:io`；实现住 service 层，内核与 tools 层仍零 dart:io（arch-guard R4）。
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:good_template/mcp/geo_provider.dart';
import 'package:good_template/mcp/weather_provider.dart';
import 'package:good_template/ports.dart';
import 'package:good_template/service/weather.dart';

void main() {
  late HttpServer server;
  late InMemoryKv kv;
  late List<Uri> seen;
  late DateTime clockNow;

  // 可控故障注入
  String? forcedBodyCode;
  int? forcedStatus;
  bool warningBroken = false;
  int lookupCount = 0;
  int nowCount = 0;
  int dailyCount = 0;

  setUp(() async {
    kv = InMemoryKv();
    await kv.settingsSet({kQweatherKey: 'TESTKEY'});
    seen = <Uri>[];
    clockNow = DateTime(2026, 10, 20, 12);
    forcedBodyCode = null;
    forcedStatus = null;
    warningBroken = false;
    lookupCount = 0;
    nowCount = 0;
    dailyCount = 0;

    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((HttpRequest req) {
      seen.add(req.uri);
      final p = req.uri.path;
      void send(int status, Object body) {
        req.response
          ..statusCode = status
          ..write(jsonEncode(body))
          ..close();
      }

      if (forcedStatus != null) {
        send(forcedStatus!, const <String, Object?>{});
        return;
      }
      switch (p) {
        case '/v2/city/lookup':
          lookupCount++;
          final q = req.uri.queryParameters['location'];
          send(200, q == '未知之城' ? _emptyLookupBody : _lookupBody);
          return;
        case '/v7/weather/now':
          nowCount++;
          send(200, forcedBodyCode == null ? _nowBody : _codeBody(forcedBodyCode!));
          return;
        case '/v7/weather/3d':
        case '/v7/weather/7d':
          dailyCount++;
          send(200, forcedBodyCode == null ? _dailyBody : _codeBody(forcedBodyCode!));
          return;
        case '/v7/warning/now':
          if (warningBroken) {
            send(500, const <String, Object?>{'code': '500'});
            return;
          }
          send(200, _warningBody);
          return;
        default:
          send(404, _codeBody('404'));
          return;
      }
    });
  });

  tearDown(() async {
    await server.close(force: true);
  });

  QWeatherProvider provider({
    LocationSensorProvider? sensor,
    Duration ttl = const Duration(minutes: 30),
  }) =>
      QWeatherProvider(
        kv,
        sensor: sensor,
        geoHost: server.address.host,
        apiHost: server.address.host,
        port: server.port,
        scheme: 'http',
        ttl: ttl,
        clock: () => clockNow,
      );

  group('两阶段查询与出参', () {
    test('城市名 → GeoAPI 换 LocationID → 出参用完整行政链', () async {
      final r = await provider().forecast(city: '朝阳');
      expect(r.success, isTrue);
      expect(r.locationId, '101010100');
      expect(r.city, '北京市 朝阳区'); // 非用户输入原词，消重名歧义
      expect((r.now?['temp']), '18');
      expect(r.forecast.length, 1);
      expect(r.alerts.length, 1);
      expect(r.isCached, isFalse);
      expect(lookupCount, 1);
    });

    test('同名城市第二次命中映射缓存（免 GeoAPI 往返）', () async {
      final p = provider();
      await p.forecast(city: '朝阳');
      await p.forecast(city: '朝阳');
      expect(lookupCount, 1);
      expect(nowCount, 1); // 第二次走天气 TTL 缓存，连数据端点也不打
    });

    test('所有天气请求显式带 unit=m（公制）', () async {
      await provider().forecast(city: '朝阳');
      for (final u in seen.where((u) => u.path.startsWith('/v7/'))) {
        expect(u.queryParameters['unit'], 'm');
        expect(u.queryParameters['key'], 'TESTKEY');
      }
    });

    test('days>3 走 7d 端点', () async {
      await provider().forecast(city: '朝阳', days: 7);
      expect(seen.any((u) => u.path == '/v7/weather/7d'), isTrue);
    });
  });

  group('坐标与回退链（weather.md 五级）', () {
    test('显式经纬度：拼接为**经度在前**且保留两位小数', () async {
      final r = await provider().forecast(lat: 39.9042, lng: 116.4074);
      expect(r.success, isTrue);
      final loc =
          seen.firstWhere((u) => u.path == '/v7/weather/now').queryParameters['location'];
      expect(loc, '116.41,39.90');
      expect(lookupCount, 0); // 坐标模式跳过 GeoAPI
    });

    test('无入参 → 回退到设置项 weather_location', () async {
      await kv.settingsSet({kWeatherLocation: '朝阳'});
      final r = await provider().forecast();
      expect(r.success, isTrue);
      expect(r.city, '北京市 朝阳区');
      expect(lookupCount, 1);
    });

    test('设置项为空 → 回退到设备定位', () async {
      final r = await provider(sensor: _SensorStub()).forecast();
      expect(r.success, isTrue);
      final loc =
          seen.firstWhere((u) => u.path == '/v7/weather/now').queryParameters['location'];
      expect(loc, '116.41,39.90');
    });

    test('五级皆空 → ERR_LOCATION_UNAVAILABLE（不再静默 null）', () async {
      final r = await provider(sensor: const NullLocationSensorProvider()).forecast();
      expect(r.success, isFalse);
      expect(r.error?.code, WeatherErr.locationUnavailable);
      expect(r.error?.suggestion, isNotNull);
      expect(seen, isEmpty); // 位置都解不出，不该打任何网络请求
    });
  });

  group('错误模型（HTTP 200 内仍有业务失败）', () {
    test('Key 缺失 → ERR_WEATHER_KEY_MISSING 且零请求', () async {
      await kv.settingsSet({kQweatherKey: ''});
      final r = await provider().forecast(city: '朝阳');
      expect(r.error?.code, WeatherErr.keyMissing);
      expect(seen, isEmpty);
    });

    test('Body code 401 → ERR_WEATHER_UNAUTHORIZED（HTTP 仍是 200）', () async {
      forcedBodyCode = '401';
      final r = await provider().forecast(city: '朝阳');
      expect(r.error?.code, WeatherErr.unauthorized);
      expect(r.error?.suggestion, contains('Host'));
    });

    test('Body code 404 → ERR_CITY_NOT_FOUND', () async {
      forcedBodyCode = '404';
      final r = await provider().forecast(city: '火星');
      expect(r.error?.code, WeatherErr.cityNotFound);
    });

    test('HTTP 429 → ERR_RATE_LIMITED（无缓存时）', () async {
      forcedStatus = 429;
      final r = await provider().forecast(city: '朝阳');
      expect(r.error?.code, WeatherErr.rateLimited);
    });

    test('GeoAPI 查无此城（location 空列表）→ ERR_CITY_NOT_FOUND', () async {
      final r = await provider().forecast(city: '未知之城');
      expect(r.success, isFalse);
      expect(r.error?.code, WeatherErr.cityNotFound);
      expect(r.error?.suggestion, contains('经纬度'));
    });
  });

  group('缓存与频控自愈', () {
    test('TTL 内命中缓存：不再发起请求且标 isCached', () async {
      final p = provider();
      final first = await p.forecast(city: '朝阳');
      expect(first.isCached, isFalse);
      final second = await p.forecast(city: '朝阳');
      expect(second.isCached, isTrue);
      expect(nowCount, 1);
    });

    test('TTL 过期后重新取数', () async {
      final p = provider();
      await p.forecast(city: '朝阳');
      clockNow = clockNow.add(const Duration(minutes: 31));
      final again = await p.forecast(city: '朝阳');
      expect(again.isCached, isFalse);
      expect(nowCount, 2);
    });

    test('429 且有未过期缓存 → 自动回放并标 isCached（不报错）', () async {
      final p = provider();
      await p.forecast(city: '朝阳');
      forcedStatus = 429;
      clockNow = clockNow.add(const Duration(minutes: 10));
      final r = await p.forecast(city: '朝阳');
      expect(r.success, isTrue);
      expect(r.isCached, isTrue);
    });

    test('取数失败且有旧缓存 → 降级回放（[DEGRADE] 路径）', () async {
      final p = provider();
      await p.forecast(city: '朝阳');
      clockNow = clockNow.add(const Duration(minutes: 31)); // 缓存过期但仍在表内
      forcedBodyCode = '401';
      final r = await p.forecast(city: '朝阳');
      expect(r.success, isTrue);
      expect(r.isCached, isTrue);
    });
  });

  group('弱依赖与并发聚合', () {
    test('预警端点 500 → alerts 恒 []，主数据照常返回', () async {
      warningBroken = true;
      final r = await provider().forecast(city: '朝阳');
      expect(r.success, isTrue);
      expect(r.alerts, isEmpty);
      expect(r.now, isNotNull);
      expect(r.forecast, isNotEmpty);
    });

    test('now 与 forecast 并发拉取（共享同一 location）', () async {
      await provider().forecast(city: '朝阳');
      final nowUri = seen.firstWhere((u) => u.path == '/v7/weather/now');
      final dailyUri = seen.firstWhere((u) => u.path == '/v7/weather/3d');
      expect(nowUri.queryParameters['location'], dailyUri.queryParameters['location']);
      expect(nowCount, 1);
      expect(dailyCount, 1);
    });
  });
}

/// 定位桩：固定 WGS-84 读数（与 geo 同范式）。
class _SensorStub implements LocationSensorProvider {
  @override
  Future<LocationReading?> current() async => LocationReading(
        lat: 39.9042,
        lng: 116.4074,
        accuracy: 5,
        coordSystem: 'WGS84',
        timestamp: 0,
      );

  @override
  Future<CompassReading?> compass() async => null;
}

Map<String, Object?> _codeBody(String code) =>
    <String, Object?>{'code': code, 'message': 'forced'};

const Map<String, Object?> _lookupBody = <String, Object?>{
  'code': '200',
  'location': [
    {
      'id': '101010100',
      'name': '朝阳区',
      'adm1': '北京市',
      'adm2': '北京市',
    },
  ],
};

const Map<String, Object?> _emptyLookupBody = <String, Object?>{
  'code': '200',
  'location': <Object?>[],
};

const Map<String, Object?> _nowBody = <String, Object?>{
  'code': '200',
  'updateTime': '2026-10-20T12:00+08:00',
  'now': {
    'temp': '18',
    'text': '多云',
    'windDir': '东北风',
    'windScale': '2',
    'humidity': '45',
    'precip': '0.0',
  },
};

const Map<String, Object?> _dailyBody = <String, Object?>{
  'code': '200',
  'updateTime': '2026-10-20T12:00+08:00',
  'daily': [
    {
      'fxDate': '2026-10-20',
      'tempMin': '10',
      'tempMax': '20',
      'textDay': '晴',
      'textNight': '多云',
      'precip': '0.0',
    },
  ],
};

const Map<String, Object?> _warningBody = <String, Object?>{
  'code': '200',
  'warning': [
    {
      'id': '11000041600000_20261020',
      'title': '北京市发布雷电蓝色预警',
      'type': '雷电',
      'level': '蓝色',
      'text': '预计未来6小时内有分散性雷阵雨',
    },
  ],
};
