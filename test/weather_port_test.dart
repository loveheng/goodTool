// 天气 UI 适配层（weather_port）单测：类型化映射 + 失败信封 + 入参校验。
//
// 覆盖红线：UI 拿**类型化对象**（不碰 MCP 文本信封，R2）；Key 缺失等失败
// 走结构化信封（带机器码），不静默 null；days / lat-lng 校验与工具面同口径。
import 'package:flutter_test/flutter_test.dart';
import 'package:good_template/mcp/weather_provider.dart';
import 'package:good_template/ui_ports/weather_port.dart';

class _FakeProvider implements WeatherProvider {
  _FakeProvider(this.result);

  final WeatherResult result;
  int callCount = 0;
  Map<String, Object?>? lastArgs;

  @override
  Future<WeatherResult> forecast({
    String? city,
    double? lat,
    double? lng,
    int days = 3,
  }) async {
    callCount++;
    lastArgs = <String, Object?>{
      'city': city,
      'lat': lat,
      'lng': lng,
      'days': days,
    };
    return result;
  }
}

void main() {
  group('WeatherPort · 成功信封类型化映射', () {
    test('now / 逐日 / 预警 → 类型化视图（和风原文字段保真）', () async {
      final provider = _FakeProvider(WeatherResult.success(
        city: '北京市 朝阳区',
        locationId: '101010100',
        updateTime: '2026-10-20T08:00+08:00',
        now: const <String, Object?>{
          'text': '晴',
          'temp': '12',
          'feelsLike': '10',
          'humidity': '45',
          'windDir': '北风',
          'windScale': '3',
        },
        forecast: const <Map<String, Object?>>[
          <String, Object?>{
            'fxDate': '2026-10-20',
            'textDay': '晴',
            'tempMax': '18',
            'tempMin': '8',
            'humidity': '40',
            'windDirDay': '北风',
            'windScaleDay': '3',
            'precip': '0.0',
          },
          <String, Object?>{
            'fxDate': '2026-10-21',
            'textDay': '多云',
            'tempMax': '16',
            'tempMin': '9',
          },
        ],
        alerts: const <Map<String, Object?>>[
          <String, Object?>{
            'title': '大风蓝色预警',
            'severity': '蓝色',
            'text': '阵风 7 级',
          },
        ],
      ));
      final port = WeatherPort(provider);
      final v = await port.forecast(city: '北京', days: 3);

      expect(v.ok, isTrue);
      expect(v.city, '北京市 朝阳区');
      expect(v.updateTime, '2026-10-20T08:00+08:00');
      expect(v.now!.text, '晴');
      expect(v.now!.temp, '12');
      expect(v.now!.feelsLike, '10');
      expect(v.days, hasLength(2));
      expect(v.days.first.date, '2026-10-20');
      expect(v.days.first.tempRange, '8 ~ 18℃');
      expect(v.days.last.tempRange, '9 ~ 16℃');
      expect(v.days.first.precip, '0.0');
      expect(v.alerts, hasLength(1));
      expect(v.alerts.first.title, '大风蓝色预警');
      expect(v.alerts.first.severity, '蓝色');
      // 参数透传：city 原样、days 缺省 3。
      expect(provider.lastArgs!['city'], '北京');
      expect(provider.lastArgs!['days'], 3);
    });

    test('空城市名 = 不传（交由 Provider 回退链处理）', () async {
      final provider = _FakeProvider(const WeatherResult.success());
      await WeatherPort(provider).forecast(city: '   ');
      expect(provider.lastArgs!['city'], isNull);
    });

    test('缓存回放标记透传（isCached）', () async {
      final provider = _FakeProvider(
        const WeatherResult.success(city: '郑州市', isCached: true),
      );
      final v = await WeatherPort(provider).forecast(city: '郑州');
      expect(v.ok, isTrue);
      expect(v.isCached, isTrue);
    });
  });

  group('WeatherPort · 失败信封（fail-closed，不静默 null）', () {
    test('Key 缺失 → ERR_WEATHER_KEY_MISSING 带建议', () async {
      final provider = _FakeProvider(const WeatherResult.failure(WeatherError(
        WeatherErr.keyMissing,
        '和风天气 API Key 未配置',
        suggestion: '请在 App 设置页填入 QWeather API Key',
      )));
      final v = await WeatherPort(provider).forecast(city: '北京');
      expect(v.ok, isFalse);
      expect(v.errorCode, WeatherErr.keyMissing);
      expect(v.suggestion, contains('设置页'));
      expect(v.days, isEmpty);
      expect(v.alerts, isEmpty);
    });

    test('未知错误码兜底为 ERR_WEATHER_UNKNOWN（不透传 null）', () async {
      final provider = _FakeProvider(const WeatherResult.failure(null));
      final v = await WeatherPort(provider).forecast(city: 'x');
      expect(v.ok, isFalse);
      expect(v.errorCode, 'ERR_WEATHER_UNKNOWN');
    });
  });

  group('WeatherPort · 入参校验（与 weather_forecast 同口径）', () {
    test('days 越界 → INVALID_ARGUMENT（不打到 Provider）', () async {
      final provider = _FakeProvider(const WeatherResult.success());
      final port = WeatherPort(provider);
      for (final d in <int>[0, 8, -1]) {
        final v = await port.forecast(days: d);
        expect(v.ok, isFalse, reason: 'days=$d 应被拒');
        expect(v.errorCode, 'INVALID_ARGUMENT');
      }
      expect(provider.callCount, 0);
    });

    test('lat/lng 只给一个 → MISSING_ARGUMENT（不猜另一半）', () async {
      final provider = _FakeProvider(const WeatherResult.success());
      final v = await WeatherPort(provider).forecast(lat: 39.9);
      expect(v.ok, isFalse);
      expect(v.errorCode, 'MISSING_ARGUMENT');
      expect(provider.callCount, 0);
    });

    test('lat/lng 成对 → 透传 Provider', () async {
      final provider = _FakeProvider(const WeatherResult.success());
      final v = await WeatherPort(provider).forecast(lat: 39.9, lng: 116.4);
      expect(v.ok, isTrue);
      expect(provider.lastArgs!['lat'], 39.9);
      expect(provider.lastArgs!['lng'], 116.4);
    });
  });
}
