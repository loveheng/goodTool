/// 地理能力端口（依赖反转接缝，arch-guard R4 无头约束）。
///
/// 内核（MCP 工具面 / 业务编排）只依赖以下抽象接口，不直接碰 HttpClient、
/// GPS 或磁力计；具体实现（真实高德 REST 调用、平台传感器）由 service 层注入，
/// 保证无设备、无网络环境下可用 Mock 走通 100% 确定性单测。
///
/// 模式对齐 [WeatherProvider]（lib/mcp/weather_provider.dart）。
library;

/// 高德 Web 服务 HTTP 端口：内核经此发起高德 REST 请求，不直连网络。
abstract class GeoHttpProvider {
  /// GET 高德 REST 资源；[path] 形如 `/v3/geocode/geo`，[query] 不含 `key`
  /// （key 由实现从设置读取后注入）。解码失败或 key 缺失抛 [GeoHttpException]。
  Future<Map<String, Object?>> get(String path, Map<String, String> query);
}

/// 地理 HTTP 异常（机器可读 code，引导 UI 弹配置卡）。
class GeoHttpException implements Exception {
  const GeoHttpException(this.code, this.message);

  /// 错误码，如 `ERR_AMAP_KEY_MISSING` / `ERR_AMAP_API`。
  final String code;

  final String message;

  @override
  String toString() => 'GeoHttpException($code): $message';
}

/// 默认空实现：未注入真实源时抛 [GeoHttpException]（code=ERR_AMAP_KEY_MISSING），
/// 引导 UI 提示用户在设置中配置高德 Key。
class NullGeoHttpProvider implements GeoHttpProvider {
  const NullGeoHttpProvider();

  @override
  Future<Map<String, Object?>> get(String path, Map<String, String> query) async =>
      throw const GeoHttpException(
          'ERR_AMAP_KEY_MISSING', '高德 Web 服务 Key 未配置');
}

/// 设备当前定位读数。
class LocationReading {
  const LocationReading({
    required this.lat,
    required this.lng,
    required this.accuracy,
    required this.coordSystem,
    required this.timestamp,
    this.altitude,
  });

  /// 纬度。
  final double lat;

  /// 经度。
  final double lng;

  /// 水平精度（米）。
  final double accuracy;

  /// 坐标系：`WGS84` | `GCJ02`。
  final String coordSystem;

  /// Unix 毫秒时间戳。
  final int timestamp;

  /// 海拔（米），缺测为 null。
  final double? altitude;
}

/// 磁力计方位读数。
class CompassReading {
  const CompassReading({
    required this.heading,
    required this.accuracy,
  });

  /// 航向角（0°~360°，正北为 0，顺时针）。
  final double heading;

  /// 精度（度），越小越准。
  final int accuracy;
}

/// 位置与传感器端口：GPS 当前坐标、磁力计航向，经平台实现注入。
abstract class LocationSensorProvider {
  /// 当前定位；无权限/无硬件返回 null（不抛）。
  Future<LocationReading?> current();

  /// 磁力计航向；无硬件返回 null（不抛）。
  Future<CompassReading?> compass();
}

/// 默认空实现：无传感器时返回 null（UI 展示授权引导卡，不闪退）。
class NullLocationSensorProvider implements LocationSensorProvider {
  const NullLocationSensorProvider();

  @override
  Future<LocationReading?> current() async => null;

  @override
  Future<CompassReading?> compass() async => null;
}

/// 八方位判定（纯算法，无平台依赖）：航向角 → 中文方位名。
///
/// 0°/360°=正北，顺时针每 45° 一档。
String compassDirection(double heading) {
  const names = [
    '正北',
    '东北',
    '正东',
    '东南',
    '正南',
    '西南',
    '正西',
    '西北',
  ];
  // 归一化到 [0,360) 并偏移到中心档（正北居中）。
  final h = ((heading % 360) + 360) % 360;
  final idx = ((h + 22.5) ~/ 45) % 8;
  return names[idx];
}
