// CompositeCalendarProvider（P2-⑦ source: system）单测：
// 双路合并 / D1 排序 / includeSystem 语义 / warnings 显式化 / 脱敏 / feeds 与 refresh 透传。
import 'package:flutter_test/flutter_test.dart';
import 'package:goodtools/mcp/calendar_provider.dart';
import 'package:goodtools/service/composite_calendar_provider.dart';

class _FakeIcs implements CalendarFeedProvider {
  @override
  Future<CalendarQueryResult> query({
    required String rangeStart,
    required String rangeEnd,
    String? timezone,
    List<String>? feedIds,
    bool includeSystem = true,
  }) async =>
      CalendarQueryResult(<CalendarEvent>[
        CalendarEvent(
          uid: 'f1:ics-1',
          title: 'ICS 事件',
          start: '2026-10-02T09:00:00Z',
          end: '2026-10-02T10:00:00Z',
          source: 'feed',
          feedId: 'f1',
          feedName: '订阅源',
        ),
      ]);

  @override
  Future<List<CalendarFeed>> feeds() async => <CalendarFeed>[
        const CalendarFeed(
            id: 'f1', name: '订阅源', url: 'https://example.com/a.ics', refreshMin: 720),
      ];

  @override
  Future<int> refresh({String? feedId}) async => feedId == null ? 1 : 1;
}

class _FakeSystem implements SystemCalendarPort {
  _FakeSystem({this.error});

  /// 非 null 时 readEvents 抛该异常（模拟未授权 / 通道缺位）。
  final CalendarFeedException? error;

  int callCount = 0;

  @override
  Future<List<SystemCalendarRawEvent>> readEvents({
    required String rangeStart,
    required String rangeEnd,
  }) async {
    callCount++;
    final err = error;
    if (err != null) throw err;
    return <SystemCalendarRawEvent>[
      const SystemCalendarRawEvent(
        uid: '42',
        calendarName: '个人',
        title: '牙医预约',
        start: '2026-10-01T14:00:00+08:00',
        end: '2026-10-01T15:00:00+08:00',
        isAllDay: false,
        location: '门诊部 13800138000',
        description: '带医保卡 doctor@example.com',
      ),
    ];
  }
}

void main() {
  test('双路合并 + D1 排序（start → uid）+ G4 复合键', () async {
    final p = CompositeCalendarProvider(_FakeIcs(), system: _FakeSystem());
    final r = await p.query(rangeStart: '2026-10-01', rangeEnd: '2026-10-07');
    expect(r.warnings, isEmpty);
    expect(r.events, hasLength(2));
    // 系统事件 10-01 14:00+08:00 = 10-01 06:00Z < ICS 10-02 09:00Z。
    expect(r.events[0].source, 'system');
    expect(r.events[0].feedName, '个人');
    expect(r.events[0].uid, 'system:42:2026-10-01T14:00:00+08:00');
    expect(r.events[1].source, 'feed');
  });

  test('includeSystem=false：不查系统源（硬开关）', () async {
    final sys = _FakeSystem();
    final p = CompositeCalendarProvider(_FakeIcs(), system: sys);
    final r = await p.query(
        rangeStart: '2026-10-01', rangeEnd: '2026-10-07', includeSystem: false);
    expect(sys.callCount, 0);
    expect(r.events, hasLength(1));
    expect(r.events.single.source, 'feed');
  });

  test('feedIds 显式点名（不含 system）= 不要系统源；含 system = 双路', () async {
    final sys = _FakeSystem();
    final p = CompositeCalendarProvider(_FakeIcs(), system: sys);
    final only = await p.query(
        rangeStart: '2026-10-01', rangeEnd: '2026-10-07', feedIds: ['f1']);
    expect(sys.callCount, 0);
    expect(only.events, hasLength(1));

    final both = await p.query(
        rangeStart: '2026-10-01',
        rangeEnd: '2026-10-07',
        feedIds: ['f1', 'system']);
    expect(sys.callCount, 1);
    expect(both.events, hasLength(2));
  });

  test('系统源缺位（未注入）→ warnings 显式化，ICS 结果照常（不静默降级）', () async {
    final p = CompositeCalendarProvider(_FakeIcs());
    final r = await p.query(rangeStart: '2026-10-01', rangeEnd: '2026-10-07');
    expect(r.events, hasLength(1));
    expect(r.warnings, hasLength(1));
    expect(r.warnings.single['code'], CalendarErr.sourceUnavailable);
    expect(r.warnings.single['source'], 'system');
  });

  test('系统源未授权 → warnings 携带 ERR_CALENDAR_PERMISSION，ICS 照常', () async {
    final p = CompositeCalendarProvider(
      _FakeIcs(),
      system: _FakeSystem(
          error: const CalendarFeedException(
              CalendarErr.permissionDenied, 'READ_CALENDAR 未授权')),
    );
    final r = await p.query(rangeStart: '2026-10-01', rangeEnd: '2026-10-07');
    expect(r.events, hasLength(1));
    expect(r.warnings.single['code'], CalendarErr.permissionDenied);
  });

  test('系统源未授权 + 自愈指引 → warning 透传 suggestion（缺省不出键）', () async {
    final p = CompositeCalendarProvider(
      _FakeIcs(),
      system: _FakeSystem(
          error: const CalendarFeedException(CalendarErr.permissionDenied,
              'READ_CALENDAR 未授权',
              suggestion: '请在 App 日历页点「授予日历权限」')),
    );
    final r = await p.query(rangeStart: '2026-10-01', rangeEnd: '2026-10-07');
    expect(r.warnings.single['suggestion'], contains('授予日历权限'));
    // 无 suggestion 的警告（如源未注入）不出该键——结构向后兼容。
    final p2 = CompositeCalendarProvider(_FakeIcs());
    final r2 = await p2.query(rangeStart: '2026-10-01', rangeEnd: '2026-10-07');
    expect(r2.warnings.single.containsKey('suggestion'), isFalse);
  });

  test('E 拍板脱敏：系统源 location / description 复用 maskPii', () async {
    final p = CompositeCalendarProvider(_FakeIcs(), system: _FakeSystem());
    final r = await p.query(rangeStart: '2026-10-01', rangeEnd: '2026-10-07');
    final sys = r.events.firstWhere((e) => e.source == 'system');
    expect(sys.location, contains('[已隐藏]'));
    expect(sys.location, isNot(contains('13800138000')));
    expect(sys.description, contains('[已隐藏]'));
    expect(sys.description, isNot(contains('example.com')));
  });

  test('feeds()：port 注入时追加系统条目；缺位时只含 ICS', () async {
    final withSys = CompositeCalendarProvider(_FakeIcs(), system: _FakeSystem());
    final feeds = await withSys.feeds();
    expect(feeds.map((f) => f.id), containsAll(['f1', 'system']));

    final withoutSys = CompositeCalendarProvider(_FakeIcs());
    expect((await withoutSys.feeds()).map((f) => f.id), ['f1']);
  });

  test("refresh('system') 返回 0（实时读取无刷新语义）；其余透传 ICS", () async {
    final p = CompositeCalendarProvider(_FakeIcs(), system: _FakeSystem());
    expect(await p.refresh(feedId: 'system'), 0);
    expect(await p.refresh(feedId: 'f1'), 1);
    expect(await p.refresh(), 1);
  });
}
