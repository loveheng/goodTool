library;

import '../mcp/calendar_provider.dart';
import '../mcp/geo_provider.dart';
import '../mcp/mcp_server.dart';
import '../mcp/settings_keys.dart';
import '../repository/settings_repository.dart';
import '../service/mcp_controller.dart';

/// 就绪态（**双通道**：色相 + 文字/图标，ui-design §6 无障碍红线）。
enum ReadinessState {
  /// 正常可用（L1）。
  ready,

  /// 未配置 / 未接入（灰阶）。
  missing,

  /// 被拒（玫瑰）——**禁与 missing 同灰阶混淆**。
  denied,
}

/// 某项能力的就绪条目。
class ReadinessItem {
  const ReadinessItem({
    required this.label,
    required this.state,
    this.detail,
  });

  /// 能力名（定位 / 日历 / 地图 Key / 天气 Key）。
  final String label;

  final ReadinessState state;

  /// 补充说明（人话中文；禁直出内部英文相位名）。
  final String? detail;
}

/// MCP 服务状态视图。
class ServiceStatusView {
  const ServiceStatusView({
    required this.running,
    required this.port,
    required this.endpoint,
    required this.hasToken,
    this.lastError,
  });

  final bool running;
  final int port;
  final String endpoint;
  final bool hasToken;
  final String? lastError;
}

/// 实时调用事件视图（内核 `McpCallEvent` → UI 视图模型）。
class CallEventView {
  const CallEventView({
    required this.name,
    required this.ts,
    required this.elapsedMs,
    required this.ok,
  });

  final String name;
  final int ts;
  final int elapsedMs;
  final bool ok;

  /// 时间戳格式化（本地 `HH:mm:ss`，遥测轨等宽渲染）。
  String get timeText {
    final d = DateTime.fromMillisecondsSinceEpoch(ts);
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(d.hour)}:${two(d.minute)}:${two(d.second)}';
  }
}

/// 仪表盘适配层：服务状态 + 权限/配置就绪矩阵 + 实时调用流。
class StatusPort {
  const StatusPort({
    required this.controller,
    required this.repository,
    required this.location,
    required this.feeds,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final McpController controller;
  final SettingsRepository repository;
  final LocationSensorProvider location;
  final CalendarFeedProvider? feeds;

  /// 时钟注入口（单测可注入固定时钟，保证就绪探测可确定性断言）。
  final DateTime Function() _clock;

  /// 服务状态快照。
  ServiceStatusView service() => ServiceStatusView(
        running: controller.running,
        port: controller.port,
        endpoint: controller.endpoint,
        hasToken: (controller.token ?? '').isNotEmpty,
        lastError: controller.lastError,
      );

  /// 实时调用流（类型化；内核侧吐事件，UI 侧 `StreamBuilder` 接）。
  Stream<CallEventView> get callEvents =>
      controller.callEvents.map(_toView);

  static CallEventView _toView(McpCallEvent e) => CallEventView(
        name: e.name,
        ts: e.ts,
        elapsedMs: e.elapsedMs,
        ok: e.ok,
      );

  /// 权限 / 配置就绪矩阵。
  ///
  /// 定位项**不探测**（探测会触发系统权限弹窗）——只判定真实定位源是否已接入；
  /// 日历项探测**当天**区间，子源未授权会在 `warnings` 里显式回
  /// `ERR_CALENDAR_PERMISSION`，据此区分「被拒」与「未配置」。
  Future<List<ReadinessItem>> readiness() async {
    final items = <ReadinessItem>[];

    final locationReady = location is! NullLocationSensorProvider;
    items.add(ReadinessItem(
      label: '定位',
      state: locationReady ? ReadinessState.ready : ReadinessState.missing,
      detail: locationReady
          ? '已接入定位源'
          : '未接入真实定位源（定位类动作恒返 PERMISSION_DENIED）',
    ));

    items.add(await _calendarReadiness());

    final snapshot = await repository.readSnapshot();
    final amapReady = snapshot.isConfigured(SettingsKeys.amapWebKey);
    items.add(ReadinessItem(
      label: '地图 Key',
      state: amapReady ? ReadinessState.ready : ReadinessState.missing,
      detail: amapReady ? '高德 Key 已配置' : '未配置高德 Key（地理动作不可用）',
    ));
    final qweatherKeyReady = snapshot.isConfigured(SettingsKeys.qweatherKey);
    final qweatherHostReady =
        snapshot.plainValues.containsKey(SettingsKeys.qweatherHost);
    final qweatherReady = qweatherKeyReady && qweatherHostReady;
    items.add(ReadinessItem(
      label: '天气',
      state: qweatherReady ? ReadinessState.ready : ReadinessState.missing,
      detail: qweatherReady
          ? '和风 Key 与 Host 已配置'
          : !qweatherKeyReady
              ? '未配置和风 Key（天气动作不可用）'
              : '未配置和风账号专属 Host（2024 起必填，天气动作不可用）',
    ));
    return items;
  }

  Future<ReadinessItem> _calendarReadiness() async {
    final provider = feeds;
    if (provider == null) {
      return const ReadinessItem(
        label: '日历',
        state: ReadinessState.missing,
        detail: '未注入日历源',
      );
    }
    final now = _clock();
    String two(int v) => v.toString().padLeft(2, '0');
    final today =
        '${now.year}-${two(now.month)}-${two(now.day)}';
    try {
      final result = await provider.query(
        rangeStart: today,
        rangeEnd: today,
        includeSystem: true,
      );
      final denied = result.warnings.any((w) =>
          w['code'] == CalendarErr.permissionDenied ||
          w['code'] == CalendarErr.sourceUnavailable);
      if (denied) {
        final warning = result.warnings.firstWhere(
          (w) =>
              w['code'] == CalendarErr.permissionDenied ||
              w['code'] == CalendarErr.sourceUnavailable,
        );
        return ReadinessItem(
          label: '日历',
          state: _isDenied(warning['code'])
              ? ReadinessState.denied
              : ReadinessState.missing,
          detail: '${warning['code']}：${warning['message']}',
        );
      }
      return const ReadinessItem(
        label: '日历',
        state: ReadinessState.ready,
        detail: '日历源可读',
      );
    } catch (e) {
      // DEGRADE: [readiness_probe] 就绪探测失败按「缺失」呈现——非数据面
      // （只影响状态展示，不丢用户数据、不写用户资产），故不阻断主链路。
      return ReadinessItem(
        label: '日历',
        state: ReadinessState.missing,
        detail: '日历源不可用（$e）',
      );
    }
  }

  static bool _isDenied(Object? code) => code == CalendarErr.permissionDenied;
}
