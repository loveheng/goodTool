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

import 'dart:convert';
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
        errorMessage = null,
        _jsonError = null;

  /// [code] 为**裸机器码**（如 `PERMISSION_DENIED`、`UNEXPECTED_TOKEN`）；
  /// `category.action:` 前缀由 [CategoryTool.call] 在派发层统一注入（G1）。
  SubActionResult.error(this.errorCode, this.errorMessage)
      : content = [
          {'type': 'text', 'text': '[$errorCode] $errorMessage'}
        ],
        isError = true,
        _jsonError = null;

  /// 结构化错误：content 为 JSON 文本，携带 calculator.md 自愈字段
  /// （offset / candidates / suggestion / expression）。前缀由 [withPrefix]
  /// 注入到 JSON 内的 `error.code`，不丢失自愈字段（G1/G5）。
  SubActionResult.structuredError(this.errorCode, this.errorMessage, this._jsonError)
      : content = [
          {
            'type': 'text',
            'text': jsonEncode(<String, Object?>{
              'success': false,
              'error': _jsonError,
            }),
          }
        ],
        isError = true;

  SubActionResult._raw({
    required this.content,
    required this.isError,
    this.errorCode,
    this.errorMessage,
  }) : _jsonError = null;

  /// MCP content 列表（成功态 = 业务输出；错误态由构造器渲染为 `[code] msg`
  /// 或结构化 JSON 错误）。
  final List<Map<String, Object?>> content;

  /// 是否业务失败（MCP 顶层字段，客户端据此判定成败）。
  final bool isError;

  /// 裸机器码（错误态非空）。
  final String? errorCode;

  /// 人类可读说明（错误态非空）。
  final String? errorMessage;

  /// 结构化错误自愈字段（仅 [structuredError] 构造时非空）。
  final Map<String, Object?>? _jsonError;

  /// 内容信封语义；与 MCP `isError` 同源派生（G4）。
  bool get success => !isError;

  /// 产出完整 `tools/call` 结果对象；内核只透传、不改写。
  Map<String, Object?> toMcpResult() => {'content': content, 'isError': isError};

  /// **G6 Actor 信封派生**：W 档命令 Actor 输出的首条 text 若为
  /// `{'success': bool, ...}` JSON 信封，则 `isError = !success`。
  ///
  /// 没有这一步，Actor 里的业务失败（URL 被 SSRF 护栏拒绝、feedId 不存在等）
  /// 只能体现为文本里的 `success:false`，MCP 顶层 `isError` 仍是 false——
  /// 客户端据此误判「调用成功」，Agent 可能继续基于失败结果推理（G4 一致性）。
  /// 非信封输出（历史 / 第三方 Actor）按成功透传，不强行解释。
  static SubActionResult fromActor(List<Map<String, Object?>> content) {
    final first = content.isEmpty ? null : content.first;
    final text = first?['text'];
    if (text is String) {
      try {
        final decoded = jsonDecode(text);
        if (decoded is Map<String, Object?>) {
          if (decoded['success'] != false) {
            return SubActionResult._raw(content: content, isError: false);
          }
          // 失败信封：**必须走 structuredError**——若用 `_raw` 构造（errorCode 为
          // null），withPrefix 会把 `[前缀: UNKNOWN]` 文本**替换掉**原 JSON 信封，
          // 自愈字段（suggestion 等）随之丢失。structuredError 使 withPrefix 原地
          // 改写 JSON 内的 code，信封其余字段保真。
          final rawError = decoded['error'];
          final errorMap = rawError is Map<String, Object?>
              ? rawError
              : <String, Object?>{
                  'code': 'ACTOR_FAILED',
                  'message': '命令执行失败'
                };
          return SubActionResult.structuredError(
            errorMap['code'] is String ? errorMap['code'] as String : 'ACTOR_FAILED',
            errorMap['message'] is String
                ? errorMap['message'] as String
                : '命令执行失败',
            errorMap,
          );
        }
      } on FormatException {
        // 非信封 JSON：按成功透传（不解释，不猜测）。
      }
    }
    return SubActionResult._raw(content: content, isError: false);
  }

  /// 派发层注入 `category.action:` 前缀；子操作只吐裸 code（G1/G5）。  ///
  /// 结构化错误（[structuredError]）原地改写 JSON 内 `error.code` 为带前缀版本，
  /// 保留 offset/candidates 等自愈字段；非结构化错误走原 `[前缀:code] msg` 文本。
  SubActionResult withPrefix(String category, String action) {
    if (!isError) return this;
    final prefixed = '$category.$action: ${errorCode ?? 'UNKNOWN'}';
    if (_jsonError != null) {
      final j = <String, Object?>{..._jsonError};
      j['code'] = prefixed;
      return SubActionResult._raw(
        content: [
          {
            'type': 'text',
            'text': jsonEncode(<String, Object?>{
              'success': false,
              'error': j,
            }),
          }
        ],
        isError: true,
        errorCode: prefixed,
        errorMessage: errorMessage ?? '',
      );
    }
    return SubActionResult.error(prefixed, errorMessage ?? '');
  }
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

  /// **G6 W 档前置校验**（可选）：`admits` 通过后、`buildCommand` 之前调用。
  ///
  /// 返回非 null ⇒ 以其为最终结果、跳过派发。存在的理由：`buildCommand` 只能
  /// 返回 [Command]，**无法表达失败**——必填缺失 / URL 护栏拒绝 / 幂等冲突这类
  /// 可预期失败若塞进行命令构造，只能抛异常，最终被内核兜成散文错误（破坏 D3
  /// 结构化错误口径）。前置校验让「校验 → 结构化错误」有正规出口。
  ///
  /// 只做**入参与格式校验**，不得触达任何写端口。
  SubActionResult? validate(Map<String, Object?> params) => null;
}

/// 工具可见性范围标记（对齐 SDK 0.2.0 `ToolVisibility`）——**纯声明，非访问控制**。
///
/// 只回答「该工具属于哪个曝光分桶」。取值经 [CategoryTool.toSchema] 原样写进
/// `tools/list` 每个工具对象的 `_meta.goodhub.visibility`，由宿主解析决定如何
/// 聚合 / 是否收进共享目录；本侧**不据此剔除条目、也不拦截任何 `tools/call`**。
///
/// **为何由 Dart 侧下发**：本仓业务逻辑全在 Dart，`McpBinderService.kt` 重写
/// `handleJsonRpc` 全量接管路由，SDK 的运行时反射派发器扫不到任何 `@McpTool`
/// 方法（因而也扫不到它的 `visibility` 参数）。`tools/list` 由 [CategoryToolFace]
/// 产出，故这个标记必须在 Dart 侧自行下发——漏发即宿主按 default-deny 判为私有。
///
/// 默认 [private]（default-deny，与 SDK `ToolVisibility.PRIVATE` 同口径）：
/// 未显式声明的分类一律私有，漏标即最严，**不臆造曝光**。
enum ToolVisibility {
  /// 仅本机 / 本地消费，宿主不得收进共享目录。
  private,

  /// 允许宿主聚合进共享面。
  shared;

  /// 线级取值（小写短名，与 SDK `ToolVisibility.wireName` 同源）。
  String get wireName => name;
}

/// 领域网关：把同类子操作聚合为 1 个公开 MCP 工具。
///
/// 公开面 = `categoryName` + `action` 枚举（每行含 `paramSignature`）；
/// 内部 = 子操作注册表 `_subs`（私有，仅经 [register] 写入）。
class CategoryTool {
  CategoryTool(
    this.categoryName,
    this.categoryDescription,
    this.commandGateway, {
    this.visibility = ToolVisibility.private,
    this.readOnlyHint = false,
    this.destructiveHint = false,
  });

  /// MCP 线级工具名。
  final String categoryName;

  /// 工具整体描述（下属 action 明细由 [toSchema] 自动拼装）。
  final String categoryDescription;

  /// 写门禁端口（唯一写入口，standards §2.3 / G3）。
  ///
  /// R 档-only 分类（如 `math_utility`）无写操作，可传 `null`——[call] 仅在
  /// 遇到 W 档子操作时才触达本端口（物理上不可能被 R 档执行体穿透）。
  final CommandGateway? commandGateway;

  /// 可见性范围标记（SDK 0.2.0）：随 [toSchema] 下发到 `_meta.goodhub.visibility`，
  /// 默认 [ToolVisibility.private]（default-deny）。纯声明——不影响本侧派发与
  /// `tools/list` 条目数，曝光策略归宿主。
  final ToolVisibility visibility;

  /// MCP 标准 annotation（SDK 0.2.0 对齐）：本分类全部子操作无副作用。
  /// 默认 false——**仅 true 时随 [toSchema] 下发 `annotations.readOnlyHint`**
  /// （与 SDK 反射派发器同口径：false 不下发，不臆造只读声明）。
  final bool readOnlyHint;

  /// MCP 标准 annotation（SDK 0.2.0 对齐）：本分类含可能破坏性的子操作（如删除）。
  /// 默认 false，仅 true 时下发 `annotations.destructiveHint`。
  final bool destructiveHint;

  final Map<String, SubAction> _subs = {};

  /// 登记子操作（package 内部 public，供分类文件跨文件调用）。
  void register(SubAction a) => _subs[a.name] = a;

  /// 生成 1 个 MCP Tool 定义：`action` 枚举 + 自由 `params` 对象 + 可见性标记。
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
        // MCP 标准 annotations（SDK 0.2.0）：readOnlyHint / destructiveHint，
        // 仅 true 时下发（false 缺席），与 SDK 反射派发器 ToolDispatcher 同口径。
        if (readOnlyHint || destructiveHint)
          'annotations': {
            if (readOnlyHint) 'readOnlyHint': true,
            if (destructiveHint) 'destructiveHint': true,
          },
        // GoodHub 私有扩展（SDK 0.2.0 约定）：纯声明，宿主据此分桶。本侧始终下发
        // （private 也下发）——与 SDK 一致保持「tools/list 反映能力全集且不臆造
        // 曝光」，漏节点才等于把判定权交给宿主瞎猜。
        '_meta': {
          'goodhub': {'visibility': visibility.wireName},
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
    } else if (sub.isWrite) {
      // G3 写门禁：子操作执行体之前拦截，物理级无法穿透
      final gw = commandGateway;
      if (gw == null) {
        // R 档-only 分类未配置网关：W 档子操作物理上不可达，fail-closed。
        result = SubActionResult.error(
            'PERMISSION_DENIED', '写操作未配置网关（gateway 为 null）');
      } else if (!gw.admits(action, params)) {
        result = SubActionResult.error(
            'PERMISSION_DENIED', 'Write operation unauthorized');
      } else if (sub.validate(params) case final SubActionResult invalid) {
        // G6 前置校验：必填 / URL 护栏 / 幂等预查等可预期失败在此转结构化错误，
        // 不进入 buildCommand / dispatch（buildCommand 无法表达失败）。
        result = invalid;
      } else {
        // 唯一写入口：W 档由网关层统一 dispatch，子操作只构造命令。
        // G6：Actor 输出统一为 `{'success': ...}` 信封，isError 由信封派生——
        // 业务失败（如 URL 被护栏拒绝）对客户端可见，而非只藏在文本里。
        result = SubActionResult.fromActor(
            await gw.dispatch(sub.buildCommand(params)));
      }
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
