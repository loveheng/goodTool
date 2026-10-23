library;

import '../action/command_gateway.dart';
import '../action/settings_commands.dart';
import '../mcp/settings_keys.dart';
import '../repository/settings_repository.dart';

/// 计算器草稿台 UI 适配层：**读经 Repository（R5），写经 CommandGateway（R1）**。
///
/// 草稿是**用户本人的纸面**（UI 会话态）：写入走 `user_save_draft` 用户命令
/// （`CommandGateway` 用户侧注册表），AI 不可经 MCP 工具面触达——与设置页
/// `SettingsPort` 同一条纪律（读不直连 KV，写不旁路网关）。
///
/// 内容口径：各块单行文本以 `\n` 连接（块本身 maxLines:1，`\n` 无损，不涉
/// JSON 编解码——R2 免检）。
class DraftPort {
  const DraftPort(this._repository, this._gateway);

  final SettingsRepository _repository;
  final CommandGateway _gateway;

  /// 读已保存草稿；从未保存过返回 null（调用方据此判断首启播种示例）。
  Future<String?> read() => _repository.read(SettingsKeys.calculatorDraft);

  /// 保存草稿内容（全量覆盖式——草稿台就是单文档纸面）。
  Future<UserCommandResult> save(String content) =>
      _gateway.dispatchUser(UserSaveDraftCommand({'content': content}));
}
