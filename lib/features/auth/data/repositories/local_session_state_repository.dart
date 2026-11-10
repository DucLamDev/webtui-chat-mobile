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

      // Một lỗi thu hồi cũ có thể tới sau khi đã đăng nhập lại cùng máy chủ.
      // Kiểm generation trước mọi thao tác xoá, kể cả kho phiên và Drift.
      if (!isCurrent) return false;

      final instanceScope = _loadInstanceScope();
      Object? firstError;
      StackTrace? firstStack;
      Future<void> cleanup(Future<void> Function() action) async {
        try {
          await action();
        } on Object catch (error, stack) {
          firstError ??= error;
          firstStack ??= stack;
        }
      }

      await cleanup(_clearNativeInstanceBinding);
      await cleanup(
        () async => _serverAccountRegistry?.clearSessionForScopeId(
          guard.instanceScopeId,
        ),
      );
      await cleanup(_secureStore.clearSession);
      await cleanup(() async => _terminateNativeCalls?.call(instanceScope));
      await cleanup(() async => _clearMessageNotifications?.call());
      await cleanup(
        () async => _clearScopedAttachmentFiles?.call(instanceScope),
      );
      await cleanup(
        () => _database.deleteScopesWithPrefix(
          'instance_v2:${guard.instanceScopeId}:',
        ),
      );
      if (firstError != null) {
        Error.throwWithStackTrace(firstError!, firstStack!);
      }
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
