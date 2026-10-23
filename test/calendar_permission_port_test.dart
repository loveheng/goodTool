// U12b 运行时日历权限申请入口单测（mock MethodChannel + 视图映射）。
//
// 覆盖红线：权限端口 fail-closed——granted / settings_opened / 平台故障
// 一律机器码透出，不假装已授权；`CalendarPort.requestPermission` 三态类型化。
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:good_template/mcp/calendar_provider.dart';
import 'package:good_template/repository/marker_repository.dart';
import 'package:good_template/service/calendar_permission_port.dart';
import 'package:good_template/service/marker_store.dart';
import 'package:good_template/ui_ports/calendar_port.dart';

/// 与 `kSystemCalendarChannel` 同名（mock 按通道名生效）。
const MethodChannel _kCalendarChannel =
    MethodChannel('com.goodhub.good_template/calendar');

class _FakePermission implements CalendarPermissionPort {
  _FakePermission(this.outcome);

  /// null = 模拟平台故障（抛 CalendarFeedException）。
  final CalendarPermissionOutcome? outcome;

  int callCount = 0;

  @override
  Future<CalendarPermissionOutcome> request() async {
    callCount++;
    final o = outcome;
    if (o == null) {
      throw const CalendarFeedException(
          CalendarErr.sourceUnavailable, '平台通道故障');
    }
    return o;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  group('U12b · 权限端口（平台通道）', () {
    test('granted / settings_opened 语义映射', () async {
      messenger.setMockMethodCallHandler(_kCalendarChannel, (call) async {
        expect(call.method, 'requestCalendarPermission');
        return 'granted';
      });
      expect(await const MethodChannelCalendarPermissionPort().request(),
          CalendarPermissionOutcome.granted);

      messenger.setMockMethodCallHandler(
          _kCalendarChannel, (call) async => 'settings_opened');
      expect(await const MethodChannelCalendarPermissionPort().request(),
          CalendarPermissionOutcome.settingsOpened);
    });

    test('PlatformException → CalendarFeedException 透出（fail-closed）', () async {
      messenger.setMockMethodCallHandler(_kCalendarChannel, (call) async {
        throw PlatformException(
            code: 'SETTINGS_LAUNCH_FAILED', message: '无设置页');
      });
      await expectLater(
        const MethodChannelCalendarPermissionPort().request(),
        throwsA(isA<CalendarFeedException>()
            .having((e) => e.code, 'code', 'SETTINGS_LAUNCH_FAILED')),
      );
    });

    test('MissingPluginException → sourceUnavailable（无头环境不假装授权）', () async {
      messenger.setMockMethodCallHandler(_kCalendarChannel,
          (call) async => throw MissingPluginException());
      await expectLater(
        const MethodChannelCalendarPermissionPort().request(),
        throwsA(isA<CalendarFeedException>().having(
            (e) => e.code, 'code', CalendarErr.sourceUnavailable)),
      );
    });

    test('返回语义异常 → parseFailed（不猜）', () async {
      messenger.setMockMethodCallHandler(
          _kCalendarChannel, (call) async => 'weird');
      await expectLater(
        const MethodChannelCalendarPermissionPort().request(),
        throwsA(isA<CalendarFeedException>()
            .having((e) => e.code, 'code', CalendarErr.parseFailed)),
      );
    });
  });

  group('U12b · CalendarPort.requestPermission 视图映射', () {
    test('granted / settingsOpened / 故障三态类型化', () async {
      final markers = MarkerRepository(store: InMemoryMarkerStore());

      final granted = CalendarPort(
        feeds: null,
        markers: markers,
        permission: _FakePermission(CalendarPermissionOutcome.granted),
      );
      final v1 = await granted.requestPermission();
      expect(v1.ok, isTrue);
      expect(v1.granted, isTrue);
      expect(v1.settingsOpened, isFalse);

      final opened = CalendarPort(
        feeds: null,
        markers: markers,
        permission: _FakePermission(CalendarPermissionOutcome.settingsOpened),
      );
      final v2 = await opened.requestPermission();
      expect(v2.ok, isTrue);
      expect(v2.granted, isFalse);
      expect(v2.settingsOpened, isTrue);

      final failed = CalendarPort(
        feeds: null,
        markers: markers,
        permission: _FakePermission(null),
      );
      final v3 = await failed.requestPermission();
      expect(v3.ok, isFalse);
      expect(v3.errorCode, CalendarErr.sourceUnavailable);
    });
  });
}
