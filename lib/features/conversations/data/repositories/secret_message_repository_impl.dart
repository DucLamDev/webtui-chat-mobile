import 'package:dio/dio.dart';
import '../../../../core/network/api_response.dart';
import '../../../../core/network/api_transport.dart';
import '../../../../core/result/result.dart';
import '../../../../core/result/result_guard.dart';
import '../../../auth/domain/repositories/device_identity_repository.dart';
import '../../domain/repositories/secret_message_repository.dart';

/// Tuyệt đối không chuyển plaintext qua outbox, Drift hoặc logger.
final class SecretMessageRepositoryImpl implements SecretMessageRepository {
  const SecretMessageRepositoryImpl(this._api, this._devices);
  final ApiTransport _api;
  final DeviceIdentityRepository _devices;
  String _path(String workspace, String channel) =>
      '/api/v1/workspaces/${Uri.encodeComponent(workspace)}/channels/${Uri.encodeComponent(channel)}/messages';
  @override
  Future<Result<void>> send(
    String workspaceId,
    String channelId,
    String body,
    String clientId,
  ) => guardResult(() async {
    await _api.post<Object>(
      _path(workspaceId, channelId),
      data: {
        'body': body,
        'secret': true,
        'kind': 'text',
        'client_message_id': clientId,
      },
      options: Options(headers: {'Idempotency-Key': clientId}),
    );
  });
  @override
  Future<Result<String>> reveal(
    String workspaceId,
    String channelId,
    String messageId,
    String token,
  ) => guardResult(() async {
    final device = await _devices.currentDevice();
    final response = await _api.post<Object>(
      '${_path(workspaceId, channelId)}/${Uri.encodeComponent(messageId)}/reveal',
      options: Options(
        headers: {'X-Device-ID': device.id, 'X-Reauth-Token': token},
      ),
    );
    return stringField(envelopeItem(response.data, 'message'), ['body']);
  });
}
