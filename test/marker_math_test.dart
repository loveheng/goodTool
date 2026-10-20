// P2-⑥ 标记周年推演 + 月网格测试（P2-③ 起含农历三策略展开与节气角标）。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:good_template/action/command_gateway.dart';
import 'package:good_template/mcp/calendar_provider.dart';
import 'package:good_template/mcp/category_tool_face.dart';
import 'package:good_template/ports.dart';
import 'package:good_template/service/calendar_actors.dart';
import 'package:good_template/service/marker_store.dart';
import 'package:good_template/tools/calendar/lunar_math.dart';
import 'package:good_template/tools/calendar/marker_math.dart';
import 'package:good_template/tools/calendar/holiday_table.dart';
import 'package:good_template/tools/system_pim_tool.dart';

void main() {
  Map<String, Object?> jsonOf(SubActionResult r) =>
      jsonDecode((r.content.first)['text']! as String) as Map<String, Object?>;

  group('周年展开（calendar.md Markers 语义）', () {
    test('年度标记：anniversaryCount / ordinalCount / daysRemaining 以基准日起算', () {
      final markers = <CalendarMarker>[
        CalendarMarker(
          id: 'mk_1',
          title: '妈妈生日',
          originalDate: '2018-10-19',
          baseYear: 2018,
          category: 'birthday',
        ),
      ];
      final out = MarkerMath.expand(
        markers,
        DateTime.utc(2026, 10, 1),
        DateTime.utc(2026, 10, 31),
      );
      expect(out, hasLength(1));
      final m = out.single;
      expect(m['date'], '2026-10-19');
      expect(m['anniversaryCount'], 8); // 2026 − 2018
      expect(m['ordinalCount'], 9); // 第 9 个生日
      expect(m['daysRemaining'], 18); // 以 rangeStart 2026-10-01 为基准
    });

    test('多年区间展开多年实例并排序', () {
      final markers = <CalendarMarker>[
        CalendarMarker(
          id: 'mk_1',
          title: '纪念日',
          originalDate: '2020-05-20',
          baseYear: 2020,
          category: 'anniversary',
        ),
      ];
      final out = MarkerMath.expand(
        markers,
        DateTime.utc(2024, 1, 1),
        DateTime.utc(2026, 12, 31),
      );
      expect(out.map((m) => m['date']).toList(),
          ['2024-05-20', '2025-05-20', '2026-05-20']);
      expect(out.last['anniversaryCount'], 6);
    });

    test('非年度标记只在起始日当天出现', () {
      final markers = <CalendarMarker>[
        CalendarMarker(
          id: 'mk_2',
          title: '入职日',
          originalDate: '2022-03-01',
          baseYear: 2022,
          category: 'milestone',
          isAnnual: false,
        ),
      ];
      final out = MarkerMath.expand(
        markers,
        DateTime.utc(2026, 1, 1),
        DateTime.utc(2026, 12, 31),
      );
      expect(out, isEmpty); // 2022 不在区间
      final inRange = MarkerMath.expand(
        markers,
        DateTime.utc(2022, 1, 1),
        DateTime.utc(2022, 12, 31),
      );
      expect(inRange.single['date'], '2022-03-01');
      expect(inRange.single['anniversaryCount'], 0);
    });

    test('平年 02-29 → 02-28 并标 approximate（不推到 3 月）', () {
      final markers = <CalendarMarker>[
        CalendarMarker(
          id: 'mk_3',
          title: '闰日生日',
          originalDate: '2024-02-29',
          baseYear: 2024,
          category: 'birthday',
        ),
      ];
      final out = MarkerMath.expand(
        markers,
        DateTime.utc(2026, 2, 1),
        DateTime.utc(2026, 2, 28),
      );
      expect(out.single['date'], '2026-02-28');
      expect(out.single['approximate'], isTrue);
    });

    test('闰年 02-29 原样命中、不标 approximate', () {
      final markers = <CalendarMarker>[
        CalendarMarker(
          id: 'mk_4',
          title: '闰日生日',
          originalDate: '2024-02-29',
          baseYear: 2024,
          category: 'birthday',
        ),
      ];
      final out = MarkerMath.expand(
        markers,
        DateTime.utc(2028, 2, 1),
        DateTime.utc(2028, 2, 29),
      );
      expect(out.single['date'], '2028-02-29');
      expect(out.single.containsKey('approximate'), isFalse);
    });

    test('农历标记 ignoreLeap：对齐平月，2026 中秋 → 2026-09-25', () {
      final markers = <CalendarMarker>[
        CalendarMarker(
          id: 'mk_5',
          title: '中秋生日',
          originalDate: '1990-08-15',
          baseYear: 1990,
          category: 'birthday',
          isLunar: true,
        ),
      ];
      final out = MarkerMath.expand(
        markers,
        DateTime.utc(2026, 1, 1),
        DateTime.utc(2026, 12, 31),
      );
      expect(out, hasLength(1));
      expect(out.single['date'], '2026-09-25'); // 2026 年中秋（官方历表事实）
      expect(out.single['anniversaryCount'], 36); // 按农历年 2026 − 1990
      expect(out.single['ordinalCount'], 37);
      expect(out.single['isLunar'], isTrue);
      expect(out.single.containsKey('approximate'), isFalse);
      expect(out.single.containsKey('lunarPending'), isFalse);
    });

    test('农历标记 strictLeap（闰月源）：平年不触发、闰年触发', () {
      // 2025 年闰六月（官方历表事实）。找下一个闰六月年做触发年断言。
      final leapYear = <int>[
        for (var y = 2026; y <= 2100; y++)
          if (LunarMath.leapMonthOf(y) == 6) y
      ].first;
      final leapSrc = <CalendarMarker>[
        CalendarMarker(
          id: 'mk_6',
          title: '闰六月生日',
          originalDate: '2025-闰6-05',
          baseYear: 2025,
          category: 'birthday',
          isLunar: true,
          leapPolicy: 'strictLeap',
        ),
      ];
      // 平年（2026 无闰六月）：不产生实例
      expect(
        MarkerMath.expand(
            leapSrc, DateTime.utc(2026, 1, 1), DateTime.utc(2026, 12, 31)),
        isEmpty,
      );
      // 闰年：触发且走闰月
      final out = MarkerMath.expand(
        leapSrc,
        DateTime.utc(leapYear, 1, 1),
        DateTime.utc(leapYear, 12, 31),
      );
      expect(out, hasLength(1));
      expect(out.single['anniversaryCount'], leapYear - 2025);
    });

    test('农历标记 followRegular（闰月源）：平年回落平月并标 approximate', () {
      final src = <CalendarMarker>[
        CalendarMarker(
          id: 'mk_7',
          title: '闰六月生日',
          originalDate: '2025-闰6-05',
          baseYear: 2025,
          category: 'birthday',
          isLunar: true,
          leapPolicy: 'followRegular',
        ),
      ];
      final out = MarkerMath.expand(
        src,
        DateTime.utc(2026, 1, 1),
        DateTime.utc(2026, 12, 31),
      );
      expect(out, hasLength(1)); // 平年仍触发
      expect(out.single['approximate'], isTrue); // 但显式标 approximate
      expect(LunarMath.leapMonthOf(2026), 0); // 2026 确无闰六月（对账）
    });

    test('农历标记解析失败 → lunarParseError 条目（不静默按公历算也不静默丢）', () {
      final src = <CalendarMarker>[
        CalendarMarker(
          id: 'mk_8',
          title: '坏数据',
          originalDate: 'not-a-date',
          baseYear: 2020,
          category: 'anniversary',
          isLunar: true,
        ),
      ];
      final out = MarkerMath.expand(
        src,
        DateTime.utc(2026, 1, 1),
        DateTime.utc(2026, 12, 31),
      );
      expect(out.single['lunarParseError'], isTrue);
      expect(out.single.containsKey('date'), isFalse);
    });
  });

  group('月网格（恒定 42 格）', () {
    test('2026 年 10 月：42 格 + firstDayOfWeek=1（周一）列起始', () {
      final cells = MarkerMath.monthGrid(
        2026, 10, 1, cnHolidayBundled, const <Map<String, Object?>>[],
      );
      expect(cells, hasLength(42));
      // 2026-10-01 是周四 → 周一为首列时前面填 3 格（9/28~9/30）
      expect(cells.first['date'], '2026-09-28');
      expect(cells.first['isCurrentMonth'], isFalse);
      expect(cells.firstWhere((c) => c['isCurrentMonth'] == true)['date'],
          '2026-10-01');
    });

    test('firstDayOfWeek=7（周日）列起始平移一格', () {
      final mon = MarkerMath.monthGrid(
          2026, 10, 1, cnHolidayBundled, const <Map<String, Object?>>[]);
      final sun = MarkerMath.monthGrid(
          2026, 10, 7, cnHolidayBundled, const <Map<String, Object?>>[]);
      expect(sun.first['date'], '2026-09-27');
      expect(sun.first['date'] != mon.first['date'], isTrue);
      expect(sun, hasLength(42));
    });

    test('国庆月 badge：假日 / 调休补班 / 普通日', () {
      final cells = MarkerMath.monthGrid(
        2026, 10, 1, cnHolidayBundled, const <Map<String, Object?>>[],
      );
      Map<String, Object?> cellOf(String date) =>
          cells.firstWhere((c) => c['date'] == date);
      expect(cellOf('2026-10-01')['badge'], 'holiday');
      expect(cellOf('2026-10-01')['isWorkday'], isFalse);
      expect(cellOf('2026-10-10')['badge'], 'adjusted_workday'); // 调休补班
      expect(cellOf('2026-10-10')['isWorkday'], isTrue);
      expect(cellOf('2026-10-08')['badge'], 'solar_term'); // 假后首个工作日，恰逢寒露
      expect(cellOf('2026-10-08')['solarTerm'], '寒露');
      expect(cellOf('2026-10-08')['isWorkday'], isTrue);
      expect(cellOf('2026-10-11')['isWorkday'], isFalse); // 假后周日
      expect(cellOf('2026-10-12')['badge'], 'none'); // 真普通日（无假无节气）
      expect(cellOf('2026-10-12')['isWorkday'], isTrue);
      // 农历角标：2026-10-01 = 农历八月廿一（中秋 2026-09-25 + 6 天）
      expect(cellOf('2026-10-01')['lunar'], '廿一');
    });

    test('markerCount 计入当日展开实例', () {
      final expanded = <Map<String, Object?>>[
        <String, Object?>{'date': '2026-10-19'},
        <String, Object?>{'date': '2026-10-19'},
      ];
      final cells = MarkerMath.monthGrid(
          2026, 10, 1, cnHolidayBundled, expanded);
      expect(cells.firstWhere((c) => c['date'] == '2026-10-19')['markerCount'],
          2);
    });

    test('holidayTableVersion 随表透出', () {
      final cells = MarkerMath.monthGrid(
          2026, 10, 1, cnHolidayBundled, const <Map<String, Object?>>[]);
      expect(cells, isNotEmpty);
      expect(cnHolidayBundled.version, 'cn-2026.1');
    });
  });

  group('端到端：marker_add → marker_list / month_grid（经 Actor 与 store）', () {
    test('添加后可按区间查到展开实例', () async {
      final store = InMemoryMarkerStore();
      final gateway = CommandGateway();
      registerCalendarActors(gateway, kv: InMemoryKv(), markers: store);
      final tool =
          buildSystemPimTool(gateway, markers: store, holidays: cnHolidayBundled);

      final add = await tool.call('calendar_marker_add', {
        'originalDate': '2018-10-19',
        'title': '妈妈生日',
        'category': 'birthday',
      });
      expect(add.isError, isFalse);

      final list = jsonOf(await tool.call('calendar_marker_list', {
        'rangeStart': '2026-10-01',
        'rangeEnd': '2026-10-31',
      }));
      final markers = list['markers'] as List;
      expect(markers, hasLength(1));
      expect(markers.single['anniversaryCount'], 8);
      expect(list['holidayTableVersion'], 'cn-2026.1');
    });

    test('month_grid 端到端：42 格 + 标记计数', () async {
      final store = InMemoryMarkerStore();
      final gateway = CommandGateway();
      registerCalendarActors(gateway, kv: InMemoryKv(), markers: store);
      final tool =
          buildSystemPimTool(gateway, markers: store, holidays: cnHolidayBundled);
      await tool.call('calendar_marker_add', {
        'originalDate': '2018-10-19',
        'title': '妈妈生日',
        'category': 'birthday',
      });

      final grid = jsonOf(await tool.call('calendar_month_grid', {
        'year': 2026,
        'month': 10,
      }));
      final days = grid['days'] as List;
      expect(days, hasLength(42));
      expect(days.firstWhere((d) => d['date'] == '2026-10-19')['markerCount'],
          1);
    });

    test('农历标记端到端：经农历引擎真实展开为公历实例', () async {
      final store = InMemoryMarkerStore();
      final gateway = CommandGateway();
      registerCalendarActors(gateway, kv: InMemoryKv(), markers: store);
      final tool =
          buildSystemPimTool(gateway, markers: store, holidays: cnHolidayBundled);
      await tool.call('calendar_marker_add', {
        'originalDate': '1990-08-15',
        'title': '中秋生日',
        'category': 'birthday',
        'isLunar': true,
      });
      final list = jsonOf(await tool.call('calendar_marker_list', {
        'rangeStart': '2026-01-01',
        'rangeEnd': '2026-12-31',
      }));
      final m = (list['markers'] as List).single;
      expect(m['date'], '2026-09-25'); // 2026 中秋
      expect(m['anniversaryCount'], 36);
      expect(m['isLunar'], isTrue);
    });

    test('未注入标记源 → fail-closed（不返回空列表假装没有标记）', () async {
      final bare = buildSystemPimTool(CommandGateway(), holidays: cnHolidayBundled);
      final r = await bare.call('calendar_marker_list', {
        'rangeStart': '2026-10-01',
        'rangeEnd': '2026-10-31',
      });
      expect(r.isError, isTrue);
      expect((jsonOf(r)['error'] as Map)['code'],
          contains('ERR_CALENDAR_SOURCE_UNAVAILABLE'));
    });

    test('firstDayOfWeek 越界 → INVALID_ARGUMENT（不兜底为 1）', () async {
      final tool =
          buildSystemPimTool(CommandGateway(), markers: InMemoryMarkerStore());
      final r = await tool.call('calendar_month_grid', {
        'year': 2026,
        'month': 10,
        'firstDayOfWeek': 9,
      });
      expect(r.isError, isTrue);
      expect((jsonOf(r)['error'] as Map)['code'], contains('INVALID_ARGUMENT'));
    });
  });
}
