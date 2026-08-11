import '../entities/auth_tokens.dart';

enum AuthTokenPersistence { durable, sessionOnly }

final class AuthTokenMutationGuard {
  const AuthTokenMutationGuard({
    required this.instanceScopeId,
    required this.generation,
  });

  final String instanceScopeId;
  final String generation;

  @override
  bool operator ==(Object other) {
    return other is AuthTokenMutationGuard &&
        other.instanceScopeId == instanceScopeId &&
        other.generation == generation;
  }

  @override
  int get hashCode => Object.hash(instanceScopeId, generation);
}

abstract interface class AuthTokenRepository {
  Future<String?> readAccessToken();

  Future<String?> readRefreshToken();

  Future<void> saveTokens(AuthTokens tokens);

  Future<AuthTokenMutationGuard?> captureMutationGuard();

  Future<bool> isMutationGuardCurrent(AuthTokenMutationGuard guard);

  Future<String?> readAccessTokenIfCurrent(AuthTokenMutationGuard guard);

  Future<String?> readRefreshTokenIfCurrent(AuthTokenMutationGuard guard);

  Future<bool> saveTokensIfCurrent(
    AuthTokens tokens,
    AuthTokenMutationGuard guard, {
    AuthTokenPersistence? persistence,
  });

  Future<void> clearTokens();

  Future<bool> clearTokensIfCurrent(AuthTokenMutationGuard guard);
}
