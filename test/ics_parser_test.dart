// P2-④ 步骤 A：RFC 5545 解析内核测试（C1 截断 / C2 EXDATE+override / D1 固定排序）。
import 'package:flutter_test/flutter_test.dart';
import 'package:goodtools/mcp/ics_parser.dart';

void main() {
  IcsParseResult parse(String ics) => IcsParser.parse(ics);

  group('基础解析', () {
    test('单次事件：UID / SUMMARY / 起止 / 描述转义', () {
      final r = parse('''
BEGIN:VCALENDAR
VERSION:2.0
BEGIN:VEVENT
UID:e1@example.com
SUMMARY:项目复盘\\, 全员
DESCRIPTION:第一行\\n第二行
LOCATION:3F-会议室
DTSTART:20261020T020000Z
DTEND:20261020T030000Z
END:VEVENT
END:VCALENDAR
''');
      expect(r.events.length, 1);
      expect(r.warnings, isEmpty);
      final e = r.events.single;
      expect(e.uid, 'e1@example.com');
      expect(e.summary, '项目复盘, 全员'); // \, 反转义
      expect(e.description, '第一行\n第二行'); // \n 反转义
      expect(e.start, DateTime.utc(2026, 10, 20, 2));
      expect(e.end, DateTime.utc(2026, 10, 20, 3));
      expect(e.isAllDay, isFalse);
    });

    test('续行展开（以空格开头）', () {
      final r = parse('''
BEGIN:VEVENT
UID:e2@x
SUMMARY:很长的标题被折
 成两行
DTSTART:20261020T020000Z
END:VEVENT
''');
      expect(r.events.single.summary, '很长的标题被折成两行');
    });

    test('全天事件：VALUE=DATE + 缺省 DTEND = 次日 00:00', () {
      final r = parse('''
BEGIN:VEVENT
UID:e3@x
SUMMARY:国庆
DTSTART;VALUE=DATE:20261001
END:VEVENT
''');
      final e = r.events.single;
      expect(e.isAllDay, isTrue);
      expect(e.start, DateTime.utc(2026, 10, 1));
      expect(e.end, DateTime.utc(2026, 10, 2)); // 缺省规则：全天 = 1 天
    });

    test('VALARM / VTIMEZONE 内容被忽略', () {
      final r = parse('''
BEGIN:VCALENDAR
BEGIN:VTIMEZONE
TZID:Asia/Shanghai
BEGIN:STANDARD
DTSTART:19700101T000000
TZOFFSETFROM:+0800
TZOFFSETTO:+0800
END:STANDARD
END:VTIMEZONE
BEGIN:VEVENT
UID:e4@x
SUMMARY:带闹钟
DTSTART:20261020T020000Z
BEGIN:VALARM
TRIGGER:-PT15M
ACTION:DISPLAY
DESCRIPTION:提醒
END:VALARM
END:VEVENT
END:VCALENDAR
''');
      expect(r.events.length, 1);
      expect(r.events.single.summary, '带闹钟');
    });

    test('缺 UID 或 DTSTART → 跳过并记 warning（不静默丢）', () {
      final r = parse('''
BEGIN:VEVENT
SUMMARY:没有 UID
DTSTART:20261020T020000Z
END:VEVENT
''');
      expect(r.events, isEmpty);
      expect(r.warnings, isNotEmpty);
    });
  });

  group('RRULE 展开（C1）', () {
    test('DAILY + COUNT=3', () {
      final events = parse('''
BEGIN:VEVENT
UID:d1@x
SUMMARY:每日站会
DTSTART:20261019T013000Z
DTEND:20261019T014000Z
RRULE:FREQ=DAILY;COUNT=3
END:VEVENT
''').events;
      final days = IcsExpander.expand(events,
              DateTime.utc(2026, 10, 1), DateTime.utc(2026, 11, 1))
          .map((i) => i.start)
          .toList();
      expect(days, [
        DateTime.utc(2026, 10, 19, 1, 30),
        DateTime.utc(2026, 10, 20, 1, 30),
        DateTime.utc(2026, 10, 21, 1, 30),
      ]);
    });

    test('WEEKLY + BYDAY=MO,WE,FR', () {
      final events = parse('''
BEGIN:VEVENT
UID:w1@x
SUMMARY:三次健身
DTSTART:20261019T013000Z
DTEND:20261019T023000Z
RRULE:FREQ=WEEKLY;BYDAY=MO,WE,FR;COUNT=6
END:VEVENT
''').events;
      final starts = IcsExpander.expand(events,
              DateTime.utc(2026, 10, 1), DateTime.utc(2026, 11, 1))
          .map((i) => i.start)
          .toList();
      expect(starts.every((d) => const [1, 3, 5].contains(d.weekday)), isTrue);
      expect(starts.length, 6);
    });

    test('MONTHLY + BYMONTHDAY=31 跨大小月 + 月末 clamp', () {
      final events = parse('''
BEGIN:VEVENT
UID:m1@x
SUMMARY:月末日
DTSTART:20261031T013000Z
DTEND:20261031T020000Z
RRULE:FREQ=MONTHLY;BYMONTHDAY=31;COUNT=4
END:VEVENT
''').events;
      final starts = IcsExpander.expand(events,
              DateTime.utc(2026, 10, 1), DateTime.utc(2027, 3, 1))
          .map((i) => i.start)
          .toList();
      // 11 月 / 2 月无 31 日 —— 按 RFC 这些月份**不触发**（不 clamp 伪造日期）
      expect(starts.map((d) => '${d.year}-${d.month}-${d.day}').toList(),
          ['2026-10-31', '2026-12-31', '2027-1-31']);
    });

    test('UNTIL 限定', () {
      final events = parse('''
BEGIN:VEVENT
UID:u1@x
SUMMARY:直到某日
DTSTART:20261019T013000Z
DTEND:20261019T020000Z
RRULE:FREQ=DAILY;UNTIL=20261021T235959Z
END:VEVENT
''').events;
      final starts = IcsExpander.expand(events,
              DateTime.utc(2026, 10, 1), DateTime.utc(2026, 12, 1))
          .map((i) => i.start)
          .toList();
      expect(starts.length, 3); // 10-19、10-20、10-21
      expect(starts.last.day, 21);
    });

    test('C1：无限 DAILY 在宽区间被 maxInstances 截断', () {
      final events = parse('''
BEGIN:VEVENT
UID:c1@x
SUMMARY:无限
DTSTART:20260101T000000Z
DTEND:20260101T001000Z
RRULE:FREQ=DAILY
END:VEVENT
''').events;
      final out = IcsExpander.expand(events, DateTime.utc(2026, 1, 1),
          DateTime.utc(2030, 1, 1));
      expect(out.length, lessThanOrEqualTo(icsMaxInstances));
    });

    test('区间外实例不返回（无 COUNT 无限规则天然安全）', () {
      final events = parse('''
BEGIN:VEVENT
UID:o1@x
SUMMARY:无限
DTSTART:20200101T000000Z
DTEND:20200101T001000Z
RRULE:FREQ=DAILY
END:VEVENT
''').events;
      final out = IcsExpander.expand(
          events, DateTime.utc(2026, 10, 1), DateTime.utc(2026, 10, 8));
      expect(out.length, 7);
      expect(out.first.start, DateTime.utc(2026, 10, 1));
    });
  });

  group('C2：EXDATE 与 override', () {
    test('EXDATE 排除指定实例', () {
      final events = parse('''
BEGIN:VEVENT
UID:x1@x
SUMMARY:每日除周三
DTSTART:20261019T013000Z
DTEND:20261019T020000Z
RRULE:FREQ=DAILY;COUNT=3
EXDATE:20261020T013000Z
END:VEVENT
''').events;
      final days = IcsExpander.expand(events, DateTime.utc(2026, 10, 1),
              DateTime.utc(2026, 11, 1))
          .map((i) => i.start.day)
          .toList();
      expect(days, [19, 21]); // 20 被排除
    });

    test('RECURRENCE-ID override 替换时间（不是追加）', () {
      final events = parse('''
BEGIN:VEVENT
UID:r1@x
SUMMARY:周会
DTSTART:20261019T013000Z
DTEND:20261019T020000Z
RRULE:FREQ=DAILY;COUNT=2
END:VEVENT
BEGIN:VEVENT
UID:r1@x
SUMMARY:周会（改到下午）
RECURRENCE-ID:20261020T013000Z
DTSTART:20261020T060000Z
DTEND:20261020T070000Z
END:VEVENT
''').events;
      final starts = IcsExpander.expand(events, DateTime.utc(2026, 10, 1),
              DateTime.utc(2026, 11, 1))
          .map((i) => i.start)
          .toList();
      expect(starts, [
        DateTime.utc(2026, 10, 19, 1, 30),
        DateTime.utc(2026, 10, 20, 6),
      ]);
    });

    test('STATUS:CANCELLED override 删除该实例', () {
      final events = parse('''
BEGIN:VEVENT
UID:r2@x
SUMMARY:周会
DTSTART:20261019T013000Z
DTEND:20261019T020000Z
RRULE:FREQ=DAILY;COUNT=2
END:VEVENT
BEGIN:VEVENT
UID:r2@x
SUMMARY:周会
RECURRENCE-ID:20261020T013000Z
DTSTART:20261020T013000Z
DTEND:20261020T020000Z
STATUS:CANCELLED
END:VEVENT
''').events;
      final days = IcsExpander.expand(events, DateTime.utc(2026, 10, 1),
              DateTime.utc(2026, 11, 1))
          .map((i) => i.start.day)
          .toList();
      expect(days, [19]);
    });
  });

  group('D1 固定排序', () {
    test('同输入可重放：start asc → uid asc', () {
      final events = parse('''
BEGIN:VEVENT
UID:b@x
SUMMARY:后
DTSTART:20261020T010000Z
DTEND:20261020T011000Z
END:VEVENT
BEGIN:VEVENT
UID:a@x
SUMMARY:先
DTSTART:20261020T010000Z
DTEND:20261020T011000Z
END:VEVENT
''').events;
      final uids = IcsExpander.expand(events, DateTime.utc(2026, 10, 1),
              DateTime.utc(2026, 11, 1))
          .map((i) => i.event.uid)
          .toList();
      expect(uids, ['a@x', 'b@x']); // 同时刻按 uid
    });
  });

  group('不支持的 FREQ', () {
    test('HOURLY 跳过并记 warning', () {
      final r = parse('''
BEGIN:VEVENT
UID:h1@x
SUMMARY:每小时
DTSTART:20261020T000000Z
DTEND:20261020T001000Z
RRULE:FREQ=HOURLY;COUNT=5
END:VEVENT
''');
      expect(r.events.single.rrule, isNull); // 降为单次
      expect(r.warnings.single, contains('FREQ'));
    });
  });
}
