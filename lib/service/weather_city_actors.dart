library;

import '../action/command_gateway.dart';
import 'weather_city_store.dart';

/// 天气城市用户侧 Actor：把**用户本人**的城市增删落到 store。
///
/// 纪律同收藏地点 Actor（`geo_favorite_actors.dart`）：
/// - 校验在 Actor 内（必填 / 取值域 / 超长），失败回**结构化机器码 + suggestion**；
/// - 写后回**写入确认**（id + 当前条数）；
/// - 写端口只在此持有；UI 经 Repository 读端口（R5）。
class WeatherCityActors {
  WeatherCityActors({required this.store, required this.writer});

  final WeatherCityStore store;
  final WeatherCityWriter writer;

  /// 登记进用户侧注册表（AI 不可触达）。
  void register(CommandGateway gateway) {
    gateway.registerUser('user_weather_city_add', addCity);
    gateway.registerUser('user_weather_city_delete', deleteCity);
  }

  /// 新增城市。载荷 `{name, lat, lng, locationId?}`。
  ///
  /// `name` 取和风完整行政链（消重名歧义，1~40 字符）；重名 trim 后全等判
  /// [WeatherCityDuplicate]；`locationId` 可选留档（取数按坐标直查不经 GeoAPI）。
  Future<UserCommandResult> addCity(Command cmd) async {
    final p = cmd.payload;

    final name = p['name'];
    if (name is! String || name.trim().isEmpty) {
      return const UserCommandResult.failure(
        'MISSING_ARGUMENT',
        '缺少必填参数 name（非空字符串）',
        suggestion: 'name 取和风行政链（如「北京市 朝阳区」），1~40 字符',
      );
    }
    final trimmedName = name.trim();
    if (trimmedName.length > weatherCityNameMaxLength) {
      return UserCommandResult.failure(
        'INVALID_ARGUMENT',
        'name 超长（${trimmedName.length} > $weatherCityNameMaxLength 字符）',
        suggestion: 'name 压缩到 $weatherCityNameMaxLength 字符以内',
      );
    }

    final lat = _asDouble(p['lat']);
    final lng = _asDouble(p['lng']);
    if (lat == null || lng == null) {
      return const UserCommandResult.failure(
        'MISSING_ARGUMENT',
        '缺少必填参数 lat / lng（数值）',
        suggestion: 'lat/lng 为 double；来自搜索结果坐标',
      );
    }
    if (lat < -90 || lat > 90 || lng < -180 || lng > 180) {
      return UserCommandResult.failure(
        'INVALID_ARGUMENT',
        '经纬度越界（lat=$lat, lng=$lng）',
        suggestion: '纬度 -90~90，经度 -180~180',
      );
    }

    final locationId = p['locationId'];
    String? trimmedLocationId;
    if (locationId is String && locationId.trim().isNotEmpty) {
      trimmedLocationId = locationId.trim();
    }

    final city = WeatherCity(
      id: newWeatherCityId(),
      name: trimmedName,
      lat: lat,
      lng: lng,
      locationId: trimmedLocationId,
    );
    try {
      final id = await writer.addCity(city);
      return UserCommandResult.success(<String, Object?>{
        'id': id,
        'name': trimmedName,
        'count': await _listCount(),
      });
    } on WeatherCityDuplicate {
      return UserCommandResult.failure(
        'WEATHER_CITY_DUPLICATE',
        '城市已存在：$trimmedName',
        suggestion: '同一城市只需添加一次',
      );
    } on WeatherCityLimitExceeded catch (e) {
      return UserCommandResult.failure(
        'WEATHER_CITY_LIMIT_EXCEEDED',
        '城市已达上限 ${e.limit} 个',
        suggestion: '开发版和风配额有限，删除不再需要的城市后再添加',
      );
    }
  }

  /// 删除城市。载荷 `{id}`。
  Future<UserCommandResult> deleteCity(Command cmd) async {
    final id = cmd.payload['id'];
    if (id is! String || id.trim().isEmpty) {
      return const UserCommandResult.failure(
        'MISSING_ARGUMENT',
        '缺少必填参数 id（城市条目 id）',
      );
    }
    final deleted = await writer.deleteCity(id.trim());
    if (!deleted) {
      return UserCommandResult.failure(
        'NOT_FOUND',
        '城市 id 不存在：${id.trim()}',
        suggestion: '先读城市列表取有效 id',
      );
    }
    return UserCommandResult.success(<String, Object?>{
      'deleted': true,
      'count': await _listCount(),
    });
  }

  Future<int> _listCount() async => (await store.list()).length;

  static double? _asDouble(Object? v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v.trim());
    return null;
  }
}
