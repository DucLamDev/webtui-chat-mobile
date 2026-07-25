import 'auth_tokens.dart';
import 'auth_user.dart';

final class AuthSession {
  const AuthSession({
    required this.tokens,
    required this.sessionId,
    this.user,
    this.refreshUntil,
  });

  final AuthTokens tokens;
  final String sessionId;
  final AuthUser? user;
  final DateTime? refreshUntil;
}
