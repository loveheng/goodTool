// P2-① 节假日表测试：内置表逐字对账国务院办公厅 2026 年通知（口径见
// lib/tools/calendar/holiday_table.dart 文件头），并覆盖 `between` 边界、
// DateMath 的工作日判定优先级（调休补班 > 法定假 > 周末）、OTA JSON 解析与坏输入拒绝。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:good_template/action/command_gateway.dart';
import 'package:good_template/mcp/category_tool_face.dart';
import 'package:good_template/tools/calendar/date_math.dart';
import 'package:good_template/tools/calendar/holiday_table.dart';
import 'package:good_template/tools/system_pim_tool.dart';

void main() {
  Map<String, Object?> jsonOf(SubActionResult r) =>
      jsonDecode(r.content.first['text']! as String) as Map<String, Object?>;

  CategoryTool tool() => buildSystemPimTool(CommandGateway());

  group('内置表逐字对账（国务院办公厅 2026 年通知）', () {
    test('版本号与条目数（法定假 33 天 + 调休补班 6 天）', () {
      expect(cnHolidayBundled.version, 'cn-2026.1');
      final all = cnHolidayBundled.between('2026-01-01', '2026-12-31');
      expect(all.length, 39);
      expect(all.where((e) => e.type == 'holiday').length, 33);
      expect(all.where((e) => e.type == 'workday').length, 6);
    });

    test('七个假期区间逐字对账（天数 = 3/9/3/5/3/3/7）', () {
      int inRange(String a, String b) => cnHolidayBundled
          .between(a, b)
          .where((e) => e.type == 'holiday')
          .length;
      expect(inRange('2026-01-01', '2026-01-03'), 3); // 元旦
      expect(inRange('2026-02-15', '2026-02-23'), 9); // 春节
      expect(inRange('2026-04-04', '2026-04-06'), 3); // 清明
      expect(inRange('2026-05-01', '2026-05-05'), 5); // 劳动节
      expect(inRange('2026-06-19', '2026-06-21'), 3); // 端午
      expect(inRange('2026-09-25', '2026-09-27'), 3); // 中秋
      expect(inRange('2026-10-01', '2026-10-07'), 7); // 国庆
    });

    test('六个调休补班日逐字对账', () {
      for (final d in const [
        '2026-01-04',
        '2026-02-14',
        '2026-02-28',
        '2026-05-09',
        '2026-09-20',
        '2026-10-10',
      ]) {
        expect(cnHolidayBundled.between(d, d).single.type, 'workday',
            reason: d);
      }
    });

    test('清明 / 端午 / 中秋无调休补班（原文即"放假"而非"放假调休"）', () {
      expect(
        cnHolidayBundled
            .between('2026-04-01', '2026-04-30')
            .where((e) => e.type == 'workday'),
        isEmpty,
      );
      expect(
        cnHolidayBundled
            .between('2026-06-01', '2026-06-30')
            .where((e) => e.type == 'workday'),
        isEmpty,
      );
      expect(
        cnHolidayBundled
            .between('2026-09-01', '2026-09-30')
            .where((e) => e.type == 'workday' && e.date != '2026-09-20'),
        isEmpty,
      );
    });

    test('between 边界：起止同日 / 空区间 / 跨年（2027 表未发布）', () {
      expect(cnHolidayBundled.between('2026-10-01', '2026-10-01').length, 1);
      expect(cnHolidayBundled.between('2026-03-01', '2026-03-31'), isEmpty);
      expect(cnHolidayBundled.between('2026-12-30', '2027-01-10'), isEmpty);
    });
  });

  group('工作日判定优先级（调休补班 > 法定假 > 周末）', () {
    bool work(String date) =>
        DateMath.isWorkday(DateMath.parseDate(date)!, cnHolidayBundled);

    test('法定假日 → 非工作日（含被吞掉的周末）', () {
      expect(work('2026-01-01'), isFalse);
      expect(work('2026-01-02'), isFalse);
      expect(work('2026-01-03'), isFalse);
      expect(work('2026-10-07'), isFalse);
    });

    test('调休补班 → 工作日（即便在周末）', () {
      expect(work('2026-01-04'), isTrue); // 周日上班
      expect(work('2026-02-14'), isTrue); // 周六上班
      expect(work('2026-02-28'), isTrue); // 周六上班
      expect(work('2026-05-09'), isTrue); // 周六上班
      expect(work('2026-09-20'), isTrue); // 周日上班
      expect(work('2026-10-10'), isTrue); // 周六上班
    });

    test('普通周末 / 工作日不受影响', () {
      expect(work('2026-01-11'), isFalse); // 普通周日
      expect(work('2026-01-05'), isTrue); // 普通周一
      expect(work('2026-10-11'), isFalse); // 假后周日
      expect(work('2026-10-08'), isTrue); // 假后周四
    });
  });

  group('端到端（经 system_pim 工具面，默认内置表生效）', () {
    test('workdays_between：国庆前后（10-01~10-11）= 11 天 / 3 个工作日',
        () async {
      final j = jsonOf(await tool().call('calendar_workdays_between', {
        'startDate': '2026-10-01',
        'endDate': '2026-10-11',
      }));
      expect(j['totalDays'], 10); // 差值语义：end − start（10-11 减 10-01）
      expect(j['workdays'], 3); // 10-08、10-09、10-10（调休补班计入）
      expect((j['holidays'] as List).length, 7);
      expect((j['adjustments'] as List).single['date'], '2026-10-10');
      expect(j['holidayTableVersion'], 'cn-2026.1');
    });

    test('workdays_between：1 月整月 = 31 天 / 21 个工作日', () async {
      final j = jsonOf(await tool().call('calendar_workdays_between', {
        'startDate': '2026-01-01',
        'endDate': '2026-01-31',
      }));
      expect(j['totalDays'], 30); // 1-31 减 1-1
      // 1/4 补班计入 + 四个完整工作周（5-9 / 12-16 / 19-23 / 26-30）
      expect(j['workdays'], 21);
    });

    test('date_calc：2/13 后一个工作日即落在调休补班日 2/14', () async {
      final j = jsonOf(await tool().call('calendar_date_calc', {
        'baseDate': '2026-02-13', // 春节前的周五
        'delta': {'workdays': 1},
      }));
      expect(j['targetDate'], '2026-02-14');
      expect(j['isWorkday'], isTrue);
    });
  });

  group('OTA 静态 JSON 解析（F3：bundle / OTA 同构）', () {
    test('合法 JSON → 按 ranges 展开（跨年）+ workdays 落位', () {
      final p = CnHolidayProvider.fromJson(<String, Object?>{
        'version': 'cn-2027.1',
        'ranges': [
          {'start': '2026-12-30', 'days': 4, 'name': '元旦'},
        ],
        'workdays': [
          {'date': '2027-01-09', 'name': '元旦调休'}
        ],
      });
      expect(p.version, 'cn-2027.1');
      expect(p.between('2026-12-30', '2027-01-02').map((e) => e.date).toList(),
          ['2026-12-30', '2026-12-31', '2027-01-01', '2027-01-02']);
      expect(p.between('2027-01-09', '2027-01-09').single.type, 'workday');
    });

    test('条目按日期升序（跨年 ranges 与 workdays 混排）', () {
      final p = CnHolidayProvider.fromJson(<String, Object?>{
        'version': 'v',
        'ranges': [
          {'start': '2027-01-01', 'days': 2, 'name': '元旦'}
        ],
        'workdays': [
          {'date': '2026-12-31', 'name': '补'}
        ],
      });
      expect(
          p
              .between('2026-01-01', '2027-12-31')
              .map((e) => e.date)
              .toList(),
          ['2026-12-31', '2027-01-01', '2027-01-02']);
    });

    test('坏输入一律 FormatException（不静默吞）', () {
      expect(
        () => CnHolidayProvider.fromJson(<String, Object?>{'ranges': []}),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => CnHolidayProvider.fromJson(
            <String, Object?>{'version': 'v', 'ranges': 'nope'}),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => CnHolidayProvider.fromJson(<String, Object?>{
          'version': 'v',
          'ranges': [
            {'start': 'not-a-date', 'days': 1, 'name': 'x'}
          ],
        }),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => CnHolidayProvider.fromJson(<String, Object?>{
          'version': 'v',
          'ranges': [
            {'start': '2027-01-01', 'days': 0, 'name': 'x'}
          ],
        }),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
