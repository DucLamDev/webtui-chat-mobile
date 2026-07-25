import '../../domain/entities/auth_session.dart';
import '../../domain/entities/auth_tokens.dart';
import '../../domain/entities/auth_user.dart';
import '../../domain/entities/user_session.dart';

final class AuthSessionDto {
  const AuthSessionDto({
    required this.tokens,
    required this.sessionId,
    this.user,
    this.refreshUntil,
  });

  final AuthUserDto? user;
  final AuthTokensDto tokens;
  final String sessionId;
  final DateTime? refreshUntil;

  factory AuthSessionDto.fromEnvelope(
    Object? envelope, {
    required bool userRequired,
  }) {
    final json = _unwrapDataMap(envelope);
    final userValue = json['user'];
    if (userRequired && userValue is! Map) {
      throw const FormatException('Auth response missing user payload.');
    }

    return AuthSessionDto(
      user: userValue is Map ? AuthUserDto.fromJson(_mapOf(userValue)) : null,
      tokens: AuthTokensDto.fromJson(_mapOf(json['tokens'])),
      sessionId: _string(json['session_id']),
      refreshUntil: _dateOrNull(json['refresh_until']),
    );
  }

  AuthSession toDomain() {
    return AuthSession(
      user: user?.toDomain(),
      tokens: tokens.toDomain(),
      sessionId: sessionId,
      refreshUntil: refreshUntil,
    );
  }
}

final class AuthUserDto {
  const AuthUserDto({
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

  factory AuthUserDto.fromJson(Map<String, dynamic> json) {
    return AuthUserDto(
      id: _string(json['id']),
      email: _string(json['email']),
      username: _string(json['username']),
      displayName: _string(json['display_name']),
      status: _string(json['status'], fallback: 'active'),
      avatarUrl: _nullableString(json['avatar_url']),
      locale: _nullableString(json['locale']),
      timezone: _nullableString(json['timezone']),
    );
  }

  AuthUser toDomain() {
    return AuthUser(
      id: id,
      email: email,
      username: username,
      displayName: displayName,
      status: status,
      avatarUrl: avatarUrl,
      locale: locale,
      timezone: timezone,
    );
  }
}

final class AuthTokensDto {
  const AuthTokensDto({
    required this.accessToken,
    required this.refreshToken,
    required this.tokenType,
    this.accessTokenExpiresAt,
    this.refreshTokenExpiresAt,
  });

  final String accessToken;
  final String refreshToken;
  final String tokenType;
  final DateTime? accessTokenExpiresAt;
  final DateTime? refreshTokenExpiresAt;

  factory AuthTokensDto.fromJson(Map<String, dynamic> json) {
    final accessToken = _string(json['access_token']);
    if (accessToken.isEmpty) {
      throw const FormatException('Auth response missing access token.');
    }

    return AuthTokensDto(
      accessToken: accessToken,
      refreshToken: _string(json['refresh_token']),
      tokenType: _string(json['token_type'], fallback: 'Bearer'),
      accessTokenExpiresAt: _dateOrNull(json['access_token_expires_at']),
      refreshTokenExpiresAt: _dateOrNull(json['refresh_token_expires_at']),
    );
  }

  AuthTokens toDomain() {
    return AuthTokens(
      accessToken: accessToken,
      refreshToken: refreshToken,
      tokenType: tokenType,
      accessTokenExpiresAt: accessTokenExpiresAt,
      refreshTokenExpiresAt: refreshTokenExpiresAt,
    );
  }
}

final class UserSessionDto {
  const UserSessionDto({
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

  factory UserSessionDto.fromJson(Map<String, dynamic> json) {
    return UserSessionDto(
      id: _string(json['id']),
      deviceName: _nullableString(json['device_name']),
      ipAddress: _nullableString(json['ip_address']),
      userAgent: _nullableString(json['user_agent']),
      expiresAt: _requiredDate(json['expires_at'], 'expires_at'),
      revokedAt: _dateOrNull(json['revoked_at']),
      createdAt: _requiredDate(json['created_at'], 'created_at'),
    );
  }

  UserSession toDomain() {
    return UserSession(
      id: id,
      deviceName: deviceName,
      ipAddress: ipAddress,
      userAgent: userAgent,
      expiresAt: expiresAt,
      revokedAt: revokedAt,
      createdAt: createdAt,
    );
  }
}

List<UserSessionDto> sessionsFromEnvelope(Object? envelope) {
  final json = _unwrapDataMap(envelope);
  final sessions = json['sessions'];
  if (sessions is! List) {
    throw const FormatException('Sessions response missing sessions list.');
  }
  return sessions
      .map((session) => UserSessionDto.fromJson(_mapOf(session)))
      .toList(growable: false);
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

DateTime? _dateOrNull(Object? value) {
  final text = value?.toString();
  if (text == null || text.isEmpty) {
    return null;
  }
  return DateTime.tryParse(text)?.toUtc();
}

DateTime _requiredDate(Object? value, String field) {
  final date = _dateOrNull(value);
  if (date == null) {
    throw FormatException('Invalid date field: $field.');
  }
  return date;
}
