library;

/// 模板冒烟测试：KV 端口 + CommandGateway 白名单/越权门 + 工具面 ping 链路。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:good_template/action/command_gateway.dart';
import 'package:good_template/mcp/mcp_server.dart';
import 'package:good_template/mcp/tool_face.dart';
import 'package:good_template/ports.dart';

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
}

class _Dummy extends Command {
  const _Dummy(String name) : super(name, const {});
}
