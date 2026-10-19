/// MCP 内核工具面端口（依赖反转接缝）：内核 McpServer 不直接依赖
/// Repository / 业务工具面，宿主 app 经本端口注入 schemas 与执行器。
/// 模板侧：新 app 实现本接口即可起 MCP 服务。
abstract class McpToolFace {
  /// tools/list 返回的工具 schema 列表。
  List<Map<String, Object?>> schemas();

  /// tools/call 单工具执行；返回**完整 result 对象**——
  /// `{'content': [...], 'isError': bool}`（MCP `CallToolResult` 形状）。
  ///
  /// `isError` 是**结果顶层字段**，绝不能塞进 Content 项（Content 只有
  /// `type`/`text`）；内核 `McpServer` 只透传本 map，不再二次赋值
  /// （standards §3.3 G4：`isError = !success` 唯一派生）。
  Future<Map<String, Object?>> call(
    String name,
    Map<String, Object?> args,
  );
}
