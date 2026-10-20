library;

/// 日历 W 档命令族（calendar.md 授权模型 A：用户委托写，仅已鉴权 MCP 会话可用）。
///
/// **G3 / arch-guard R7 纪律**：命令只**承载载荷**，鉴权与派发由 `CategoryTool`
/// 网关层统一执行；本文件不出现 dispatch / admits 调用，执行体（Actor）也**不在
/// 本文件**——Actor 住 service 层，由装配件登记进 [CommandGateway]。
///
/// **命令名 = MCP action 名**：`CategoryTool.call` 以 action 名查
/// `CommandGateway.admits`，二者必须同名，否则 W 档一律被拒（fail-closed）。
///
/// 校验职责划分：必填与 URL 护栏（SSRF / 强制 HTTPS）在 **Actor 内**执行，
/// 返回结构化错误码——工具层只负责把载荷原样封成命令（calendar.md「两道硬控制」①）。
import 'command_gateway.dart';

/// 添加订阅源（`calendar_subscribe`）。
class CalendarSubscribeCommand extends Command {
  const CalendarSubscribeCommand(Map<String, Object?> payload)
      : super('calendar_subscribe', payload);
}

/// 移除订阅源（`calendar_unsubscribe`）。
class CalendarUnsubscribeCommand extends Command {
  const CalendarUnsubscribeCommand(Map<String, Object?> payload)
      : super('calendar_unsubscribe', payload);
}

/// 强制即时同步（`calendar_refresh`）。
class CalendarRefreshCommand extends Command {
  const CalendarRefreshCommand(Map<String, Object?> payload)
      : super('calendar_refresh', payload);
}

/// 添加重要事件标记（`calendar_marker_add`）。
class CalendarMarkerAddCommand extends Command {
  const CalendarMarkerAddCommand(Map<String, Object?> payload)
      : super('calendar_marker_add', payload);
}

/// 删除重要事件标记（`calendar_marker_delete`）。
class CalendarMarkerDeleteCommand extends Command {
  const CalendarMarkerDeleteCommand(Map<String, Object?> payload)
      : super('calendar_marker_delete', payload);
}
