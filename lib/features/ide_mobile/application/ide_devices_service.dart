import '../data/ide_rpc_client.dart';
import '../domain/ide_server_models.dart';
import '../domain/ide_tools_models.dart';

/// `devices.*` (Phụ lục C3): điện thoại đã gắn của chính người dùng.
class IdeDevicesService {
  IdeDevicesService(this._rpc);

  final IdeRpcClient _rpc;

  Future<List<IdeDevice>> list() async =>
      IdeDevice.parseList(await _rpc.call('devices.list', const {}));

  /// Trả `true` khi máy vừa gỡ chính là máy đang gọi.
  Future<bool> revoke(String deviceId) async => toolBool(
    toolMap(
      await _rpc.call('devices.revoke', {'device_id': deviceId}),
    )['current'],
  );
}
