// S7a 高德 REST 实现测试：起本地 HttpServer 走通**真实请求链路**（非 Mock HttpClient），
// 覆盖 key 注入、成功解析、失败状态、非 JSON、Key 缺位 fail-closed。
//
// 仅单测注入 host/port/scheme（生产恒 restapi.amap.com + https），故本文件
// 允许 `dart:io`——生产实现住 service 层，内核与 tools 层仍零 dart:io（arch-guard R4）。
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:good_template/mcp/geo_provider.dart';
import 'package:good_template/service/amap_http_provider.dart';

void main() {
  late HttpServer server;
  late List<Uri> seen;

  setUp(() async {
    seen = <Uri>[];
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((HttpRequest req) {
      seen.add(req.uri);
      req.response
        ..statusCode = HttpStatus.ok
        ..write(jsonEncode(<String, Object?>{'status': '1', 'info': 'OK'}))
        ..close();
    });
  });

  tearDown(() async {
    await server.close(force: true);
  });

  /// 指向本地服务的 provider（key 由 [key] 提供）。
  AmapHttpProvider local(Future<String?> Function() key) => AmapHttpProvider(
        key,
        null,
        server.address.host,
        server.port,
        'http',
      );

  test('成功：path 透传 + key 注入查询串 + JSON 解析', () async {
    final p = local(() async => 'TESTKEY');
    final body = await p.get('/v3/geocode/geo', {'address': '北京市朝阳区'});
    expect(body['status'], '1');
    expect(seen.single.path, '/v3/geocode/geo');
    expect(seen.single.queryParameters['key'], 'TESTKEY');
    expect(seen.single.queryParameters['address'], '北京市朝阳区');
  });

  test('Key 缺位 → ERR_AMAP_KEY_MISSING 且**不发请求**（fail-closed）', () async {
    final p = local(() async => null);
    await expectLater(
      p.get('/v3/geocode/geo', {}),
      throwsA(isA<GeoHttpException>()
          .having((e) => e.code, 'code', 'ERR_AMAP_KEY_MISSING')),
    );
    expect(seen, isEmpty);

    final blank = local(() async => '   ');
    await expectLater(
      blank.get('/v3/geocode/geo', {}),
      throwsA(isA<GeoHttpException>()
          .having((e) => e.code, 'code', 'ERR_AMAP_KEY_MISSING')),
    );
  });

  test('非 200 → ERR_AMAP_API（带状态码，不吞）', () async {
    await server.close(force: true);
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((HttpRequest req) {
      req.response
        ..statusCode = HttpStatus.internalServerError
        ..write('boom')
        ..close();
    });
    final p = local(() async => 'K');
    await expectLater(
      p.get('/v3/geocode/geo', {}),
      throwsA(isA<GeoHttpException>()
          .having((e) => e.code, 'code', 'ERR_AMAP_API')
          .having((e) => e.message, 'message', contains('500'))),
    );
  });

  test('非 JSON 响应体 → ERR_AMAP_API', () async {
    await server.close(force: true);
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((HttpRequest req) {
      req.response
        ..statusCode = HttpStatus.ok
        ..write('<html>网关拦截</html>')
        ..close();
    });
    final p = local(() async => 'K');
    await expectLater(
      p.get('/v3/geocode/geo', {}),
      throwsA(isA<GeoHttpException>()
          .having((e) => e.code, 'code', 'ERR_AMAP_API')
          .having((e) => e.message, 'message', contains('JSON'))),
    );
  });

  test('JSON 数组（结构漂移）→ ERR_AMAP_API，不上抛裸异常', () async {
    await server.close(force: true);
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((HttpRequest req) {
      req.response
        ..statusCode = HttpStatus.ok
        ..write('[1,2,3]')
        ..close();
    });
    final p = local(() async => 'K');
    await expectLater(
      p.get('/v3/geocode/geo', {}),
      throwsA(isA<GeoHttpException>()
          .having((e) => e.code, 'code', 'ERR_AMAP_API')),
    );
  });

  test('默认装配指向高德 HTTPS（生产口径不被测试注入污染）', () async {
    final p = AmapHttpProvider(() async => 'K');
    // 生产构造不持端口/协议字段，故仅断言常量口径。
    expect(amapRestHost, 'restapi.amap.com');
    expect(p, isA<GeoHttpProvider>());
  });
}
