library;

import '../action/command_gateway.dart';
import '../mcp/settings_keys.dart';
import '../mcp/settings_kv.dart';

/// 地图页「上次定位点」用户侧 Actor：把 UI 会话态（GCJ-02 视图坐标）落 KV。
///
/// 纪律同设置 Actor（`settings_actors.dart`）：校验在 Actor 内（必填 / 取值域），
/// 失败回结构化机器码；写端口（KV）只在此持有，UI 经 Port → 网关（R1）。
/// `geo_last_location` 是**会话态键**：不进 userWritable / 回显枚举，
/// AI 不可经 MCP 工具面触达（`user_geo_save_last_location` 只登记用户侧）。
class GeoLastLocationActor {
  GeoLastLocationActor({required this.kv});

  final SettingsKv kv;

  /// 登记进用户侧注册表（AI 不可触达）。
  void register(CommandGateway gateway) {
    gateway.registerUser('user_geo_save_last_location', save);
  }

  /// 记住上次定位点。载荷 `{lat, lng}`（GCJ-02 显示坐标）。
  Future<UserCommandResult> save(Command cmd) async {
    final p = cmd.payload;
    final lat = _asDouble(p['lat']);
    final lng = _asDouble(p['lng']);
    if (lat == null || lng == null) {
      return const UserCommandResult.failure(
        'MISSING_ARGUMENT',
        '缺少必填参数 lat / lng（数值）',
        suggestion: 'lat/lng 为 GCJ-02 double 坐标',
      );
    }
    if (lat < -90 || lat > 90 || lng < -180 || lng > 180) {
      return UserCommandResult.failure(
        'INVALID_ARGUMENT',
        '经纬度越界（lat=$lat, lng=$lng）',
        suggestion: '纬度 -90~90，经度 -180~180',
      );
    }
    await kv.settingsSet(<String, String>{
      SettingsKeys.geoLastLocation: '$lat,$lng',
    });
    return const UserCommandResult.success(<String, Object?>{'saved': true});
  }

  static double? _asDouble(Object? v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v.trim());
    return null;
  }
}
