// ICS 驱动的节假日来源（替代内置写死表）：从用户订阅的 ICS 事件生成 [HolidayEntry]，
// 注入到日历 UI 与 system_pim 命令面（节假日 / 调休工作日推算）。
//
// 设计要点（对应日历改造决策）：
// - 「去写死」：不再默认依赖内置 2026 表 [cnHolidayBundled]；节假日数据完全来自
//   用户订阅的在线 ICS——未订阅任何含节假日 / 调休标记的源时回落 [EmptyHolidayProvider]
//   （空表，workdays 仅跳过周末，绝不编造官方放假 / 补班判断）。
// - 「按内容渲染，不做源特判」：扫描**所有订阅 ICS**（不含系统日历），逐事件按标题
//   分类——含 [workdayHints]（『调休』/『补班』/『班』）判为调休补班（workday），
//   含 [holidayHints]（『假期』/『休』/『放假』/『法定』）判为法定假（holiday），
//   两者都不含的事件不当作节假日标记（避免把普通日程 / 节气 / 赛事误染）。
//   不再要求 feed 名称含『节假日』这类特判（用户订阅即按规范渲染）。
//
// 同步接口 [between] 由内存缓存支撑；缓存经 [warm] 异步预热（ICS 源已本地缓存，
// 预热很快）。[between] 在未预热区间返回空（fail-closed，不返回陈旧 / 编造条目）。
library;

import 'dart:developer';

import '../../mcp/calendar_provider.dart';

/// ICS 驱动的节假日 / 调休来源：从订阅 ICS 事件生成 [HolidayEntry]。
class IcsHolidayProvider implements HolidayProvider {
  IcsHolidayProvider(
    this._feeds, {
    this.workdayHints =
        const <String>{'调休', '补班', '班', '串休', '倒休', '换休', '上班'},
    this.holidayHints = const <String>{
      '假期',
      '休',
      '放假',
      '法定',
      '节假日',
    },
  });

  final CalendarFeedProvider _feeds;

  /// 标题含这些串之一即判定为调休补班（workday）。
  final Set<String> workdayHints;

  /// 标题含这些串之一即判定为法定假（holiday）；与 [workdayHints] 都不含的事件
  /// 不当作节假日标记（防误染普通日程 / 节气 / 赛事）。
  final Set<String> holidayHints;

  final Map<String, HolidayEntry> _byDate = <String, HolidayEntry>{};

  DateTime? _warmStart;

  String _version = 'ics-holiday:unwarmed';

  @override
  String get version => _version;

  /// 异步预热：扫描 [from, to] 区间内**所有订阅 ICS**（不含系统日历）的事件，
  /// 按标题内容分类为法定假 / 调休补班，建立按日缓存。
  ///
  /// 缺省窗口 = 当前年前后各 2 年（覆盖绝大多数查询）；可显式传入以缩小开销。
  /// C1 约束：源层 `query` 跨度上限 90 天，故内部按 ≤90 天切片查询。
  ///
  /// 源不可用 / 无命中节假日标记时**不抛**：记 [DEGRADE] 日志并保留空表
  /// （fail-closed，不编造放假 / 补班判断）。
  Future<void> warm({DateTime? from, DateTime? to}) async {
    // 运行时源预热窗口中心；此处 DateTime.now() 属 I/O 适配层，非 F1 纯计算纪律范围。
    final int y = DateTime.now().year;
    final start = from ?? DateTime.utc(y - 2, 1, 1);
    final end = to ?? DateTime.utc(y + 2, 12, 31);

    try {
      // 切片查询（C1：单段 ≤90 天）；[feedIds] 不传 = 所有订阅 ICS，
      // [includeSystem] = false 排除系统日历（其普通日程不当作节假日标记）。
      var cursor = start;
      while (!cursor.isAfter(end)) {
        final segEnd = cursor.add(const Duration(days: 89));
        final sliceEnd = segEnd.isAfter(end) ? end : segEnd;
        final result = await _feeds.query(
          rangeStart: _iso(cursor),
          rangeEnd: _iso(sliceEnd),
          includeSystem: false,
        );
        for (final e in result.events) {
          final key = e.start.length >= 10 ? e.start.substring(0, 10) : e.start;
          // 仅按 SUMMARY（标题）分类，**不**扫描 DESCRIPTION：本 ICS（YangH9）每个
          // 假期事件的 DESCRIPTION 都会列出补班安排（如「9月28日、10月11日上班」含『班』），
          // 若把描述也纳入判定，『班』会命中整个国庆 / 劳动节 / 春节假期，把它们误判为
          // 调休补班（workday）。补班事件标题自带『补班』、假期事件标题自带『假期』，
          // 标题已足够区分，描述只作展示（description 字段）不参与休/班判定。
          final text = e.title;
          final isWorkday = workdayHints.any((h) => text.contains(h));
          final isHoliday =
              !isWorkday && holidayHints.any((h) => text.contains(h));
          // 两者都不含 → 非节假日事件，跳过（不误染普通日程 / 节气 / 赛事）。
          if (!isWorkday && !isHoliday) continue;
          _byDate[key] = HolidayEntry(
            date: key,
            name: e.title,
            type: isWorkday ? 'workday' : 'holiday',
            description: e.description,
          );
        }
        cursor = sliceEnd.add(const Duration(days: 1));
      }
      _warmStart = start;
      _version = _byDate.isEmpty
          ? 'ics-holiday:none'
          : 'ics-holiday:${DateTime.now().toUtc().toIso8601String()}';
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
