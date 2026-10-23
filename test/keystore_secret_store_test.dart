// ui-console U5 收尾：KeystoreSecretStore 平台通道语义 + fail-closed 映射。
//
// 覆盖红线（standards §6.1 / §1.2）：
//  - 凭证经**平台通道**读写（明文不出进程边界到 Dart 之上的存储）；
//  - 缺键语义 = null（端口约定），平台故障 = SecretStoreException 透出，
//    **绝不**被吞成 null 假装「未配置」。
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goodtools/mcp/secret_store.dart';
import 'package:goodtools/mcp/settings_keys.dart';
import 'package:goodtools/ports.dart';
import 'package:goodtools/service/keystore_secret_store.dart';
import 'package:goodtools/service/persistent_kv.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  /// 装一个内存版「平台」（模拟 Kotlin 侧 Keystore 通道行为）。
  void mockPlatform(Map<String, String> backing) {
    messenger.setMockMethodCallHandler(kSecretStoreChannel, (call) async {
      final args = Map<String, Object?>.from(call.arguments as Map);
      final key = args['key'] as String;
      switch (call.method) {
        case 'read':
          return backing[key];
        case 'write':
          backing[key] = args['value'] as String;
          return null;
        case 'delete':
          backing.remove(key);
          return null;
        default:
          throw MissingPluginException();
      }
    });
  }

  group('KeystoreSecretStore · 平台通道语义', () {
    test('read/write/delete 经通道往返，缺键回 null', () async {
      final backing = <String, String>{};
      mockPlatform(backing);
      const secrets = KeystoreSecretStore();

      expect(await secrets.read(SettingsKeys.amapWebKey), isNull);

      await secrets.write(SettingsKeys.amapWebKey, 'amap-secret-42');
      expect(await secrets.read(SettingsKeys.amapWebKey), 'amap-secret-42');

      await secrets.write(SettingsKeys.amapWebKey, 'rotated-99');
      expect(await secrets.read(SettingsKeys.amapWebKey), 'rotated-99');

      await secrets.delete(SettingsKeys.amapWebKey);
      expect(await secrets.read(SettingsKeys.amapWebKey), isNull);
    });

    test('SecretAwareKv 分流：凭证键走平台通道，普通键不走', () async {
      final backing = <String, String>{};
      mockPlatform(backing);
      final plain = InMemoryKv(); // 仅观测「普通键未泄入凭证通道」
      final kv = SecretAwareKv(plain: plain, secrets: const KeystoreSecretStore());

      await kv.settingsSet(<String, String>{
        SettingsKeys.qweatherKey: 'q-secret',
        SettingsKeys.identityPrompt: '我是夜班工程师',
      });

      // 凭证经平台通道（mock 内存）落地；普通键未泄入凭证通道。
      expect(backing[SettingsKeys.qweatherKey], 'q-secret');
      expect(await plain.settingsGet(SettingsKeys.qweatherKey), isNull);
      expect(await plain.settingsGet(SettingsKeys.identityPrompt), '我是夜班工程师');

      // 写空串 = 清除：凭证通道收到 delete，无残留。
      await kv.settingsSet(<String, String>{SettingsKeys.qweatherKey: ''});
      expect(backing.containsKey(SettingsKeys.qweatherKey), isFalse);
      expect(await kv.settingsGet(SettingsKeys.qweatherKey), isNull);
    });

    test('PlatformException 透出为 SecretStoreException（fail-closed）', () async {
      messenger.setMockMethodCallHandler(kSecretStoreChannel, (call) async {
        throw PlatformException(code: 'KEYSTORE_ERROR', message: '解密失败');
      });
      const secrets = KeystoreSecretStore();

      await expectLater(
        secrets.read(SettingsKeys.amapWebKey),
        throwsA(isA<SecretStoreException>()
            .having((e) => e.code, 'code', 'KEYSTORE_ERROR')
            .having((e) => e.message, 'message', contains('解密失败'))),
      );
      // 写路径同样 fail-closed：不静默丢弃用户输入。
      await expectLater(
        secrets.write(SettingsKeys.amapWebKey, 'k'),
        throwsA(isA<SecretStoreException>()),
      );
    });

    test('通道未注册 → unavailable（无头环境可观测，不降级为空存储）', () async {
      messenger.setMockMethodCallHandler(
          kSecretStoreChannel, (call) async => throw MissingPluginException());
      const secrets = KeystoreSecretStore();

      await expectLater(
        secrets.read(SettingsKeys.amapWebKey),
        throwsA(isA<SecretStoreException>()
            .having((e) => e.code, 'code', SecretStoreErr.unavailable)),
      );
    });
  });
}
