import '../../../../core/network/api_response.dart';
import '../../../../core/network/api_transport.dart';
import '../../domain/entities/workspace_invite.dart';

/// `GET /api/v1/invites/{token}`, `POST /api/v1/invites/{token}/accept`.
final class InviteRemoteDataSource {
  const InviteRemoteDataSource(this._api);

  final ApiTransport _api;

  Future<WorkspaceInvitePreview> preview(String token) async {
    final response = await _api.get<Object>(_path(token));
    final map = envelopeItem(response.data, 'invite');
    final workspace = jsonMap(field(map, const ['workspace']));
    return WorkspaceInvitePreview(
      workspaceId: stringField(workspace, const [
        'id',
      ], fallback: stringField(map, const ['workspace_id'])),
      workspaceName: stringField(workspace, const [
        'name',
      ], fallback: 'Workspace'),
      workspaceSlug: nullableStringField(workspace, const ['slug']),
      domain: nullableStringField(map, const ['domain'])?.toLowerCase(),
      kind: nullableStringField(map, const ['kind']),
      emailHint: nullableStringField(map, const ['email_hint']),
      status: stringField(map, const [
        'status',
      ], fallback: 'active').trim().toLowerCase(),
      expiresAt: nullableDateTimeField(map, const ['expires_at']),
    );
  }

  Future<InviteAcceptResult> accept(String token) async {
    final response = await _api.post<Object>(
      '${_path(token)}/accept',
      data: const <String, Object?>{},
    );
    final map = envelopeItem(response.data, 'invite');
    return InviteAcceptResult(
      workspaceId: stringField(map, const ['workspace_id']),
      status: stringField(map, const [
        'status',
      ], fallback: 'joined').trim().toLowerCase(),
    );
  }
}

String _path(String token) {
  final clean = token.trim();
  if (!isValidInviteToken(clean)) {
    throw const FormatException('Invite token is invalid.');
  }
  return '/api/v1/invites/${Uri.encodeComponent(clean)}';
}
