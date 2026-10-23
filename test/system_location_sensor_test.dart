// 定位源健壮性回归钉（2026-10-23 根因）：
// 原实现只 catch `TimeoutException`，而 geolocator 在**系统定位开关关闭**时抛
// `LocationServiceDisabledException`、权限流程异常抛 `PermissionDeniedException`
// ——这些异常冒泡出端口后，地图页 `await` 抛出、`setState` 不执行，「定位中…」
// 永久挂起、相机停在硬编码原始起点（用户报「进地图定位原始起点」）。
//
// 本文件锁定端口契约：**任何失败一律收敛为 null（不抛）**，且分档回退可用。
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:goodtools/service/system_location_sensor.dart';

void main() {
  late GeolocatorPlatform original;

  setUp(() {
    original = GeolocatorPlatform.instance;
  });

  tearDown(() {
    GeolocatorPlatform.instance = original;
  });

  Position pos({
    double lat = 39.9042,
    double lng = 116.4074,
    Duration age = Duration.zero,
  }) =>
      Position(
        latitude: lat,
        longitude: lng,
        timestamp: DateTime.now().subtract(age),
        accuracy: 5,
        altitude: 30,
        altitudeAccuracy: 1,
        heading: 0,
        headingAccuracy: 1,
        speed: 0,
        speedAccuracy: 1,
      );

  group('权限与系统开关（fail-closed，不抛）', () {
    test('权限被拒 → null', () async {
      GeolocatorPlatform.instance = _FakeGeo(
        permission: LocationPermission.denied,
        permissionAfterRequest: LocationPermission.denied,
      );
      expect(await const SystemLocationSensorProvider().current(), isNull);
    });

    test('权限 deniedForever → null', () async {
      GeolocatorPlatform.instance =
          _FakeGeo(permission: LocationPermission.deniedForever);
      expect(await const SystemLocationSensorProvider().current(), isNull);
    });

    test('请求权限后仍被拒 → null', () async {
      GeolocatorPlatform.instance = _FakeGeo(
        permission: LocationPermission.denied,
        permissionAfterRequest: LocationPermission.denied,
      );
      expect(await const SystemLocationSensorProvider().current(), isNull);
    });

    test('系统定位开关关闭 → null（不打取位请求）', () async {
      final fake = _FakeGeo(serviceEnabled: false);
      GeolocatorPlatform.instance = fake;
      expect(await const SystemLocationSensorProvider().current(), isNull);
      expect(fake.currentCalls, 0);
    });
  });

  group('异常收敛（根因回归钉）', () {
    test('LocationServiceDisabledException → null 不外泄', () async {
      GeolocatorPlatform.instance = _FakeGeo(
        currentError: const LocationServiceDisabledException(),
      );
      expect(await const SystemLocationSensorProvider().current(), isNull);
    });

    test('PermissionDeniedException → null 不外泄', () async {
      GeolocatorPlatform.instance = _FakeGeo(
        currentError: const PermissionDeniedException('denied'),
      );
      expect(await const SystemLocationSensorProvider().current(), isNull);
    });

    test('平台通道异常（PlatformException）→ null 不外泄', () async {
      GeolocatorPlatform.instance = _FakeGeo(
        currentError: PlatformException(code: 'ERR', message: 'boom'),
      );
      expect(await const SystemLocationSensorProvider().current(), isNull);
    });

    test('权限流程异常 → null 不外泄', () async {
      GeolocatorPlatform.instance = _FakeGeo(
        permissionError: const PermissionDeniedException('perm flow'),
      );
      expect(await const SystemLocationSensorProvider().current(), isNull);
    });
  });

  group('分档回退（提高自动定位成功率）', () {
    test('高精度超时 → 低精度档成功 → 返回读数（WGS-84）', () async {
      final fake = _FakeGeo();
      fake.errorsByAccuracy[LocationAccuracy.high] = TimeoutException('gps cold');
      fake.positionsByAccuracy[LocationAccuracy.low] = pos();
      GeolocatorPlatform.instance = fake;
      final r = await const SystemLocationSensorProvider().current();
      expect(r, isNotNull);
      expect(r!.lat, closeTo(39.9042, 1e-9));
      expect(r.lng, closeTo(116.4074, 1e-9));
      expect(r.coordSystem, 'WGS84');
      expect(fake.accuraciesTried, <LocationAccuracy>[
        LocationAccuracy.high,
        LocationAccuracy.low,
      ]);
    });

    test('两档都失败 → 回退上次已知位置（新鲜）', () async {
      final fake = _FakeGeo(
        currentError: TimeoutException('gps cold'),
        lastKnown: pos(lat: 31.2304, lng: 121.4737),
      );
      GeolocatorPlatform.instance = fake;
      final r = await const SystemLocationSensorProvider().current();
      expect(r, isNotNull);
      expect(r!.lat, closeTo(31.2304, 1e-9));
    });

    test('上次已知位置已过期 → null（不把地图带到旧地点）', () async {
      GeolocatorPlatform.instance = _FakeGeo(
        currentError: TimeoutException('gps cold'),
        lastKnown: pos(age: const Duration(minutes: 30)),
      );
      expect(await const SystemLocationSensorProvider().current(), isNull);
    });

    test('三档全败 → null（不伪造坐标）', () async {
      GeolocatorPlatform.instance = _FakeGeo(
        currentError: TimeoutException('gps cold'),
      );
      expect(await const SystemLocationSensorProvider().current(), isNull);
    });
  });
}

/// 可编程的假平台：按精度档注入「抛异常 / 返回读数」。
class _FakeGeo extends GeolocatorPlatform {
  _FakeGeo({
    this.permission = LocationPermission.whileInUse,
    this.permissionAfterRequest = LocationPermission.whileInUse,
    this.serviceEnabled = true,
    this.currentError,
    this.permissionError,
    this.lastKnown,
  });

  LocationPermission permission;
  LocationPermission permissionAfterRequest;
  bool serviceEnabled;

  /// 所有精度档统一抛出的异常（null → 正常返回）。
  Object? currentError;

  /// 权限流程抛出的异常。
  Object? permissionError;

  /// 上次已知位置（null → 无）。
  Position? lastKnown;

  /// 按精度档注入的异常（该档优先于 [currentError]）。
  final Map<LocationAccuracy, Object> errorsByAccuracy = {};

  /// 按精度档注入的读数（该档优先于默认读数）。
  final Map<LocationAccuracy, Position> positionsByAccuracy = {};

  /// 记录实际尝试过的精度档（断言分档回退顺序）。
  final List<LocationAccuracy> accuraciesTried = <LocationAccuracy>[];

  /// 取位调用次数（断言「开关关闭时零请求」）。
  int currentCalls = 0;

  @override
  Future<LocationPermission> checkPermission() async {
    if (permissionError != null) throw permissionError!;
    return permission;
  }

  @override
  Future<LocationPermission> requestPermission() async {
    if (permissionError != null) throw permissionError!;
    return permissionAfterRequest;
  }

  @override
  Future<bool> isLocationServiceEnabled() async => serviceEnabled;

  @override
  Future<Position> getCurrentPosition({LocationSettings? locationSettings}) async {
    currentCalls++;
    final acc = locationSettings?.accuracy ?? LocationAccuracy.best;
    accuraciesTried.add(acc);
    final injected = errorsByAccuracy[acc];
    if (injected != null) throw injected;
    final pos = positionsByAccuracy[acc];
    if (pos != null) return pos;
    if (currentError != null) throw currentError!;
    return Position(
      latitude: 39.9042,
      longitude: 116.4074,
      timestamp: DateTime.now(),
      accuracy: 5,
      altitude: 30,
      altitudeAccuracy: 1,
      heading: 0,
      headingAccuracy: 1,
      speed: 0,
      speedAccuracy: 1,
    );
  }

  @override
  Future<Position?> getLastKnownPosition({bool forceLocationManager = false}) async =>
      lastKnown;
}
