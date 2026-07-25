import '../../../../core/security/secure_key_value_store.dart';
import '../../domain/entities/auth_tokens.dart';
import '../../domain/repositories/auth_token_repository.dart';

final class SecureAuthTokenRepository implements AuthTokenRepository {
  const SecureAuthTokenRepository(this._store);

  final SecureKeyValueStore _store;

  @override
  Future<String?> readAccessToken() {
    return _store.read(SecureStoreKey.accessToken);
  }

  @override
  Future<String?> readRefreshToken() {
    return _store.read(SecureStoreKey.refreshToken);
  }

  @override
  Future<void> saveTokens(AuthTokens tokens) async {
    await _store.write(SecureStoreKey.accessToken, tokens.accessToken);
    if (tokens.refreshToken.trim().isNotEmpty) {
      await _store.write(SecureStoreKey.refreshToken, tokens.refreshToken);
    }
  }

  @override
  Future<void> clearTokens() async {
    await Future.wait([
      _store.delete(SecureStoreKey.accessToken),
      _store.delete(SecureStoreKey.refreshToken),
    ]);
  }
}
