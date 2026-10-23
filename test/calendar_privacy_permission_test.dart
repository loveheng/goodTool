// U12a 脱敏开关接线单测（无测试绑定——ICS 路用本地 HttpServer 打真实回环）。
//
// 覆盖红线：`privacy_mask_pii` 开关态现读生效——关（'0'）= 原文透出；
// 未设置 = 开（保护性缺省，对齐 E 拍板）；ICS 路与系统路同语义；
// 设置快照默认态与内核行为同源。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:goodtools/mcp/calendar_provider.dart';
import 'package:goodtools/mcp/pii_mask.dart';
import 'package:goodtools/mcp/settings_keys.dart';
import 'package:goodtools/mcp/settings_kv.dart';
import 'package:goodtools/ports.dart';
import 'package:goodtools/repository/settings_repository.dart';
import 'package:goodtools/service/composite_calendar_provider.dart';
import 'package:goodtools/service/ics_feed_provider.dart';

const String _kPiiIcs = '''
BEGIN:VCALENDAR
VERSION:2.0
PRODID:-//goodtools test//test//EN
BEGIN:VEVENT
UID:pii@x
DTSTAMP:20261001T000000Z
SUMMARY:带 PII 的事件
DTSTART:20261002T010000Z
DTEND:20261002T020000Z
LOCATION:门诊部 13800138000
DESCRIPTION:带医保卡 doctor@example.com
END:VEVENT
END:VCALENDAR
''';

class _FakeSystem implements SystemCalendarPort {
  @override
  Future<List<SystemCalendarRawEvent>> readEvents({
    required String rangeStart,
    required String rangeEnd,
  }) async =>
      <SystemCalendarRawEvent>[
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

void main() {
  group('U12a · 脱敏开关语义（piiMaskEnabledBy）', () {
    test('未设置 = 开（保护性缺省）；显式 0 = 关；1 = 开', () {
      expect(piiMaskEnabledBy(null), isTrue);
      expect(piiMaskEnabledBy('1'), isTrue);
      expect(piiMaskEnabledBy('0'), isFalse);
      // 脏值不放宽：非 '0' 一律按开处理（保守侧）。
      expect(piiMaskEnabledBy('garbage'), isTrue);
    });
  });

  group('U12a · ICS 路：开关现读生效', () {
    late HttpServer server;
    late SettingsKv kv;
    late IcsFeedProvider feeds;

    setUp(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((HttpRequest req) {
        req.response
          ..statusCode = 200
          ..write(_kPiiIcs)
          ..close();
      });
      kv = InMemoryKv();
      feeds = IcsFeedProvider(
        kv,
        host: server.address.host,
        port: server.port,
        scheme: 'http',
      );
      await kv.settingsSet(<String, String>{
        kCalendarFeedsKey:
            '[{"id":"f1","name":"PII 源","url":"https://example.com/pii.ics"}]',
      });
    });

    tearDown(() async => server.close(force: true));

    test('未设置开关 = 脱敏（默认档，行为不回归）', () async {
      final r = await feeds.query(
          rangeStart: '2026-10-01', rangeEnd: '2026-10-31');
      final e = r.events.single;
      expect(e.location, contains(piiMaskPlaceholder));
      expect(e.location, isNot(contains('13800138000')));
      expect(e.description, isNot(contains('example.com')));
    });

    test("开关写 '0' = 原文透出（用户显式放松，不静默兜底）", () async {
      await kv.settingsSet(<String, String>{SettingsKeys.privacyMaskPii: '0'});
      final r = await feeds.query(
          rangeStart: '2026-10-01', rangeEnd: '2026-10-31');
      final e = r.events.single;
      expect(e.location, contains('13800138000'));
      expect(e.description, contains('doctor@example.com'));
    });

    test("开关从 '0' 改回 '1'：下次查询即恢复脱敏（现读生效）", () async {
      await kv.settingsSet(<String, String>{SettingsKeys.privacyMaskPii: '0'});
      await feeds.query(rangeStart: '2026-10-01', rangeEnd: '2026-10-31');
      await kv.settingsSet(<String, String>{SettingsKeys.privacyMaskPii: '1'});
      final r = await feeds.query(
          rangeStart: '2026-10-01', rangeEnd: '2026-10-31');
      expect(r.events.single.location, isNot(contains('13800138000')));
    });
  });

  group('U12a · 系统路：合并源注入同一开关语义', () {
    test('解析器返 false → 系统事件原文透出', () async {
      final p = CompositeCalendarProvider(
        _NoopIcs(),
        system: _FakeSystem(),
        maskPiiEnabled: () async => false,
      );
      final r = await p.query(rangeStart: '2026-10-01', rangeEnd: '2026-10-07');
      final sys = r.events.firstWhere((e) => e.source == 'system');
      expect(sys.location, contains('13800138000'));
      expect(sys.description, contains('doctor@example.com'));
    });

    test('解析器返 true → 系统事件脱敏（与 ICS 路同口径）', () async {
      final p = CompositeCalendarProvider(
        _NoopIcs(),
        system: _FakeSystem(),
        maskPiiEnabled: () async => true,
      );
      final r = await p.query(rangeStart: '2026-10-01', rangeEnd: '2026-10-07');
      final sys = r.events.firstWhere((e) => e.source == 'system');
      expect(sys.location, contains(piiMaskPlaceholder));
    });

    test('未注入解析器 = 开（保护性缺省，与接线前一致）', () async {
      final p = CompositeCalendarProvider(_NoopIcs(), system: _FakeSystem());
      final r = await p.query(rangeStart: '2026-10-01', rangeEnd: '2026-10-07');
      final sys = r.events.firstWhere((e) => e.source == 'system');
      expect(sys.location, contains(piiMaskPlaceholder));
    });
  });

  group('U12a · 设置快照默认态', () {
    test('未设置 maskPii = 快照开关为真（默认开）；模糊定位 = 假（opt-in）', () async {
      final repo = SettingsRepository(kv: InMemoryKv());
      final s = await repo.readSnapshot();
      expect(s.isSwitchOn(SettingsKeys.privacyMaskPii), isTrue);
      expect(s.isSwitchOn(SettingsKeys.privacyBlurLocation), isFalse);
    });

    test("写 '0' 后快照开关为假（用户显式关闭可观测）", () async {
      final kv = InMemoryKv();
      await kv.settingsSet(<String, String>{SettingsKeys.privacyMaskPii: '0'});
      final s = await SettingsRepository(kv: kv).readSnapshot();
      expect(s.isSwitchOn(SettingsKeys.privacyMaskPii), isFalse);
    });
  });
}

/// 空 ICS 桩（系统路测试不需要 ICS 数据）。
class _NoopIcs implements CalendarFeedProvider {
  @override
  Future<CalendarQueryResult> query({
    required String rangeStart,
    required String rangeEnd,
    String? timezone,
    List<String>? feedIds,
    bool includeSystem = true,
  }) async =>
      const CalendarQueryResult(<CalendarEvent>[]);

  @override
  Future<List<CalendarFeed>> feeds() async => const <CalendarFeed>[];

  @override
  Future<int> refresh({String? feedId}) async => 0;
}
