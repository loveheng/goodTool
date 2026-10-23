/// 真实位置传感器源：geolocator（系统定位）→ [LocationSensorProvider]。
///
/// 替换 `NullLocationSensorProvider`（恒返 null 的 fail-closed 空实现）：
/// 注入后 `geo_current` MCP action、地图页「我的位置」、天气回退链末级
/// 一次全部激活。坐标输出为 **WGS-84**（GPS 原生）——请求高德/渲染画布前
/// 由上层经 `CoordConvert.normalize` 归一化到 GCJ-02（lib/geo 内核），
/// 本文件不做坐标变换（平台层只管取数）。
///
/// 失败口径对齐端口契约：无权限 / 无硬件 / 超时 → 返回 null（不抛），
/// 由调用方 fail-closed 展示引导（MCP 侧 `ERR_LOCATION_UNAVAILABLE`，
/// UI 侧胶囊提示检查权限与定位开关）。**不以 0/空坐标兜底**。
///
/// 2026-10-23 修正（地图进场停在「原始起点」根因）：
/// 原实现只 catch `TimeoutException`，而 geolocator 在**系统定位开关关闭**时
/// 抛 `LocationServiceDisabledException`、权限流程异常时抛
/// `PermissionDeniedException`/`PermissionRequestInProgressException`——
/// 这些异常会**冒泡出端口**，调用方（地图页 `_locateMe`）的 `await` 抛出后
/// `setState` 不执行，「定位中…」状态永久挂起、相机停在硬编码初始中心。
/// 现口径：**任何失败一律收敛为 null（端口契约行为）**，并打 `[LOC]` 日志
/// 保留原因（不静默吞异常）。
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../mcp/geo_provider.dart';

class SystemLocationSensorProvider implements LocationSensorProvider {
  const SystemLocationSensorProvider();

  /// 高精度档（GPS）超时——GPS 冷启动常超 10s。
  static const Duration highAccuracyTimeout = Duration(seconds: 12);

  /// 低精度档（网络定位）超时——高精度超时后的回退档，室内秒级出结果。
  static const Duration lowAccuracyTimeout = Duration(seconds: 8);

  /// 「上次已知位置」可采信的最大陈旧度：超过则丢弃（避免跳到几小时前的旧点）。
  static const Duration maxStaleAge = Duration(minutes: 2);

  @override
  Future<LocationReading?> current() async {
    if (!await _ensurePermission()) return null;

    // 系统定位开关：关闭时 geolocator 抛 LocationServiceDisabledException——
    // 先探测并 fail-closed，避免异常冒泡（见文件头「2026-10-23 修正」）。
    try {
      final enabled = await GeolocatorPlatform.instance.isLocationServiceEnabled();
      if (!enabled) {
        debugPrint('[LOC] 系统定位开关未开启 → 返回 null（提示用户开启系统定位）');
        return null;
      }
    } on Exception catch (e) {
      // 探测失败不阻断取位（部分设备/模拟器不支持该探测），继续往下走。
      debugPrint('[LOC] 定位服务开关探测失败（继续尝试取位）: $e');
    }

    // ① 高精度（GPS）。
    final high = await _readAt(LocationAccuracy.high, highAccuracyTimeout);
    if (high != null) return high;

    // ② 低精度回退（网络定位）——高精度超时后的第二档，显著提高室内成功率。
    final low = await _readAt(LocationAccuracy.low, lowAccuracyTimeout);
    if (low != null) return low;

    // ③ 上次已知位置兜底：仅采信 2 分钟内的新鲜读数（过期坐标会把地图带到旧地点）。
    final last = await _readLastKnown();
    if (last != null) return last;

    debugPrint('[LOC] 三档定位均失败 → 返回 null（检查定位权限与系统定位开关）');
    return null;
  }

  /// 权限流程：已授权直接过；未授权则请求一次；仍拒（denied / deniedForever）
  /// → false（调用方返回 null，fail-closed 不伪造坐标）。
  Future<bool> _ensurePermission() async {
    try {
      var permission = await GeolocatorPlatform.instance.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await GeolocatorPlatform.instance.requestPermission();
      }
      // deniedForever：系统设置里手动拒过，运行时弹窗不再出现——只能引导去设置。
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        debugPrint('[LOC] 定位权限未授予（$permission）→ 返回 null');
        return false;
      }
      return true;
    } on Exception catch (e) {
      debugPrint('[LOC] 定位权限流程异常 → 返回 null: $e');
      return false;
    }
  }

  /// 取一档定位读数；失败（超时/异常）返回 null，不抛。
  Future<LocationReading?> _readAt(LocationAccuracy accuracy, Duration timeout) async {
    try {
      final position = await GeolocatorPlatform.instance.getCurrentPosition(
        locationSettings: LocationSettings(accuracy: accuracy, timeLimit: timeout),
      );
      return _toReading(position);
    } on TimeoutException {
      debugPrint('[LOC] $accuracy 档定位超时（${timeout.inSeconds}s）');
      return null;
    } on Exception catch (e) {
      debugPrint('[LOC] $accuracy 档定位失败: $e');
      return null;
    }
  }

  /// 上次已知位置（系统缓存）；仅采信 [maxStaleAge] 内的新鲜读数。
  Future<LocationReading?> _readLastKnown() async {
    try {
      final position =
          await GeolocatorPlatform.instance.getLastKnownPosition();
      if (position == null) return null;
      final age = DateTime.now().difference(position.timestamp);
      if (age > maxStaleAge) {
        debugPrint('[LOC] 上次已知位置已过期（${age.inMinutes} 分钟前）→ 不采信');
        return null;
      }
      return _toReading(position);
    } on Exception catch (e) {
      debugPrint('[LOC] 读取上次已知位置失败: $e');
      return null;
    }
  }

  /// 平台读数 → 端口读数（WGS-84 原样透传，坐标系转换由上层内核负责）。
  LocationReading _toReading(Position position) => LocationReading(
        lat: position.latitude,
        lng: position.longitude,
        accuracy: position.accuracy,
        coordSystem: 'WGS84',
        timestamp: position.timestamp.millisecondsSinceEpoch,
        altitude: position.altitude,
      );

  @override
  Future<CompassReading?> compass() async => null; // 磁力计未接（域内待办）
}
