final class UserSession {
  const UserSession({
    required this.id,
    required this.expiresAt,
    required this.createdAt,
    this.deviceName,
    this.ipAddress,
    this.userAgent,
    this.revokedAt,
  });

  final String id;
  final String? deviceName;
  final String? ipAddress;
  final String? userAgent;
  final DateTime expiresAt;
  final DateTime createdAt;
  final DateTime? revokedAt;

  bool get isActive => revokedAt == null && expiresAt.isAfter(DateTime.now());
}
