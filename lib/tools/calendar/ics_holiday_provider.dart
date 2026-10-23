// ICS 驱动的节假日来源（替代内置写死表）：从用户订阅的「节假日」ICS feed 事件
// 生成 [HolidayEntry]，注入到日历 UI 与 system_pim 命令面（节假日 / 调休工作日推算）。
//
// 设计要点（对应日历改造决策）：
// - 「去写死」：不再默认依赖内置 2026 表 [cnHolidayBundled]；节假日数据完全来自
//   用户 ICS 导入——未订阅 / 未命中「节假日」feed 时回落 [EmptyHolidayProvider]
//   （空表，workdays 仅跳过周末，绝不编造官方放假 / 补班判断）。
// - 「专用节假日 feed」：feed 名称包含 [feedNameHint]（默认『节假日』）即视为节假日源；
//   其余 feed（普通日程 / 系统日历）不渲染橙色日号与班标。
// - 补班日判定：节假日 feed 中事件标题含 [workdayHints]（『调休』/『补班』/『班』）
//   之一判为调休补班（workday），否则为法定假（holiday）。
//
// 同步接口 [between] 由内存缓存支撑；缓存经 [warm] 异步预热（ICS 源已本地缓存，
// 预热很快）。[between] 在未预热区间返回空（fail-closed，不返回陈旧 / 编造条目）。
library;

import 'dart:developer';

import '../../mcp/calendar_provider.dart';

/// ICS 驱动的节假日 / 调休来源：从指定 ICS feed 事件生成 [HolidayEntry]。
class IcsHolidayProvider implements HolidayProvider {
  IcsHolidayProvider(
    this._feeds, {
    this.feedNameHint = '节假日',
    this.workdayHints = const <String>{'调休', '补班', '班'},
  });

  final CalendarFeedProvider _feeds;

  /// feed 名称包含该串即视为节假日源（默认『节假日』）。
  final String feedNameHint;

  /// 标题含这些串之一即判定为调休补班（workday），否则为法定假（holiday）。
  final Set<String> workdayHints;

  final Map<String, HolidayEntry> _byDate = <String, HolidayEntry>{};

  DateTime? _warmStart;

  String _version = 'ics-holiday:unwarmed';

  @override
  String get version => _version;

  /// 异步预热：拉取 [from, to] 区间内「节假日」feed 的 ICS 事件，建立按日缓存。
  ///
  /// 缺省窗口 = 当前年前后各 2 年（覆盖绝大多数查询）；可显式传入以缩小开销。
  /// C1 约束：源层 `query` 跨度上限 90 天，故内部按 ≤90 天切片查询。
  ///
  /// 源不可用 / 无「节假日」feed 时**不抛**：记 [DEGRADE] 日志并保留空表
  /// （fail-closed，不编造放假 / 补班判断）。
  Future<void> warm({DateTime? from, DateTime? to}) async {
    // 运行时源预热窗口中心；此处 DateTime.now() 属 I/O 适配层，非 F1 纯计算纪律范围。
    final int y = DateTime.now().year;
    final start = from ?? DateTime.utc(y - 2, 1, 1);
    final end = to ?? DateTime.utc(y + 2, 12, 31);

    try {
      final allFeeds = await _feeds.feeds();
      final ids = allFeeds
          .where((f) => f.name.contains(feedNameHint))
          .map((f) => f.id)
          .toList();
      if (ids.isEmpty) {
        // UNCERTAIN: 未发现名称含『节假日』的订阅源——节假日标记整体回落空表。
        // 用户需订阅名称含该关键词的 ICS（如中国法定节假日源）才会生效。
        _version = 'ics-holiday:none';
        return;
      }

      // 切片查询（C1：单段 ≤90 天）。
      var cursor = start;
      while (!cursor.isAfter(end)) {
        final segEnd = cursor.add(const Duration(days: 89));
        final sliceEnd = segEnd.isAfter(end) ? end : segEnd;
        final result = await _feeds.query(
          rangeStart: _iso(cursor),
          rangeEnd: _iso(sliceEnd),
          includeSystem: false,
          feedIds: ids,
        );
        for (final e in result.events) {
          final key = e.start.length >= 10 ? e.start.substring(0, 10) : e.start;
          final isWorkday = workdayHints.any((h) => e.title.contains(h));
          _byDate[key] = HolidayEntry(
            date: key,
            name: e.title,
            type: isWorkday ? 'workday' : 'holiday',
          );
        }
        cursor = sliceEnd.add(const Duration(days: 1));
      }
      _warmStart = start;
      _version = 'ics-holiday:${DateTime.now().toUtc().toIso8601String()}';
    } on CalendarFeedException catch (e) {
      // DEGRADE: 节假日源不可用 → 空表 fallback（不编造），记日志不静默。
      _version = 'ics-holiday:error';
      log('[DEGRADE] IcsHolidayProvider.warm 源不可用：${e.code} ${e.message}',
          name: 'IcsHolidayProvider');
    } catch (e) {
      _version = 'ics-holiday:error';
      log('[DEGRADE] IcsHolidayProvider.warm 失败：$e',
          name: 'IcsHolidayProvider');
    }
  }

  @override
  List<HolidayEntry> between(String startDate, String endDate) {
    if (_warmStart == null) {
      // UNCERTAIN: 尚未预热——返回空，不编造（调用方应已触发 warm）。
      return const <HolidayEntry>[];
    }
    final out = <HolidayEntry>[];
    _byDate.forEach((k, v) {
      if (k.compareTo(startDate) >= 0 && k.compareTo(endDate) <= 0) out.add(v);
    });
    return out;
  }

  static String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
