library;

import '../service/weather_city_store.dart';

/// 天气城市**读聚合层**（R5 落点）：UI 经此读城市列表，不直连 store。
///
/// **写端口（`WeatherCityWriter`）不在此暴露**——城市增删必经
/// `CommandGateway` 用户侧注册表（R1），写端口只给 service 层 Actor 持有
/// （对齐 `favorite_repository.dart` 口径）。
class WeatherCityRepository {
  WeatherCityRepository({required this.store});

  final WeatherCityStore store;

  /// 全量城市列表（上限 10 条可控，直接全量）。
  Future<List<WeatherCity>> list() => store.list();
}
