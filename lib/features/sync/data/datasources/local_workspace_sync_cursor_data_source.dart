import '../../../../core/database/app_database.dart';

final class LocalWorkspaceSyncCursorDataSource {
  const LocalWorkspaceSyncCursorDataSource(this._database);

  final AppDatabase _database;

  Future<String?> readCursor({required String workspaceId}) {
    return _database.readKeyValue(scope: _scope(workspaceId), key: 'cursor');
  }

  Future<void> saveCursor({
    required String workspaceId,
    required String cursor,
  }) {
    return _database.putKeyValue(
      scope: _scope(workspaceId),
      key: 'cursor',
      value: cursor,
    );
  }
}

String _scope(String workspaceId) {
  return 'workspace_sync:$workspaceId';
}
