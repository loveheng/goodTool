/// 日历能力端口（依赖反转接缝，arch-guard R4 无头约束）。
///
/// 内核（MCP 工具面 / 业务编排）只依赖以下抽象接口，不碰 `dart:io`、不直连
/// 系统日历 ContentProvider；具体实现（ICS 拉取与 RFC 5545 解析、系统日历读取、
/// 标记持久化）由 service 层注入，保证无设备、无网络环境下用 Mock 走通确定性单测。
///
/// 模式对齐 [WeatherProvider] / [GeoHttpProvider]；契约正文见 `docs/product/calendar.md`。
library;

/// 结构化错误码（calendar.md D3 枚举）。
///
/// `ERR_CALENDAR_SOURCE_UNAVAILABLE` 为 P1 阶段新增：源未注入时 **fail-closed**
/// （与 `ERR_AMAP_KEY_MISSING` / `ERR_WEATHER_KEY_MISSING` 同构，standards §1.2），
/// 而非返回空列表假装「查到了但没有」。
abstract final class CalendarErr {
  /// 查询跨度超过 90 天硬上限（C1：不静默截断）。
  static const rangeTooWide = 'ERR_RANGE_TOO_WIDE';

  /// feedId 不存在（G1：Agent 无权凭空操作）。
  static const feedNotFound = 'ERR_FEED_NOT_FOUND';

  /// URL 非法 / 明文 http / 回环与私网地址（SSRF 护栏）。
  static const invalidUrl = 'ERR_INVALID_URL';

  /// ICS 解析失败。
  static const parseFailed = 'ERR_PARSE_FAILED';

  /// 网络异常 / 超时。
  static const network = 'ERR_NETWORK';

  /// 频控（G2：refresh 最小间隔）。
  static const rateLimited = 'ERR_RATE_LIMITED';

  /// 端口实现缺位（P1：ICS / 系统日历 / 农历 / 时区源尚未注入）。
  static const sourceUnavailable = 'ERR_CALENDAR_SOURCE_UNAVAILABLE';
}

/// 节假日与调休条目（F3：版本化表，含 OTA 热更）。
class HolidayEntry {
  const HolidayEntry({
    required this.date,
    required this.name,
    required this.type,
  });

  /// `YYYY-MM-DD`。
  final String date;
  final String name;

  /// `holiday` = 法定节假日；`workday` = 调休补班（周末上班）。
  final String type;
}

/// 节假日表端口：版本化 + 可覆写（测试确定性）+ 支持 OTA 热更。
///
/// **默认实现 [EmptyHolidayProvider] 不编造官方数据**——国务院年度安排须以官方
/// 公布为准，凭记忆填充会造成错误的「今天放假/补班」判断（比不判断更糟）。
/// 真实表导入见域内待办 P2。
abstract class HolidayProvider {
  /// 表版本号（出参回写，使 Agent 可知当前判断依据）。
  String get version;

  /// 区间内的节假日与调休条目。
  List<HolidayEntry> between(String startDate, String endDate);
}

/// 缺省空表：`workdays` 仅跳过周末，`holidays`/`adjustments` 恒为空数组。
class EmptyHolidayProvider implements HolidayProvider {
  const EmptyHolidayProvider();

  @override
  String get version => 'empty-0';

  @override
  List<HolidayEntry> between(String startDate, String endDate) =>
      const <HolidayEntry>[];
}

/// 日历事件（D2 轻量视图：剥离参会人 / 组织者 / 会议状态等会议专属字段）。
class CalendarEvent {
  const CalendarEvent({
    required this.uid,
    required this.title,
    required this.start,
    required this.end,
    this.isAllDay = false,
    this.location,
    this.description,
    this.source = 'feed',
    this.feedId,
    this.feedName,
    this.timezone,
    this.isCached = false,
  });

  final String uid;
  final String title;

  /// ISO 8601 带显式 offset（B3）；全天事件按 B2 浮当地日界。
  final String start;
  final String end;
  final bool isAllDay;
  final String? location;
  final String? description;

  /// `system` | `feed`。
  final String source;
  final String? feedId;
  final String? feedName;
  final String? timezone;
  final bool isCached;

  Map<String, Object?> toJson() => <String, Object?>{
        'uid': uid,
        'title': title,
        'start': start,
        'end': end,
        'isAllDay': isAllDay,
        'location': ?location,
        'description': ?description,
        'source': source,
        'feedId': ?feedId,
        'feedName': ?feedName,
        'timezone': ?timezone,
        'isCached': isCached,
      };
}

/// 订阅源（系统日历 / 在线 ICS）。
class CalendarFeed {
  const CalendarFeed({
    required this.id,
    required this.name,
    required this.url,
    required this.refreshMin,
    this.lastSyncTime,
    this.status = 'ok',
  });

  final String id;
  final String name;

  /// 已规整为 https 的地址（C3：`webcal://` → `https://`）。
  final String url;
  final int refreshMin;
  final String? lastSyncTime;
  final String status;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'name': name,
        'url': url,
        'refreshMin': refreshMin,
        'lastSyncTime': ?lastSyncTime,
        'status': status,
      };
}

/// 重要事件标记（Markers：一等公民，存于用户私有 store，不依赖系统日历）。
class CalendarMarker {
  const CalendarMarker({
    required this.id,
    required this.title,
    required this.originalDate,
    required this.baseYear,
    required this.category,
    this.isAnnual = true,
    this.isLunar = false,
    this.leapPolicy = 'ignoreLeap',
  });

  final String id;
  final String title;

  /// 真实起始日期：`YYYY-MM-DD`（公历）或农历同格式（[isLunar] 为 true）。
  final String originalDate;

  /// 起始年（周年推演基准）。
  final int baseYear;

  /// `birthday` | `anniversary` | `milestone`。
  final String category;
  final bool isAnnual;
  final bool isLunar;

  /// `ignoreLeap` | `strictLeap` | `followRegular`。
  final String leapPolicy;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'title': title,
        'originalDate': originalDate,
        'baseYear': baseYear,
        'category': category,
        'isAnnual': isAnnual,
        'isLunar': isLunar,
        'leapPolicy': leapPolicy,
      };
}

/// 事件源端口（P2 真实源：ICS 拉取 + RFC 5545 解析 + RRULE 展开 + 脱敏）。
abstract class CalendarFeedProvider {
  /// 按区间查询事件（C1 区间上限、C2 EXDATE/RECURRENCE-ID、D1 分页与固定排序）。
  Future<List<CalendarEvent>> query({
    required String rangeStart,
    required String rangeEnd,
    String? timezone,
    List<String>? feedIds,
    int? limit,
  });

  /// 列出系统源与订阅源。
  Future<List<CalendarFeed>> feeds();
}

/// 标记存储端口（用户私有 store；**写必经 CommandGateway**，本端口只读）。
abstract class CalendarMarkerStore {
  Future<List<CalendarMarker>> list({
    required String rangeStart,
    required String rangeEnd,
    String? category,
  });
}
