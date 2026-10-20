// 相对日期表达式解析（P2-③）：`calendar_resolve_date` 的消歧内核。
//
// 契约（calendar.md「日期消歧与月网格」）：支持 `next_friday` / `today+3` /
// `q4_start` / `lunar:2026-08-15` / 节日别名（如 `mid_autumn`）等表达式，
// 内置别名表 + 农历引擎解析，**杜绝 LLM 自算幻觉**。
//
// **F1 纯函数纪律**：相对型表达式与不带年份的节日别名**必须有 baseDate**
// （实现内禁 DateTime.now()，基准日由调用方显式注入）——这是文档 B1 链在
// 纯函数约束下的唯一确定解释：B1 提供时区回退，不提供「今天」。
library;

import 'lunar_math.dart';

/// 表达式解析失败信号（code ∈ MISSING_ARGUMENT / INVALID_ARGUMENT，
/// 由工具层直接转结构化错误）。
class ResolveException implements Exception {
  const ResolveException(this.code, this.message, {this.suggestion});
  final String code;
  final String message;
  final String? suggestion;
  @override
  String toString() => 'ResolveException($code): $message';
}

/// 解析结果：公历日 + 人话说明（出参 description）。
typedef ResolvedDate = ({DateTime date, String description});

/// 表达式解析器。
class ResolveExpression {
  const ResolveExpression._();

  /// 农历节日别名表（key → 农历 月/日）。文档示例 `mid_autumn` 必须在列。
  static const Map<String, (int, int)> _lunarFestivals = {
    'spring_festival': (1, 1), // 春节
    'chinese_new_year': (1, 1), // 同上（英文名别名）
    'lantern_festival': (1, 15), // 元宵
    'dragon_boat': (5, 5), // 端午
    'double_seventh': (7, 7), // 七夕
    'mid_autumn': (8, 15), // 中秋
    'double_ninth': (9, 9), // 重阳
    'laba': (12, 8), // 腊八
  };

  /// 公历固定节日别名表（key → 月/日）。
  static const Map<String, (int, int)> _solarFestivals = {
    'new_year': (1, 1), // 元旦
    'women_day': (3, 8),
    'labour_day': (5, 1),
    'youth_day': (5, 4),
    'children_day': (6, 1),
    'teachers_day': (9, 10),
    'national_day': (10, 1),
  };

  /// 节气节日别名（公历浮动日，须查节气表）。
  static const Set<String> _solarTermFestivals = {'qingming'};

  static final RegExp _lunarRe =
      RegExp(r'^lunar:(\d{4})-(闰?)(\d{1,2})-(\d{1,2})$');
  static final RegExp _todayRe = RegExp(r'^today(?:([+-])(\d+))?$');
  static final RegExp _nextRe = RegExp(r'^next_(monday|tuesday|wednesday|thursday|friday|saturday|sunday)$');
  static const Map<String, int> _weekdays = {
    'monday': DateTime.monday,
    'tuesday': DateTime.tuesday,
    'wednesday': DateTime.wednesday,
    'thursday': DateTime.thursday,
    'friday': DateTime.friday,
    'saturday': DateTime.saturday,
    'sunday': DateTime.sunday,
  };

  /// 解析表达式。
  ///
  /// [baseDate] 供相对型（today±N / next_* / q*_start）与不带年份的别名用；
  /// 绝对型（`lunar:` / `别名:YYYY`）不依赖 baseDate。
  static ResolvedDate resolve(Object? raw, {DateTime? baseDate}) {
    if (raw is! String || raw.trim().isEmpty) {
      throw const ResolveException(
          'MISSING_ARGUMENT', '缺少必填参数 expression（日期表达式）');
    }
    final expr = raw.trim().toLowerCase();

    // ① lunar:YYYY-闰M-DD
    final lm = _lunarRe.firstMatch(expr);
    if (lm != null) {
      final y = int.parse(lm.group(1)!);
      final isLeap = lm.group(2) == '闰';
      final mo = int.parse(lm.group(3)!);
      final d = int.parse(lm.group(4)!);
      final solar = LunarMath.lunarToSolar(y, mo, d, isLeapMonth: isLeap);
      return (
        date: solar,
        description: '农历 $y 年${isLeap ? '闰' : ''}$mo 月 $d 日 → '
            '公历 ${DateFmt.fmt(solar)}',
      );
    }

    // ② today / today±N
    final tm = _todayRe.firstMatch(expr);
    if (tm != null) {
      final base = _requireBase(baseDate, expr);
      final sign = tm.group(1);
      final n = sign == null ? 0 : (sign == '-' ? -int.parse(tm.group(2)!) : int.parse(tm.group(2)!));
      final target = base.add(Duration(days: n));
      return (
        date: target,
        description: '基准 ${DateFmt.fmt(base)} ${n == 0 ? '' : (n > 0 ? '+ ' : '− ')}'
            '${n.abs()} 天 → ${DateFmt.fmt(target)}',
      );
    }

    // ③ next_<weekday>（严格「下一个」，不含当天）
    final nm = _nextRe.firstMatch(expr);
    if (nm != null) {
      final base = _requireBase(baseDate, expr);
      final wd = _weekdays[nm.group(1)!]!;
      var diff = (wd - base.weekday) % 7;
      if (diff == 0) diff = 7;
      final target = base.add(Duration(days: diff));
      return (
        date: target,
        description: '基准 ${DateFmt.fmt(base)}（周${'一二三四五六日'[base.weekday - 1]}）'
            '之后的下一个${nm.group(1)!} → ${DateFmt.fmt(target)}',
      );
    }

    // ④ q1~q4_start（baseDate 所在年）
    final qm = RegExp(r'^q([1-4])_start$').firstMatch(expr);
    if (qm != null) {
      final base = _requireBase(baseDate, expr);
      final startMonth = (int.parse(qm.group(1)!) - 1) * 3 + 1;
      final target = DateTime.utc(base.year, startMonth, 1);
      return (
        date: target,
        description: '${base.year} 年 Q${qm.group(1)} 起始日 → ${DateFmt.fmt(target)}',
      );
    }

    // ⑤ 节日别名：`alias` 或 `alias:YYYY`（未知别名直接 INVALID_ARGUMENT，
    //    不落入「缺 baseDate」误报——先认名，再问基准）
    final aliasMatch = RegExp(r'^([a-z_]+)(?::(\d{4}))?$').firstMatch(expr);
    if (aliasMatch != null) {
      final alias = aliasMatch.group(1)!;
      if (!_lunarFestivals.containsKey(alias) &&
          !_solarFestivals.containsKey(alias) &&
          !_solarTermFestivals.contains(alias)) {
        throw ResolveException(
          'INVALID_ARGUMENT',
          '未知节日别名：$alias',
          suggestion: '农历节日：${_lunarFestivals.keys.join(" / ")}；'
              '公历节日：${_solarFestivals.keys.join(" / ")}；节气节日：qingming',
        );
      }
      final yearRaw = aliasMatch.group(2);
      if (yearRaw != null) {
        final y = int.parse(yearRaw);
        if (y < 1900 || y > 2100) {
          throw ResolveException('INVALID_ARGUMENT',
              '节日别名的年份须在农历引擎支持范围 1900–2100：$y');
        }
      }
      final year = yearRaw != null
          ? int.parse(yearRaw)
          : _requireBase(baseDate, expr).year;
      return _resolveFestival(alias, year);
    }

    throw ResolveException(
      'INVALID_ARGUMENT',
      '无法识别的日期表达式：$raw',
      suggestion: '支持 today / today±N / next_<weekday> / q1~q4_start / '
          'lunar:YYYY-MM-DD（闰月 lunar:YYYY-闰M-DD）/ 节日别名（可带 :YYYY）',
    );
  }

  static ResolvedDate _resolveFestival(String alias, int year) {
    final lunar = _lunarFestivals[alias];
    if (lunar != null) {
      final (mo, d) = lunar;
      final solar = LunarMath.lunarToSolar(year, mo, d);
      return (
        date: solar,
        description: '节日别名 $alias（农历 $year 年$mo 月 $d 日）→ '
            '公历 ${DateFmt.fmt(solar)}',
      );
    }
    final solarFixed = _solarFestivals[alias];
    if (solarFixed != null) {
      final (mo, d) = solarFixed;
      final solar = DateTime.utc(year, mo, d);
      return (
        date: solar,
        description: '节日别名 $alias（公历 $year-$mo-$d）',
      );
    }
    if (_solarTermFestivals.contains(alias)) {
      // 节气节日：查该农历年的节气表（'清明' key 已在库源码钉死为中文）。
      final solar = LunarMath.jieQiTableOfYear(year)['清明'];
      if (solar == null) {
        // 库表异常属实现错误而非入参错误，fail-visible。
        throw ResolveException('INVALID_ARGUMENT', '节气表缺少清明（$year 年）');
      }
      final target = DateTime.utc(solar.year, solar.month, solar.day);
      return (
        date: target,
        description: '节气节日 $alias（$year 年清明）→ 公历 ${DateFmt.fmt(target)}',
      );
    }
    // 不可达：调用方已先验别名（认名再问基准）。
    throw ResolveException('INVALID_ARGUMENT', '未知节日别名：$alias');
  }

  /// 相对表达式的基准日必须显式注入（F1：禁 DateTime.now()，不静默取当天）。
  static DateTime _requireBase(DateTime? baseDate, String expr) {
    if (baseDate == null) {
      throw ResolveException(
        'MISSING_ARGUMENT',
        '表达式 $expr 为相对型，必须显式传 baseDate（实现内禁用 DateTime.now()）',
        suggestion: 'baseDate 传 YYYY-MM-DD，或给表达式显式带年份（如 mid_autumn:2027）',
      );
    }
    return baseDate;
  }
}

/// 独立日期格式化（避免反向依赖 DateMath 造成 tools 内互相纠缠）。
class DateFmt {
  const DateFmt._();

  static String fmt(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
