library;

import '../action/command_gateway.dart';
import '../action/geo_commands.dart';
import '../mcp/settings_keys.dart';
import '../repository/settings_repository.dart';

/// 地图页「上次定位点」UI 适配层：**读经 Repository（R5），写经 CommandGateway（R1）**。
///
/// 与 [DraftPort] 同一条纪律：定位点是 UI 会话态，读不直连 KV、写不旁路网关。
/// 坐标口径 = GCJ-02 显示坐标（与地图瓦片同系，进场恢复即用，无需再纠偏）。
class GeoLastLocationPort {
  const GeoLastLocationPort(this._repository, this._gateway);

  final SettingsRepository _repository;
  final CommandGateway _gateway;

  /// 读上次定位点；从未定位过返回 null（调用方保持占位中心并等刷新定位）。
  Future<({double lat, double lng})?> read() async {
    final raw = await _repository.read(SettingsKeys.geoLastLocation);
    if (raw == null) return null;
    final parts = raw.split(',');
    if (parts.length != 2) return null;
    final lat = double.tryParse(parts[0].trim());
    final lng = double.tryParse(parts[1].trim());
    if (lat == null || lng == null) return null;
    return (lat: lat, lng: lng);
  }

  /// 记住定位点（GCJ-02）。
  Future<UserCommandResult> save(double lat, double lng) =>
      _gateway.dispatchUser(
          UserGeoSaveLastLocationCommand({'lat': lat, 'lng': lng}));
}
