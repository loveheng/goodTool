/// 高德 Web 服务数字签名（sig）纯 Dart 实现（无头可跑，arch-guard R4）。
///
/// 高德对 Web 服务（含静态图 `v3/staticmap`、搜索/地理编码接口）开启签名校验时，
/// 客户端须按规范生成 `sig` 拼入请求，否则返回 `INVALID_USER_SCODE`（签名无效）
/// 导致无法出图或检索失败。
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

/// 高德数字签名：对请求参数按 key ASCII 升序拼接 + secret，MD5 → 32 位小写十六进制。
///
/// 算法（高德开放平台规范）：
/// 1. 取全部请求参数（含 `key`，**不含** `sig`），按参数名 ASCII 升序排序；
/// 2. 依次拼接为 `key1value1key2value2...`（无分隔符）；
/// 3. 末尾追加上 `secret`；
/// 4. 整体 MD5 → 32 位小写 hex，即 `sig`。
///
/// 示例：
/// ```dart
/// final sig = amapSign({'key': 'K', 'location': '116.4,39.9'}, 'SECRET');
/// // 拼入请求：...&sig=$sig
/// ```
String amapSign(Map<String, String> params, String secret) {
  final keys = params.keys.toList()..sort();
  final buffer = StringBuffer();
  for (final k in keys) {
    buffer.write(k);
    buffer.write(params[k]!);
  }
  buffer.write(secret);
  final digest = md5.convert(utf8.encode(buffer.toString()));
  return digest.toString(); // crypto 默认输出小写 hex
}
