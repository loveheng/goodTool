import 'package:flutter_test/flutter_test.dart';
import 'package:goodtools/action/command_gateway.dart';
import 'package:goodtools/action/geo_commands.dart';
import 'package:goodtools/geo/coord_convert.dart';
import 'package:goodtools/service/favorite_place_store.dart';
import 'package:goodtools/service/geo_favorite_actors.dart';
import 'package:goodtools/ui_ports/geo_port.dart';

void main() {
  group('FavoritePlaceStore（InMemory 双实现）', () {
    test('add → list → delete 闭环', () async {
      final store = InMemoryFavoritePlaceStore();
      final id = await store.addPlace(const FavoritePlace(
        id: 'geo_fav_00000001',
        name: '公司',
        lat: 39.9,
        lng: 116.4,
        address: '某地',
      ));
      expect(id, 'geo_fav_00000001');
      final list = await store.list();
      expect(list, hasLength(1));
      expect(list.single.name, '公司');
      expect(list.single.coordSystem, 'GCJ02');
      expect(await store.deletePlace(id), isTrue);
      expect(await store.list(), isEmpty);
      // 重复删除：无匹配回 false（Actor 转 NOT_FOUND）。
      expect(await store.deletePlace(id), isFalse);
    });

    test('超上限抛 FavoriteLimitExceeded，不静默挤掉旧条目', () async {
      final store = InMemoryFavoritePlaceStore();
      for (var i = 0; i < favoritePlaceLimit; i++) {
        await store.addPlace(FavoritePlace(
          id: 'geo_fav_${i.toString().padLeft(8, '0')}',
          name: '地点$i',
          lat: 0,
          lng: 0,
        ));
      }
      await expectLater(
        store.addPlace(const FavoritePlace(
          id: 'geo_fav_overflow',
          name: '超出',
          lat: 0,
          lng: 0,
        )),
        throwsA(isA<FavoriteLimitExceeded>()),
      );
      expect((await store.list()).length, favoritePlaceLimit);
    });
  });

  group('GeoFavoriteActors（用户侧校验收口）', () {
    late InMemoryFavoritePlaceStore store;
    late GeoFavoriteActors actors;
    late CommandGateway gateway;

    setUp(() {
      store = InMemoryFavoritePlaceStore();
      actors = GeoFavoriteActors(store: store, writer: store);
      gateway = CommandGateway();
      actors.register(gateway);
    });

    Future<UserCommandResult> add(Map<String, Object?> payload) =>
        gateway.dispatchUser(UserGeoFavoriteAddCommand(payload));

    test('成功新增：回 id + 条数确认（standards §5.2 轻量快照）', () async {
      final r = await add(<String, Object?>{
        'name': '公司',
        'lat': 39.9,
        'lng': '116.4', // LLM 弱类型漂移：数字可包字符串（宽容解析）
      });
      expect(r.ok, isTrue);
      expect((r.data! as Map<String, Object?>)['count'], 1);
      expect((r.data! as Map<String, Object?>)['name'], '公司');
      expect((await store.list()).single.id, (r.data! as Map)['id']);
    });

    test('缺 name / 空白 name → MISSING_ARGUMENT', () async {
      expect((await add(<String, Object?>{'lat': 1, 'lng': 2})).errorCode,
          'MISSING_ARGUMENT');
      expect(
          (await add(<String, Object?>{'name': '  ', 'lat': 1, 'lng': 2}))
              .errorCode,
          'MISSING_ARGUMENT');
    });

    test('name 超 40 字符 → INVALID_ARGUMENT', () async {
      final r = await add(<String, Object?>{
        'name': '长' * 41,
        'lat': 1,
        'lng': 2,
      });
      expect(r.errorCode, 'INVALID_ARGUMENT');
    });

    test('经纬度越界 → INVALID_ARGUMENT（不静默 clamp）', () async {
      final r = await add(<String, Object?>{'name': 'x', 'lat': 91, 'lng': 2});
      expect(r.errorCode, 'INVALID_ARGUMENT');
      final r2 = await add(<String, Object?>{'name': 'x', 'lat': 1, 'lng': 181});
      expect(r2.errorCode, 'INVALID_ARGUMENT');
    });

    test('未知 coordSystem → INVALID_ARGUMENT；WGS84 合法', () async {
      final bad = await add(<String, Object?>{
        'name': 'x',
        'lat': 1,
        'lng': 2,
        'coordSystem': 'BD09',
      });
      expect(bad.errorCode, 'INVALID_ARGUMENT');
      final good = await add(<String, Object?>{
        'name': 'x',
        'lat': 1,
        'lng': 2,
        'coordSystem': 'WGS84',
      });
      expect(good.ok, isTrue);
      expect((await store.list()).single.coordSystem, 'WGS84');
    });

    test('超上限 → FAVORITE_LIMIT_EXCEEDED', () async {
      for (var i = 0; i < favoritePlaceLimit; i++) {
        await store.addPlace(FavoritePlace(
          id: 'geo_fav_${i.toString().padLeft(8, '0')}',
          name: '地点$i',
          lat: 0,
          lng: 0,
        ));
      }
      final r = await add(<String, Object?>{'name': '超出', 'lat': 1, 'lng': 2});
      expect(r.errorCode, 'FAVORITE_LIMIT_EXCEEDED');
    });

    test('删除：成功回确认；id 不存在 → NOT_FOUND（不静默成功）', () async {
      final id = await store.addPlace(const FavoritePlace(
        id: 'geo_fav_aa',
        name: '公司',
        lat: 1,
        lng: 2,
      ));
      final del = await gateway.dispatchUser(
          UserGeoFavoriteDeleteCommand(<String, Object?>{'id': id}));
      expect(del.ok, isTrue);
      expect((del.data! as Map<String, Object?>)['deleted'], isTrue);
      expect((del.data! as Map<String, Object?>)['count'], 0);
      final miss = await gateway.dispatchUser(
          UserGeoFavoriteDeleteCommand(<String, Object?>{'id': 'geo_fav_xx'}));
      expect(miss.errorCode, 'NOT_FOUND');
    });

    test('AI 侧不可触达：AI dispatch 通道无 user_geo_* 命令（fail-closed）', () async {
      // AI 侧派发按未登记拒绝（文本信封），绝不落到用户侧 Actor。
      // （用具体命令类构造；Command 为抽象基类。）
      final aiResult = await gateway.dispatch(
        const UserGeoFavoriteAddCommand(<String, Object?>{
          'name': 'x',
          'lat': 1,
          'lng': 2,
        }),
      );
      expect(aiResult.single['text'], contains('未开放给 AI'));
      expect(await store.list(), isEmpty);
    });

    test('folder：缺省 = 未分类；合法夹名落库并回显', () async {
      final noFolder = await add(<String, Object?>{'name': '家', 'lat': 1, 'lng': 2});
      expect(noFolder.ok, isTrue);
      expect((noFolder.data! as Map<String, Object?>)['folder'], '');
      expect((await store.list()).single.folder, '');

      final withFolder = await add(<String, Object?>{
        'name': '公司',
        'lat': 3,
        'lng': 4,
        'folder': ' 通勤 ',
      });
      expect(withFolder.ok, isTrue);
      expect((withFolder.data! as Map<String, Object?>)['folder'], '通勤');
      final places = await store.list();
      expect(places.singleWhere((p) => p.name == '公司').folder, '通勤');
    });

    test('folder 超 20 字符 → INVALID_ARGUMENT；空白 = 未分类', () async {
      final long = await add(<String, Object?>{
        'name': 'x',
        'lat': 1,
        'lng': 2,
        'folder': '夹' * 21,
      });
      expect(long.errorCode, 'INVALID_ARGUMENT');
      final blank = await add(<String, Object?>{
        'name': 'x',
        'lat': 1,
        'lng': 2,
        'folder': '   ',
      });
      expect(blank.ok, isTrue);
      expect((await store.list()).single.folder, '');
    });
  });

  group('收藏夹分组（groupFavoritesByFolder）', () {
    FavoritePlaceView v(String id, String folder) => FavoritePlaceView(
          id: id,
          name: '地点$id',
          lat: 0,
          lng: 0,
          coordSystem: 'GCJ02',
          folder: folder,
        );

    test('非空夹名字典序在前、未分类恒最后；组内保序', () {
      final groups = groupFavoritesByFolder(<FavoritePlaceView>[
        v('1', ''),
        v('2', '美食'),
        v('3', ''),
        v('4', '通勤'),
        v('5', '美食'),
      ]);
      expect(groups.map((g) => g.folder).toList(), <String>['美食', '通勤', '']);
      expect(groups[0].places.map((p) => p.id), <String>['2', '5']);
      expect(groups[1].places.map((p) => p.id), <String>['4']);
      expect(groups[2].places.map((p) => p.id), <String>['1', '3']);
    });

    test('全未分类 → 单组「」；空列表 → 空分组', () {
      final all = groupFavoritesByFolder(<FavoritePlaceView>[v('1', ''), v('2', '')]);
      expect(all, hasLength(1));
      expect(all.single.folder, '');
      expect(groupFavoritesByFolder(const <FavoritePlaceView>[]), isEmpty);
    });
  });

  group('收藏夹迁移（老数据无 folder 字段）', () {
    test('fromJson 缺 folder → 未分类（数据完整保留，不丢弃）', () {
      final p = FavoritePlace.fromJson(<String, Object?>{
        'id': 'geo_fav_old',
        'name': '老收藏',
        'lat': 39.9,
        'lng': 116.4,
        'coordSystem': 'GCJ02',
      });
      expect(p.folder, '');
      expect(p.name, '老收藏');
      // round-trip：folder 显式落库。
      expect(FavoritePlace.fromJson(p.toJson()).folder, '');
    });
  });

  group('GeoMapPort（静态图 URL）', () {
    test('未配置 Key fail-closed 返 ERR_AMAP_KEY_MISSING', () async {
      final port = GeoMapPort(readKey: () async => null, readSecret: () async => null);
      final view = await port.staticMapUrl(lat: 39.9, lng: 116.4);
      expect(view.ok, isFalse);
      expect(view.errorCode, 'ERR_AMAP_KEY_MISSING');
      expect(view.url, isNull);
    });

    test('配 Key 产出 https 静态图 URL，含标记与 key（Key 明文不出端口外）',
        () async {
      final port = GeoMapPort(
        readKey: () async => 'test-key',
        readSecret: () async => null,
      );
      final view = await port.staticMapUrl(lat: 39.9, lng: 116.4, label: 'A');
      expect(view.ok, isTrue);
      final uri = Uri.parse(view.url!);
      expect(uri.scheme, 'https');
      expect(uri.host, 'restapi.amap.com');
      expect(uri.path, '/v3/staticmap');
      expect(uri.queryParameters['key'], 'test-key');
      expect(uri.queryParameters['markers'], contains('116.400000,39.900000'));
    });

    test('WGS84 入参自动归一化到 GCJ-02（偏移可见）', () async {
      final port = GeoMapPort(
        readKey: () async => 'k',
        readSecret: () async => null,
      );
      final wgs = await port.staticMapUrl(lat: 39.908722, lng: 116.397499, coordSystem: 'WGS84');
      final gcj = await port.staticMapUrl(lat: 39.908722, lng: 116.397499, coordSystem: 'GCJ02');
      expect(wgs.ok, isTrue);
      expect(gcj.ok, isTrue);
      // WGS-84 → GCJ-02 在北京有数百米偏移，location 参数应不同。
      expect(Uri.parse(wgs.url!).queryParameters['location'],
          isNot(Uri.parse(gcj.url!).queryParameters['location']));
    });
  });

  group('FavoritePlaceView（类型化视图）', () {
    test('域模型 → 视图映射：address 缺省透传、坐标格式化 6 位', () {
      final v = FavoritePlaceView.fromFavorite(const FavoritePlace(
        id: 'geo_fav_1',
        name: '公司',
        lat: 39.908722,
        lng: 116.397499,
      ));
      expect(v.address, isNull);
      expect(v.formatted, '39.908722, 116.397499');
      expect(v.coordSystem, 'GCJ02');
      final list = FavoritePlaceView.listFrom(<FavoritePlace>[
        const FavoritePlace(id: 'a', name: 'a', lat: 0, lng: 0),
        const FavoritePlace(id: 'b', name: 'b', lat: 0, lng: 0, address: 'x'),
      ]);
      expect(list, hasLength(2));
      expect(list[1].address, 'x');
    });

    test('WGS84 收藏点坐标可直接经 CoordConvert 归一化（内核件共用）', () {
      final g = CoordConvert.wgs84ToGcj02(const GeoPoint(39.908722, 116.397499));
      expect(g.lat, closeTo(39.91, 0.01));
      expect(g.lng, closeTo(116.40, 0.01));
    });
  });
}
