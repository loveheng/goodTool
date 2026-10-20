// P2-⑥ 标记周年推演 + 月网格测试（公历部分；农历待 P2-③）。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:good_template/action/command_gateway.dart';
import 'package:good_template/mcp/calendar_provider.dart';
import 'package:good_template/mcp/category_tool_face.dart';
import 'package:good_template/ports.dart';
import 'package:good_template/service/calendar_actors.dart';
import 'package:good_template/service/marker_store.dart';
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

    test('农历标记：不静默按公历算，标 lunarPending', () {
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
      expect(out.single['lunarPending'], isTrue);
      expect(out.single.containsKey('date'), isFalse); // 不给可能出错的公历日期
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
      expect(cellOf('2026-10-08')['badge'], 'none'); // 假后首个工作日
      expect(cellOf('2026-10-08')['isWorkday'], isTrue);
      expect(cellOf('2026-10-11')['isWorkday'], isFalse); // 假后周日
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

    test('农历标记端到端： lunarPending 透出、不给公历日期', () async {
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
      expect(list['note'], contains('P2-③'));
      expect((list['markers'] as List).single['lunarPending'], isTrue);
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
