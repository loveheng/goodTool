/// 天气能力端口（依赖反转接缝，arch-guard R4 无头约束）。
///
/// 内核（MCP 工具面 / 业务编排）只依赖以下抽象接口，不直接碰 HttpClient 或
/// 定位；具体实现（和风 QWeather 联网、坐标回退）由 service 层注入，保证无设备、
/// 无网络环境下可用 Mock 走通 100% 确定性单测。
///
/// 模式对齐 [GeoHttpProvider]（lib/mcp/geo_provider.dart）。
/// 契约正文见 `docs/product/weather.md`（错误模型 / 回退链 / 传输层硬性约束）。
library;

/// 天气错误码枚举（product/weather.md「错误模型」；命名对齐地理的 `ERR_AMAP_*`）。
abstract final class WeatherErr {
  /// `qweather_key` 未配置（SettingsKv 读取为空）。
  static const keyMissing = 'ERR_WEATHER_KEY_MISSING';

  /// HTTP/Body `401`/`402`/`403`：Key 无效、额度透支、Host 错配、无接口权限。
  static const unauthorized = 'ERR_WEATHER_UNAUTHORIZED';

  /// 未配置和风账号专属 API Host（2024 起公共 devapi/api 域名已停用返回 403）。
  static const hostMissing = 'ERR_WEATHER_HOST_MISSING';

  /// 账号专属 Host 无效或该 Host 未开通目标 API（和风 403 `Invalid Host` /
  /// 404「服务不可访问」等文案）——与「Key 无效」区分开，便于走「去改 Host」自愈。
  static const hostInvalid = 'ERR_WEATHER_HOST_INVALID';

  /// GeoAPI 查无此城，或天气 Body `code:"404"` 无该地点数据。
  static const cityNotFound = 'ERR_CITY_NOT_FOUND';

  /// 回退链五級皆空（无 lat/lng、无 city、无设置城市、无定位权限）。
  static const locationUnavailable = 'ERR_LOCATION_UNAVAILABLE';

  /// 网络异常 / 超时 / DNS 失败（HTTP 层）。
  static const network = 'ERR_NETWORK';

  /// HTTP 429 或 Body `code:"429"`，且无可用缓存可回退。
  static const rateLimited = 'ERR_RATE_LIMITED';
}

/// 结构化天气错误（自愈三件套：机器码 + 人话 + 指引）。
///
/// `suggestion` 面向 Agent 给出「下一步怎么做」，不透传原始业务码与堆栈。
class WeatherError {
  const WeatherError(this.code, this.message, {this.suggestion});

  final String code;
  final String message;
  final String? suggestion;
}

/// 天气结果信封：**永不 null**。
///
/// 原设计「失败返回 null」是反模式——Key 缺失/配额耗尽时返回 null，Agent 会
/// 编造天气或给出无因失败（weather.md「错误模型」）。故统一为结构化信封。
class WeatherResult {
  const WeatherResult.success({
    this.city,
    this.locationId,
    this.updateTime,
    this.now,
    this.forecast = const <Map<String, Object?>>[],
    this.alerts = const <Map<String, Object?>>[],
    this.isCached = false,
  })  : success = true,
        error = null;

  const WeatherResult.failure(this.error)
      : success = false,
        city = null,
        locationId = null,
        updateTime = null,
        now = null,
        forecast = const <Map<String, Object?>>[],
        alerts = const <Map<String, Object?>>[],
        isCached = false;

  final bool success;
  final WeatherError? error;

  /// 和风返回的**完整行政链**（如「北京市 朝阳区」），消除重名歧义。
  final String? city;

  /// 和风 LocationID（如 `101010100`）。
  final String? locationId;

  /// 数据更新时间（ISO 8601 带偏移，原样保真透传）。
  final String? updateTime;

  /// 实时天气投影（`now` 端点）。
  final Map<String, Object?>? now;

  /// 逐日预报；弱依赖失败时为 `[]`（非空、不 null）。
  final List<Map<String, Object?>> forecast;

  /// 气象预警；**弱依赖**——无预警或请求失败恒为 `[]`，不阻断主数据。
  final List<Map<String, Object?>> alerts;

  /// 是否回放缓存（TTL 命中或 429 缓存回退）。
  final bool isCached;
}

/// 天气投影提供方抽象：内核（工具面）仅依赖本接口，不碰 `dart:io`。
///
/// 具体实现 `QWeatherProvider`（HttpClient）落 `lib/service/weather.dart`。
abstract class WeatherProvider {
  /// 实时 + [days] 天预报 + 预警；**永不返回 null**（失败走 [WeatherResult.failure]）。
  ///
  /// 位置优先级由实现按 weather.md「缺省回退链」处理：显式 `lat/lng` > `city` >
  /// 设置项 `weather_location` > `LocationSensorProvider.current()`。
  Future<WeatherResult> forecast({
    String? city,
    double? lat,
    double? lng,
    int days = 3,
  });
}

/// 默认空实现：未注入真实源时返回 `ERR_WEATHER_KEY_MISSING` 信封（引导配置），
/// **不是 null**——静默 null 会让 Agent 编造天气。
class NullWeatherProvider implements WeatherProvider {
  const NullWeatherProvider();

  @override
  Future<WeatherResult> forecast({
    String? city,
    double? lat,
    double? lng,
    int days = 3,
  }) async =>
      const WeatherResult.failure(WeatherError(
        WeatherErr.keyMissing,
        '和风天气 API Key 未配置',
        suggestion: '请在 App 设置页填入 QWeather API Key',
      ));
}
