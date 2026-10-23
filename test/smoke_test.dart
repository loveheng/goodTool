library;

/// 模板冒烟测试：KV 端口 + CommandGateway 白名单/越权门 + 工具面 ping 链路。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:goodtools/action/command_gateway.dart';
import 'package:goodtools/mcp/mcp_server.dart';
import 'package:goodtools/mcp/tool_face.dart';
import 'package:goodtools/ports.dart';
import 'package:goodtools/service/mcp_controller.dart';

class _PongFace implements McpToolFace {
  @override
  List<Map<String, Object?>> schemas() => const [];

  @override
  Future<Map<String, Object?>> call(String name, Map<String, Object?> args) async => {
        'content': [
          {'type': 'text', 'text': 'pong'}
        ],
        'isError': false,
      };
}

/// 业务失败桩：isError=true，用于验证内核**透传**而非改写。
class _ErrorFace implements McpToolFace {
  @override
  List<Map<String, Object?>> schemas() => const [];

  @override
  Future<Map<String, Object?>> call(String name, Map<String, Object?> args) async => {
        'content': [
          {'type': 'text', 'text': '[geo.geo_teleport: UNKNOWN_ACTION] 无此指令'}
        ],
        'isError': true,
      };
}

void main() {
  test('InMemoryKv 读回写值', () async {
    final kv = InMemoryKv();
    await kv.settingsSet({'a': '1'});
    expect(await kv.settingsGet('a'), '1');
    expect(await kv.settingsGet('b'), isNull);
  });

  test('CommandGateway：未登记拒绝 / 已登记分发', () async {
    final gw = CommandGateway();
    final unregistered = await gw.dispatch(_Dummy('nope'));
    expect(unregistered.first['text'], contains('未开放'));
    gw.register('ok', (_) async => const [
          {'type': 'text', 'text': 'done'}
        ]);
    final ok = await gw.dispatch(_Dummy('ok'));
    expect(ok.first['text'], 'done');
  });

  test('McpServer.handleJsonRpc：initialize + ping 全链路（纯 Dart 内核）', () async {
    final server = McpServer(toolFace: _PongFace(), tokenProvider: () => null);
    final init = await server.handleJsonRpc(jsonEncode({
      'jsonrpc': '2.0',
      'id': 1,
      'method': 'initialize',
      'params': {'protocolVersion': '2025-03-26'},
    }));
    final initMap = jsonDecode(init) as Map<String, Object?>;
    expect(initMap['result'], isNotNull);
    final call = await server.handleJsonRpc(jsonEncode({
      'jsonrpc': '2.0',
      'id': 2,
      'method': 'tools/call',
      'params': {'name': 'ping', 'arguments': {}},
    }));
    expect(jsonDecode(call)['result'], isNotNull);
  });

  test('McpServer：tools/call 错误态 isError 原样透传（内核不改写为成功）',
      () async {
    final server = McpServer(toolFace: _ErrorFace(), tokenProvider: () => null);
    final resp = await server.handleJsonRpc(jsonEncode({
      'jsonrpc': '2.0',
      'id': 3,
      'method': 'tools/call',
      'params': {'name': 'geo', 'arguments': {'action': 'geo_teleport'}},
    }));
    final result = (jsonDecode(resp) as Map)['result'] as Map;
    expect(result['isError'], isTrue);
    expect(
      ((result['content'] as List).first as Map)['text'],
      contains('UNKNOWN_ACTION'),
    );
  });

  test('serverInfo 为本 app 标识（无模板项目名残留）', () async {
    final server = McpServer(toolFace: _PongFace(), tokenProvider: () => null);
    final init = await server.handleJsonRpc(jsonEncode({
      'jsonrpc': '2.0',
      'id': 4,
      'method': 'initialize',
      'params': {'protocolVersion': '2025-03-26'},
    }));
    final info =
        ((jsonDecode(init) as Map)['result'] as Map)['serverInfo'] as Map;
    expect(info['name'], 'goodtools');
  });

  test('McpController.pushSuggestion 广播建议（内核不再按工具名嗅探）',
      () async {
    final controller = McpController(
      kv: InMemoryKv(),
      toolFaceFactory: () => _PongFace(),
    );
    expectLater(controller.suggestionStream, emits(<String, Object?>{'key': 'x'}));
    controller.pushSuggestion(const {'key': 'x'});
  });
}

class _Dummy extends Command {
  const _Dummy(String name) : super(name, const {});
}
