// 重要事件标记存储（P2-⑤）：CalendarMarkerStore（读）+ CalendarMarkerWriter（写）
// 端口的双实现。标记是用户私有数据（calendar.md「Markers 一等公民」）。
//
// - [InMemoryMarkerStore]：Binder isolate / 单测——无平台通道依赖，进程重启即失
//   （Binder isolate 本就每次拉起重建，语义可接受）。
// - [SharedPrefsMarkerStore]：真实持久化（shared_preferences，JSON 字符串列表）。
//
// 纪律：写端口**只给命令 Actor 持有**（经装配件注入）；工具层只见读端口。
library;

import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import '../mcp/calendar_provider.dart';

/// shared_preferences 键（CalendarMarker JSON 数组）。
const String kCalendarMarkersPrefKey = 'calendar_markers';

/// 标记编解码与 id 生成（两实现共用，避免双写漂移）。
CalendarMarker decodeMarker(String raw) {
  final m = jsonDecode(raw) as Map<String, Object?>;
  return CalendarMarker(
    id: m['id'] as String,
    title: m['title'] as String,
    originalDate: m['originalDate'] as String,
    baseYear: (m['baseYear'] as num).toInt(),
    category: m['category'] as String,
    isAnnual: (m['isAnnual'] as bool?) ?? true,
    isLunar: (m['isLunar'] as bool?) ?? false,
    leapPolicy: (m['leapPolicy'] as String?) ?? 'ignoreLeap',
  );
}

String encodeMarker(CalendarMarker m) => jsonEncode(m.toJson());

/// `mk_` + 8 位十六进制（进程内足够唯一；删除按 id 精确匹配，不追求全局唯一）。
String newMarkerId() =>
    'mk_${Random.secure().nextInt(1 << 32).toRadixString(16).padLeft(8, '0')}';

/// 内存实现：进程重启即失。
class InMemoryMarkerStore implements CalendarMarkerStore, CalendarMarkerWriter {
  final List<CalendarMarker> _items = <CalendarMarker>[];

  @override
  Future<List<CalendarMarker>> list({
    required String rangeStart,
    required String rangeEnd,
    String? category,
  }) async =>
      _items
          .where((m) => category == null || m.category == category)
          .toList(growable: false);

  @override
  Future<String> addMarker({
    required String originalDate,
    required String title,
    required String category,
    int? baseYear,
    bool isAnnual = true,
    bool isLunar = false,
    String leapPolicy = 'ignoreLeap',
  }) async {
    final m = CalendarMarker(
      id: newMarkerId(),
      title: title,
      originalDate: originalDate.trim(),
      baseYear: baseYear ?? _deriveBaseYear(originalDate),
      category: category,
      isAnnual: isAnnual,
      isLunar: isLunar,
      leapPolicy: leapPolicy,
    );
    _items.add(m);
    return m.id;
  }

  @override
  Future<bool> deleteMarker(String markerId) async {
    final n = _items.length;
    _items.removeWhere((m) => m.id == markerId);
    return _items.length != n;
  }
}

/// SharedPreferences 持久化实现。
class SharedPrefsMarkerStore
    implements CalendarMarkerStore, CalendarMarkerWriter {
  SharedPrefsMarkerStore(this._prefs);

  final SharedPreferences _prefs;

  static const String key = kCalendarMarkersPrefKey;

  static Future<SharedPrefsMarkerStore> open() async =>
      SharedPrefsMarkerStore(await SharedPreferences.getInstance());

  @override
  Future<List<CalendarMarker>> list({
    required String rangeStart,
    required String rangeEnd,
    String? category,
  }) async =>
      _decode()
          .where((m) => category == null || m.category == category)
          .toList(growable: false);

  @override
  Future<String> addMarker({
    required String originalDate,
    required String title,
    required String category,
    int? baseYear,
    bool isAnnual = true,
    bool isLunar = false,
    String leapPolicy = 'ignoreLeap',
  }) async {
    final m = CalendarMarker(
      id: newMarkerId(),
      title: title,
      originalDate: originalDate.trim(),
      baseYear: baseYear ?? _deriveBaseYear(originalDate),
      category: category,
      isAnnual: isAnnual,
      isLunar: isLunar,
      leapPolicy: leapPolicy,
    );
    await _save(<CalendarMarker>[..._decode(), m]);
    return m.id;
  }

  @override
  Future<bool> deleteMarker(String markerId) async {
    final all = _decode();
    final next = all.where((m) => m.id != markerId).toList(growable: false);
    if (next.length == all.length) return false;
    await _save(next);
    return true;
  }

  List<CalendarMarker> _decode() =>
      (_prefs.getStringList(key) ?? const <String>[])
          .map(decodeMarker)
          .toList(growable: false);

  Future<void> _save(List<CalendarMarker> markers) async {
    await _prefs.setStringList(
        key, markers.map(encodeMarker).toList(growable: false));
  }
}

/// 从完整 `YYYY-MM-DD` 派生根年份（无年份格式时抛错——由调用方转结构化错误，
/// 不在此静默兜底为当年）。
int _deriveBaseYear(String originalDate) {
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(originalDate.trim());
  if (m == null) {
    throw FormatException(
        'originalDate 须为完整 YYYY-MM-DD；无年份格式必须显式传 baseYear');
  }
  return int.parse(m.group(1)!);
}
