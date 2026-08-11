import '../../../../core/database/app_database.dart';
import '../../../../core/security/instance_scope.dart';
import '../../../../core/security/instance_session_mutation_lock.dart';
import '../../../../core/security/secure_key_value_store.dart';
import '../../../../core/security/server_account_registry.dart';
import '../../domain/repositories/auth_token_repository.dart';
import '../../domain/repositories/session_state_repository.dart';

final class LocalSessionStateRepository implements SessionStateRepository {
  const LocalSessionStateRepository({
    required SecureKeyValueStore secureStore,
    required AppDatabase database,
    required InstanceScope? Function() loadInstanceScope,
    required Future<void> Function() clearNativeInstanceBinding,
    Future<void> Function(InstanceScope?)? terminateNativeCalls,
    Future<void> Function()? clearMessageNotifications,
    Future<void> Function(InstanceScope?)? clearScopedAttachmentFiles,
    SecureServerAccountRegistry? serverAccountRegistry,
  }) : _secureStore = secureStore,
       _database = database,
       _loadInstanceScope = loadInstanceScope,
       _clearNativeInstanceBinding = clearNativeInstanceBinding,
       _terminateNativeCalls = terminateNativeCalls,
       _clearMessageNotifications = clearMessageNotifications,
       _clearScopedAttachmentFiles = clearScopedAttachmentFiles,
       _serverAccountRegistry = serverAccountRegistry;

  final SecureKeyValueStore _secureStore;
  final AppDatabase _database;
  final InstanceScope? Function() _loadInstanceScope;
  final Future<void> Function() _clearNativeInstanceBinding;
  final Future<void> Function(InstanceScope?)? _terminateNativeCalls;
  final Future<void> Function()? _clearMessageNotifications;
  final Future<void> Function(InstanceScope?)? _clearScopedAttachmentFiles;
  final SecureServerAccountRegistry? _serverAccountRegistry;

  @override
  Future<AuthTokenMutationGuard?> captureActiveSessionGuard() {
    return InstanceSessionMutationLock.runExclusive(() async {
      final values = await Future.wait<String?>([
        _secureStore.read(SecureStoreKey.activeInstanceScopeId),
        _secureStore.read(SecureStoreKey.activeInstanceGeneration),
      ]);
      final scopeId = values[0]?.trim() ?? '';
      final generation = values[1]?.trim() ?? '';
      if (scopeId.isEmpty || generation.isEmpty) return null;
      return AuthTokenMutationGuard(
        instanceScopeId: scopeId,
        generation: generation,
      );
    });
  }

  @override
  Future<void> resetForServerSwitch() async {
    // Invalidate both native and secure bindings before enumerating message
    // notifications. A concurrent renderer will then fail its post-show check
    // and cancel the exact notification it may just have displayed.
    final instanceScope = _loadInstanceScope();
    await _clearNativeInstanceBinding();
    await _secureStore.clearSession();
    await _terminateNativeCalls?.call(instanceScope);
    await _clearMessageNotifications?.call();
    await _clearScopedAttachmentFiles?.call(instanceScope);
  }

  @override
  Future<void> resetForLogout() async {
    final instanceScope = _loadInstanceScope();
    await _clearNativeInstanceBinding();
    await _serverAccountRegistry?.clearActiveSession();
    await _secureStore.clearSession();
    await _terminateNativeCalls?.call(instanceScope);
    await _clearMessageNotifications?.call();
    await _clearScopedAttachmentFiles?.call(instanceScope);
    if (instanceScope != null) {
      await _database.deleteScopesWithPrefix(instanceScope.storagePrefix);
    }
  }

  @override
  Future<bool> resetForLogoutIfCurrent(AuthTokenMutationGuard guard) {
    return InstanceSessionMutationLock.runExclusive(() async {
      final values = await Future.wait<String?>([
        _secureStore.read(SecureStoreKey.activeInstanceScopeId),
        _secureStore.read(SecureStoreKey.activeInstanceGeneration),
      ]);
      final isCurrent =
          values[0] == guard.instanceScopeId && values[1] == guard.generation;

      await _serverAccountRegistry?.clearSessionForScopeId(
        guard.instanceScopeId,
      );
      await _database.deleteScopesWithPrefix(
        'instance_v2:${guard.instanceScopeId}:',
      );
      if (!isCurrent) return false;

      final instanceScope = _loadInstanceScope();
      await _clearNativeInstanceBinding();
      await _secureStore.clearSession();
      await _terminateNativeCalls?.call(instanceScope);
      await _clearMessageNotifications?.call();
      await _clearScopedAttachmentFiles?.call(instanceScope);
      return true;
    });
  }

  @override
  Future<bool> hasAnySavedSession() {
    return InstanceSessionMutationLock.runExclusive(() async {
      final registry =
          _serverAccountRegistry ?? SecureServerAccountRegistry(_secureStore);
      final activeState = await Future.wait<String?>([
        _secureStore.read(SecureStoreKey.accessToken),
        _secureStore.read(SecureStoreKey.refreshToken),
        _secureStore.read(SecureStoreKey.activeInstanceScopeId),
        _secureStore.read(SecureStoreKey.sessionInstanceScopeId),
        _secureStore.read(SecureStoreKey.sessionPersistence),
      ]);
      final activeScopeId = activeState[2]?.trim() ?? '';
      final hasActiveToken = activeState
          .take(2)
          .any((value) => value?.trim().isNotEmpty == true);
      final activeIsDurable =
          hasActiveToken &&
          activeScopeId.isNotEmpty &&
          activeState[3] == activeScopeId &&
          activeState[4] == durableSessionPersistenceValue &&
          await registry.hasDurableSessionForScopeId(activeScopeId);
      if (activeIsDurable) {
        return true;
      }
      return registry.hasAnySavedSession();
    });
  }
}
