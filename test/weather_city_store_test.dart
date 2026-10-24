import 'package:flutter_test/flutter_test.dart';
import 'package:goodtools/action/command_gateway.dart';
import 'package:goodtools/action/weather_commands.dart';
import 'package:goodtools/service/weather_city_store.dart';
import 'package:goodtools/service/weather_city_actors.dart';

void main() {
  /// data 快照读取（`UserCommandResult.data` 为 Object?，测试内统一 cast）。
  Map<String, Object?>? castData(UserCommandResult r) =>
      r.data as Map<String, Object?>?;

  group('WeatherCityStore · 内存实现', () {
    late InMemoryWeatherCityStore store;

    setUp(() => store = InMemoryWeatherCityStore());

    test('新增后可读回；按 id 精确删除', () async {
      final id = await store.addCity(const WeatherCity(
        id: 'wx_city_a',
        name: '北京市 朝阳区',
        lat: 39.92,
        lng: 116.43,
        locationId: '101010300',
      ));
      expect(id, 'wx_city_a');
      expect((await store.list()).single.name, '北京市 朝阳区');

      expect(await store.deleteCity('wx_city_a'), isTrue);
      expect(await store.list(), isEmpty);
      expect(await store.deleteCity('wx_city_a'), isFalse);
    });

    test('重名（trim 后全等）拒绝且不静默覆盖', () async {
      await store.addCity(const WeatherCity(
          id: 'wx_city_a', name: '北京市 朝阳区', lat: 1, lng: 2));
      expect(
        () => store.addCity(const WeatherCity(
            id: 'wx_city_b', name: ' 北京市 朝阳区 ', lat: 3, lng: 4)),
        throwsA(isA<WeatherCityDuplicate>()),
      );
      expect((await store.list()).length, 1);
    });

    test('达到上限后拒绝新增（不挤掉旧条目）', () async {
      for (var i = 0; i < weatherCityLimit; i++) {
        await store.addCity(WeatherCity(
            id: 'wx_city_$i', name: '城市$i', lat: i.toDouble(), lng: 0));
      }
      expect(
        () => store.addCity(const WeatherCity(
            id: 'wx_city_x', name: '溢出城', lat: 0, lng: 0)),
        throwsA(isA<WeatherCityLimitExceeded>()),
      );
      expect((await store.list()).length, weatherCityLimit);
    });
  });

  group('WeatherCityActors · 用户侧命令校验', () {
    late InMemoryWeatherCityStore store;
    late WeatherCityActors actors;
    late CommandGateway gateway;

    setUp(() {
      store = InMemoryWeatherCityStore();
      actors = WeatherCityActors(store: store, writer: store);
      gateway = CommandGateway();
      actors.register(gateway);
    });

    test('缺 name / 坐标 → MISSING_ARGUMENT', () async {
      final r1 = await actors
          .addCity(const UserWeatherCityAddCommand({'lat': 1, 'lng': 2}));
      expect(r1.errorCode, 'MISSING_ARGUMENT');
      final r2 = await actors
          .addCity(const UserWeatherCityAddCommand({'name': '北京'}));
      expect(r2.errorCode, 'MISSING_ARGUMENT');
    });

    test('坐标越界 → INVALID_ARGUMENT', () async {
      final r = await actors.addCity(const UserWeatherCityAddCommand(
          {'name': '北京', 'lat': 91, 'lng': 0}));
      expect(r.errorCode, 'INVALID_ARGUMENT');
    });

    test('成功写入回确认（id + count）', () async {
      final r = await actors.addCity(const UserWeatherCityAddCommand({
        'name': '北京市 朝阳区',
        'lat': 39.92,
        'lng': 116.43,
        'locationId': '101010300',
      }));
      expect(r.ok, isTrue);
      expect(castData(r)?['count'], 1);
      expect(castData(r)?['name'], '北京市 朝阳区');
    });

    test('重名 → WEATHER_CITY_DUPLICATE；上限 → WEATHER_CITY_LIMIT_EXCEEDED',
        () async {
      await actors.addCity(
          const UserWeatherCityAddCommand({'name': '北京', 'lat': 1, 'lng': 2}));
      final dup = await actors.addCity(
          const UserWeatherCityAddCommand({'name': '北京', 'lat': 3, 'lng': 4}));
      expect(dup.errorCode, 'WEATHER_CITY_DUPLICATE');

      for (var i = 0; i < weatherCityLimit - 1; i++) {
        await actors.addCity(UserWeatherCityAddCommand(
            {'name': '城市$i', 'lat': 1, 'lng': 2}));
      }
      final full = await actors.addCity(
          const UserWeatherCityAddCommand({'name': '溢出城', 'lat': 1, 'lng': 2}));
      expect(full.errorCode, 'WEATHER_CITY_LIMIT_EXCEEDED');
    });

    test('删除不存在 id → NOT_FOUND；删除成功回 deleted+count', () async {
      final nf = await actors
          .deleteCity(const UserWeatherCityDeleteCommand({'id': 'wx_city_none'}));
      expect(nf.errorCode, 'NOT_FOUND');

      final add = await actors.addCity(
          const UserWeatherCityAddCommand({'name': '北京', 'lat': 1, 'lng': 2}));
      final id = castData(add)?['id'] as String;
      final del =
          await actors.deleteCity(UserWeatherCityDeleteCommand({'id': id}));
      expect(del.ok, isTrue);
      expect(castData(del)?['deleted'], isTrue);
      expect(castData(del)?['count'], 0);
    });

    test('网关登记后可派发（用户侧注册表生效）', () async {
      final r = await gateway.dispatchUser(const UserWeatherCityAddCommand({
        'name': '上海市 浦东新区',
        'lat': 31.22,
        'lng': 121.54,
      }));
      expect(r.ok, isTrue);
    });
  });
}
