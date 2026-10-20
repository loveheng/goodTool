/// 日历能力端口（依赖反转接缝，arch-guard R4 无头约束）。
///
/// 内核（MCP 工具面 / 业务编排）只依赖以下抽象接口，不碰 `dart:io`、不直连
/// 系统日历 ContentProvider；具体实现（ICS 拉取与 RFC 5545 解析、系统日历读取、
/// 标记持久化）由 service 层注入，保证无设备、无网络环境下用 Mock 走通确定性单测。
///
/// 模式对齐 [WeatherProvider] / [GeoHttpProvider]；契约正文见 `docs/product/calendar.md`。
library;

/// 订阅源刷新周期下限（分钟）。tools 层前置校验与 service 层 Actor 共用，
/// 避免两侧魔法数漂移。
const int calendarMinRefreshMin = 5;

/// **C1**：查询跨度硬上限（天）。超限报 `ERR_RANGE_TOO_WIDE`，不静默截断。
/// tools 层与 `IcsFeedProvider` 双层复检共用本常量。
const int calendarMaxRangeDays = 90;

/// feed 列表持久化键（SettingsKv，JSON 数组）。Actor（service 层）与
/// `IcsFeedProvider` 共用同一键，避免两侧各存一份导致读到不同列表。
const String kCalendarFeedsKey = 'calendar_feeds';

/// ICS 原文缓存键前缀（`ics_body_<feedId>`）。G3：`unsubscribe` 必须清该前缀缓存。
const String kIcsBodyPrefix = 'ics_body_';

/// 上次同步时间键前缀（`ics_sync_<feedId>`），`lastSyncTime` 与 G2 频控共用。
const String kIcsSyncPrefix = 'ics_sync_';

/// 订阅源刷新周期上限（分钟，1 周）。
const int calendarMaxRefreshMin = 10080;

/// 默认刷新周期（分钟，12 小时）。
const int calendarDefaultRefreshMin = 720;

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

  /// 标记 id 不存在（日历 warnings 一律明确错误，Agent 无权凭空操作）。
  static const markerNotFound = 'ERR_MARKER_NOT_FOUND';

  /// 系统日历未授权 READ_CALENDAR（P2-⑦：fail-closed，不返回空列表假装无日程）。
  static const permissionDenied = 'ERR_CALENDAR_PERMISSION';
}

/// 设备时区端口（calendar.md 时区治理 **B1 基准链**）：
///
/// ```
/// 用户设置 calendar.timezone → 设备时区（本端口）→ UTC
/// ```
///
/// 端口住内核（依赖反转接缝）：真实设备时区由装配件 / 平台层注入；
/// 无头测试与缺省装配走 [UtcTimezoneProvider]（确定性，F1 纪律）。
abstract class DeviceTimezoneProvider {
  /// IANA 时区名（如 `Asia/Shanghai`）。
  String get timezone;
}

/// B1 链终值：UTC。无头壳未接入平台时区通道前的缺省——**显式 UTC 而非假装本地**，
/// 出参 `timezone` 字段回写让 Agent 可知判断依据（与 `holidayTableVersion` 同一口径）。
class UtcTimezoneProvider implements DeviceTimezoneProvider {
  const UtcTimezoneProvider();

  @override
  String get timezone => 'UTC';
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

// ---------------------------------------------------------------------------
// 系统日历源端口（P2-⑦ source: system）
// ---------------------------------------------------------------------------

/// 系统日历原始事件（平台通道回传的**未脱敏**原始视图；数据类住内核，纯 Dart）。
///
/// [start] / [end] 由平台层格式化为 ISO 8601：
/// 全天事件为 `YYYY-MM-DD`（B2 浮当日界，end 已做排他日回退）；定时事件带显式
/// offset（B3，如 `2026-10-20T08:00:00+08:00`）——时区换算住平台层（设备本地
/// 时区是唯一事实来源），内核不做二次解释。
class SystemCalendarRawEvent {
  const SystemCalendarRawEvent({
    required this.uid,
    required this.calendarName,
    required this.title,
    required this.start,
    required this.end,
    required this.isAllDay,
    this.location,
    this.description,
  });

  /// 事件行 id（`CalendarContract.Instances.EVENT_ID`；同一事件跨天 RRULE
  /// 会出现多实例，uid 由合并层加日期后缀保证唯一）。
  final String uid;
  final String calendarName;
  final String title;
  final String start;
  final String end;
  final bool isAllDay;
  final String? location;
  final String? description;
}

/// 系统日历读取端口（依赖反转接缝，与 [DeviceTimezoneProvider] 同模式）。
///
/// 内核不沾平台 API：真实实现（MethodChannel → CalendarContract）由 service
/// 层注入；无头测试用桩。实现须 **fail-closed**：未授权 / 引擎缺位时抛
/// [CalendarFeedException]（code = `ERR_CALENDAR_PERMISSION` /
/// `ERR_CALENDAR_SOURCE_UNAVAILABLE`），不得返回空列表假装「无日程」。
abstract class SystemCalendarPort {
  /// 区间查询（`YYYY-MM-DD`，含首尾日）。
  Future<List<SystemCalendarRawEvent>> readEvents({
    required String rangeStart,
    required String rangeEnd,
  });
}

/// 查询结果：事件全量 + 子源 warnings（部分失败显式化，不静默降级）。
class CalendarQueryResult {
  const CalendarQueryResult(
    this.events, {
    this.warnings = const <Map<String, Object?>>[],
  });

  /// 全量事件（`start → uid` 排序）。
  final List<CalendarEvent> events;

  /// 子源失败清单（元素含 `source` / `code` / `message`）。
  /// 非空时调用方必须原样透出到出参——静默丢弃即降级（ai-sideeffect-guard）。
  final List<Map<String, Object?>> warnings;
}

/// 源层失败信号（携带机器码；工具层 / Actor 捕获后转结构化错误，不把堆栈漏给 Agent）。
class CalendarFeedException implements Exception {
  const CalendarFeedException(this.code, this.message, {this.suggestion});
  final String code;
  final String message;
  final String? suggestion;
  @override
  String toString() => 'CalendarFeedException($code): $message';
}

/// 事件源端口（P2-④ 真实源：ICS 拉取 + RFC 5545 解析 + RRULE 展开 + 脱敏）。
abstract class CalendarFeedProvider {
  /// 按区间查询事件（C1 区间上限、C2 EXDATE/RECURRENCE-ID、D1 固定排序）。
  ///
  /// 返回**全量**（按 `start → uid` 排序）；分页截断与 `hasMore` 由调用方处理
  /// （limit 不进端口——截断语义属于工具层，源层留全量便于二次过滤）。
  /// 子源失败以 [CalendarQueryResult.warnings] 显式透出，不静默丢路。
  Future<CalendarQueryResult> query({
    required String rangeStart,
    required String rangeEnd,
    String? timezone,
    List<String>? feedIds,
    bool includeSystem = true,
  });

  /// 列出系统源与订阅源。
  Future<List<CalendarFeed>> feeds();

  /// 强制同步；返回成功刷新的源数。[feedId] 为空表示全部。
  /// 频控（G2）命中抛 [CalendarFeedException]（code = `ERR_RATE_LIMITED`）。
  Future<int> refresh({String? feedId});
}

/// 标记存储端口（用户私有 store；**写必经 CommandGateway**，本端口只读）。
abstract class CalendarMarkerStore {
  Future<List<CalendarMarker>> list({
    required String rangeStart,
    required String rangeEnd,
    String? category,
  });
}

/// 标记**写**端口：只给命令 Actor（service 层）用——工具层/子操作不得持有，
/// 否则写路径绕过 CommandGateway（R1 / G3）。
abstract class CalendarMarkerWriter {
  /// 新增标记，返回 `markerId`。
  ///
  /// [baseYear] 缺省时从 [originalDate] 的完整年份派生；仅当传入无年份格式
  /// （`MM-DD`）时调用方必须显式提供（calendar.md「originalDate 为年份单一真相源」）。
  Future<String> addMarker({
    required String originalDate,
    required String title,
    required String category,
    int? baseYear,
    bool isAnnual,
    bool isLunar,
    String leapPolicy,
  });

  /// 删除标记；返回是否确实删除（幂等语义由调用方决定）。
  Future<bool> deleteMarker(String markerId);
}

// ---------------------------------------------------------------------------
// 订阅 URL 护栏（calendar.md「两道硬控制」①，安全关键）
// ---------------------------------------------------------------------------
// 住**内核**而非 tools 层：命令 Actor（service 层）也要复用——而 standards §1 里
// `service` 出向只含 `mcp`/`action`，不得 import `tools`；护栏放内核两侧均可复用。
//
// 纪律：URL 必须是**调用方显式传入的参数**，禁止 Agent 自造或「建议」订阅地址；
// 校验在命令执行器内执行（C3 + SSRF 防护），不在工具层拦完就放行。
//
// 内核纯 Dart：刻意**不使用 `dart:io` 的 `InternetAddress`**——地址判定走字符串
// 与正则即可覆盖 RFC 1918 / 回环 / 链路本地，守住「内核不沾平台 API」。

/// 护栏结论：通过带规整后的 [uri]，拒绝带机器码与说明。
class UrlGuardResult {
  const UrlGuardResult.ok(this.uri)
      : code = null,
        message = null;
  const UrlGuardResult.reject(this.code, this.message) : uri = null;

  final Uri? uri;
  final String? code;
  final String? message;

  bool get ok => uri != null;
}

/// 规整并校验订阅 URL：
/// ① `webcal://` → `https://` 后**强制 HTTPS**，拒绝 `http` 明文回退（C3）；
/// ② 拒绝回环 / 私网 / 链路本地地址（防 SSRF 拉内网 ICS）。
UrlGuardResult guardCalendarUrl(Object? raw) {
  if (raw is! String || raw.trim().isEmpty) {
    return const UrlGuardResult.reject('MISSING_ARGUMENT', '缺少必填参数 url');
  }
  final parsed = Uri.tryParse(raw.trim());
  if (parsed == null) {
    return const UrlGuardResult.reject(
        'ERR_INVALID_URL', 'URL 无法解析：仅接受 https / webcal');
  }
  final scheme = parsed.scheme.toLowerCase();
  final Uri uri;
  switch (scheme) {
    case 'webcal':
      // C3 协议规整：webcal 仅作「这是个日历」的语义标记，传输必须 HTTPS。
      uri = parsed.replace(scheme: 'https');
    case 'https':
      uri = parsed;
    case 'http':
      return const UrlGuardResult.reject(
          'ERR_INVALID_URL', '拒绝明文 http：webcal 已规整为 https，禁止降级回退');
    default:
      return UrlGuardResult.reject(
          'ERR_INVALID_URL', '不支持的协议：$scheme（仅接受 https / webcal）');
  }
  if (uri.host.isEmpty) {
    return const UrlGuardResult.reject('ERR_INVALID_URL', 'URL 缺少主机名');
  }
  if (isForbiddenHost(uri.host)) {
    return UrlGuardResult.reject('ERR_INVALID_URL',
        '拒绝回环 / 私网 / 链路本地地址（SSRF 护栏）：${uri.host}');
  }
  return UrlGuardResult.ok(uri);
}

/// 回环与私网判定（IPv4 / IPv6 / 主机名）。
bool isForbiddenHost(String host) {
  var h = host.toLowerCase().trim();
  // IPv6 字面量形如 [::1]
  if (h.startsWith('[') && h.endsWith(']')) h = h.substring(1, h.length - 1);

  if (h == 'localhost' || h.endsWith('.localhost')) return true;
  if (h == '::1' || h == '0.0.0.0' || h == '::') return true;
  if (h.startsWith('::ffff:')) return true; // IPv4-mapped，一律按私网处理

  final v4 = RegExp(r'^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$').firstMatch(h);
  if (v4 != null) {
    final o = <int>[
      int.parse(v4.group(1)!),
      int.parse(v4.group(2)!),
      int.parse(v4.group(3)!),
      int.parse(v4.group(4)!),
    ];
    if (o.any((x) => x > 255)) return true; // 非法 IPv4 字面量
    if (o[0] == 0 || o[0] == 10 || o[0] == 127) return true; // 本网 / 私网 / 回环
    if (o[0] == 172 && o[1] >= 16 && o[1] <= 31) return true; // 172.16.0.0/12
    if (o[0] == 192 && o[1] == 168) return true; // 192.168.0.0/16
    if (o[0] == 169 && o[1] == 254) return true; // 链路本地 169.254.0.0/16
    return false;
  }

  if (h.contains(':')) {
    // IPv6：取首个 hextet 判 fe80::/10（链路本地）与 fc00::/7（唯一本地）。
    final head = h.split(':').first;
    final hextet = int.tryParse(head, radix: 16);
    if (hextet == null) return true;
    if (hextet >= 0xfe80 && hextet <= 0xfebf) return true;
    if (hextet >= 0xfc00 && hextet <= 0xfdff) return true;
  }
  return false;
}
