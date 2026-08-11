import '../../../../core/database/app_database.dart';
import '../../../../core/security/instance_scope.dart';
import '../../../../core/security/secure_key_value_store.dart';
import '../../domain/repositories/workspace_session_repository.dart';

final class LocalWorkspaceSessionRepository
    implements WorkspaceSessionRepository {
  const LocalWorkspaceSessionRepository({
    required SecureKeyValueStore secureStore,
    required AppDatabase database,
    required InstanceScope instanceScope,
  }) : _secureStore = secureStore,
       _database = database,
       _instanceScope = instanceScope;

  final SecureKeyValueStore _secureStore;
  final AppDatabase _database;
  final InstanceScope _instanceScope;

  @override
  Future<String?> readActiveWorkspaceId() async {
    final values = await Future.wait<String?>([
      _secureStore.read(SecureStoreKey.activeWorkspaceId),
      _secureStore.read(SecureStoreKey.activeWorkspaceInstanceScopeId),
      _secureStore.read(SecureStoreKey.activeInstanceScopeId),
    ]);
    if (values[1] != _instanceScope.storageId ||
        values[2] != _instanceScope.storageId) {
      return null;
    }
    return values[0];
  }

  @override
  Future<void> saveActiveWorkspaceId(String workspaceId) async {
    final activeScopeId = await _secureStore.read(
      SecureStoreKey.activeInstanceScopeId,
    );
    if (activeScopeId != _instanceScope.storageId) {
      throw StateError('Active server changed while saving workspace state.');
    }
    await _secureStore.write(SecureStoreKey.activeWorkspaceId, workspaceId);
    await _secureStore.write(
      SecureStoreKey.activeWorkspaceInstanceScopeId,
      _instanceScope.storageId,
    );
  }

  @override
  Future<void> resetRuntimeForSwitch({
    required String? previousWorkspaceId,
    required String nextWorkspaceId,
  }) async {
    await _database.deleteScope(_instanceScope.localScope('workspace_runtime'));
  }
}
