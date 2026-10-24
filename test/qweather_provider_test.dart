// S5c 和风真实源测试：起本地 HttpServer 走通**真实请求链路**（非 Mock HttpClient），
// 逐条断言 product/weather.md 的硬性约束：两阶段查询、五级回退链、200 内业务码拦截、
// unit=m、lng,lat 顺序、预警弱依赖、TTL 缓存、429 频控回退。
//
// 仅单测注入 host/port/scheme/clock（生产恒 HTTPS + KV 配置），故本文件允许
// `dart:io`；实现住 service 层，内核与 tools 层仍零 dart:io（arch-guard R4）。
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:goodtools/mcp/geo_provider.dart';
import 'package:goodtools/mcp/weather_provider.dart';
import 'package:goodtools/ports.dart';
import 'package:goodtools/service/weather.dart';

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

  /// 请求到达记录（path, 时刻）——护栏②串行化断言的数据源。
  final List<(String, DateTime)> arrivals = <(String, DateTime)>[];

  /// 强制返回的错误体（配合 [forcedStatus] 造和风真实错误文案）。
  Map<String, Object?>? forcedErrorBody;

  /// 强制返回的 200 响应体（造「HTTP 200 但体内是错误」的形态）。
  Map<String, Object?>? forcedOkBody;

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
    forcedErrorBody = null;
    forcedOkBody = null;
    arrivals.clear();

    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((HttpRequest req) {
      seen.add(req.uri);
      arrivals.add((req.uri.path, DateTime.now()));
      final p = req.uri.path;
      void send(int status, Object body) {
        req.response
          ..statusCode = status
          ..write(jsonEncode(body))
          ..close();
      }

      if (forcedStatus != null) {
        send(forcedStatus!, forcedErrorBody ?? const <String, Object?>{});
        return;
      }
      switch (p) {
        case '/geo/v2/city/lookup':
        case '/v2/city/lookup':
          lookupCount++;
          final q = req.uri.queryParameters['location'];
          // '未知之城' 与海域坐标（-160.00,0.00）都查无此城。
          send(
              200,
              (q == '未知之城' || q == '-160.00,0.00')
                  ? _emptyLookupBody
                  : _lookupBody);
          return;
        case '/v7/weather/now':
          nowCount++;
          if (forcedOkBody != null) {
            send(200, forcedOkBody!);
            return;
          }
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
        case '/v7/air/now':
        case '/v7/indices/1d':
        case '/v7/indices/3d':
        case '/v7/astronomy/solar':
        case '/v7/minutely/5m':
          send(200, forcedBodyCode == null ? _projectionBody(p) : _codeBody(forcedBodyCode!));
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
    Duration pacing = Duration.zero,
    Duration rateLimitCooldown = qweatherRateLimitCooldown,
  }) =>
      QWeatherProvider(
        kv,
        sensor: sensor,
        apiHost: server.address.host,
        port: server.port,
        scheme: 'http',
        ttl: ttl,
        pacing: pacing,
        rateLimitCooldown: rateLimitCooldown,
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

    test('未配置 Host → ERR_WEATHER_HOST_MISSING（2024 起公共域名停用）', () async {
      // 不注入 apiHost override、KV 也未设 qweather_host；坐标模式跳过 GeoAPI，
      // 直达天气端点时 _apiHost() 应给出明确的 Host 缺失错误而非误导性 403。
      final r = await QWeatherProvider(kv).forecast(lat: 39.9042, lng: 116.4074);
      expect(r.success, isFalse);
      expect(r.error?.code, WeatherErr.hostMissing);
      expect(r.error?.suggestion, contains('qweatherapi'));
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

  group('Host 配置与错误体真因（2024 起公共域名停用）', () {
    test('Host 归一化：去协议/尾部斜杠/路径段，统一小写', () {
      expect(normalizeQweatherHost('https://ACCT.re.qweatherapi.com/'),
          'acct.re.qweatherapi.com');
      expect(normalizeQweatherHost('  acct.re.qweatherapi.com  '),
          'acct.re.qweatherapi.com');
      expect(normalizeQweatherHost('http://acct.re.qweatherapi.com/v7'),
          'acct.re.qweatherapi.com');
      expect(normalizeQweatherHost(''), '');
    });

    test('KV 里的 Host 带协议/斜杠也能正常出网（归一化后 URI 不畸形）', () async {
      await kv.settingsSet({kQweatherHost: 'https://${server.address.host}/'});
      final p = QWeatherProvider(kv, port: server.port, scheme: 'http');
      final r = await p.forecast(city: '朝阳');
      expect(r.success, isTrue,
          reason: '${r.error?.code} / ${r.error?.message}');
      // 请求确实落到本地服务器（URI 未畸形）且走账号 Host 口径路径。
      expect(seen.any((u) => u.path == '/geo/v2/city/lookup'), isTrue);
      expect(seen.any((u) => u.path == '/v7/weather/now'), isTrue);
    });

    test('账号专属 Host：GeoAPI 与天气走同一 Host（GeoAPI 带 /geo 前缀）', () async {
      await kv.settingsSet({kQweatherHost: server.address.host});
      final p = QWeatherProvider(kv, port: server.port, scheme: 'http');
      final r = await p.forecast(city: '朝阳');
      expect(r.success, isTrue);
      expect(seen.any((u) => u.path == '/geo/v2/city/lookup'), isTrue);
      expect(seen.any((u) => u.path == '/v7/weather/now'), isTrue);
    });

    test('未配置 Host 时城市解析不再打公共 GeoAPI → ERR_WEATHER_HOST_MISSING', () async {
      final r = await QWeatherProvider(kv).forecast(city: '朝阳');
      expect(r.error?.code, WeatherErr.hostMissing);
      expect(seen, isEmpty); // 公共域名已失效，不做无谓往返
    });

    test('403 Invalid Host → ERR_WEATHER_HOST_INVALID（错误体透传真因）', () async {
      forcedStatus = 403;
      forcedErrorBody = const <String, Object?>{
        'error': {
          'status': 403,
          'type': 'https://dev.qweather.com/docs/resource/error-code/#invalid-host',
          'title': 'Invalid Host',
          'detail': 'An invalid or unauthorized API Host.',
        },
      };
      final r = await provider().forecast(city: '朝阳');
      expect(r.error?.code, WeatherErr.hostInvalid);
      expect(r.error?.message, contains('Invalid Host'));
      expect(r.error?.suggestion, contains('qweatherapi'));
    });

    test('403 Security Restriction → 安全限制文案（区别于鉴权失败）', () async {
      forcedStatus = 403;
      forcedErrorBody = const <String, Object?>{
        'error': {
          'status': 403,
          'type':
              'https://dev.qweather.com/docs/resource/error-code/#security-restriction',
          'title': 'Security Restriction',
          'detail': 'Request is denied by security restriction settings.',
        },
      };
      final r = await provider().forecast(city: '朝阳');
      expect(r.error?.code, WeatherErr.unauthorized);
      expect(r.error?.message, contains('安全限制'));
      expect(r.error?.message, isNot(contains('鉴权失败')));
      expect(r.error?.suggestion, contains('控制台'));
    });

    test('404「服务不可访问」→ ERR_WEATHER_HOST_INVALID', () async {
      forcedStatus = 404;
      forcedErrorBody = const <String, Object?>{
        'error': {
          'status': 404,
          'title': 'Not Found',
          'detail': '服务不可访问',
        },
      };
      final r = await provider().forecast(city: '朝阳');
      expect(r.error?.code, WeatherErr.hostInvalid);
      expect(r.error?.message, contains('服务不可访问'));
    });

    test('HTTP 200 + JSON:API 错误体 → 不返回「成功但 now 为空」', () async {
      forcedOkBody = const <String, Object?>{
        'error': {
          'status': 403,
          'title': 'Invalid Host',
          'detail': 'An invalid or unauthorized API Host.',
        },
      };
      final r = await provider().forecast(city: '朝阳');
      expect(r.success, isFalse);
      expect(r.error?.code, WeatherErr.hostInvalid);
      expect(r.now, isNull);
    });
  });

  group('城市搜索（UI 搜索条）', () {
    test('多候选类型化：行政链折叠 + lat/lon/locationId', () async {
      final r = await provider().searchCity('朝阳');
      expect(r.success, isTrue);
      expect(r.options, hasLength(1));
      final o = r.options.single;
      expect(o.name, '北京市 朝阳区'); // 相邻重复段折叠
      expect(o.lat, closeTo(39.92, 1e-6));
      expect(o.lng, closeTo(116.43, 1e-6));
      expect(o.locationId, '101010100');
    });

    test('查无此城 → 成功但空列表（非错误）', () async {
      final r = await provider().searchCity('未知之城');
      expect(r.success, isTrue);
      expect(r.options, isEmpty);
    });

    test('空查询不打网络', () async {
      final r = await provider().searchCity('  ');
      expect(r.success, isTrue);
      expect(r.options, isEmpty);
      expect(seen, isEmpty);
    });

    test('未配 Key → ERR_WEATHER_KEY_MISSING（不静默空列表）', () async {
      await kv.settingsSet({kQweatherKey: ''});
      final r = await provider().searchCity('北京');
      expect(r.success, isFalse);
      expect(r.error?.code, WeatherErr.keyMissing);
    });

    test('GeoAPI 403 Invalid Host → ERR_WEATHER_HOST_INVALID', () async {
      forcedStatus = 403;
      forcedErrorBody = const <String, Object?>{
        'error': {
          'status': 403,
          'title': 'Invalid Host',
          'detail': 'An invalid or unauthorized API Host.',
        },
      };
      final r = await provider().searchCity('北京');
      expect(r.success, isFalse);
      expect(r.error?.code, WeatherErr.hostInvalid);
    });
  });

  group('坐标反查城市（地图选点加城市）', () {
    test('坐标 → location=lng,lat（经度在前、两位小数）→ 类型化候选', () async {
      final r = await provider()
          .lookupCityByCoords(lat: 39.921534, lng: 116.434527);
      expect(r.success, isTrue);
      expect(r.options, hasLength(1));
      final o = r.options.single;
      expect(o.name, '北京市 朝阳区');
      expect(o.locationId, '101010100');
      // 和风规范：经度在前、纬度在后，两位小数（与天气查询同口径）。
      expect(seen.single.queryParameters['location'], '116.43,39.92');
      expect(seen.single.path, '/geo/v2/city/lookup');
    });

    test('海域/无人区查无 → 成功但空列表（非错误）', () async {
      // 桩按 location 参数区分：坐标查到空列表（searchCity 的 '未知之城' 仍返回候选）。
      final r = await provider().lookupCityByCoords(lat: 0, lng: -160);
      expect(r.success, isTrue);
      expect(r.options, isEmpty);
    });

    test('未配 Key → ERR_WEATHER_KEY_MISSING（不静默空列表）', () async {
      await kv.settingsSet({kQweatherKey: ''});
      final r =
          await provider().lookupCityByCoords(lat: 39.92, lng: 116.43);
      expect(r.success, isFalse);
      expect(r.error?.code, WeatherErr.keyMissing);
    });

    test('GeoAPI 403 Invalid Host → ERR_WEATHER_HOST_INVALID', () async {
      forcedStatus = 403;
      forcedErrorBody = const <String, Object?>{
        'error': {
          'status': 403,
          'title': 'Invalid Host',
          'detail': 'An invalid or unauthorized API Host.',
        },
      };
      final r =
          await provider().lookupCityByCoords(lat: 39.92, lng: 116.43);
      expect(r.success, isFalse);
      expect(r.error?.code, WeatherErr.hostInvalid);
    });
  });

  group('配额护栏（singleflight / 串行节流 / 429 冷却）', () {
    test('护栏① 同 key 并发合并：并发两查同一坐标只出一次网', () async {
      final p = provider();
      final r = await Future.wait(<Future<WeatherResult>>[
        p.forecast(lat: 39.92, lng: 116.43),
        p.forecast(lat: 39.92, lng: 116.43),
      ]);
      expect(r[0].success, isTrue);
      expect(r[1].success, isTrue);
      // 共享在途取数：第二个等待者拿同一份结果，非缓存回放。
      expect(r[1].isCached, isFalse);
      expect(nowCount, 1);
      expect(dailyCount, 1);
    });

    test('护栏② 不同 key 串行出网：无并发重叠，pacing 间隔生效', () async {
      final p = provider(pacing: const Duration(milliseconds: 200));
      final sw = Stopwatch()..start();
      await Future.wait(<Future<WeatherResult>>[
        p.forecast(lat: 39.92, lng: 116.43),
        p.forecast(lat: 31.23, lng: 121.47),
      ]);
      sw.stop();
      // 串行化：第二个取数的首个 now 请求不早于第一个取数的 warning 收尾
      // （并发实现会在第一个取数中途插入请求）。
      final warningAt =
          arrivals.firstWhere((a) => a.$1 == '/v7/warning/now').$2;
      final nowAt =
          arrivals.where((a) => a.$1 == '/v7/weather/now').toList()[1].$2;
      expect(nowAt.isAfter(warningAt), isTrue);
      // pacing 200ms：回环取数仅数 ms，总耗时由 pacing 间隔主导（不早触发）。
      expect(sw.elapsedMilliseconds, greaterThanOrEqualTo(190));
    });

    test('护栏③ 429 冷却：冷却期内零出网（有缓存回放/无缓存带冷却指引），期满恢复', () async {
      final p = provider();
      final r1 = await p.forecast(lat: 39.92, lng: 116.43);
      expect(r1.success, isTrue);
      forcedStatus = 429;
      // 无缓存城市：429 → 开启冷却窗，带码失败。
      final r2 = await p.forecast(lat: 31.23, lng: 121.47);
      expect(r2.success, isFalse);
      expect(r2.error?.code, WeatherErr.rateLimited);
      final seenAtCooldown = seen.length;
      // 已缓存城市：冷却期内回放缓存（标 isCached），零出网。
      final r3 = await p.forecast(lat: 39.92, lng: 116.43);
      expect(r3.success, isTrue);
      expect(r3.isCached, isTrue);
      expect(seen.length, seenAtCooldown);
      // 无缓存城市：冷却期内仍失败，指引带冷却语义，依旧零出网。
      final r4 = await p.forecast(lat: 31.23, lng: 121.47);
      expect(r4.success, isFalse);
      expect(r4.error?.suggestion, contains('冷却'));
      expect(seen.length, seenAtCooldown);
      // 冷却期满（推进注入时钟）→ 恢复出网（仍 429，再次进入冷却）。
      clockNow = clockNow.add(const Duration(seconds: 61));
      final r5 = await p.forecast(lat: 31.23, lng: 121.47);
      expect(r5.success, isFalse);
      expect(seen.length, greaterThan(seenAtCooldown));
    });
  });

  group('域深化四件（air / indices / astronomy / minutely）', () {
    test('air：airNow 投影 + 独立缓存键位（不与预报互串）', () async {
      final p = provider();
      final r = await p.air(lat: 39.92, lng: 116.43);
      expect(r.success, isTrue);
      expect(r.now?['aqi'], '55');
      expect(r.now?['category'], '良');
      expect(seen.single.path, '/v7/air/now');
      // 键位隔离：随后同坐标 forecast 不吃 air 缓存，仍发真实请求。
      final f = await p.forecast(lat: 39.92, lng: 116.43);
      expect(f.success, isTrue);
      expect(nowCount, 1);
    });

    test('indices：days=3 走 3d 端点 + type 透传 + 列表投影', () async {
      final r = await provider()
          .indices(lat: 39.92, lng: 116.43, days: 3, type: '1,3');
      expect(r.success, isTrue);
      expect(r.forecast, hasLength(1));
      expect(r.forecast.single['name'], '穿衣指数');
      expect(r.now, isNull);
      final uri = seen.single;
      expect(uri.path, '/v7/indices/3d');
      expect(uri.queryParameters['type'], '1,3');
      expect(uri.queryParameters['unit'], 'm');
    });

    test('astronomy：缺省注入设备今日 date + solar 投影', () async {
      final r = await provider().astronomy(lat: 39.92, lng: 116.43);
      expect(r.success, isTrue);
      expect(r.now?['sunrise'], '06:15');
      expect(seen.single.path, '/v7/astronomy/solar');
      expect(seen.single.queryParameters['date'],
          matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')));
    });

    test('minutely：summary 进 now.summary，序列进 forecast', () async {
      final r = await provider().minutely(lat: 39.92, lng: 116.43);
      expect(r.success, isTrue);
      expect(r.now?['summary'], '未来两小时不会下雨');
      expect(r.forecast, hasLength(1));
      expect(r.forecast.single['precip'], '0.0');
      expect(seen.single.path, '/v7/minutely/5m');
    });

    test('未配 Key → ERR_WEATHER_KEY_MISSING（不静默空）', () async {
      await kv.settingsSet({kQweatherKey: ''});
      final r = await provider().air(lat: 39.92, lng: 116.43);
      expect(r.success, isFalse);
      expect(r.error?.code, WeatherErr.keyMissing);
    });

    test('共享护栏：429 冷却对四件同样生效（冷却期内零出网）', () async {
      final p = provider();
      final ok = await p.air(lat: 39.92, lng: 116.43);
      expect(ok.success, isTrue);
      forcedStatus = 429;
      final other = await p.minutely(lat: 31.23, lng: 121.47);
      expect(other.success, isFalse);
      final seenAt = seen.length;
      final cached = await p.air(lat: 39.92, lng: 116.43);
      expect(cached.success, isTrue);
      expect(cached.isCached, isTrue);
      expect(seen.length, seenAt);
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

/// 域深化四件的按端点响应体（服务桩）。
Map<String, Object?> _projectionBody(String path) => switch (path) {
      '/v7/air/now' => _airBody,
      '/v7/indices/1d' || '/v7/indices/3d' => _indicesBody,
      '/v7/astronomy/solar' => _solarBody,
      '/v7/minutely/5m' => _minutelyBody,
      _ => _airBody,
    };

const Map<String, Object?> _airBody = <String, Object?>{
  'code': '200',
  'updateTime': '2026-10-20T12:00+08:00',
  'airNow': {
    'aqi': '55',
    'category': '良',
    'primary': 'PM10',
    'pm10': '60',
    'pm2p5': '35',
  },
};

const Map<String, Object?> _indicesBody = <String, Object?>{
  'code': '200',
  'updateTime': '2026-10-20T12:00+08:00',
  'daily': [
    {
      'date': '2026-10-20',
      'type': '3',
      'name': '穿衣指数',
      'level': '5',
      'category': '较冷',
      'text': '建议着厚外套',
    },
  ],
};

const Map<String, Object?> _solarBody = <String, Object?>{
  'code': '200',
  'updateTime': '2026-10-20T12:00+08:00',
  'solar': {'sunrise': '06:15', 'sunset': '17:35'},
};

const Map<String, Object?> _minutelyBody = <String, Object?>{
  'code': '200',
  'updateTime': '2026-10-20T12:00+08:00',
  'summary': '未来两小时不会下雨',
  'minutely': [
    {'fxTime': '2026-10-20T12:05+08:00', 'precip': '0.0'},
  ],
};

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
      'lat': '39.92000',
      'lon': '116.43000',
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
