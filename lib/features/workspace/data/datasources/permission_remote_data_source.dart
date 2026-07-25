import '../../../../core/network/api_response.dart';
import '../../../../core/network/api_transport.dart';
import '../../domain/entities/workspace_permission.dart';

final class PermissionRemoteDataSource {
  const PermissionRemoteDataSource(this._api);

  final ApiTransport _api;

  Future<List<WorkspacePermission>> listForWorkspace(String workspaceId) async {
    final response = await _api.get<Object>(
      '/api/v1/rbac/me',
      queryParameters: {'workspace_id': workspaceId},
    );
    return envelopeList(
      response.data,
      'permissions',
    ).map(_permissionFromMap).toList(growable: false);
  }
}

WorkspacePermission _permissionFromMap(JsonMap map) {
  final code = stringField(map, const ['code']);
  final parts = code.split('.');
  return WorkspacePermission(
    id: stringField(map, const ['id'], fallback: code),
    code: code,
    module: stringField(map, const [
      'module',
    ], fallback: parts.isNotEmpty ? parts.first : ''),
    action: stringField(map, const [
      'action',
    ], fallback: parts.length > 1 ? parts.sublist(1).join('.') : ''),
    name: stringField(map, const ['name'], fallback: code),
    description: nullableStringField(map, const ['description']),
  );
}
