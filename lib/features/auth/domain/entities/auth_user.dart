final class AuthUser {
  const AuthUser({
    required this.id,
    required this.email,
    required this.username,
    required this.displayName,
    required this.status,
    this.avatarUrl,
    this.locale,
    this.timezone,
  });

  final String id;
  final String email;
  final String username;
  final String displayName;
  final String status;
  final String? avatarUrl;
  final String? locale;
  final String? timezone;
}
