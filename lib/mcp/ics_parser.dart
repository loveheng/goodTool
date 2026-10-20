// RFC 5545 ICS 解析与 RRULE 展开内核（P2-④ 步骤 A）。
//
// 纯 Dart、零依赖（守 arch-guard R4 内核无平台依赖；service 层负责网络与缓存）。
// 落点与 `date_math.dart` 同级（tools 域内核）。
//
// **覆盖范围（calendar.md C1/C2 + 实现要点）**：
//   - 行展开（CRLF/LF + 续行）、组件边界（VCALENDAR / VEVENT / VALARM / VTIMEZONE）
//   - 属性参数（VALUE=DATE、TZID=…）、RFC 5545 文本转义反转义
//   - DTEND/DURATION 缺省规则（非全天无 DTEND = 点事件；全天 = 单日）
//   - RRULE：FREQ=DAILY/WEEKLY/MONTHLY/YEARLY + INTERVAL + COUNT + UNTIL +
//     BYMONTHDAY + BYMONTH + WEEKLY 的 BYDAY
//   - EXDATE 排除、RECURRENCE-ID override（替换）+ STATUS:CANCELLED（删除）
//   - **C1 防御**：单事件展开实例上限 [icsMaxInstances]（默认 365），超限截断
//     （区间外本就不返回，天然安全）
//   - **时区**：`Z` 归一 UTC；TZID/浮动按**名义 UTC** 处理（不解析 IANA 规则）——
//     这是 package:timezone 引入（P2-② 待批准）前的显式限制，文档已标注。
library;

/// 单事件展开实例数上限（C1 防御，独立于查询区间）。
const int icsMaxInstances = 365;

/// 解析后的 VEVENT（原始形态；RRULE 未展开）。
class IcsEvent {
  const IcsEvent({
    required this.uid,
    required this.start,
    required this.end,
    required this.isAllDay,
    this.summary,
    this.description,
    this.location,
    this.rrule,
    this.exDates = const <DateTime>[],
    this.recurrenceId,
    this.cancelled = false,
  });

  final String uid;
  final DateTime start;
  final DateTime end;
  final bool isAllDay;
  final String? summary;
  final String? description;
  final String? location;

  /// 原始 RRULE 串（已解折叠），null 表示单次事件。
  final String? rrule;

  /// 排除实例（开始时刻，UTC 名义值）。
  final List<DateTime> exDates;

  /// override 标记：非 null 表示这是覆盖某实例的 VEVENT（替换语义）。
  final DateTime? recurrenceId;
  final bool cancelled;
}

/// 展开后的单个实例。
class IcsInstance {
  const IcsInstance({required this.event, required this.start, required this.end});

  final IcsEvent event;
  final DateTime start;
  final DateTime end;
}

/// 解析结果（含警告，便于上层透出「有 N 条被跳过」而不静默丢弃）。
class IcsParseResult {
  const IcsParseResult(this.events, this.warnings);
  final List<IcsEvent> events;
  final List<String> warnings;
}

/// RFC 5545 子集解析器。
class IcsParser {
  const IcsParser._();

  /// 解析 ICS 文本。**不支持的 FREQ**（HOURLY/MINUTELY/SECONDLY）整条跳过并记 warning。
  static IcsParseResult parse(String raw) {
    final warnings = <String>[];
    final events = <IcsEvent>[];
    final lines = _unfold(raw);

    Map<String, _Prop>? props; // 当前 VEVENT 属性（null = 不在 VEVENT 内）
    for (final line in lines) {
      if (line.isEmpty) continue;
      final upper = line.toUpperCase();
      if (upper.startsWith('BEGIN:VEVENT')) {
        props = <String, _Prop>{};
        continue;
      }
      if (upper.startsWith('END:VEVENT')) {
        if (props != null) {
          final e = _build(props, warnings);
          if (e != null) events.add(e);
        }
        props = null;
        continue;
      }
      if (props == null) continue; // VEVENT 之外的组件（VTIMEZONE/VALARM 等）忽略
      final prop = _Prop.parse(line);
      if (prop == null) continue;
      if (prop.name == 'EXDATE') {
        // 同名多次出现（多参数分组）累积到同一 _Prop。
        final bucket = props['_exdate'] ?? _Prop('_exdate', <String, String>{}, '');
        props['_exdate'] = bucket..append(prop);
      } else {
        props[prop.name] = prop; // 同名后者覆盖（RFC 允许，后写胜）
      }
    }

    return IcsParseResult(List.unmodifiable(events), List.unmodifiable(warnings));
  }

  /// 行展开：RFC 5545 规定以 CRLF 或 LF 折行，续行以空格/制表符开头。
  static List<String> _unfold(String raw) {
    final out = <String>[];
    for (var line in raw.split(RegExp(r'\r\n|\r|\n'))) {
      if (line.isEmpty) continue;
      if ((line.startsWith(' ') || line.startsWith('\t')) && out.isNotEmpty) {
        out[out.length - 1] = '${out[out.length - 1]}${line.substring(1)}';
      } else {
        out.add(line);
      }
    }
    return out;
  }

  static String _unescape(String value) => value
      .replaceAll(r'\n', '\n')
      .replaceAll(r'\N', '\n')
      .replaceAll(r'\,', ',')
      .replaceAll(r'\;', ';')
      .replaceAll(r'\\', '\\');

  static IcsEvent? _build(Map<String, _Prop> props, List<String> warnings) {
    final startProp = props['DTSTART'];
    final uidProp = props['UID'];
    if (startProp == null || uidProp == null) {
      warnings.add('VEVENT 缺少 UID 或 DTSTART，跳过');
      return null;
    }
    final start = _parseDate(startProp);
    if (start == null) {
      warnings.add('DTSTART 无法解析：${startProp.value}');
      return null;
    }

    final endProp = props['DTEND'];
    final end = endProp == null ? _defaultEnd(start, startProp) : _parseDate(endProp);

    final isAllDay = (startProp.params['VALUE'] ?? '').toUpperCase() == 'DATE' ||
        RegExp(r'^\d{8}$').hasMatch(startProp.value.trim());

    final ridProp = props['RECURRENCE-ID'];
    final recurrenceId = ridProp == null ? null : _parseDate(ridProp);

    final exDates = <DateTime>[];
    final exProp = props['_exdate'];
    if (exProp != null) {
      for (final part in exProp.allValues) {
        final d = _parseDate(_Prop('', <String, String>{}, part.trim()));
        if (d != null) exDates.add(d);
      }
    }

    final rruleProp = props['RRULE'];
    final rrule = rruleProp?.value.trim();
    if (rrule != null && rrule.toUpperCase().contains('FREQ=HOURLY') ||
        rrule != null && rrule.toUpperCase().contains('FREQ=MINUTELY') ||
        rrule != null && rrule.toUpperCase().contains('FREQ=SECONDLY')) {
      warnings.add('不支持的 FREQ（HOURLY/MINUTELY/SECONDLY），事件按单次处理：$rrule');
      return IcsEvent(
        uid: uidProp.value.trim(),
        start: start,
        end: end ?? _defaultEnd(start, startProp),
        isAllDay: isAllDay,
        summary: _text(props['SUMMARY']),
        description: _text(props['DESCRIPTION']),
        location: _text(props['LOCATION']),
        recurrenceId: recurrenceId,
        cancelled: (props['STATUS']?.value.trim().toUpperCase() ?? '') ==
            'CANCELLED',
      );
    }

    return IcsEvent(
      uid: uidProp.value.trim(),
      start: start,
      end: end ?? _defaultEnd(start, startProp),
      isAllDay: isAllDay,
      summary: _text(props['SUMMARY']),
      description: _text(props['DESCRIPTION']),
      location: _text(props['LOCATION']),
      rrule: rrule,
      exDates: List.unmodifiable(exDates),
      recurrenceId: recurrenceId,
      cancelled:
          (props['STATUS']?.value.trim().toUpperCase() ?? '') == 'CANCELLED',
    );
  }

  static String? _text(_Prop? p) =>
      p == null ? null : _unescape(p.value.trim());

  /// RFC 5545：DTEND 缺省时 DTSTART 的值决定（非全天点事件 = 0 时长；全天 = 1 天）。
  static DateTime _defaultEnd(DateTime start, _Prop startProp) {
    final allDay = (startProp.params['VALUE'] ?? '').toUpperCase() == 'DATE' ||
        RegExp(r'^\d{8}$').hasMatch(startProp.value.trim());
    return allDay ? start.add(const Duration(days: 1)) : start;
  }

  /// 解析 ICS 日期/时间：`Z` → UTC；日期（8 位）→ 名义 UTC 00:00；浮点 → 名义 UTC。
  static DateTime? _parseDate(_Prop prop) {
    final raw = prop.value.trim();
    if (RegExp(r'^\d{8}$').hasMatch(raw)) {
      return DateTime.utc(
          int.parse(raw.substring(0, 4)), int.parse(raw.substring(4, 6)), int.parse(raw.substring(6, 8)));
    }
    final m = RegExp(r'^(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})(Z?)$')
        .firstMatch(raw);
    if (m == null) return null;
    // **不能用 `DateTime(...).toUtc()`**：那会把 ICS 墙钟按本机时区偏移
    // （CN +8 时 02:00Z 变成前一天 18:00）。Z 与 TZID/浮点都以 `DateTime.utc`
    // 存储——前者即真 UTC，后者为「名义 UTC」（不解析 IANA 规则，P2-② 修正）。
    return DateTime.utc(
      int.parse(m.group(1)!),
      int.parse(m.group(2)!),
      int.parse(m.group(3)!),
      int.parse(m.group(4)!),
      int.parse(m.group(5)!),
      int.parse(m.group(6)!),
    );
  }
}

/// 一行属性：`NAME;PARAM=V;PARAM2=V2:value`。
class _Prop {
  _Prop(this.name, this.params, this.value);

  final String name;
  final Map<String, String> params;
  final String value;

  /// EXDATE 多值累积（同一属性名多次出现 / 逗号多值）。
  final List<String> _extra = <String>[];

  List<String> get allValues => <String>[...value.split(','), ..._extra];

  void append(_Prop other) => _extra.addAll(other.value.split(','));

  static _Prop? parse(String line) {
    final colon = _indexOfUnquoted(line, ':');
    if (colon < 0) return null;
    final left = line.substring(0, colon);
    var value = line.substring(colon + 1);
    final semi = _indexOfUnquoted(left, ';');
    final String name;
    final String paramsPart;
    if (semi < 0) {
      name = left;
      paramsPart = '';
    } else {
      name = left.substring(0, semi);
      paramsPart = left.substring(semi + 1);
    }
    if (name.trim().isEmpty) return null;
    final params = <String, String>{};
    for (final part in _splitUnquoted(paramsPart, ';')) {
      final eq = part.indexOf('=');
      if (eq > 0) {
        params[part.substring(0, eq).trim().toUpperCase()] =
            part.substring(eq + 1).trim();
      }
    }
    return _Prop(name.trim().toUpperCase(), params, value);
  }

  static int _indexOfUnquoted(String s, String ch) {
    var quoted = false;
    for (var i = 0; i < s.length; i++) {
      final c = s[i];
      if (c == '"') quoted = !quoted;
      if (!quoted && s.startsWith(ch, i)) return i;
    }
    return -1;
  }

  static List<String> _splitUnquoted(String s, String ch) {
    final out = <String>[];
    var quoted = false;
    var start = 0;
    for (var i = 0; i < s.length; i++) {
      final c = s[i];
      if (c == '"') quoted = !quoted;
      if (!quoted && c == ch) {
        out.add(s.substring(start, i));
        start = i + 1;
      }
    }
    out.add(s.substring(start));
    return out;
  }
}

/// RRULE 展开：把 RRULE + EXDATE + override 展开成区间内的实例列表。
class IcsExpander {
  const IcsExpander._();

  /// 展开 [events] 到区间 `[from, to)`（UTC）。
  ///
  /// [maxInstances] 为单事件实例上限（C1）。返回按 `start → uid` 固定排序（D1）。
  static List<IcsInstance> expand(
    List<IcsEvent> events,
    DateTime from,
    DateTime to, {
    int maxInstances = icsMaxInstances,
  }) {
    final out = <IcsInstance>[];

    // override：按 uid + recurrenceId 索引（替换语义，非追加 —— C2）。
    final overrides = <String, Map<DateTime, IcsEvent>>{};
    for (final e in events) {
      final rid = e.recurrenceId;
      if (rid == null) continue;
      overrides.putIfAbsent(e.uid, () => <DateTime, IcsEvent>{})[rid] = e;
    }

    for (final e in events) {
      if (e.recurrenceId != null) continue; // override 不进基础序列
      if (e.cancelled && e.rrule == null) continue; // 单次且取消

      final perUid = overrides[e.uid] ?? const <DateTime, IcsEvent>{};
      var emitted = 0;
      for (final start in _occurrences(e, from, to, maxInstances)) {
        if (emitted >= maxInstances) break; // C1 截断
        emitted++;

        // C2：override 替换 / 删除优先于 EXDATE 与基础实例
        final override = perUid[start];
        if (override != null) {
          if (!override.cancelled && _intersects(override.start, override.end, from, to)) {
            out.add(IcsInstance(event: override, start: override.start, end: override.end));
          }
          continue;
        }
        if (e.exDates.contains(start)) continue; // C2：EXDATE 排除单实例

        final dur = e.end.difference(e.start);
        final end = start.add(dur);
        if (!_intersects(start, end, from, to)) continue;
        out.add(IcsInstance(event: e, start: start, end: end));
      }
    }

    out.sort((a, b) {
      final c = a.start.compareTo(b.start);
      return c != 0 ? c : a.event.uid.compareTo(b.event.uid);
    });
    return List.unmodifiable(out);
  }

  /// 生成事件在 `[from, to)` 内的开始时刻（无 RRULE → 单次；有则按规则展开）。
  static Iterable<DateTime> _occurrences(
    IcsEvent e,
    DateTime from,
    DateTime to,
    int maxInstances,
  ) sync* {
    final rrule = e.rrule;
    if (rrule == null || rrule.trim().isEmpty) {
      if (_intersects(e.start, e.end, from, to)) yield e.start;
      return;
    }
    final rule = _Rrule.parse(rrule);
    if (rule == null) {
      if (_intersects(e.start, e.end, from, to)) yield e.start;
      return;
    }

    var cursor = DateTime.utc(e.start.year, e.start.month, e.start.day);
    var count = 0;
    var guard = 0;
    // 区间外 guard：最多迭代 maxInstances * 8 次（含区间外轨迹），防病态规则死循环。
    final guardMax = maxInstances * 8;
    while (guard++ < guardMax) {
      if (rule.until != null && cursor.isAfter(rule.until!)) return;
      if (rule.count != null && count >= rule.count!) return;
      if (cursor.isAfter(to)) return;

      if (rule.matches(cursor, e)) {
        final start = cursor.add(e.start.difference(DateTime.utc(
                e.start.year, e.start.month, e.start.day)))
            .toUtc();
        count++;
        if (!start.isBefore(from) && start.isBefore(to)) yield start;
        if (rule.count != null && count >= rule.count!) return;
      }

      switch (rule.freq) {
        case 'DAILY':
          cursor = cursor.add(Duration(days: rule.interval));
        case 'WEEKLY':
          final days = rule.byDay;
          if (days == null || days.isEmpty) {
            cursor = cursor.add(Duration(days: 7 * rule.interval));
          } else {
            cursor = _nextByDay(cursor, days, rule);
          }
        case 'MONTHLY':
          cursor = _addMonths(
              cursor, rule.interval, _dayOf(event: e, rule: rule));
        case 'YEARLY':
          cursor = _addMonths(
              cursor, 12 * rule.interval, _dayOf(event: e, rule: rule));
        default:
          return;
      }
    }
  }

  /// 月/年步进的目标「日」：BYMONTHDAY 首个值优先，否则取事件起始日。
  static int _dayOf({required IcsEvent event, required _Rrule rule}) =>
      rule.byMonthDay?.first ?? event.start.day;

  static DateTime _nextByDay(DateTime cursor, List<int> days, _Rrule rule) {
    // 本周内下一个 BYDAY；没有则跳到下周首个 BYDAY。
    for (var d = 1; d <= 7; d++) {
      final next = cursor.add(Duration(days: d));
      if (days.contains(next.weekday)) return next;
    }
    return cursor.add(Duration(days: 7 * rule.interval));
  }

  /// 月末 clamp（1/31 + 1 月 → 2/28）。
  static DateTime _addMonths(DateTime cursor, int months, int day) {
    final total = cursor.month - 1 + months;
    final y = cursor.year + (total ~/ 12);
    final mo = (total % 12) + 1;
    final last = DateTime.utc(y, mo + 1, 0).day;
    return DateTime.utc(y, mo, day > last ? last : day);
  }

  static bool _intersects(DateTime start, DateTime end, DateTime from, DateTime to) =>
      start.isBefore(to) && end.isAfter(from);
}

/// RRULE 的最小可用子集。
class _Rrule {
  const _Rrule({
    required this.freq,
    required this.interval,
    this.count,
    this.until,
    this.byMonthDay,
    this.byMonth,
    this.byDay,
  });

  final String freq;
  final int interval;
  final int? count;
  final DateTime? until;
  final List<int>? byMonthDay;
  final List<int>? byMonth;
  final List<int>? byDay; // ISO 周几：1=周一 … 7=周日

  static _Rrule? parse(String raw) {
    final freqMatch = RegExp(r'FREQ=([A-Z]+)', caseSensitive: false)
        .firstMatch(raw);
    final freq = freqMatch?.group(1)?.toUpperCase();
    if (freq == null ||
        !const {'DAILY', 'WEEKLY', 'MONTHLY', 'YEARLY'}.contains(freq)) {
      return null;
    }
    var interval = 1;
    final intervalMatch = RegExp(r'INTERVAL=(\d+)', caseSensitive: false)
        .firstMatch(raw);
    if (intervalMatch != null) {
      interval = int.tryParse(intervalMatch.group(1)!) ?? 1;
      if (interval < 1) interval = 1;
    }
    final byMonth = RegExp(r'BYMONTH=(\d+(?:,\d+)*)', caseSensitive: false)
        .firstMatch(raw)
        ?.group(1)
        ?.split(',')
        .map(int.tryParse)
        .whereType<int>()
        .toList();
    return _Rrule(
      freq: freq,
      interval: interval,
      count: RegExp(r'COUNT=(\d+)', caseSensitive: false)
          .firstMatch(raw)
          ?.group(1)
          ?.let(int.tryParse),
      until: _parseUntil(raw),
      byMonthDay: RegExp(r'BYMONTHDAY=(-?\d+(?:,-?\d+)*)', caseSensitive: false)
          .firstMatch(raw)
          ?.group(1)
          ?.split(',')
          .map(int.tryParse)
          .whereType<int>()
          .toList(),
      byMonth: byMonth,
      byDay: RegExp(r'BYDAY=([A-Z,0-9]+)', caseSensitive: false)
          .firstMatch(raw)
          ?.group(1)
          ?.toUpperCase()
          .split(',')
          .map(_isoWeekday)
          .whereType<int>()
          .toList(),
    );
  }

  static DateTime? _parseUntil(String raw) {
    final m = RegExp(r'UNTIL=(\d{8}(?:T\d{6}Z?)?)', caseSensitive: false)
        .firstMatch(raw);
    final v = m?.group(1);
    if (v == null) return null;
    if (v.length == 8) {
      return DateTime.utc(int.parse(v.substring(0, 4)),
          int.parse(v.substring(4, 6)), int.parse(v.substring(6, 8)));
    }
    final t = RegExp(r'^(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})(Z?)$')
        .firstMatch(v);
    if (t == null) return null;
    // 同 _parseDate：一律 DateTime.utc 存储，禁 toUtc()。
    return DateTime.utc(
      int.parse(t.group(1)!),
      int.parse(t.group(2)!),
      int.parse(t.group(3)!),
      int.parse(t.group(4)!),
      int.parse(t.group(5)!),
      int.parse(t.group(6)!),
    );
  }

  /// 该 cursor 日是否命中：**按 FREQ 分流**——BYMONTHDAY 只对 MONTHLY/YEARLY
  /// 生效；BYDAY 对 WEEKLY 生效；DAILY 不做日过滤（否则每天规则会被月日过滤成
  /// 每月一天，RRULE 语义错误）。
  bool matches(DateTime cursor, IcsEvent event) {
    if (byMonth != null && byMonth!.isNotEmpty && !byMonth!.contains(cursor.month)) {
      return false;
    }
    switch (freq) {
      case 'WEEKLY':
        return byDay == null || byDay!.isEmpty || byDay!.contains(cursor.weekday);
      case 'MONTHLY':
      case 'YEARLY':
        return (byMonthDay ?? <int>[event.start.day]).contains(cursor.day);
      default: // DAILY
        return true;
    }
  }

  static int? _isoWeekday(String s) => switch (s) {
        'MO' => 1,
        'TU' => 2,
        'WE' => 3,
        'TH' => 4,
        'FR' => 5,
        'SA' => 6,
        'SU' => 7,
        _ => null,
      };
}

extension _Let<T> on T {
  R let<R>(R Function(T) f) => f(this);
}
