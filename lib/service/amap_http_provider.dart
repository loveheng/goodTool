// 高德 Web 服务 REST 实现（S7a）：`GeoHttpProvider` 端口的**真实源**实现。
//
// 落点依据 standards §1.3「新平台/硬件能力 → lib/service + Provider 端口」：
// 端口定义在 lib/mcp/geo_provider.dart（内核只认抽象），网络实现住 service 层，
// 内核与 tools 层零 dart:io（arch-guard R4 无头约束）。
//
// 错误口径（§1.2 端口实现 fail-closed）：一律抛带机器码的 [GeoHttpException]，
// 由 geo 适配层的 `_amapGet` 转成 `geo.<action>: <code>` 错误——不返回空 Map、
// 不以空列表兜底（禁静默降级）。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../mcp/geo_provider.dart';

/// 高德 REST 域名。
const String amapRestHost = 'restapi.amap.com';

/// 单次请求超时（高德 Web 服务 P99 远低于此；Binder 侧另有原生 5s 兜底）。
const Duration amapRequestTimeout = Duration(seconds: 8);

/// 高德 Web 服务 REST 实现：GET [host][path]，`key` 由 [keyReader] **每次请求懒读**。
///
/// 懒读而非构造期读死，理由有二：
/// 1. 装配是同步的（Binder 入口 `mcpBinderMain` 是 `void`，无法 await），
///    而 KV 读取是异步的——把异步推到请求发生时，装配面才能保持同步；
/// 2. 用户在设置里补填 Key 后**无需重建工具面**即生效。
///
/// [keyReader] 返回 null/空串 ⇒ 抛 `ERR_AMAP_KEY_MISSING`（引导 UI 弹配置卡）。
class AmapHttpProvider implements GeoHttpProvider {
  /// [_client] / [_host] / [_port] / [_scheme] 为**注入口**（生产走默认高德 HTTPS；
  /// 单测注入本地 `HttpServer` 即可走通真实请求链路，无需 Mock HttpClient）。
  AmapHttpProvider(this._keyReader,
      [this._client, this._host = amapRestHost, this._port, this._scheme = 'https']);

  final Future<String?> Function() _keyReader;

  /// 注入的客户端（单测可传桩；生产为 null → 每次请求自建并在结束时关闭）。
  final HttpClient? _client;
  final String _host;

  /// 端口（null = 协议默认端口）。
  final int? _port;

  /// 协议方案（生产恒 https；仅单测注入本地 http 服务）。
  final String _scheme;

  @override
  Future<Map<String, Object?>> get(String path, Map<String, String> query) async {
    final key = await _keyReader();
    if (key == null || key.trim().isEmpty) {
      throw const GeoHttpException(
          'ERR_AMAP_KEY_MISSING', '高德 Web 服务 Key 未配置');
    }

    final external = _client != null;
    final client = _client ?? HttpClient();
    try {
      final uri = Uri(
        scheme: _scheme,
        host: _host,
        port: _port,
        path: path,
        queryParameters: <String, String>{...query, 'key': key},
      );
      final req = await client.getUrl(uri).timeout(amapRequestTimeout);
      final res = await req.close().timeout(amapRequestTimeout);
      if (res.statusCode != HttpStatus.ok) {
        // 先排空响应体，否则连接不复用且 socket 悬挂。
        await res.drain<void>();
        throw GeoHttpException(
            'ERR_AMAP_API', '高德返回 HTTP ${res.statusCode}');
      }
      final text = await res
          .transform(utf8.decoder)
          .fold<String>('', (acc, s) => '$acc$s')
          .timeout(amapRequestTimeout);

      final Object? decoded;
      try {
        decoded = jsonDecode(text);
      } on FormatException {
        throw const GeoHttpException(
            'ERR_AMAP_API', '高德响应不是合法 JSON');
      }
      if (decoded is! Map<String, Object?>) {
        throw const GeoHttpException(
            'ERR_AMAP_API', '高德响应不是 JSON 对象');
      }
      return decoded;
    } on GeoHttpException {
      rethrow;
    } on SocketException catch (e) {
      throw GeoHttpException('ERR_AMAP_NETWORK', '网络不可达：${e.message}');
    } on TimeoutException catch (_) {
      throw const GeoHttpException('ERR_AMAP_TIMEOUT', '高德请求超时');
    } on HttpException catch (e) {
      throw GeoHttpException('ERR_AMAP_NETWORK', 'HTTP 层失败：${e.message}');
    } on Exception catch (e) {
      throw GeoHttpException('ERR_AMAP_API', '高德请求失败：$e');
    } finally {
      if (!external) client.close(force: true);
    }
  }
}
