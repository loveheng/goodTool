library;

import '../action/calendar_commands.dart';
import '../action/command_gateway.dart';
import '../mcp/calendar_provider.dart';
import '../service/composite_calendar_provider.dart';

/// 日历 ICS 订阅管理端口（App 设置页用）：**读经 Provider、写经网关**。
///
/// - 列表读经 [CalendarFeedProvider]（R5：UI 不直连 KV / Db，只读端口取类型化对象）；
/// - 增删/刷新经 [CommandGateway] 用户侧注册表（R1：唯一写入口；R2：回类型化
///   [UserCommandResult]，UI 不 jsonDecode）。
///
/// 与 [CalendarPort]（日历只读视图）的分工：本端口管「订阅源本身的增删管理」，
/// 那个端口管「日程密度 / 当日快照」读取——前者是设置面，后者是浏览面。
class CalendarFeedPort {
  const CalendarFeedPort(this._gateway, this._provider);

  final CommandGateway _gateway;
  final CalendarFeedProvider? _provider;

  /// 列出用户订阅的 ICS 源（剔除系统日历伪源 `system`）。
  ///
  /// 无真实源（未装配）时回落空表（fail-closed，不假装已订阅）。
  Future<List<CalendarFeed>> listFeeds() async {
    final provider = _provider;
    if (provider == null) return const <CalendarFeed>[];
    final all = await provider.feeds();
    return all.where((f) => f.id != kSystemCalendarFeedId).toList();
  }

  /// 订阅一个在线 ICS 源（URL 须 https、非私网/回环，SSRF 护栏在 Actor 内复检）。
  Future<UserCommandResult> subscribe({
    required String url,
    String? name,
    int? refreshMin,
  }) {
    final args = <String, Object?>{'url': url};
    if (name != null) args['name'] = name;
    if (refreshMin != null) args['refreshMin'] = refreshMin;
    return _gateway.dispatchUser(CalendarSubscribeCommand(args));
  }

  /// 退订（清 ICS 缓存与同步时间戳在 Actor 内完成，G3）。
  Future<UserCommandResult> unsubscribe(String feedId) =>
      _gateway.dispatchUser(
        CalendarUnsubscribeCommand(<String, Object?>{'feedId': feedId}),
      );

  /// 强制即时同步（[feedId] 为空 = 全部）；无真实源时 Actor fail-closed。
  Future<UserCommandResult> refresh([String? feedId]) {
    final args = <String, Object?>{};
    if (feedId != null) args['feedId'] = feedId;
    return _gateway.dispatchUser(CalendarRefreshCommand(args));
  }
}
