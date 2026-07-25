import '../../../../core/network/api_response.dart';
import '../../../../core/network/api_transport.dart';
import '../../domain/entities/auth_session.dart';
import '../../domain/entities/auth_tokens.dart';
import '../../domain/entities/auth_user.dart';
import '../../domain/entities/device_identity.dart';
import '../../domain/entities/user_session.dart';

final class AuthRemoteDataSource {
  const AuthRemoteDataSource(this._api);

  final ApiTransport _api;

  Future<AuthSession> login({
    required String identifier,
    required String password,
    required DeviceIdentity device,
  }) async {
    final response = await _api.post<Object>(
      '/api/v1/auth/login',
      data: {
        'identifier': identifier,
        'password': password,
        'device_name': device.displayName,
      },
    );
    return _authSessionFromResponse(response.data);
  }

  Future<AuthSession> register({
    required String displayName,
    required String email,
    required String username,
    required String password,
    required DeviceIdentity device,
  }) async {
    final response = await _api.post<Object>(
      '/api/v1/auth/register',
      data: {
        'display_name': displayName,
        'email': email,
        'username': username,
        'password': password,
        'device_name': device.displayName,
      },
    );
    return _authSessionFromResponse(response.data);
  }

  Future<AuthSession> loginWithGoogle({
    required String credential,
    required DeviceIdentity device,
  }) async {
    final response = await _api.post<Object>(
      '/api/v1/auth/google',
      data: {'credential': credential, 'device_name': device.displayName},
    );
    return _authSessionFromResponse(response.data);
  }

  Future<AuthSession> refresh(String refreshToken) async {
    final response = await _api.post<Object>(
      '/api/v1/auth/refresh',
      data: {'refresh_token': refreshToken},
    );
    return _authSessionFromResponse(response.data, refreshToken: refreshToken);
  }

  Future<void> logout(String refreshToken) async {
    await _api.post<Object>(
      '/api/v1/auth/logout',
      data: {'refresh_token': refreshToken},
    );
  }

  Future<List<UserSession>> listSessions() async {
    final response = await _api.get<Object>('/api/v1/auth/sessions');
    return envelopeList(
      response.data,
      'sessions',
    ).map(_userSessionFromMap).toList(growable: false);
  }

  Future<void> revokeSession(String sessionId) async {
    await _api.delete<Object>('/api/v1/auth/sessions/$sessionId');
  }

  Future<void> revokeAllSessions() async {
    await _api.delete<Object>('/api/v1/auth/sessions');
  }
}

AuthSession _authSessionFromResponse(Object? value, {String? refreshToken}) {
  final map = envelopeItem(value, 'auth');
  final tokensMap = jsonMap(field(map, const ['tokens']));
  final source = tokensMap.isEmpty ? map : tokensMap;
  final expiresIn = intField(map, const ['expires_in'], fallback: 0);
  final accessExpiresAt =
      nullableDateTimeField(source, const [
        'access_token_expires_at',
        'accessTokenExpiresAt',
      ]) ??
      (expiresIn > 0
          ? DateTime.now().toUtc().add(Duration(seconds: expiresIn))
          : null);

  return AuthSession(
    tokens: AuthTokens(
      accessToken: stringField(source, const ['access_token', 'accessToken']),
      refreshToken: stringField(source, const [
        'refresh_token',
        'refreshToken',
      ], fallback: refreshToken ?? ''),
      tokenType: stringField(source, const [
        'token_type',
        'tokenType',
      ], fallback: 'Bearer'),
      accessTokenExpiresAt: accessExpiresAt,
      refreshTokenExpiresAt: nullableDateTimeField(source, const [
        'refresh_token_expires_at',
        'refreshTokenExpiresAt',
      ]),
    ),
    sessionId: stringField(map, const ['session_id', 'sessionId', 'id']),
    user: _authUserFromMapOrNull(jsonMap(field(map, const ['user']))),
    refreshUntil: nullableDateTimeField(map, const [
      'refresh_until',
      'refreshUntil',
    ]),
  );
}

AuthUser? _authUserFromMapOrNull(JsonMap map) {
  if (map.isEmpty) {
    return null;
  }
  return AuthUser(
    id: stringField(map, const ['id']),
    email: stringField(map, const ['email']),
    username: stringField(map, const ['username']),
    displayName: stringField(map, const [
      'display_name',
      'displayName',
      'name',
    ], fallback: stringField(map, const ['username', 'email'])),
    status: stringField(map, const ['status'], fallback: 'active'),
    avatarUrl: nullableStringField(map, const ['avatar_url', 'avatarUrl']),
    locale: nullableStringField(map, const ['locale']),
    timezone: nullableStringField(map, const ['timezone']),
  );
}

UserSession _userSessionFromMap(JsonMap map) {
  return UserSession(
    id: stringField(map, const ['id']),
    deviceName: nullableStringField(map, const ['device_name', 'deviceName']),
    ipAddress: nullableStringField(map, const ['ip_address', 'ipAddress']),
    userAgent: nullableStringField(map, const ['user_agent', 'userAgent']),
    expiresAt: dateTimeField(map, const [
      'expires_at',
      'expiresAt',
    ], fallback: DateTime.now().toUtc().add(const Duration(days: 1))),
    createdAt: dateTimeField(map, const ['created_at', 'createdAt']),
    revokedAt: nullableDateTimeField(map, const ['revoked_at', 'revokedAt']),
  );
}
