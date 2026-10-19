library;

/// 示例工具面：示范新 app 如何实现 McpToolFace 端口并接入 CommandGateway。
/// 两个演示工具：ping（读）、echo_set（写，走唯一写入口）。
/// 新 app 上工时：删除本文件，按 shiguang lib/mcp/tools.dart 的模式写自己的工具面。
import 'dart:convert';

import '../action/command_gateway.dart';
import '../mcp/tool_face.dart';

/// 记忆 KV（示例存储；真实 app 换成自己的 repository/store）。
final Map<String, String> sampleStore = {};

class SampleToolFace implements McpToolFace {
  SampleToolFace(this.gateway);

  final CommandGateway gateway;

  @override
  List<Map<String, Object?>> schemas() => [
        {
          'name': 'ping',
          'description': '探活：返回 pong 与当前工具面版本',
          'inputSchema': {'type': 'object', 'properties': {}},
        },
        {
          'name': 'note_put',
          'description': '写一条备忘（演示唯一写入口：写操作必经 CommandGateway）',
          'inputSchema': {
            'type': 'object',
            'properties': {
              'key': {'type': 'string'},
              'value': {'type': 'string'},
            },
            'required': ['key', 'value'],
          },
        },
      ];

  @override
  Future<Map<String, Object?>> call(
    String name,
    Map<String, Object?> args,
  ) async {
    switch (name) {
      case 'ping':
        return {
          'content': [
            {'type': 'text', 'text': 'pong (good_template toolface v0.1)'}
          ],
          'isError': false,
        };
      case 'note_put':
        // 唯一写入口：一切 AI 写操作经 CommandGateway 分发，禁绕过
        final content = await gateway.dispatch(_NotePutCommand(args));
        return {'content': content, 'isError': false};
      default:
        // 未知工具 = 失败（isError: true），不得让 Agent 误判为成功
        return {
          'content': [
            {'type': 'text', 'text': '未知工具: $name'}
          ],
          'isError': true,
        };
    }
  }
}

/// 示例写命令（sealed 命令族在此按 app 需要扩充）。
class _NotePutCommand extends Command {
  const _NotePutCommand(Map<String, Object?> payload)
      : super('note_put', payload);
}

/// jsonEncode 出口（工具面返回体统一走 json 编码口径）。
String encodeContent(List<Map<String, Object?>> content) => jsonEncode(content);
