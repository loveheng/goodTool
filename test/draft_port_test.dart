library;

/// 草稿持久化链路单测：`DraftPort` → `user_save_draft`（用户侧网关）→
/// Actor 校验与落盘 → `SettingsRepository` 读回。全程 InMemoryKv，无设备可跑。
///
/// 覆盖：写读闭环 / 空串（清空语义）/ 未登记命令 fail-closed / 非法载荷。

import 'package:flutter_test/flutter_test.dart';
import 'package:goodtools/action/command_gateway.dart';
import 'package:goodtools/action/settings_commands.dart';
import 'package:goodtools/mcp/settings_keys.dart';
import 'package:goodtools/ports.dart';
import 'package:goodtools/repository/settings_repository.dart';
import 'package:goodtools/service/settings_actors.dart';
import 'package:goodtools/ui_ports/draft_port.dart';

void main() {
  late InMemoryKv kv;
  late SettingsRepository repository;
  late CommandGateway gateway;
  late DraftPort port;

  setUp(() {
    kv = InMemoryKv();
    repository = SettingsRepository(kv: kv);
    gateway = CommandGateway();
    SettingsActors(repository: repository).register(gateway);
    port = DraftPort(repository, gateway);
  });

  test('写读闭环：save 后 read 回同值', () async {
    final result = await port.save('1200 * 85%\n10 km to mi');
    expect(result.ok, isTrue);

    final saved = await port.read();
    expect(saved, '1200 * 85%\n10 km to mi');
    expect(await kv.settingsGet(SettingsKeys.calculatorDraft),
        '1200 * 85%\n10 km to mi');
  });

  test('空串 = 清空语义：read 回空串（非 null，示例不再复活）', () async {
    await port.save('');
    final saved = await port.read();
    expect(saved, '');
  });

  test('写后回写入确认（lines 数）', () async {
    final result = await port.save('a\nb\nc');
    expect(result.ok, isTrue);
    expect(result.data, <String, Object?>{'saved': true, 'lines': 3});
  });

  test('非法载荷（content 非 String）→ 结构化失败不落盘', () async {
    final bad = await gateway
        .dispatchUser(const UserSaveDraftCommand({'content': 42}));
    expect(bad.ok, isFalse);
    expect(bad.errorCode, 'DRAFT_CONTENT_INVALID');
    expect(bad.suggestion, isNotNull);
    expect(await port.read(), isNull); // 未落盘
  });

  test('未登记命令 fail-closed（USER_COMMAND_NOT_REGISTERED）', () async {
    final bareGateway = CommandGateway();
    final barePort = DraftPort(repository, bareGateway);
    final result = await barePort.save('anything');
    expect(result.ok, isFalse);
    expect(result.errorCode, 'USER_COMMAND_NOT_REGISTERED');
  });
}
