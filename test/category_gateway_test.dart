library;

/// 领域网关契约测试（纯 Dart，无设备可跑）：覆盖二级派发、枚举外拦截、
/// 写门禁机械不可穿透、错误前缀自动注入、isError 唯一派生。
///
/// 对应 coding-standards §3.3 G1–G5 与设计稿 domain_gateway.md 验证清单。
import 'package:flutter_test/flutter_test.dart';
import 'package:goodtools/action/command_gateway.dart';
import 'package:goodtools/mcp/category_tool_face.dart';

/// R 档子操作（读）：继承基类 `isWrite: false` 默认。
class _EchoSub extends SubAction {
  @override
  String get name => 'echo';

  @override
  String get description => '回显入参文本（读）';

  @override
  String get paramSignature => 'echo(text: string) [必填: text]';

  @override
  Future<SubActionResult> execute(Map<String, Object?> params) async {
    final text = params['text'];
    if (text is! String) {
      return SubActionResult.error('INVALID_ARGUMENT', 'text 必须为字符串');
    }
    return SubActionResult.success([
      {'type': 'text', 'text': 'echo: $text'}
    ]);
  }
}

/// W 档子操作（写）：覆写 `isWrite` + 只构造命令，派发由网关层执行。
class _WriteSub extends SubAction {
  _WriteSub(this._touched);
  final List<String> _touched;

  @override
  String get name => 'write_thing';

  @override
  String get description => '演示写操作（W 档，经 CommandGateway）';

  @override
  String get paramSignature => 'write_thing(id: string) [必填: id]';

  @override
  bool get isWrite => true;

  @override
  Future<SubActionResult> execute(Map<String, Object?> params) async {
    _touched.add('EXECUTE_TOUCHED'); // 未授权时不得触达
    return SubActionResult.success(const <Map<String, Object?>>[]);
  }

  @override
  Command buildCommand(Map<String, Object?> params) => _WriteCommand(params);
}

class _WriteCommand extends Command {
  const _WriteCommand(Map<String, Object?> payload) : super('write_thing', payload);
}

void main() {
  late CommandGateway gw;

  setUp(() {
    gw = CommandGateway();
  });

  test('派发闭环：R 档子操作执行并回 content', () async {
    final cat = CategoryTool('demo', '演示分类', gw);
    cat.register(_EchoSub());
    final r = await cat.call('echo', {'text': 'hi'});
    expect(r.success, isTrue);
    expect(r.isError, isFalse);
    expect(r.content.first['text'], 'echo: hi');
  });

  test('枚举外 action → UNKNOWN_ACTION，错误前缀由派发层注入', () async {
    final cat = CategoryTool('demo', '演示分类', gw);
    cat.register(_EchoSub());
    final r = await cat.call('nope', const <String, Object?>{});
    expect(r.isError, isTrue);
    expect(r.success, isFalse);
    expect(r.content.first['text'], contains('demo.nope: UNKNOWN_ACTION'));
  });

  test('W 档未登记 → PERMISSION_DENIED（带前缀），且执行体未被触达', () async {
    final cat = CategoryTool('demo', '演示分类', gw);
    final touched = <String>[];
    cat.register(_WriteSub(touched));
    final r = await cat.call('write_thing', {'id': 'x'});
    expect(r.isError, isTrue);
    expect(r.errorCode, 'demo.write_thing: PERMISSION_DENIED');
    expect(r.content.first['text'], contains('demo.write_thing: PERMISSION_DENIED'));
    expect(touched, isEmpty);
  });

  test('W 档命中越权键 → 拦截，执行体未被触达', () async {
    gw.register('write_thing', (_) async => const <Map<String, Object?>>[]);
    gw.forbiddenKeys = {'id'}; // 模拟 AI 无权写入的键
    final cat = CategoryTool('demo', '演示分类', gw);
    final touched = <String>[];
    cat.register(_WriteSub(touched));
    final r = await cat.call('write_thing', {'id': 'x'});
    expect(r.isError, isTrue);
    expect(r.errorCode, 'demo.write_thing: PERMISSION_DENIED');
    expect(touched, isEmpty);
  });

  test('toMcpResult 硬绑定 isError = !success', () async {
    final cat = CategoryTool('demo', '演示分类', gw);
    cat.register(_EchoSub());

    final ok = (await cat.call('echo', {'text': 'a'})).toMcpResult();
    expect(ok['isError'], isFalse);
    expect(ok['content'], isNotEmpty);

    final bad = (await cat.call('nope', const <String, Object?>{})).toMcpResult();
    expect(bad['isError'], isTrue);
    expect(bad['content'], isNotEmpty);
  });

  test('toSchema：action 枚举 + paramSignature 进描述', () async {
    final cat = CategoryTool('demo', '演示分类', gw);
    cat.register(_EchoSub());
    final s = cat.toSchema();

    expect(s['name'], 'demo');
    expect(s['description'], contains('echo(text: string) [必填: text]'));

    final props =
        (s['inputSchema']! as Map<String, Object?>)['properties']! as Map<String, Object?>;
    final action = props['action']! as Map<String, Object?>;
    expect(action['enum'], ['echo']);
    expect(props['params'], isNotNull);
  });

  test('toSchema：可见性默认 private（default-deny，漏标即最严）', () {
    final cat = CategoryTool('demo', '演示分类', gw);
    cat.register(_EchoSub());
    final meta = cat.toSchema()['_meta']! as Map<String, Object?>;
    final goodhub = meta['goodhub']! as Map<String, Object?>;
    expect(goodhub['visibility'], 'private');
  });

  test('toSchema：显式 shared 下发到 _meta.goodhub.visibility', () {
    final cat = CategoryTool('demo', '演示分类', gw,
        visibility: ToolVisibility.shared);
    cat.register(_EchoSub());
    final meta = cat.toSchema()['_meta']! as Map<String, Object?>;
    final goodhub = meta['goodhub']! as Map<String, Object?>;
    expect(goodhub['visibility'], 'shared');
  });
}
