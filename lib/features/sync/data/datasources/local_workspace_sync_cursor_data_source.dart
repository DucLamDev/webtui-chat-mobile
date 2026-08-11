import '../../../../core/database/app_database.dart';
import '../../../../core/security/instance_scope.dart';

final class LocalWorkspaceSyncCursorDataSource {
  const LocalWorkspaceSyncCursorDataSource(this._database, this._instanceScope);

  final AppDatabase _database;
  final InstanceScope _instanceScope;

  Future<String?> readCursor({required String workspaceId}) {
    return _database.readKeyValue(
      scope: _instanceScope.localScope(_scope(workspaceId)),
      key: 'cursor',
    );
  }

  Future<void> saveCursor({
    required String workspaceId,
    required String cursor,
  }) {
    return _database.putKeyValue(
      scope: _instanceScope.localScope(_scope(workspaceId)),
      key: 'cursor',
      value: cursor,
    );
  }
}

String _scope(String workspaceId) {
  return 'workspace_sync:$workspaceId';
}
