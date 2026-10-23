/// 地理内核确定性单测：坐标纠偏 + 静态图 URL + 八方位。
/// 纯 Dart、无头、无网络，结果 100% 可复现。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:goodtools/geo/amap_sign.dart';
import 'package:goodtools/geo/coord_convert.dart';
import 'package:goodtools/geo/rdp.dart';
import 'package:goodtools/geo/static_map_url.dart';
import 'package:goodtools/mcp/geo_provider.dart';

const beijing = GeoPoint(39.9042, 116.4074); // 境内 WGS-84 近似
const newYork = GeoPoint(40.7128, -74.0060); // 境外

void main() {
  group('CoordConvert · 坐标系互转', () {
    test('境外坐标不做 GCJ-02 变换（原样返回）', () {
      expect(CoordConvert.wgs84ToGcj02(newYork), newYork);
      expect(CoordConvert.gcj02ToWgs84(newYork), newYork);
    });

    test('境外短路边界精确卡位（经度上界 137.8347 / 纬度下界 0.8293）', () {
      // 经度：137.83 境内应变换；137.84 境外原样返回
      const insideLng = GeoPoint(39.9, 137.83);
      const outsideLng = GeoPoint(39.9, 137.84);
      expect(CoordConvert.wgs84ToGcj02(insideLng), isNot(insideLng));
      expect(CoordConvert.wgs84ToGcj02(outsideLng), outsideLng);
      // 纬度：0.82 境外原样返回；0.84 境内应变换
      const outsideLat = GeoPoint(0.82, 116.4);
      const insideLat = GeoPoint(0.84, 116.4);
      expect(CoordConvert.wgs84ToGcj02(outsideLat), outsideLat);
      expect(CoordConvert.wgs84ToGcj02(insideLat), isNot(insideLat));
      // BD-09 同样短路（输入即 GCJ-02 语义）
      expect(CoordConvert.gcj02ToBd09(outsideLng), outsideLng);
      expect(CoordConvert.bd09ToGcj02(outsideLng), outsideLng);
    });

    test('WGS-84→GCJ-02 产生正向偏移（百米级，非 0）', () {
      final g = CoordConvert.wgs84ToGcj02(beijing);
      final dLat = (g.lat - beijing.lat).abs();
      final dLng = (g.lng - beijing.lng).abs();
      expect(dLat, greaterThan(1e-5));
      expect(dLng, greaterThan(1e-4));
      expect(dLat, lessThan(0.01));
      expect(dLng, lessThan(0.01));
    });

    test('WGS-84 ↔ GCJ-02 往返闭环（8 次迭代精度）', () {
      final g = CoordConvert.wgs84ToGcj02(beijing);
      final back = CoordConvert.gcj02ToWgs84(g);
      expect(back.lat, closeTo(beijing.lat, 1e-6));
      expect(back.lng, closeTo(beijing.lng, 1e-6));
    });

    test('GCJ-02 ↔ BD-09 往返闭环', () {
      final b = CoordConvert.gcj02ToBd09(beijing);
      final back = CoordConvert.bd09ToGcj02(b);
      // BD-09 公式固有残差约 1e-6（≈1 米），属可接受精度。
      expect(back.lat, closeTo(beijing.lat, 1e-5));
      expect(back.lng, closeTo(beijing.lng, 1e-5));
    });

    test('WGS-84 ↔ BD-09 组合往返闭环', () {
      final b = CoordConvert.wgs84ToBd09(beijing);
      final back = CoordConvert.bd09ToWgs84(b);
      expect(back.lat, closeTo(beijing.lat, 1e-5));
      expect(back.lng, closeTo(beijing.lng, 1e-5));
    });

    test('normalize 任意互转等价组合路径', () {
      final viaBd = CoordConvert.normalize(
          beijing, CoordSystem.wgs84, CoordSystem.bd09);
      expect(viaBd, CoordConvert.wgs84ToBd09(beijing));
      final back = CoordConvert.normalize(
          viaBd, CoordSystem.bd09, CoordSystem.wgs84);
      expect(back.lat, closeTo(beijing.lat, 1e-5));
    });
  });

  group('CoordConvert · Haversine 测距', () {
    test('同点距离为 0', () {
      expect(CoordConvert.haversineMeters(beijing, beijing), 0.0);
    });

    test('赤道上 1 经度 ≈ 111.3 km', () {
      final d = CoordConvert.haversineMeters(
          const GeoPoint(0, 0), const GeoPoint(0, 1));
      expect(d, greaterThan(110900));
      expect(d, lessThan(111500));
    });

    test('1 纬度 ≈ 111.1 km', () {
      final d = CoordConvert.haversineMeters(
          const GeoPoint(0, 0), const GeoPoint(1, 0));
      expect(d, greaterThan(110000));
      expect(d, lessThan(111500));
    });

    test('对称性', () {
      final a = CoordConvert.haversineMeters(beijing, newYork);
      final b = CoordConvert.haversineMeters(newYork, beijing);
      expect(a, b);
    });
  });

  group('AmapStaticMap · URL 构建', () {
    const key = 'TESTKEY';

    test('基本形态：restapi host + 必填参数', () {
      final url = AmapStaticMap.buildUrl(
        key: key,
        center: beijing,
        zoom: 12,
        size: (750, 400),
      );
      expect(url, startsWith('https://restapi.amap.com/v3/staticmap?'));
      final uri = Uri.parse(url);
      expect(uri.queryParameters['key'], key);
      expect(uri.queryParameters['zoom'], '12');
      expect(uri.queryParameters['size'], '750*400');
      // 中心点为 GCJ-02 原样（beijing 这里当作 GCJ-02 入参）
      expect(uri.queryParameters['location'], '116.407400,39.904200');
    });

    test('标记点与折线编码进 URL', () {
      final url = AmapStaticMap.buildUrl(
        key: key,
        markers: [
          StaticMapMarker(
            point: beijing,
            color: 0xFF0000,
            label: 'A',
          )
        ],
        paths: [
          StaticMapPath([
            beijing,
            const GeoPoint(39.91, 116.41),
          ])
        ],
      );
      final uri = Uri.parse(url);
      expect(uri.queryParameters.containsKey('markers'), isTrue);
      expect(uri.queryParameters.containsKey('paths'), isTrue);
      expect(uri.queryParameters['markers'], contains('116.407400,39.904200'));
      expect(uri.queryParameters['paths'], contains(';'));
    });

    test('coordSystem=WGS84 入参自动归一化到 GCJ-02', () {
      final url = AmapStaticMap.buildUrl(
        key: key,
        center: beijing,
        coordSystem: CoordSystem.wgs84,
      );
      final uri = Uri.parse(url);
      final g = CoordConvert.wgs84ToGcj02(beijing);
      expect(uri.queryParameters['location'],
          '${g.lng.toStringAsFixed(6)},${g.lat.toStringAsFixed(6)}');
    });

    test('确定性：相同入参产出相同 URL', () {
      final a = AmapStaticMap.buildUrl(key: key, center: beijing, zoom: 10);
      final b = AmapStaticMap.buildUrl(key: key, center: beijing, zoom: 10);
      expect(a, b);
    });
  });

  group('compassDirection · 八方位', () {
    test('基准方位', () {
      expect(compassDirection(0), '正北');
      expect(compassDirection(90), '正东');
      expect(compassDirection(180), '正南');
      expect(compassDirection(270), '正西');
    });

    test('324° → 西北', () {
      expect(compassDirection(324), '西北');
    });

    test('跨 360 归一化', () {
      expect(compassDirection(360), '正北');
      expect(compassDirection(-45), '西北');
      expect(compassDirection(405), '东北'); // 405%360=45° → 东北
    });
  });

  group('GeoHttpProvider · 端口默认实现', () {
    test('未注入源抛 ERR_AMAP_KEY_MISSING', () async {
      final provider = const NullGeoHttpProvider();
      late Object e;
      try {
        await provider.get('/v3/geocode/geo', {});
      } catch (err) {
        e = err;
      }
      expect(e, isA<GeoHttpException>());
      expect((e as GeoHttpException).code, 'ERR_AMAP_KEY_MISSING');
    });

    test('传感器空实现返回 null（不抛）', () async {
      const sensors = NullLocationSensorProvider();
      expect(await sensors.current(), isNull);
      expect(await sensors.compass(), isNull);
    });
  });

  group('amapSign · 高德数字签名', () {
    test('输出 32 位小写 hex', () {
      final sig = amapSign({'key': 'K', 'location': '116.4,39.9'}, 'SECRET');
      expect(sig, hasLength(32));
      expect(sig, matches(RegExp(r'^[0-9a-f]{32}$')));
    });

    test('参数顺序无关（按 key 升序拼接）', () {
      final a = amapSign({'b': '2', 'a': '1', 'key': 'K'}, 'S');
      final b = amapSign({'key': 'K', 'a': '1', 'b': '2'}, 'S');
      expect(a, b);
    });

    test('同输入确定性 / 异 secret 不同', () {
      final p = {'key': 'K', 'q': 'x'};
      expect(amapSign(p, 'S1'), amapSign(p, 'S1'));
      expect(amapSign(p, 'S1'), isNot(amapSign(p, 'S2')));
    });
  });

  group('rdpSimplify · 道格拉斯-普克抽稀', () {
    test('共线点坍缩为两端点', () {
      final line = List.generate(
          50, (i) => GeoPoint(39.9 + i * 0.001, 116.4 + i * 0.001));
      final out = rdpSimplify(line, epsilonMeters: 1);
      expect(out.length, 2);
      expect(out.first, line.first);
      expect(out.last, line.last);
    });

    test('直角拐点被保留', () {
      final pts = [
        const GeoPoint(39.900, 116.400),
        const GeoPoint(39.900, 116.410), // 拐点
        const GeoPoint(39.901, 116.410),
      ];
      final out = rdpSimplify(pts, epsilonMeters: 0.1);
      expect(out.length, 3);
    });

    test('硬上限：200 点长轨迹抽稀后 ≤ 80 点且首尾保留', () {
      final zig = List.generate(200, (i) {
        final lat = 39.9 + i * 0.0005;
        final lng = 116.4 + (i.isEven ? 0.0 : 0.003);
        return GeoPoint(lat, lng);
      });
      final out = rdpSimplify(zig, epsilonMeters: 1, maxPoints: 80);
      expect(out.length, lessThanOrEqualTo(80));
      expect(out.first, zig.first);
      expect(out.last, zig.last);
    });
  });

  group('AmapStaticMap · 签名与自适应视口', () {
    const key = 'TESTKEY';

    test('secret 非空时 URL 携带 32 位 sig', () {
      final url = AmapStaticMap.buildUrl(
        key: key,
        center: beijing,
        secret: 'SECRET',
      );
      final uri = Uri.parse(url);
      final sig = uri.queryParameters['sig']!;
      expect(sig, matches(RegExp(r'^[0-9a-f]{32}$')));
      // 相同入参 sig 稳定
      final url2 = AmapStaticMap.buildUrl(
        key: key,
        center: beijing,
        secret: 'SECRET',
      );
      expect(Uri.parse(url2).queryParameters['sig'], sig);
    });

    test('autoFit 按路径跨距自动逆算 zoom 与中心', () {
      final far = [
        const GeoPoint(22.50, 113.90), // 深圳南山附近
        const GeoPoint(22.55, 114.10), // 深圳罗湖附近
      ];
      final url = AmapStaticMap.buildUrl(
        key: key,
        paths: [
          StaticMapPath(far),
        ],
        autoFit: true,
        size: (750, 400),
      );
      final uri = Uri.parse(url);
      expect(uri.queryParameters.containsKey('location'), isTrue);
      final zoom = int.parse(uri.queryParameters['zoom']!);
      expect(zoom, inInclusiveRange(3, 17));
      // 中心点约为两点的中点（GCJ-02 入参）
      final loc = uri.queryParameters['location']!.split(',');
      final midLng = (113.90 + 114.10) / 2;
      final midLat = (22.50 + 22.55) / 2;
      expect(double.parse(loc[0]), closeTo(midLng, 0.01));
      expect(double.parse(loc[1]), closeTo(midLat, 0.01));
    });

    test('paths 超长被 RDP 抽稀（URL 长度受控）', () {
      final longPath = List.generate(
          500,
          (i) => GeoPoint(
              39.9 + 0.0001 * i, 116.4 + 0.0001 * (i % 2 == 0 ? 0 : 1)));
      final url = AmapStaticMap.buildUrl(
        key: key,
        paths: [StaticMapPath(longPath)],
      );
      // 抽稀后 URL 远小于 2048 上限
      expect(url.length, lessThan(2048));
    });
  });
}
