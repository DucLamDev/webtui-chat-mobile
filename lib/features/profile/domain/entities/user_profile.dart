final class UserProfile {
  const UserProfile({
    required this.id,
    required this.email,
    required this.username,
    required this.displayName,
    required this.status,
    required this.locale,
    required this.timezone,
    this.avatarUrl,
    this.phoneNumber,
  });

  final String id;
  final String email;
  final String username;
  final String displayName;
  final String status;
  final String locale;
  final String timezone;
  final String? avatarUrl;
  final String? phoneNumber;
}
