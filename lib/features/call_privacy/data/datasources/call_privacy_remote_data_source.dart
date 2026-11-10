import '../../../../core/network/api_response.dart';
import '../../../../core/network/api_transport.dart';
import '../../domain/entities/call_privacy.dart';

final class CallPrivacyRemoteDataSource {
  const CallPrivacyRemoteDataSource(this._api);

  final ApiTransport _api;

  Future<WhoCanCallMe> load({required String workspaceId}) async {
    final response = await _api.get<Object>(_path(workspaceId));
    return _parse(response.data);
  }

  Future<WhoCanCallMe> update({
    required String workspaceId,
    required WhoCanCallMe value,
  }) async {
    final response = await _api.put<Object>(
      _path(workspaceId),
      data: {'who_can_call_me': value.apiValue},
    );
    return _parse(response.data);
  }
}

String _path(String workspaceId) =>
    '/api/v1/workspaces/${Uri.encodeComponent(workspaceId.trim())}'
    '/me/call-privacy';

WhoCanCallMe _parse(Object? data) {
  final item = envelopeItem(data, 'call_privacy');
  return WhoCanCallMe.fromApi(
    stringField(item, const ['who_can_call_me', 'whoCanCallMe']),
  );
}
