import '../../../../core/network/api_response.dart';
import '../../../../core/network/api_transport.dart';
import '../../domain/entities/workspace.dart';

final class WorkspaceRemoteDataSource {
  const WorkspaceRemoteDataSource(this._api);

  final ApiTransport _api;

  Future<List<Workspace>> listMine() async {
    final response = await _api.get<Object>('/api/v1/workspaces');
    return envelopeList(
      response.data,
      'workspaces',
    ).map(_workspaceFromMap).toList(growable: false);
  }

  Future<Workspace> get(String workspaceId) async {
    final response = await _api.get<Object>('/api/v1/workspaces/$workspaceId');
    return _workspaceFromMap(envelopeItem(response.data, 'workspace'));
  }
}

Workspace _workspaceFromMap(JsonMap map) {
  return Workspace(
    id: stringField(map, const ['id']),
    slug: stringField(map, const ['slug']),
    name: stringField(map, const ['name']),
    plan: stringField(map, const ['plan'], fallback: 'standard'),
    status: stringField(map, const ['status'], fallback: 'active'),
    description: nullableStringField(map, const ['description']),
    ownerId: nullableStringField(map, const ['owner_id', 'ownerId']),
  );
}
