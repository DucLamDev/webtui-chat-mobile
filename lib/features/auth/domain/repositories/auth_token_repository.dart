import '../entities/auth_tokens.dart';

abstract interface class AuthTokenRepository {
  Future<String?> readAccessToken();

  Future<String?> readRefreshToken();

  Future<void> saveTokens(AuthTokens tokens);

  Future<void> clearTokens();
}
