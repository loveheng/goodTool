library;

/// 地图页「上次定位点」持久化链路单测：`GeoLastLocationPort` →
/// `user_geo_save_last_location`（用户侧网关）→ Actor 校验落盘 →
/// `SettingsRepository` 读回。全程 InMemoryKv，无设备可跑。
///
/// 覆盖：写读闭环 / 载荷校验（缺参 / 越界）/ 未登记命令 fail-closed /
/// 脏数据容错（KV 里非 `lat,lng` 文本读回 null 不抛）。

import 'package:flutter_test/flutter_test.dart';
import 'package:goodtools/action/command_gateway.dart';
import 'package:goodtools/action/geo_commands.dart';
import 'package:goodtools/mcp/settings_keys.dart';
import 'package:goodtools/ports.dart';
import 'package:goodtools/repository/settings_repository.dart';
import 'package:goodtools/service/geo_last_location_actor.dart';
import 'package:goodtools/ui_ports/geo_last_location_port.dart';

void main() {
  late InMemoryKv kv;
  late SettingsRepository repository;
  late CommandGateway gateway;
  late GeoLastLocationPort port;

  setUp(() {
    kv = InMemoryKv();
    repository = SettingsRepository(kv: kv);
    gateway = CommandGateway();
    GeoLastLocationActor(kv: kv).register(gateway);
    port = GeoLastLocationPort(repository, gateway);
  });

  test('写读闭环：save 后 read 回同坐标', () async {
    final result = await port.save(31.2304, 121.4737);
    expect(result.ok, isTrue);

    final last = await port.read();
    expect(last, isNotNull);
    expect(last!.lat, 31.2304);
    expect(last.lng, 121.4737);
    expect(await kv.settingsGet(SettingsKeys.geoLastLocation),
        '31.2304,121.4737');
  });

  test('未定位过 read 回 null（首启保持占位中心等刷新定位）', () async {
    expect(await port.read(), isNull);
  });

  test('缺参（lat 非 num）→ 结构化失败不落盘', () async {
    final bad = await gateway
        .dispatchUser(const UserGeoSaveLastLocationCommand({'lng': 121.0}));
    expect(bad.ok, isFalse);
    expect(bad.errorCode, 'MISSING_ARGUMENT');
    expect(await port.read(), isNull);
  });

  test('越界（lat=91）→ 结构化失败不落盘', () async {
    final bad = await gateway.dispatchUser(
        const UserGeoSaveLastLocationCommand({'lat': 91.0, 'lng': 121.0}));
    expect(bad.ok, isFalse);
    expect(bad.errorCode, 'INVALID_ARGUMENT');
    expect(await port.read(), isNull);
  });

  test('未登记命令 fail-closed（USER_COMMAND_NOT_REGISTERED）', () async {
    final bareGateway = CommandGateway();
    final barePort = GeoLastLocationPort(repository, bareGateway);
    final result = await barePort.save(31.0, 121.0);
    expect(result.ok, isFalse);
    expect(result.errorCode, 'USER_COMMAND_NOT_REGISTERED');
  });

  test('脏数据容错：KV 里非 lat,lng 文本读回 null 不抛', () async {
    await kv.settingsSet(<String, String>{
      SettingsKeys.geoLastLocation: 'not-a-coord',
    });
    expect(await port.read(), isNull);

    await kv.settingsSet(<String, String>{
      SettingsKeys.geoLastLocation: '1.0,2.0,3.0',
    });
    expect(await port.read(), isNull);
  });
}
