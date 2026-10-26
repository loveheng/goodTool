// IcsHolidayProvider 回归测试：从 YangH9 风格 ICS 复现「假期被误判为补班」的 bug。
//
// 关键结构：每个假期事件（SUMMARY 含『假期』）的 DESCRIPTION 都会列出补班安排
// （如「9月28日、10月11日上班」含『班』），而补班事件（SUMMARY 含『补班』）独立存在。
// 分类必须只看 SUMMARY（标题），否则『班』会命中整个国庆 / 劳动节假期，误判为 workday。
import 'package:flutter_test/flutter_test.dart';
import 'package:goodtools/mcp/calendar_provider.dart';
import 'package:goodtools/tools/calendar/ics_holiday_provider.dart';

/// 事件源桩：返回 YangH9 风格的事件——假期事件描述里带『上班』补班说明。
class _YangH9Feeds implements CalendarFeedProvider {
  @override
  Future<CalendarQueryResult> query({
    required String rangeStart,
    required String rangeEnd,
    String? timezone,
    List<String>? feedIds,
    bool includeSystem = true,
  }) async {
    const makeup = '9月28日（周日）、10月11日（周六）上班。';
    const makeup51 = '4月27日（周日）上班。';
    return CalendarQueryResult(<CalendarEvent>[
      // 国庆假期（描述含『上班』）
      CalendarEvent(
        uid: 'g1',
        title: '「国庆节、中秋节 假期」 第1天/共8天',
        start: '2026-10-01',
        end: '2026-10-02',
        description: '六、国庆节、中秋节：10月1日至8日放假调休，共8天。$makeup',
      ),
      CalendarEvent(
        uid: 'g2',
        title: '「国庆节、中秋节 假期」 第8天/共8天',
        start: '2026-10-08',
        end: '2026-10-09',
        description: '六、国庆节、中秋节：10月1日至8日放假调休，共8天。$makeup',
      ),
      // 国庆补班（独立事件）
      CalendarEvent(
        uid: 'g3',
        title: '「国庆节、中秋节 补班」 第1天/共2天',
        start: '2026-09-28',
        end: '2026-09-28',
        description: '六、国庆节、中秋节：10月1日至8日放假调休，共8天。$makeup',
      ),
      // 劳动节假期（描述含『上班』）
      CalendarEvent(
        uid: 'l1',
        title: '「劳动节 假期」 第1天/共5天',
        start: '2026-05-01',
        end: '2026-05-02',
        description: '四、劳动节：5月1日至5日放假调休，共5天。$makeup51',
      ),
      CalendarEvent(
        uid: 'l2',
        title: '「劳动节 补班」 第1天/共1天',
        start: '2026-04-27',
        end: '2026-04-27',
        description: '四、劳动节：5月1日至5日放假调休，共5天。$makeup51',
      ),
    ]);
  }

  @override
  Future<List<CalendarFeed>> feeds() async => const <CalendarFeed>[];

  @override
  Future<int> refresh({String? feedId}) async => 0;
}

void main() {
  group('IcsHolidayProvider 分类正确性', () {
    test('假期事件（描述含「上班」）判为 holiday，不误判为 workday', () async {
      final p = IcsHolidayProvider(_YangH9Feeds());
      await p.warm();
      final holiday = p.between('2026-10-01', '2026-10-08');
      expect(holiday, isNotEmpty);
      for (final e in holiday) {
        expect(e.type, 'holiday', reason: '${e.date} ${e.name} 不应是补班');
      }
    });

    test('补班事件判为 workday', () async {
      final p = IcsHolidayProvider(_YangH9Feeds());
      await p.warm();
      final makeup = p.between('2026-09-28', '2026-09-28');
      expect(makeup.single.type, 'workday');
      final makeup2 = p.between('2026-04-27', '2026-04-27');
      expect(makeup2.single.type, 'workday');
    });

    test('劳动节假期（描述含「上班」）不被误判为 workday', () async {
      final p = IcsHolidayProvider(_YangH9Feeds());
      await p.warm();
      final holiday = p.between('2026-05-01', '2026-05-01');
      expect(holiday.single.type, 'holiday');
    });
  });
}
