// ui-console 契约测试：用户写入口（CommandGateway 用户侧注册表）、凭证安全分流、
// 设置 Actor 的结构化失败、适配层（计算器 / 时空 / 设置）的类型化出口。
//
// 覆盖红线：AI 侧**不可触达** user_* 命令（信任模型机制化）、凭证**不回显明文**
// （standards §6.1）、失败一律带机器码而非静默兜底。
import 'package:flutter_test/flutter_test.dart';
import 'package:goodtools/action/command_gateway.dart';
import 'package:goodtools/action/settings_commands.dart';
import 'package:goodtools/mcp/settings_keys.dart';
import 'package:goodtools/ports.dart';
import 'package:goodtools/repository/settings_repository.dart';
import 'package:goodtools/service/in_memory_secret_store.dart';
import 'package:goodtools/service/persistent_kv.dart';
import 'package:goodtools/service/settings_actors.dart';
import 'package:goodtools/ui_ports/calculator_port.dart';
import 'package:goodtools/ui_ports/geo_port.dart';
import 'package:goodtools/ui_ports/settings_port.dart';

void main() {
  group('CommandGateway · 用户侧注册表', () {
    test('AI 侧 dispatch 不可触达 user_* 命令（未登记即拒）', () async {
      final gateway = CommandGateway();
      final result = await gateway.dispatch(
        UserSetApiKeyCommand(<String, Object?>{
          'provider': 'amap',
          'key': 'k',
        }),
      );
      expect(result.first['text'], contains('未开放给 AI'));
    });

    test('用户侧派发返回类型化结果（非文本信封）', () async {
      final kv = SecretAwareKv(
        plain: InMemoryKv(),
        secrets: InMemorySecretStore(),
      );
      final gateway = CommandGateway();
      SettingsActors(repository: SettingsRepository(kv: kv)).register(gateway);

      final result = await gateway.dispatchUser(
        UserSetApiKeyCommand(<String, Object?>{
          'provider': 'amap',
          'key': 'abcdef123456',
        }),
      );
      expect(result.ok, isTrue);
      expect(result.data, isA<UserSettingsSnapshot>());
    });

    test('用户侧未登记命令 fail-closed（不静默忽略）', () async {
      final gateway = CommandGateway();
      final result = await gateway.dispatchUser(
        UserSetIdentityProfileCommand(<String, Object?>{'text': 'x'}),
      );
      expect(result.ok, isFalse);
      expect(result.errorCode, 'USER_COMMAND_NOT_REGISTERED');
    });
  });

  group('凭证安全分流', () {
    test('凭证键走 SecretStore，普通键走持久化 KV', () async {
      final plain = InMemoryKv();
      final secrets = InMemorySecretStore();
      final kv = SecretAwareKv(plain: plain, secrets: secrets);

      await kv.settingsSet(<String, String>{
        SettingsKeys.amapWebKey: 'secret-key',
        SettingsKeys.identityPrompt: '我是夜班工程师',
      });

      expect(await secrets.read(SettingsKeys.amapWebKey), 'secret-key');
      expect(await plain.settingsGet(SettingsKeys.amapWebKey), isNull);
      expect(await plain.settingsGet(SettingsKeys.identityPrompt), '我是夜班工程师');
      expect(await kv.settingsGet(SettingsKeys.amapWebKey), 'secret-key');
    });

    test('凭证写空串 = 清除（不落明文残留）', () async {
      final secrets = InMemorySecretStore();
      final kv = SecretAwareKv(plain: InMemoryKv(), secrets: secrets);
      await kv.settingsSet(<String, String>{SettingsKeys.amapWebKey: 'k'});
      await kv.settingsSet(<String, String>{SettingsKeys.amapWebKey: ''});
      expect(await secrets.read(SettingsKeys.amapWebKey), isNull);
    });
  });

  group('SettingsActors · 结构化失败与零明文', () {
    late SettingsRepository repository;
    late CommandGateway gateway;

    setUp(() {
      final kv = SecretAwareKv(
        plain: InMemoryKv(),
        secrets: InMemorySecretStore(),
      );
      repository = SettingsRepository(kv: kv);
      gateway = CommandGateway();
      SettingsActors(repository: repository).register(gateway);
    });

    test('写 Key 后快照只给掩码、不含明文', () async {
      final result = await gateway.dispatchUser(
        UserSetApiKeyCommand(<String, Object?>{
          'provider': 'qweather',
          'key': 'qweather-secret-9876',
        }),
      );
      expect(result.ok, isTrue);
      final snapshot = result.data! as UserSettingsSnapshot;
      expect(snapshot.isConfigured(SettingsKeys.qweatherKey), isTrue);
      expect(snapshot.credentialMasked[SettingsKeys.qweatherKey], contains('9876'));
      expect(snapshot.credentialMasked[SettingsKeys.qweatherKey],
          isNot(contains('qweather-secret')));
    });

    test('未知 provider → INVALID_ARGUMENT', () async {
      final result = await gateway.dispatchUser(
        UserSetApiKeyCommand(<String, Object?>{
          'provider': 'notepad',
          'key': 'x',
        }),
      );
      expect(result.ok, isFalse);
      expect(result.errorCode, 'INVALID_ARGUMENT');
      expect(result.suggestion, isNotNull);
    });

    test('缺 provider → MISSING_ARGUMENT', () async {
      final result = await gateway.dispatchUser(
        UserSetApiKeyCommand(<String, Object?>{'key': 'x'}),
      );
      expect(result.ok, isFalse);
      expect(result.errorCode, 'MISSING_ARGUMENT');
    });

    test('未知脱敏开关 → INVALID_ARGUMENT', () async {
      final result = await gateway.dispatchUser(
        UserSetPrivacySwitchCommand(<String, Object?>{
          'key': 'privacy_nope',
          'enabled': true,
        }),
      );
      expect(result.ok, isFalse);
      expect(result.errorCode, 'INVALID_ARGUMENT');
    });

    test('脱敏开关写后回最新状态', () async {
      final result = await gateway.dispatchUser(
        UserSetPrivacySwitchCommand(<String, Object?>{
          'key': SettingsKeys.privacyMaskPii,
          'enabled': true,
        }),
      );
      expect(result.ok, isTrue);
      final snapshot = result.data! as UserSettingsSnapshot;
      expect(snapshot.isSwitchOn(SettingsKeys.privacyMaskPii), isTrue);
    });

    test('身份画像写后可回读原文', () async {
      final result = await gateway.dispatchUser(
        UserSetIdentityProfileCommand(<String, Object?>{'text': ' 夜班工程师 '}),
      );
      expect(result.ok, isTrue);
      final snapshot = result.data! as UserSettingsSnapshot;
      expect(snapshot.identityPrompt, '夜班工程师');
    });
  });

  group('适配层 · 类型化出口', () {
    test('计算器：成功给双轨出参（格式化 + 无损数值）', () {
      const port = CalculatorPort();
      final view = port.eval('0.1 + 0.2');
      expect(view.ok, isTrue);
      expect(view.numeric, '0.3');
      expect(view.text, '0.3');
    });

    test('计算器：失败带机器码与自愈建议（不静默兜底）', () {
      const port = CalculatorPort();
      final view = port.eval('1 +');
      expect(view.ok, isFalse);
      expect(view.errorCode, isNotNull);
      expect(view.errorCode, isNotEmpty);
    });

    test('单位换算：失败带机器码', () {
      const port = CalculatorPort();
      final view = port.convert(1, 'km', 'kg');
      expect(view.ok, isFalse);
      expect(view.errorCode, 'DIMENSION_MISMATCH');
    });

    test('坐标换算：三坐标系齐出（纯内核，不需 Key）', () {
      const port = GeoPort();
      final view = port.convertPoint(39.908722, 116.397499);
      expect(view.ok, isTrue);
      expect(view.points.length, 3);
      expect(view.points.first.label, 'WGS-84');
      // 境内坐标纠偏：GCJ-02 相对 WGS-84 有正向偏移。
      expect(view.points[1].lat, greaterThan(view.points[0].lat));
    });

    test('坐标越界 → INVALID_ARGUMENT', () {
      const port = GeoPort();
      final view = port.convertPoint(200, 300);
      expect(view.ok, isFalse);
      expect(view.errorCode, 'INVALID_ARGUMENT');
    });

    test('测距：同点为 0，不同点为正', () {
      const port = GeoPort();
      expect(port.distance(39.9, 116.4, 39.9, 116.4).distanceMeters, 0);
      expect(
        port.distance(39.9, 116.4, 40.0, 116.5).distanceMeters,
        greaterThan(0),
      );
    });

    test('设置适配层：写经 CommandGateway 用户侧（返回类型化结果）', () async {
      final kv = SecretAwareKv(
        plain: InMemoryKv(),
        secrets: InMemorySecretStore(),
      );
      final gateway = CommandGateway();
      final repository = SettingsRepository(kv: kv);
      SettingsActors(repository: repository).register(gateway);
      final port = SettingsPort(repository, gateway);

      final result = await port.setApiKey(provider: 'amap', key: 'k-1234');
      expect(result.ok, isTrue);
      final snapshot = await port.read();
      expect(snapshot.isConfigured(SettingsKeys.amapWebKey), isTrue);
    });
  });
}
