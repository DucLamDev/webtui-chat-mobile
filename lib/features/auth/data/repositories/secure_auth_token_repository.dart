import '../../../../core/security/instance_session_mutation_lock.dart';
import '../../../../core/security/secure_key_value_store.dart';
import '../../../../core/security/server_account_registry.dart';
import '../../domain/entities/auth_tokens.dart';
import '../../domain/repositories/auth_token_repository.dart';

final class SecureAuthTokenRepository implements AuthTokenRepository {
  SecureAuthTokenRepository(
    this._store, {
    Future<void> Function(bool durable)? setNativeSessionDurable,
  }) : _setNativeSessionDurable = setNativeSessionDurable;

  final SecureKeyValueStore _store;
  final Future<void> Function(bool durable)? _setNativeSessionDurable;
  AuthTokenMutationGuard? _sessionOnlyGuard;
  String? _sessionAccessToken;
  String? _sessionRefreshToken;

  @override
  Future<String?> readAccessToken() {
    return InstanceSessionMutationLock.runExclusive(() async {
      if (!await _hasActiveInstanceBinding()) return null;
      final guard = await _activeGuard();
      if (guard != null && _sessionOnlyGuard == guard) {
        return _sessionAccessToken;
      }
      return guard == null
          ? null
          : _readDurableToken(SecureStoreKey.accessToken, guard);
    });
  }

  @override
  Future<String?> readRefreshToken() {
    return InstanceSessionMutationLock.runExclusive(() async {
      if (!await _hasActiveInstanceBinding()) return null;
      final guard = await _activeGuard();
      if (guard != null && _sessionOnlyGuard == guard) {
        return _sessionRefreshToken;
      }
      return guard == null
          ? null
          : _readDurableToken(SecureStoreKey.refreshToken, guard);
    });
  }

  @override
  Future<void> saveTokens(AuthTokens tokens) async {
    final guard = await captureMutationGuard();
    if (guard == null ||
        !await saveTokensIfCurrent(
          tokens,
          guard,
          persistence: AuthTokenPersistence.durable,
        )) {
      throw StateError('Cannot save tokens without a validated instance.');
    }
  }

  @override
  Future<AuthTokenMutationGuard?> captureMutationGuard() {
    return InstanceSessionMutationLock.runExclusive(() async {
      final values = await Future.wait<String?>([
        _store.read(SecureStoreKey.activeInstanceScopeId),
        _store.read(SecureStoreKey.liveDiscoveryValidatedScopeId),
        _store.read(SecureStoreKey.activeInstanceGeneration),
      ]);
      final scopeId = values[0]?.trim() ?? '';
      final generation = values[2]?.trim() ?? '';
      if (scopeId.isEmpty || values[1] != scopeId || generation.isEmpty) {
        return null;
      }
      return AuthTokenMutationGuard(
        instanceScopeId: scopeId,
        generation: generation,
      );
    });
  }

  @override
  Future<bool> isMutationGuardCurrent(AuthTokenMutationGuard guard) {
    return InstanceSessionMutationLock.runExclusive(
      () => _guardIsCurrent(guard),
    );
  }

  @override
  Future<String?> readAccessTokenIfCurrent(AuthTokenMutationGuard guard) {
    return InstanceSessionMutationLock.runExclusive(() async {
      if (!await _guardIsCurrent(guard) || !await _hasActiveInstanceBinding()) {
        return null;
      }
      if (_sessionOnlyGuard == guard) return _sessionAccessToken;
      return _readDurableToken(SecureStoreKey.accessToken, guard);
    });
  }

  @override
  Future<String?> readRefreshTokenIfCurrent(AuthTokenMutationGuard guard) {
    return InstanceSessionMutationLock.runExclusive(() async {
      if (!await _guardIsCurrent(guard) || !await _hasActiveInstanceBinding()) {
        return null;
      }
      if (_sessionOnlyGuard == guard) return _sessionRefreshToken;
      return _readDurableToken(SecureStoreKey.refreshToken, guard);
    });
  }

  @override
  Future<bool> saveTokensIfCurrent(
    AuthTokens tokens,
    AuthTokenMutationGuard guard, {
    AuthTokenPersistence? persistence,
  }) {
    return InstanceSessionMutationLock.runExclusive(() async {
      if (!await _guardIsCurrent(guard)) return false;
      final effectivePersistence =
          persistence ??
          (_sessionOnlyGuard == guard
              ? AuthTokenPersistence.sessionOnly
              : AuthTokenPersistence.durable);
      if (effectivePersistence == AuthTokenPersistence.sessionOnly) {
        // Revoke the account record first. Persistent reads require this
        // record as well as the global marker, so a process death at any later
        // await cannot resurrect the previous durable session.
        await SecureServerAccountRegistry(
          _store,
        ).clearSessionForScopeId(guard.instanceScopeId);
        await _setNativeSessionDurable?.call(false);
        await _store.delete(SecureStoreKey.sessionPersistence);
        await _store.write(
          SecureStoreKey.sessionInstanceScopeId,
          guard.instanceScopeId,
        );
        _sessionOnlyGuard = guard;
        _sessionAccessToken = tokens.accessToken;
        _sessionRefreshToken = tokens.refreshToken.trim().isEmpty
            ? null
            : tokens.refreshToken;
        await Future.wait([
          _store.delete(SecureStoreKey.accessToken),
          _store.delete(SecureStoreKey.refreshToken),
        ]);
      } else {
        await _store.write(
          SecureStoreKey.sessionInstanceScopeId,
          guard.instanceScopeId,
        );
        if (_sessionOnlyGuard == guard) {
          _clearSessionOnlyTokens();
        }
        await _store.write(SecureStoreKey.accessToken, tokens.accessToken);
        if (tokens.refreshToken.trim().isNotEmpty) {
          await _store.write(SecureStoreKey.refreshToken, tokens.refreshToken);
        } else {
          await _store.delete(SecureStoreKey.refreshToken);
        }
        await _store.write(
          SecureStoreKey.sessionPersistence,
          durableSessionPersistenceValue,
        );
        await SecureServerAccountRegistry(_store).stashActiveSession();
        await _setNativeSessionDurable?.call(true);
      }
      return true;
    });
  }

  @override
  Future<void> clearTokens() {
    return InstanceSessionMutationLock.runExclusive(_clearTokensUnlocked);
  }

  @override
  Future<bool> clearTokensIfCurrent(AuthTokenMutationGuard guard) {
    return InstanceSessionMutationLock.runExclusive(() async {
      if (!await _guardIsCurrent(guard)) return false;
      await _clearTokensUnlocked();
      return true;
    });
  }

  Future<void> _clearTokensUnlocked() async {
    _clearSessionOnlyTokens();
    await SecureServerAccountRegistry(_store).clearActiveSession();
    await _setNativeSessionDurable?.call(false);
    await Future.wait([
      _store.delete(SecureStoreKey.accessToken),
      _store.delete(SecureStoreKey.refreshToken),
      _store.delete(SecureStoreKey.sessionInstanceScopeId),
      _store.delete(SecureStoreKey.sessionPersistence),
    ]);
  }

  void _clearSessionOnlyTokens() {
    _sessionOnlyGuard = null;
    _sessionAccessToken = null;
    _sessionRefreshToken = null;
  }

  Future<AuthTokenMutationGuard?> _activeGuard() async {
    final values = await Future.wait<String?>([
      _store.read(SecureStoreKey.activeInstanceScopeId),
      _store.read(SecureStoreKey.activeInstanceGeneration),
    ]);
    final scopeId = values[0]?.trim() ?? '';
    final generation = values[1]?.trim() ?? '';
    if (scopeId.isEmpty || generation.isEmpty) return null;
    return AuthTokenMutationGuard(
      instanceScopeId: scopeId,
      generation: generation,
    );
  }

  Future<bool> _guardIsCurrent(AuthTokenMutationGuard guard) async {
    final values = await Future.wait<String?>([
      _store.read(SecureStoreKey.activeInstanceScopeId),
      _store.read(SecureStoreKey.liveDiscoveryValidatedScopeId),
      _store.read(SecureStoreKey.activeInstanceGeneration),
    ]);
    return values[0] == guard.instanceScopeId &&
        values[1] == guard.instanceScopeId &&
        values[2] == guard.generation;
  }

  Future<bool> _hasActiveInstanceBinding() async {
    final values = await Future.wait<String?>([
      _store.read(SecureStoreKey.activeInstanceScopeId),
      _store.read(SecureStoreKey.liveDiscoveryValidatedScopeId),
      _store.read(SecureStoreKey.sessionInstanceScopeId),
      _store.read(SecureStoreKey.activeInstanceGeneration),
    ]);
    final active = values[0]?.trim() ?? '';
    final live = values[1]?.trim() ?? '';
    final session = values[2]?.trim() ?? '';
    final generation = values[3]?.trim() ?? '';
    return active.isNotEmpty &&
        active == live &&
        active == session &&
        generation.isNotEmpty;
  }

  Future<String?> _readDurableToken(
    SecureStoreKey key,
    AuthTokenMutationGuard guard,
  ) async {
    if (!await _hasDurablePersistenceForGuard(guard)) return null;
    final token = await _store.read(key);
    if (!await _hasDurablePersistenceForGuard(guard)) return null;
    return token;
  }

  Future<bool> _hasDurablePersistenceForGuard(
    AuthTokenMutationGuard guard,
  ) async {
    if (!await _guardIsCurrent(guard)) return false;
    final values = await Future.wait<String?>([
      _store.read(SecureStoreKey.sessionInstanceScopeId),
      _store.read(SecureStoreKey.sessionPersistence),
    ]);
    if (values[0] != guard.instanceScopeId ||
        values[1] != durableSessionPersistenceValue) {
      return false;
    }
    return SecureServerAccountRegistry(
      _store,
    ).hasDurableSessionForScopeId(guard.instanceScopeId);
  }
}
