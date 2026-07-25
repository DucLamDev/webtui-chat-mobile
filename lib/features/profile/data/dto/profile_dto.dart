import '../../domain/entities/user_profile.dart';

final class UserProfileDto {
  const UserProfileDto({
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

  factory UserProfileDto.fromEnvelope(Object? envelope) {
    return UserProfileDto.fromJson(_unwrapDataMap(envelope));
  }

  factory UserProfileDto.fromJson(Map<String, dynamic> json) {
    return UserProfileDto(
      id: _string(json['id']),
      email: _string(json['email']),
      username: _string(json['username']),
      displayName: _string(json['display_name']),
      status: _string(json['status'], fallback: 'active'),
      locale: _string(json['locale'], fallback: 'vi'),
      timezone: _string(json['timezone'], fallback: 'Asia/Ho_Chi_Minh'),
      avatarUrl: _nullableString(json['avatar_url']),
      phoneNumber: _nullableString(json['phone_number']),
    );
  }

  UserProfile toDomain() {
    return UserProfile(
      id: id,
      email: email,
      username: username,
      displayName: displayName,
      status: status,
      locale: locale,
      timezone: timezone,
      avatarUrl: avatarUrl,
      phoneNumber: phoneNumber,
    );
  }
}

final class UploadedFileDto {
  const UploadedFileDto({required this.id});

  final String id;

  factory UploadedFileDto.fromEnvelope(Object? envelope) {
    final json = _unwrapDataMap(envelope);
    return UploadedFileDto(id: _string(json['id']));
  }
}

Map<String, dynamic> _unwrapDataMap(Object? envelope) {
  final root = _mapOf(envelope);
  final data = root.containsKey('data') ? root['data'] : root;
  return _mapOf(data);
}

Map<String, dynamic> _mapOf(Object? value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return Map<String, dynamic>.from(value);
  }
  throw const FormatException('Expected JSON object.');
}

String _string(Object? value, {String fallback = ''}) {
  return value?.toString() ?? fallback;
}

String? _nullableString(Object? value) {
  final text = value?.toString().trim();
  if (text == null || text.isEmpty) {
    return null;
  }
  return text;
}
