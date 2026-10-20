library;

/// 唯一写入口空框架（模式提取自 shiguang lib/action/command_handler.dart，
/// 模式照抄拾贝 item_action_handler）。
///
/// 红线语义（新 app 照此执行）：一切 AI 写操作必经 [CommandGateway]，禁绕过直写存储。
/// 三层门：
/// 1. 白名单：只有 [Command] 子类登记过的命令才能进来（未登记 = errPermission）；
/// 2. propose 校验：`propose_*` 前缀命令携带提案载荷，[validatePropose] 机械校验，
///    校验失败原样拒绝（AI 不得改写用户意图）；
/// 3. 越权门：[forbiddenKeys] 列出的键 AI 无权写入，命中即拒（提示引导用户自设）。
///
/// 新 app 用法：定义自己的 sealed 命令族（继承 [Command]），在 [register] 登记
/// Actor，工具面（McpToolFace.call）统一转发到这里。
import 'dart:async';

/// 写命令基类：name 为工具面同名命令；payload 为参数。
abstract class Command {
  const Command(this.name, this.payload);
  final String name;
  final Map<String, Object?> payload;
}

/// 命令执行器：拿到命令返回 MCP content 形状（Map 列表）。
typedef CommandActor = Future<List<Map<String, Object?>>> Function(Command cmd);

/// **用户侧**命令执行器：返回**类型化结果**，不走 MCP 的 `{content,isError}` 文本信封。
///
/// 与 AI 侧 `CommandActor` 的分工：AI 侧要序列化成文本给 LLM，用户侧（App 设置页）
/// 直接吃类型化对象——若让 UI 去 `jsonDecode` 文本信封，必触 R2
/// （ui-design §8.3 规则 2：类型化对象由内核/适配层构造）。
typedef UserCommandActor = Future<UserCommandResult> Function(Command cmd);

/// 用户侧命令结果（类型化；无 JSON 信封、无文本信封）。
class UserCommandResult {
  const UserCommandResult({
    required this.ok,
    this.data,
    this.errorCode,
    this.message,
    this.suggestion,
  });

  /// 成功结果（`data` 为类型化快照）。
  const UserCommandResult.success(this.data)
      : ok = true,
        errorCode = null,
        message = null,
        suggestion = null;

  /// 失败结果（带机器码与自愈指引）。
  const UserCommandResult.failure(
    this.errorCode,
    this.message, {
    this.suggestion,
  })  : ok = false,
        data = null;

  final bool ok;

  /// 写后最新状态快照（对齐读工具同形状，standards §5.2）。
  final Object? data;

  final String? errorCode;
  final String? message;
  final String? suggestion;
}

class CommandGateway {
  final Map<String, CommandActor> _actors = {};

  /// AI 无权写入的键（越权门）：新 app 按自己的权限边界登记。
  Set<String> forbiddenKeys = {};

  /// 登记命令 → 执行器（App 侧装配时调用；AI 不可经工具面注册）。
  void register(String name, CommandActor actor) => _actors[name] = actor;

  /// 用户侧命令注册表（与 AI 侧 `_actors` **物理分离**）。
  ///
  /// 产品信任模型：敏感设置（地图/天气 Key、脱敏开关、身份画像）**仅用户本人
  /// 在 App 内自设**，Agent 经工具写入会被拒。故用户命令不进 AI 侧注册表——
  /// AI 只能触达 `CategoryTool` 枚举内的 action，用户命令**不可经 MCP 工具面到达**。
  final Map<String, UserCommandActor> _userActors = {};

  /// 登记**用户本人**触发的命令（UI 设置页等）；AI 不可经工具面注册或触达。
  void registerUser(String name, UserCommandActor actor) =>
      _userActors[name] = actor;

  /// 用户侧唯一写入口。
  ///
  /// 与 AI 侧**同一写入口语义**（同一 `CommandGateway` 实例、同一命令族规范），
  /// 但有两处刻意的差异：
  /// 1. **不经过 AI 专属的 `forbiddenKeys` 越权门**——该门拦的是 AI，不是用户本人；
  /// 2. 返回**类型化对象**而非文本信封——UI 不得 `jsonDecode`（R2）。
  ///
  /// 未登记即拒（fail-closed），不静默忽略。
  Future<UserCommandResult> dispatchUser(Command cmd) async {
    final actor = _userActors[cmd.name];
    if (actor == null) {
      return UserCommandResult.failure(
        'USER_COMMAND_NOT_REGISTERED',
        '命令 ${cmd.name} 未登记（用户侧）',
        suggestion: '请确认该命令已在 CommandGateway.registerUser 中登记',
      );
    }
    return actor(cmd);
  }

  /// AI 是否可执行该命令（白名单 + 越权门）。
  bool admits(String name, Map<String, Object?> args) {
    if (!_actors.containsKey(name)) return false;
    final keys = args.keys.toSet();
    return keys.intersection(forbiddenKeys).isEmpty;
  }

  /// 唯一写入口：未登记 / 越权一律拒；通过则分发。
  Future<List<Map<String, Object?>>> dispatch(Command cmd) async {
    final actor = _actors[cmd.name];
    if (actor == null) {
      return [
        {'type': 'text', 'text': '错误：命令 ${cmd.name} 未开放给 AI'}
      ];
    }
    if (!admits(cmd.name, cmd.payload)) {
      return [
        {'type': 'text', 'text': '错误：${cmd.name} 命中越权键，请建议用户在 app 内自行修改'}
      ];
    }
    return actor(cmd);
  }

  /// propose 机械校验钩子：新 app 覆写以实现「提案先验，不合格整单拒」。
  Future<String?> validatePropose(Command cmd) async => null;
}
