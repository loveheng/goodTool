// 事件脱敏（E 拍板 · P2-④）：calendar_query 出参前统一执行。
//
// 规则：**不可逆 mask**（非 tokenize，防重标识）；对同一原文输出稳定掩码
// （同串同掩码，保确定性——CalendarEvent 的 isCached 重放必须与首次一致）。
// 默认只开 `PII_MASK_PHONE_EMAIL`；`PII_MASK_LOCATION`（物理住址）需用户显式开启
// （误伤风险高：location 字段常含正常地名）。
//
// 住内核（lib/mcp）：service 层转 CalendarEvent 与 tools 层都会用到，
// 且两层都可 import 内核（standards §1）。
library;

/// 默认脱敏等级（电话 / 邮箱 / 固话）。
const Set<String> piiMaskDefaultLevels = <String>{'PII_MASK_PHONE_EMAIL'};

/// 稳定占位掩码（同串同掩码）。
const String piiMaskPlaceholder = '[已隐藏]';

final RegExp _phoneRe = RegExp(r'(?<!\d)(?:\+?86-?)?1[3-9]\d{9}(?!\d)');
final RegExp _landlineRe = RegExp(r'(?<!\d)0\d{2,3}-?\d{7,8}(?!\d)');
final RegExp _emailRe =
    RegExp(r'[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}');

/// 对文本脱敏；null 安全（返回 null）。
String? maskPii(String? text, {Set<String> levels = piiMaskDefaultLevels}) {
  if (text == null || text.isEmpty) return text;
  if (!levels.contains('PII_MASK_PHONE_EMAIL')) return text;
  return text
      .replaceAll(_phoneRe, piiMaskPlaceholder)
      .replaceAll(_landlineRe, piiMaskPlaceholder)
      .replaceAll(_emailRe, piiMaskPlaceholder);
}

/// 脱敏开关（`privacy_mask_pii`）的值 → 是否启用脱敏。
///
/// **保护性缺省**：未设置（null）= 开——对齐 E 拍板「默认对 Agent 视角 mask」，
/// 开关只允许用户**显式放松**（写 `'0'`），不放宽默认。未设置时行为与开关接线前
/// 完全一致（无回归）；U12a 后 UI 开关与内核行为同源。
bool piiMaskEnabledBy(String? switchValue) => switchValue != '0';
