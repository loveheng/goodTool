// 天气城市存储：WeatherCityStore（读）+ WeatherCityWriter（写）端口的双实现。
// 多城市列表是用户私有数据（product/weather.md「用户侧城市管理」），写操作
// 不进 MCP 工具面（对齐收藏地点 favorite_place_store 范式）。
//
// - [InMemoryWeatherCityStore]：Binder isolate / 单测——无平台通道依赖。
// - [SharedPrefsWeatherCityStore]：真实持久化（shared_preferences，JSON 字符串
//   列表）。非凭证数据，不走 SecretStore/Keystore 分流。
//
// 纪律：写端口**只给用户侧 Actor 持有**（经装配件注入）；UI 层只见
// Repository 暴露的读端口（R5）。
library;

import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

/// shared_preferences 键（WeatherCity JSON 数组）。
const String kWeatherCitiesPrefKey = 'weather_cities';

/// 城市条数硬上限（配额护栏：开发版和风配额极低，多城市取数放大频控压力）。
const int weatherCityLimit = 10;

/// 城市名长度上限（Actor 校验）。
const int weatherCityNameMaxLength = 40;

/// 已添加城市（用户侧数据）。
class WeatherCity {
  const WeatherCity({
    required this.id,
    required this.name,
    required this.lat,
    required this.lng,
    this.locationId,
  });

  /// `wx_city_` + 8 位十六进制。
  final String id;

  /// 展示名（和风完整行政链，如「北京市 朝阳区」；Actor 校验 1~40 字符）。
  final String name;

  /// 纬度（WGS-84/GCJ-02 差异在天气精度下可忽略，和风按坐标直查）。
  final double lat;

  /// 经度。
  final double lng;

  /// 和风 LocationID（搜索时解析所得，留档；取数按坐标直查不经 GeoAPI）。
  final String? locationId;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'name': name,
        'lat': lat,
        'lng': lng,
        if (locationId != null) 'locationId': locationId,
      };

  /// 解码失败抛 [FormatException]，由调用方转结构化错误——不静默跳过坏行。
  static WeatherCity fromJson(Map<String, Object?> m) => WeatherCity(
        id: m['id'] as String,
        name: m['name'] as String,
        lat: (m['lat'] as num).toDouble(),
        lng: (m['lng'] as num).toDouble(),
        locationId: m['locationId'] as String?,
      );
}

/// id 生成（对齐 favorite_place_store 口径）。
String newWeatherCityId() =>
    'wx_city_${Random.secure().nextInt(1 << 32).toRadixString(16).padLeft(8, '0')}';

/// 读端口（UI 经 Repository 只读聚合层访问，R5）。
abstract class WeatherCityStore {
  Future<List<WeatherCity>> list();
}

/// 写端口（只给用户侧 Actor 持有）。
abstract class WeatherCityWriter {
  /// 新增一条，返回 id；超出 [weatherCityLimit] 抛 [WeatherCityLimitExceeded]；
  /// 重名（trim 后全等）抛 [WeatherCityDuplicate]——不静默去重覆盖。
  Future<String> addCity(WeatherCity city);

  /// 按 id 删除；无匹配返回 false（Actor 转 NOT_FOUND）。
  Future<bool> deleteCity(String id);
}

/// 超出城市上限（Actor 转 `WEATHER_CITY_LIMIT_EXCEEDED`，不静默挤掉旧条目）。
class WeatherCityLimitExceeded implements Exception {
  const WeatherCityLimitExceeded(this.limit);
  final int limit;
}

/// 重名城市（Actor 转 `WEATHER_CITY_DUPLICATE`）。
class WeatherCityDuplicate implements Exception {
  const WeatherCityDuplicate(this.name);
  final String name;
}

/// 内存实现：进程重启即失。
class InMemoryWeatherCityStore implements WeatherCityStore, WeatherCityWriter {
  final List<WeatherCity> _items = <WeatherCity>[];

  @override
  Future<List<WeatherCity>> list() async =>
      List<WeatherCity>.unmodifiable(_items);

  @override
  Future<String> addCity(WeatherCity city) async {
    if (_items.any((c) => c.name.trim() == city.name.trim())) {
      throw WeatherCityDuplicate(city.name);
    }
    if (_items.length >= weatherCityLimit) {
      throw WeatherCityLimitExceeded(weatherCityLimit);
    }
    _items.add(city);
    return city.id;
  }

  @override
  Future<bool> deleteCity(String id) async {
    final n = _items.length;
    _items.removeWhere((c) => c.id == id);
    return _items.length != n;
  }
}

/// SharedPreferences 持久化实现。
class SharedPrefsWeatherCityStore
    implements WeatherCityStore, WeatherCityWriter {
  SharedPrefsWeatherCityStore(this._prefs);

  final SharedPreferences _prefs;

  static const String key = kWeatherCitiesPrefKey;

  static Future<SharedPrefsWeatherCityStore> open() async =>
      SharedPrefsWeatherCityStore(await SharedPreferences.getInstance());

  @override
  Future<List<WeatherCity>> list() async => _decode();

  @override
  Future<String> addCity(WeatherCity city) async {
    final all = _decode();
    if (all.any((c) => c.name.trim() == city.name.trim())) {
      throw WeatherCityDuplicate(city.name);
    }
    if (all.length >= weatherCityLimit) {
      throw WeatherCityLimitExceeded(weatherCityLimit);
    }
    await _save(<WeatherCity>[...all, city]);
    return city.id;
  }

  @override
  Future<bool> deleteCity(String id) async {
    final all = _decode();
    final next = all.where((c) => c.id != id).toList(growable: false);
    if (next.length == all.length) return false;
    await _save(next);
    return true;
  }

  List<WeatherCity> _decode() => (_prefs.getStringList(key) ?? const <String>[])
      .map((raw) =>
          WeatherCity.fromJson(jsonDecode(raw) as Map<String, Object?>))
      .toList(growable: false);

  Future<void> _save(List<WeatherCity> cities) async {
    await _prefs.setStringList(
        key, cities.map((c) => jsonEncode(c.toJson())).toList(growable: false));
  }
}
