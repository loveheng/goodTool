library;

import 'package:flutter/services.dart';

import '../mcp/calendar_provider.dart';
import 'system_calendar_port.dart';

/// 日历运行时权限申请的结果语义（U12b；与 Kotlin `SystemCalendarChannel`
/// 的 `requestCalendarPermission` 回传值一一对应，勿单方改动）。
enum CalendarPermissionOutcome {
  /// 已授权（无需操作）。
  granted,

  /// 未授权，已跳转系统设置页——用户去授予，返回后重试。
  settingsOpened,
}

/// 日历运行时权限端口（U12b：运行时日历权限申请 UI 入口的平台侧）。
///
/// 落点依据 standards §1.3「新平台能力 → service + Provider 端口」：跳转系统
/// 设置的平台细节住本层，UI 经端口调用，不写 `Platform.isX`（R3）。
///
/// fail-closed 纪律：通道异常一律转 [CalendarFeedException] 携带机器码透出，
/// **绝不**回「已授权」假装就绪——那会让未授权看起来像无日程。
abstract class CalendarPermissionPort {
  /// 申请日历权限；已授权或已引导跳转后返回对应语义。
  Future<CalendarPermissionOutcome> request();
}

/// MethodChannel 实现：复用系统日历通道（同引擎双注册纪律见
/// `kSystemCalendarChannel` 注释）。
class MethodChannelCalendarPermissionPort implements CalendarPermissionPort {
  const MethodChannelCalendarPermissionPort();

  /// 与 Kotlin 侧 `METHOD_REQUEST_PERMISSION` 一致。
  static const String _method = 'requestCalendarPermission';

  @override
  Future<CalendarPermissionOutcome> request() async {
    final Object? result;
    try {
      result =
          await kSystemCalendarChannel.invokeMethod<Object?>(_method);
    } on MissingPluginException {
      throw const CalendarFeedException(
        CalendarErr.sourceUnavailable,
        '日历权限通道未注册（当前运行环境无平台引擎）',
        suggestion: '在 Android 设备上运行本壳后重试',
      );
    } on PlatformException catch (e) {
      throw CalendarFeedException(
        e.code,
        '日历权限申请失败：${e.message ?? e.code}',
        suggestion: '检查系统设置是否可正常打开后重试',
      );
    }
    return switch (result) {
      'granted' => CalendarPermissionOutcome.granted,
      'settings_opened' => CalendarPermissionOutcome.settingsOpened,
      _ => throw const CalendarFeedException(
          CalendarErr.parseFailed,
          '日历权限通道返回语义异常（既非 granted 也非 settings_opened）',
        ),
    };
  }
}
