library;

import '../mcp/weather_provider.dart';

/// 实时天气视图（类型化；和风 `now` 投影）。
class WeatherNowView {
  const WeatherNowView({
    required this.text,
    this.temp,
    this.feelsLike,
    this.humidity,
    this.windDir,
    this.windScale,
  });

  /// 天气现象（人话中文，和风原样）。
  final String text;

  /// 温度（原始串，遥测轨渲染；单位 ℃）。
  final String? temp;

  /// 体感温度。
  final String? feelsLike;

  /// 相对湿度（%）。
  final String? humidity;

  /// 风向。
  final String? windDir;

  /// 风力级。
  final String? windScale;
}

/// 逐日预报视图（类型化；和风 `daily` 投影）。
class WeatherDayView {
  const WeatherDayView({
    required this.date,
    required this.textDay,
    this.tempMax,
    this.tempMin,
    this.humidity,
    this.windDirDay,
    this.windScaleDay,
    this.precip,
  });

  /// 日期（`YYYY-MM-DD`）。
  final String date;

  /// 白天天气现象。
  final String textDay;

  final String? tempMax;
  final String? tempMin;
  final String? humidity;
  final String? windDirDay;
  final String? windScaleDay;

  /// 降水量（mm）。
  final String? precip;

  /// 温度区间展示串（`12 ~ 20℃`；缺段不脑补）。
  String get tempRange {
    final lo = tempMin;
    final hi = tempMax;
    if (lo == null && hi == null) return '';
    if (lo == null) return '$hi℃';
    if (hi == null) return '$lo℃';
    return '$lo ~ $hi℃';
  }
}

/// 气象预警视图（弱依赖：无预警恒空列表）。
class WeatherAlertView {
  const WeatherAlertView({required this.title, this.severity, this.description});

  final String title;

  /// 等级（和风原样，如「橙色」）。
  final String? severity;

  final String? description;
}

/// 天气查询结果视图（永不 null 的类型化信封）。
class WeatherView {
  const WeatherView({
    required this.ok,
    this.city,
    this.updateTime,
    this.now,
    this.days = const <WeatherDayView>[],
    this.alerts = const <WeatherAlertView>[],
    this.isCached = false,
    this.errorCode,
    this.message,
    this.suggestion,
  });

  final bool ok;

  /// 和风完整行政链（消重名歧义）。
  final String? city;

  /// 数据更新时间（ISO 8601 原样保真）。
  final String? updateTime;

  final WeatherNowView? now;

  final List<WeatherDayView> days;

  final List<WeatherAlertView> alerts;

  /// 是否回放缓存（TTL 命中或 429 回退）。
  final bool isCached;

  final String? errorCode;
  final String? message;
  final String? suggestion;
}

/// 天气 UI 适配层：`WeatherProvider` → 类型化视图。
///
/// 与 MCP 工具面**并列共享同一内核**（装配期注入同一 `QWeatherProvider`
/// 实例——UI 与 Agent 同源，频控/缓存不分裂）；UI 不消费文本信封（R2）。
///
/// days 合法域 1~7（与 `weather_forecast` 同口径）：越界带码失败，不静默兜底。
class WeatherPort {
  const WeatherPort(this._provider);

  final WeatherProvider _provider;

  static const int minDays = 1;
  static const int maxDays = 7;
  static const int defaultDays = 3;

  Future<WeatherView> forecast({
    String? city,
    double? lat,
    double? lng,
    int days = defaultDays,
  }) async {
    if (days < minDays || days > maxDays) {
      return WeatherView(
        ok: false,
        errorCode: 'INVALID_ARGUMENT',
        message: 'days 超出范围：$days',
        suggestion: 'days 取 $minDays~$maxDays',
      );
    }
    if ((lat == null) != (lng == null)) {
      return const WeatherView(
        ok: false,
        errorCode: 'MISSING_ARGUMENT',
        message: 'lat 与 lng 须成对传入（或改用城市名）',
        suggestion: '经纬度必须成对；只给一个无法定位',
      );
    }

    final r = await _provider.forecast(
      city: (city != null && city.trim().isNotEmpty) ? city.trim() : null,
      lat: lat,
      lng: lng,
      days: days,
    );

    if (!r.success) {
      final e = r.error;
      return WeatherView(
        ok: false,
        errorCode: e?.code ?? 'ERR_WEATHER_UNKNOWN',
        message: e?.message ?? '天气取数失败',
        suggestion: e?.suggestion,
      );
    }
    return WeatherView(
      ok: true,
      city: r.city,
      updateTime: r.updateTime,
      now: _toNow(r.now),
      days: r.forecast.map(_toDay).toList(growable: false),
      alerts: r.alerts.map(_toAlert).toList(growable: false),
      isCached: r.isCached,
    );
  }

  static WeatherNowView? _toNow(Map<String, Object?>? raw) {
    if (raw == null) return null;
    String? s(String k) {
      final v = raw[k];
      return (v is String && v.isNotEmpty) ? v : v?.toString();
    }

    return WeatherNowView(
      text: s('text') ?? '未知',
      temp: s('temp'),
      feelsLike: s('feelsLike'),
      humidity: s('humidity'),
      windDir: s('windDir'),
      windScale: s('windScale'),
    );
  }

  static WeatherDayView _toDay(Map<String, Object?> raw) {
    String? s(String k) {
      final v = raw[k];
      return (v is String && v.isNotEmpty) ? v : v?.toString();
    }

    return WeatherDayView(
      date: s('fxDate') ?? '',
      textDay: s('textDay') ?? '未知',
      tempMax: s('tempMax'),
      tempMin: s('tempMin'),
      humidity: s('humidity'),
      windDirDay: s('windDirDay'),
      windScaleDay: s('windScaleDay'),
      precip: s('precip'),
    );
  }

  static WeatherAlertView _toAlert(Map<String, Object?> raw) {
    String? s(String k) {
      final v = raw[k];
      return (v is String && v.isNotEmpty) ? v : v?.toString();
    }

    return WeatherAlertView(
      title: s('title') ?? '气象预警',
      severity: s('severity'),
      description: s('text'),
    );
  }
}
