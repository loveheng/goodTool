// 领域网关契约层（分类嵌入模式）：把 N 个细粒度子操作聚合为 1 个 MCP 工具。
//
// 机械约束正文 = docs/project/coding-standards.md §3.3 G1–G5；设计正文 =
// docs/project/domain_gateway.md。
//
// 可见性纪律（§3.3 G2）：Dart 无「同 package 可见、跨 package 不可见」修饰符，
// 故抽象契约（SubAction / CategoryTool / register）须为 package 内部 public 才能
// 被跨文件子类化；封外部 package 靠**不把本文件进包的公共 barrel 导出**，而非 `_` 前缀。
// 具体子操作实现类（`_XxxSub`）仍以 `_` 前缀私有于各自分类文件。
library;

import '../action/command_gateway.dart';
import 'tool_face.dart';

/// 子操作结构化结果：对齐 MCP `CallToolResult`。
///
/// **G4**：`isError` 在**结果顶层**（Content 项只有 `type`/`text`），由 `success`
/// 唯一派生（`isError = !success`）——本类构造后即不可变，故「`isError:false` 而
/// `success:false`」的矛盾体在类型层面不可能出现。禁止在 `McpServer` 或任何
/// 调用点二次赋值。
class SubActionResult {
  const SubActionResult.success(this.content)
      : isError = false,
        errorCode = null,
        errorMessage = null;

  /// [code] 为**裸机器码**（如 `PERMISSION_DENIED`、`UNEXPECTED_TOKEN`）；
  /// `category.action:` 前缀由 [CategoryTool.call] 在派发层统一注入（G1）。
  SubActionResult.error(this.errorCode, this.errorMessage)
      : content = [
          {'type': 'text', 'text': '[$errorCode] $errorMessage'}
        ],
        isError = true;

  /// MCP content 列表（成功态 = 业务输出；错误态由构造器渲染为 `[code] msg`）。
  final List<Map<String, Object?>> content;

  /// 是否业务失败（MCP 顶层字段，客户端据此判定成败）。
  final bool isError;

  /// 裸机器码（错误态非空）。
  final String? errorCode;

  /// 人类可读说明（错误态非空）。
  final String? errorMessage;

  /// 内容信封语义；与 MCP `isError` 同源派生（G4）。
  bool get success => !isError;

  /// 产出完整 `tools/call` 结果对象；内核只透传、不改写。
  Map<String, Object?> toMcpResult() => {'content': content, 'isError': isError};

  /// 派发层注入 `category.action:` 前缀；子操作只吐裸 code（G1/G5）。
  SubActionResult withPrefix(String category, String action) => isError
      ? SubActionResult.error(
          '$category.$action: ${errorCode ?? 'UNKNOWN'}', errorMessage ?? '')
      : this;
}

/// 子操作契约：一个细粒度能力（如 `geo_compass`、`calendar_marker_add`）。
///
/// **G2**：本契约为 package 内部 public（`_` 是文件级私有，跨文件无法子类化），
/// 具体实现以 `_XxxSub` 私有于各自分类文件。
abstract class SubAction {
  /// 线级指令名；**原样沿用 `docs/product/*.md` 的原子动作名，禁止改名 / 自造**（G1）。
  String get name;

  /// 「怎么用才对」的描述：推荐用法 / 适用场景 / 参数约束 / 反例（standards §3.1）。
  String get description;

  /// 紧凑参数签名，由 [CategoryTool.toSchema] 自动拼进 action 枚举描述（G1）。
  /// 例：`geo_compass()` / `calc_eval(expr: string) [必填: expr]`
  String get paramSignature;

  /// **G3** 写标记：true ⇒ [CategoryTool.call] 在执行体之前强制 `admits` 校验。
  bool get isWrite => false;

  /// R 档执行体（isWrite=false 时由网关调用）。
  Future<SubActionResult> execute(Map<String, Object?> params);

  /// W 档命令构造（isWrite=true 时由网关调用，构造后由**网关层**统一 dispatch）。
  /// 子操作只构造命令，**禁止自行派发、禁止自行鉴权**（G3）。
  Command buildCommand(Map<String, Object?> params) =>
      throw UnsupportedError('R 档子操作无命令构造');
}

/// 领域网关：把同类子操作聚合为 1 个公开 MCP 工具。
///
/// 公开面 = `categoryName` + `action` 枚举（每行含 `paramSignature`）；
/// 内部 = 子操作注册表 `_subs`（私有，仅经 [register] 写入）。
class CategoryTool {
  CategoryTool(
    this.categoryName,
    this.categoryDescription,
    this.commandGateway,
  );

  /// MCP 线级工具名。
  final String categoryName;

  /// 工具整体描述（下属 action 明细由 [toSchema] 自动拼装）。
  final String categoryDescription;

  /// 写门禁端口（唯一写入口，standards §2.3 / G3）。
  final CommandGateway commandGateway;

  final Map<String, SubAction> _subs = {};

  /// 登记子操作（package 内部 public，供分类文件跨文件调用）。
  void register(SubAction a) => _subs[a.name] = a;

  /// 生成 1 个 MCP Tool 定义：`action` 枚举 + 自由 `params` 对象。
  ///
  /// G1：参数名与类型经 `paramSignature` 随枚举一起下发给 LLM，兼顾命中率与 Token。
  Map<String, Object?> toSchema() => {
        'name': categoryName,
        'description': '$categoryDescription\n支持操作：\n'
            '${_subs.values.map((a) => '- ${a.paramSignature}: ${a.description}').join('\n')}',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'action': {
              'type': 'string',
              'enum': _subs.keys.toList(),
              'description': '目标执行指令（参数见各行签名）',
            },
            'params': {
              'type': 'object',
              'description': '该指令的具体键值参数（字段名与类型见 action 描述）',
            },
          },
          'required': ['action'],
        },
      };

  /// 二级派发：枚举校验 → 写门禁拦截 → 执行 / 统一派发 → 注入错误前缀。
  ///
  /// **G1**：本方法刻意做成**单一出口**——所有分支（含网关层自身的拒绝）都汇入
  /// 同一个 `result`，再由唯一的 `withPrefix` 注入 `category.action:` 前缀。
  /// 新增早退分支不可能漏掉前缀注入；子操作只吐裸 code（G5）。
  Future<SubActionResult> call(String action, Map<String, Object?> params) async {
    final SubActionResult result;
    final sub = _subs[action];
    if (sub == null) {
      result = SubActionResult.error(
          'UNKNOWN_ACTION', '分类 $categoryName 无指令 $action');
    } else if (sub.isWrite && !commandGateway.admits(action, params)) {
      // G3 写门禁：子操作执行体之前拦截，物理级无法穿透
      result = SubActionResult.error(
          'PERMISSION_DENIED', 'Write operation unauthorized');
    } else if (sub.isWrite) {
      // 唯一写入口：W 档由网关层统一 dispatch，子操作只构造命令
      result = SubActionResult.success(
          await commandGateway.dispatch(sub.buildCommand(params)));
    } else {
      result = await sub.execute(params);
    }
    return result.withPrefix(categoryName, action);
  }
}

/// 聚合工具面：实现 [McpToolFace]，线级只暴露各分类工具名 + `action` 枚举。
///
/// 注册/派发对内核零侵入——内核只认 `McpToolFace`，不感知分类概念。
class CategoryToolFace implements McpToolFace {
  CategoryToolFace(this._categories);
  final List<CategoryTool> _categories;

  @override
  List<Map<String, Object?>> schemas() =>
      _categories.map((c) => c.toSchema()).toList();

  @override
  Future<Map<String, Object?>> call(String name, Map<String, Object?> args) async {
    CategoryTool? cat;
    for (final c in _categories) {
      if (c.categoryName == name) {
        cat = c;
        break;
      }
    }
    if (cat == null) {
      return SubActionResult.error('UNKNOWN_TOOL', '未识别的服务分类: $name')
          .toMcpResult();
    }
    final action = args['action'];
    if (action is! String) {
      return SubActionResult.error('MISSING_ACTION', '请求缺少 action 字段')
          .toMcpResult();
    }
    final params = args['params'] is Map<String, Object?>
        ? args['params'] as Map<String, Object?>
        : const <String, Object?>{};
    return (await cat.call(action, params)).toMcpResult();
  }
}

/// LLM 弱类型输出宽容解析（防数字/布尔被包成字符串等漂移）。
///
/// **G5**：仅允许在**子操作入参边界**使用；不可解析一律返回 null，由子操作
/// 转成带 `code` 的 [SubActionResult.error]，**禁止取默认值兜底**。
double? parseDouble(Object? val) {
  if (val is num) return val.toDouble();
  if (val is String) return double.tryParse(val);
  return null;
}

int? parseInt(Object? val) {
  if (val is int) return val;
  if (val is double) return val.truncate();
  if (val is String) return int.tryParse(val);
  return null;
}

bool? parseBool(Object? val) {
  if (val is bool) return val;
  if (val is String) return val.toLowerCase() == 'true';
  return null;
}
