import '../../../../core/database/app_database.dart';
import '../../../../core/security/secure_key_value_store.dart';
import '../../domain/repositories/workspace_session_repository.dart';

final class LocalWorkspaceSessionRepository
    implements WorkspaceSessionRepository {
  const LocalWorkspaceSessionRepository({
    required SecureKeyValueStore secureStore,
    required AppDatabase database,
  }) : _secureStore = secureStore,
       _database = database;

  final SecureKeyValueStore _secureStore;
  final AppDatabase _database;

  @override
  Future<String?> readActiveWorkspaceId() {
    return _secureStore.read(SecureStoreKey.activeWorkspaceId);
  }

  @override
  Future<void> saveActiveWorkspaceId(String workspaceId) {
    return _secureStore.write(SecureStoreKey.activeWorkspaceId, workspaceId);
  }

  @override
  Future<void> resetRuntimeForSwitch({
    required String? previousWorkspaceId,
    required String nextWorkspaceId,
  }) async {
    await _database.deleteScope('workspace_runtime');
  }
}
