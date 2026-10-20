// 订阅 URL 护栏（calendar.md「两道硬控制」①，安全关键）。
//
// 纪律：URL 必须是**调用方显式传入的参数**，禁止 Agent 自造或「建议」订阅地址；
// 校验在**命令执行器内**执行（C3 + SSRF 防护），不在工具层拦完就放行。
//
// 内核纯 Dart：刻意**不使用 `dart:io` 的 `InternetAddress`**——地址判定走字符串
// 与正则即可覆盖 RFC 1918 / 回环 / 链路本地，守住「内核不沾平台 API」。
library;

/// 护栏结论：通过带规整后的 [uri]，拒绝带机器码与说明。
class UrlGuardResult {
  const UrlGuardResult.ok(this.uri)
      : code = null,
        message = null;
  const UrlGuardResult.reject(this.code, this.message) : uri = null;

  final Uri? uri;
  final String? code;
  final String? message;

  bool get ok => uri != null;
}

/// 规整并校验订阅 URL：
/// ① `webcal://` → `https://` 后**强制 HTTPS**，拒绝 `http` 明文回退（C3）；
/// ② 拒绝回环 / 私网 / 链路本地地址（防 SSRF 拉内网 ICS）。
UrlGuardResult guardCalendarUrl(Object? raw) {
  if (raw is! String || raw.trim().isEmpty) {
    return const UrlGuardResult.reject('MISSING_ARGUMENT', '缺少必填参数 url');
  }
  final parsed = Uri.tryParse(raw.trim());
  if (parsed == null) {
    return const UrlGuardResult.reject(
        'ERR_INVALID_URL', 'URL 无法解析：仅接受 https / webcal');
  }
  final scheme = parsed.scheme.toLowerCase();
  final Uri uri;
  switch (scheme) {
    case 'webcal':
      // C3 协议规整：webcal 仅作「这是个日历」的语义标记，传输必须 HTTPS。
      uri = parsed.replace(scheme: 'https');
    case 'https':
      uri = parsed;
    case 'http':
      return const UrlGuardResult.reject(
          'ERR_INVALID_URL', '拒绝明文 http：webcal 已规整为 https，禁止降级回退');
    default:
      return UrlGuardResult.reject(
          'ERR_INVALID_URL', '不支持的协议：$scheme（仅接受 https / webcal）');
  }
  if (uri.host.isEmpty) {
    return const UrlGuardResult.reject('ERR_INVALID_URL', 'URL 缺少主机名');
  }
  if (_isForbiddenHost(uri.host)) {
    return UrlGuardResult.reject('ERR_INVALID_URL',
        '拒绝回环 / 私网 / 链路本地地址（SSRF 护栏）：${uri.host}');
  }
  return UrlGuardResult.ok(uri);
}

/// 回环与私网判定（IPv4 / IPv6 / 主机名）。
bool _isForbiddenHost(String host) {
  var h = host.toLowerCase().trim();
  // IPv6 字面量形如 [::1]
  if (h.startsWith('[') && h.endsWith(']')) h = h.substring(1, h.length - 1);

  if (h == 'localhost' || h.endsWith('.localhost')) return true;
  if (h == '::1' || h == '0.0.0.0' || h == '::') return true;
  if (h.startsWith('::ffff:')) return true; // IPv4-mapped，一律按私网处理

  final v4 = RegExp(r'^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$').firstMatch(h);
  if (v4 != null) {
    final o = <int>[
      int.parse(v4.group(1)!),
      int.parse(v4.group(2)!),
      int.parse(v4.group(3)!),
      int.parse(v4.group(4)!),
    ];
    if (o.any((x) => x > 255)) return true; // 非法 IPv4 字面量
    if (o[0] == 0 || o[0] == 10 || o[0] == 127) return true; // 本网 / 私网 / 回环
    if (o[0] == 172 && o[1] >= 16 && o[1] <= 31) return true; // 172.16.0.0/12
    if (o[0] == 192 && o[1] == 168) return true; // 192.168.0.0/16
    if (o[0] == 169 && o[1] == 254) return true; // 链路本地 169.254.0.0/16
    return false;
  }

  if (h.contains(':')) {
    // IPv6：取首个 hextet 判 fe80::/10（链路本地）与 fc00::/7（唯一本地）。
    final head = h.split(':').first;
    final hextet = int.tryParse(head, radix: 16);
    if (hextet == null) return true;
    if (hextet >= 0xfe80 && hextet <= 0xfebf) return true;
    if (hextet >= 0xfc00 && hextet <= 0xfdff) return true;
  }
  return false;
}
