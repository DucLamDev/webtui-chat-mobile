import '../../../../core/database/app_database.dart';
import '../../../../core/security/instance_scope.dart';

final class ClearWorkspaceCacheUseCase {
  const ClearWorkspaceCacheUseCase(this._database, this._instanceScope);

  final AppDatabase _database;
  final InstanceScope _instanceScope;

  Future<void> execute({required String workspaceId}) async {
    final normalized = workspaceId.trim();
    if (normalized.isEmpty) {
      return;
    }
    await _database.deleteScope(
      _instanceScope.localScope('conversation_cache:$normalized'),
    );
    await _database.deleteScopesWithPrefix(
      _instanceScope.localScope('message_cache:$normalized:'),
    );
  }
}
