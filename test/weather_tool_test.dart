// S5b weather 领域网关适配层测试：Mock WeatherProvider 走通派发闭环与错误口径。
//
// 断言对齐 product/weather.md：出参双轨信封、错误恒带 code/message/suggestion、
// 预警恒为空数组（弱依赖）、days 越界与经纬度不成对一律带码返回（不静默兜底）。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:good_template/mcp/category_tool_face.dart';
import 'package:good_template/mcp/weather_provider.dart';
import 'package:good_template/tools/weather_tool.dart';

void main() {
  /// 单条 text content → 解码后的 JSON。
  Map<String, Object?> jsonOf(SubActionResult r) =>
      jsonDecode((r.content.first)['text']! as String) as Map<String, Object?>;

  Map<String, Object?> errOf(SubActionResult r) =>
      jsonOf(r)['error']! as Map<String, Object?>;

  final okNow = <String, Object?>{
    'temp': '18',
    'text': '多云',
    'windDir': '东北风',
    'windScale': '2',
    'humidity': '45',
    'precip': '0.0',
  };
  final okForecast = <Map<String, Object?>>[
    {
      'date': '2026-10-20',
      'tempMin': '10',
      'tempMax': '20',
      'textDay': '晴',
      'textNight': '多云',
      'precip': '0.0',
    },
  ];

  WeatherResult okResult({
    String city = '北京市 朝阳区',
    String locationId = '101010100',
    bool isCached = false,
  }) =>
      WeatherResult.success(
        city: city,
        locationId: locationId,
        updateTime: '2026-10-20T12:00+08:00',
        now: okNow,
        forecast: okForecast,
        alerts: const <Map<String, Object?>>[],
        isCached: isCached,
      );

  group('能力面对账', () {
    test('weather 分类恰好 1 个 action：weather_forecast', () {
      final props =
          (buildWeatherTool(const NullWeatherProvider()).toSchema()['inputSchema']
              as Map)['properties'] as Map;
      expect(((props['action'] as Map)['enum'] as List).cast<String>(),
          ['weather_forecast']);
    });

    test('描述带紧凑参数签名（消参数盲盒）', () {
      final desc =
          buildWeatherTool(const NullWeatherProvider()).toSchema()['description']
              as String;
      expect(desc, contains('weather_forecast('));
      expect(desc, contains('days?: int'));
    });
  });

  group('派发闭环', () {
    test('成功：出参为完整双轨信封（含 now/forecast/alerts/isCached）', () async {
      final cat = buildWeatherTool(_MockWeather(okResult()));
      final r = await cat.call('weather_forecast', {'city': '北京'});
      expect(r.isError, isFalse);
      final j = jsonOf(r);
      expect(j['success'], isTrue);
      expect(j['city'], '北京市 朝阳区');
      expect(j['locationId'], '101010100');
      expect(j['now'], okNow);
      expect(j['forecast'], okForecast);
      expect(j['alerts'], isEmpty); // 弱依赖：无预警恒 []
      expect(j['isCached'], isFalse);
      expect(j['days'], 3); // 缺省 3
    });

    test('days 缺省 3 / 显式 7 均原样透传给 Provider', () async {
      final calls = <int>[];
      final cat = buildWeatherTool(_MockWeather(okResult(), onCall: (p) {
        calls.add(p.days);
      }));
      await cat.call('weather_forecast', {'city': '北京'});
      await cat.call('weather_forecast', {'city': '北京', 'days': 7});
      expect(calls, [3, 7]);
    });

    test('G5 宽容解析：days 数字串等价于数值', () async {
      final calls = <int>[];
      final cat = buildWeatherTool(_MockWeather(okResult(), onCall: (p) {
        calls.add(p.days);
      }));
      final r = await cat.call('weather_forecast', {'city': '北京', 'days': '7'});
      expect(r.isError, isFalse);
      expect(calls, [7]);
    });

    test('经纬度入参透传（成对）', () async {
      double? gotLat, gotLng;
      final cat = buildWeatherTool(_MockWeather(okResult(), onCall: (p) {
        gotLat = p.lat;
        gotLng = p.lng;
      }));
      final r = await cat.call('weather_forecast', {
        'lat': 39.9042,
        'lng': 116.4074,
      });
      expect(r.isError, isFalse);
      expect(gotLat, 39.9042);
      expect(gotLng, 116.4074);
    });

    test('缓存命中：isCached 原样透出', () async {
      final cat = buildWeatherTool(_MockWeather(okResult(isCached: true)));
      final j = jsonOf(await cat.call('weather_forecast', {'city': '北京'}));
      expect(j['isCached'], isTrue);
    });

    test('出参省略空字段（city/locationId/updateTime 缺失时不吐 null）', () async {
      final cat = buildWeatherTool(_MockWeather(const WeatherResult.success()));
      final j = jsonOf(await cat.call('weather_forecast', {}));
      expect(j.containsKey('city'), isFalse);
      expect(j.containsKey('now'), isFalse);
      expect(j['forecast'], isEmpty);
      expect(j['alerts'], isEmpty);
    });
  });

  group('错误口径（永不静默 null，前缀由派发层注入）', () {
    test('未注入真实源 → ERR_WEATHER_KEY_MISSING + suggestion', () async {
      final cat = buildWeatherTool(const NullWeatherProvider());
      final r = await cat.call('weather_forecast', {'city': '北京'});
      expect(r.isError, isTrue);
      expect(errOf(r)['code'], startsWith('weather.weather_forecast:'));
      expect(errOf(r)['code'], contains('ERR_WEATHER_KEY_MISSING'));
      expect(errOf(r)['suggestion'], isNotNull);
    });

    test('城市查无 → ERR_CITY_NOT_FOUND 透传（带 suggestion）', () async {
      final cat = buildWeatherTool(_MockWeather(const WeatherResult.failure(
        WeatherError(WeatherErr.cityNotFound, '查无此城：火星',
            suggestion: '检查城市名写法，或改用经纬度查询'),
      )));
      final e = errOf(await cat.call('weather_forecast', {'city': '火星'}));
      expect(e['code'], contains('ERR_CITY_NOT_FOUND'));
      expect(e['suggestion'], contains('经纬度'));
    });

    test('回退链全空 → ERR_LOCATION_UNAVAILABLE', () async {
      final cat = buildWeatherTool(_MockWeather(const WeatherResult.failure(
        WeatherError(WeatherErr.locationUnavailable, '无法确定位置',
            suggestion: '在设置页预设城市，或授予定位权限'),
      )));
      final e = errOf(await cat.call('weather_forecast', {}));
      expect(e['code'], contains('ERR_LOCATION_UNAVAILABLE'));
    });

    test('days 越界 → INVALID_ARGUMENT（不静默兜底为 3）', () async {
      final cat = buildWeatherTool(_MockWeather(okResult()));
      for (final bad in [0, 8, -1]) {
        final e = errOf(
            await cat.call('weather_forecast', {'city': '北京', 'days': bad}));
        expect(e['code'], contains('INVALID_ARGUMENT'));
      }
    });

    test('days 非整数 → INVALID_ARGUMENT', () async {
      final cat = buildWeatherTool(_MockWeather(okResult()));
      final e = errOf(
          await cat.call('weather_forecast', {'city': '北京', 'days': '三天'}));
      expect(e['code'], contains('INVALID_ARGUMENT'));
    });

    test('lat/lng 不成对 → MISSING_ARGUMENT', () async {
      final cat = buildWeatherTool(_MockWeather(okResult()));
      final e = errOf(await cat.call('weather_forecast', {'lat': 39.9}));
      expect(e['code'], contains('MISSING_ARGUMENT'));
    });

    test('lat 非数值 → INVALID_ARGUMENT', () async {
      final cat = buildWeatherTool(_MockWeather(okResult()));
      final e = errOf(await cat.call('weather_forecast', {
        'lat': 'abc',
        'lng': 116.4,
      }));
      expect(e['code'], contains('INVALID_ARGUMENT'));
    });

    test('枚举外 action → UNKNOWN_ACTION（不幻觉执行）', () async {
      final cat = buildWeatherTool(const NullWeatherProvider());
      final r = await cat.call('weather_time_machine', {});
      expect(r.isError, isTrue);
      expect(r.content.first['text'], contains('UNKNOWN_ACTION'));
    });
  });
}

/// 调用参数快照（供断言透传是否保真）。
class _ForecastParams {
  _ForecastParams({this.city, this.lat, this.lng, required this.days});
  final String? city;
  final double? lat;
  final double? lng;
  final int days;
}

/// 天气端口桩：回放固定信封并记录入参。
class _MockWeather implements WeatherProvider {
  _MockWeather(this._result, {this.onCall});

  final WeatherResult _result;
  final void Function(_ForecastParams p)? onCall;

  @override
  Future<WeatherResult> forecast({
    String? city,
    double? lat,
    double? lng,
    int days = 3,
  }) async {
    onCall?.call(
        _ForecastParams(city: city, lat: lat, lng: lng, days: days));
    return _result;
  }
}
