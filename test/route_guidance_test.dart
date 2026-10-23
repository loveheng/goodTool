import 'package:flutter_test/flutter_test.dart';
import 'package:goodtools/geo/route_guidance.dart';

void main() {
  group('turnKindOf（instruction → 相对转向）', () {
    test('左右转 / 小角度 / 直行 / 掉头 / 环岛', () {
      expect(turnKindOf('左转进入深南大道'), TurnKind.left);
      expect(turnKindOf('请向右转'), TurnKind.right);
      expect(turnKindOf('靠左行驶'), TurnKind.left);
      expect(turnKindOf('沿路靠右直行'), TurnKind.right);
      expect(turnKindOf('向右前方行驶进入xx路'), TurnKind.slightRight);
      expect(turnKindOf('向左前方斜插'), TurnKind.slightLeft);
      expect(turnKindOf('沿科技园中一路向北步行120米'), TurnKind.straight);
      expect(turnKindOf('掉头沿原路返回'), TurnKind.uturn);
      expect(turnKindOf('进入环岛第2出口'), TurnKind.roundabout);
    });

    test('同句多关键词取最具体（前方 > 直转）', () {
      // 「向右前方」含「右」但先命中 slight 词表。
      expect(turnKindOf('向右前方行驶'), TurnKind.slightRight);
      // 掉头优先于一切。
      expect(turnKindOf('直行后掉头'), TurnKind.uturn);
    });

    test('出发 / 到达', () {
      expect(turnKindOf('出发沿民治大道向北'), TurnKind.start);
      expect(turnKindOf('到达终点'), TurnKind.end);
    });

    test('未识别 → unknown（不猜方向）', () {
      expect(turnKindOf('乘坐电梯上楼'), TurnKind.unknown);
      expect(turnKindOf(''), TurnKind.unknown);
    });
  });

  group('absoluteBearingOf（高德 orientation → 角度）', () {
    test('中文八方位', () {
      expect(absoluteBearingOf('北'), 0);
      expect(absoluteBearingOf('东北'), 45);
      expect(absoluteBearingOf('东南'), 135);
      expect(absoluteBearingOf('西南'), 225);
      expect(absoluteBearingOf('西北'), 315);
      expect(absoluteBearingOf(' 正东 '), 90);
    });

    test('数字角度串归一化到 [0,360)', () {
      expect(absoluteBearingOf('90'), 90);
      expect(absoluteBearingOf('-90'), 270);
      expect(absoluteBearingOf('450'), 90);
    });

    test('空 / null / 不可解析 → null（不兜底）', () {
      expect(absoluteBearingOf(null), isNull);
      expect(absoluteBearingOf(''), isNull);
      expect(absoluteBearingOf('随便'), isNull);
    });
  });

  test('bearingDirectionName（角度 → 八方位名，22.5° 居中容差）', () {
    expect(bearingDirectionName(0), '正北');
    expect(bearingDirectionName(20), '正北'); // 正北档覆盖 -22.5~22.5
    expect(bearingDirectionName(44), '东北'); // 44 距东北中心 45° 只差 1°
    expect(bearingDirectionName(45), '东北');
    expect(bearingDirectionName(90), '正东');
    expect(bearingDirectionName(181), '正南');
    expect(bearingDirectionName(350), '正北'); // 350 距正北 10°，落正北档
    expect(bearingDirectionName(337), '西北');
  });
}
