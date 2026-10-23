/// 路线步骤的导航语义解析（纯 Dart，无头可测，arch-guard R4）。
///
/// 高德 REST 返回的 step 只有自然语言 `instruction`（如「沿科技园中一路向北
/// 步行 120 米」）与中文绝对方位 `orientation`（如「北」「东南」）。UI 要把
/// 每步渲染成「转向图标 + 方位图标 + 文案」，需要把自然语言解析成结构化
/// **相对转向**（TurnKind）与 **绝对方位角**（0=北，顺时针）。
///
/// 解析是**尽力而为**：未命中关键词回 `unknown`（图标走中性箭头），不以猜测
/// 兜底成某个确定转向——猜错转向比没有图标更糟。
library;

/// 相对转向类型（相对当前行进方向）。
enum TurnKind {
  /// 左转。
  left,

  /// 右转。
  right,

  /// 向左前方（小角度左偏）。
  slightLeft,

  /// 向右前方（小角度右偏）。
  slightRight,

  /// 直行。
  straight,

  /// 掉头 / 调头。
  uturn,

  /// 进入 / 驶出环岛。
  roundabout,

  /// 步行/骑行出发（首步常为「出发」）。
  start,

  /// 到达终点。
  end,

  /// 未能识别（中性展示，不猜）。
  unknown,
}

/// 中文绝对方位 → 角度（0=正北，顺时针）。
///
/// 高德 `orientation` 输出中文方位（北/东北/东/…）；也容忍数字角度串。
/// 未识别返回 null（UI 不显示方位，不以默认方向兜底）。
double? absoluteBearingOf(String? orientation) {
  if (orientation == null) return null;
  final v = orientation.trim();
  if (v.isEmpty) return null;
  const table = <String, double>{
    '北': 0,
    '东北': 45,
    '东': 90,
    '东南': 135,
    '南': 180,
    '西南': 225,
    '西': 270,
    '西北': 315,
    '正北': 0,
    '正东': 90,
    '正南': 180,
    '正西': 270,
  };
  final hit = table[v];
  if (hit != null) return hit;
  final deg = double.tryParse(v);
  if (deg == null) return null;
  return ((deg % 360) + 360) % 360;
}

/// 高德 instruction 自然语言 → 相对转向（关键词优先级匹配）。
///
/// 优先级从具体到泛化：掉头 > 环岛 > 小角度（前方/斜）> 左/右 > 直行 >
/// 出发/到达。同句多关键词时取最具体的动作（「向右前方行驶进入xx路」记
/// slightRight 而非 right）。
TurnKind turnKindOf(String instruction) {
  final s = instruction;
  if (s.contains('掉头') || s.contains('调头') || s.contains('回转')) {
    return TurnKind.uturn;
  }
  if (s.contains('环岛')) return TurnKind.roundabout;
  if (s.contains('出发')) return TurnKind.start;
  if (s.contains('到达')) return TurnKind.end;
  // 小角度先行：含「前方 / 斜 / 偏」的左/右。
  if (_containsAny(s, const ['向左前方', '向右前方', '向左斜', '向右斜', '向左偏', '向右偏', '靠左前', '靠右前'])) {
    return s.contains('左') ? TurnKind.slightLeft : TurnKind.slightRight;
  }
  if (s.contains('左转') || s.contains('向左转') || s.contains('左拐') || s.contains('靠左')) {
    return TurnKind.left;
  }
  if (s.contains('右转') || s.contains('向右转') || s.contains('右拐') || s.contains('靠右')) {
    return TurnKind.right;
  }
  if (s.contains('直行') || s.contains('向前') || s.contains('径直') || s.contains('沿')) {
    return TurnKind.straight;
  }
  return TurnKind.unknown;
}

bool _containsAny(String s, List<String> keys) => keys.any(s.contains);

/// 绝对方位角 → 八方位中文名（0=北，45° 一档，22.5° 居中容差）。
String bearingDirectionName(double bearing) {
  const names = ['正北', '东北', '正东', '东南', '正南', '西南', '正西', '西北'];
  final h = ((bearing % 360) + 360) % 360;
  return names[((h + 22.5) ~/ 45) % 8];
}
