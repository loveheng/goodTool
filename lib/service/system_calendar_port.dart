// 系统日历读取端口的真实实现（P2-⑦）：MethodChannel → Android CalendarContract。
//
// 落点依据 standards §1.3「新平台能力 → service + Provider 端口」：平台通道细节住
// 本层，内核只见 [SystemCalendarPort] 抽象（arch-guard R4：services 非 UI 依赖，
// 无头内核不沾 Flutter）。
//
// fail-closed 纪律（standards §1.2）：所有平台侧失败都转 [CalendarFeedException]
// 携带机器码透出——未授权 `ERR_CALENDAR_PERMISSION`、引擎/通道缺位
// `ERR_CALENDAR_SOURCE_UNAVAILABLE`——**绝不返回空列表假装「无日程」**。
library;

import 'package:flutter/services.dart';

import '../mcp/calendar_provider.dart';

/// 与 Kotlin 侧 `SystemCalendarChannel.kt` 保持一致的通道名（勿单方改动）。
const MethodChannel kSystemCalendarChannel =
    MethodChannel('com.goodhub.goodtools/calendar');

class MethodChannelSystemCalendarPort implements SystemCalendarPort {
  const MethodChannelSystemCalendarPort();

  @override
  Future<List<SystemCalendarRawEvent>> readEvents({
    required String rangeStart,
    required String rangeEnd,
  }) async {
    final Object? result;
    try {
      result = await kSystemCalendarChannel.invokeMethod<Object?>(
        'queryEvents',
        <String, String>{'rangeStart': rangeStart, 'rangeEnd': rangeEnd},
      );
    } on MissingPluginException {
      throw const CalendarFeedException(
        CalendarErr.sourceUnavailable,
        '系统日历通道未注册（当前运行环境无平台引擎）',
        suggestion: '在 Android 设备上运行本壳后重试',
      );
    } on PlatformException catch (e) {
      // 平台侧机器码映射：权限未授权单列（引导授权），其余归源不可用。
      final code = e.code == 'PERMISSION_DENIED'
          ? CalendarErr.permissionDenied
          : CalendarErr.sourceUnavailable;
      throw CalendarFeedException(code, '系统日历读取失败：${e.message ?? e.code}');
    }
    if (result is! List) {
      throw const CalendarFeedException(
          CalendarErr.parseFailed, '系统日历通道返回格式异常（非数组）');
    }
    return result.map(_fromMap).toList();
  }

  SystemCalendarRawEvent _fromMap(Object? raw) {
    if (raw is! Map) {
      throw const CalendarFeedException(
          CalendarErr.parseFailed, '系统日历通道返回条目格式异常');
    }
    final m = Map<String, Object?>.from(raw);
    final uid = m['uid'];
    final calendarName = m['calendarName'];
    final title = m['title'];
    final start = m['start'];
    final end = m['end'];
    if (uid is! String ||
        calendarName is! String ||
        title is! String ||
        start is! String ||
        end is! String) {
      throw const CalendarFeedException(
          CalendarErr.parseFailed, '系统日历通道返回条目缺必填字段');
    }
    return SystemCalendarRawEvent(
      uid: uid,
      calendarName: calendarName,
      title: title,
      start: start,
      end: end,
      isAllDay: m['isAllDay'] == true,
      location: m['location'] is String ? m['location'] as String : null,
      description:
          m['description'] is String ? m['description'] as String : null,
    );
  }
}
