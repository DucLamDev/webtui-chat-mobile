import 'dart:convert';

import 'package:webtui_chat/core/result/result.dart';
import 'package:webtui_chat/features/auth/domain/entities/auth_session.dart';
import 'package:webtui_chat/features/auth/domain/entities/auth_tokens.dart';
import 'package:webtui_chat/features/auth/domain/entities/user_session.dart';
import 'package:webtui_chat/features/auth/domain/repositories/auth_repository.dart';
import 'package:webtui_chat/features/auth/domain/repositories/auth_token_repository.dart';
import 'package:webtui_chat/features/auth/domain/repositories/session_state_repository.dart';

const testGuard = AuthTokenMutationGuard(
  instanceScopeId: 'scope-a',
  generation: 'generation-a',
);

/// JWT giả (không ký) chỉ để đọc claim `sid`.
String fakeJwt({String? sid}) {
  String part(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return '${part({'alg': 'HS256'})}.'
      '${part({'sub': 'user-1', 'sid': ?sid})}.signature';
}

final class MemoryTokenRepository implements AuthTokenRepository {
  MemoryTokenRepository({
    this.guard = testGuard,
    this.accessToken,
    this.refreshToken,
  });

  AuthTokenMutationGuard? guard;
  String? accessToken;
  String? refreshToken;
  int clearCalls = 0;

  @override
  Future<AuthTokenMutationGuard?> captureMutationGuard() async => guard;

  @override
  Future<bool> isMutationGuardCurrent(AuthTokenMutationGuard value) async =>
      guard == value;

  @override
  Future<String?> readAccessToken() async => accessToken;

  @override
  Future<String?> readRefreshToken() async => refreshToken;

  @override
  Future<String?> readAccessTokenIfCurrent(
    AuthTokenMutationGuard value,
  ) async => guard == value ? accessToken : null;

  @override
  Future<String?> readRefreshTokenIfCurrent(
    AuthTokenMutationGuard value,
  ) async => guard == value ? refreshToken : null;

  @override
  Future<void> saveTokens(AuthTokens tokens) async {
    accessToken = tokens.accessToken;
    refreshToken = tokens.refreshToken;
  }

  @override
  Future<bool> saveTokensIfCurrent(
    AuthTokens tokens,
    AuthTokenMutationGuard value, {
    AuthTokenPersistence? persistence,
  }) async {
    if (guard != value) return false;
    await saveTokens(tokens);
    return true;
  }

  @override
  Future<void> clearTokens() async {
    clearCalls++;
    accessToken = null;
    refreshToken = null;
  }

  @override
  Future<bool> clearTokensIfCurrent(AuthTokenMutationGuard value) async {
    if (guard != value) return false;
    await clearTokens();
    return true;
  }
}

final class RecordingSessionStateRepository implements SessionStateRepository {
  RecordingSessionStateRepository({this.guard = testGuard});

  AuthTokenMutationGuard? guard;
  final resetGuards = <AuthTokenMutationGuard>[];
  Future<void> Function()? beforeReset;

  @override
  Future<AuthTokenMutationGuard?> captureActiveSessionGuard() async => guard;

  @override
  Future<bool> hasAnySavedSession() async => false;

  @override
  Future<void> resetForLogout() async {}

  @override
  Future<bool> resetForLogoutIfCurrent(AuthTokenMutationGuard value) async {
    await beforeReset?.call();
    resetGuards.add(value);
    return guard == value;
  }

  @override
  Future<void> resetForServerSwitch() async {}
}

/// Kho auth giả: chỉ hiện thực các hàm test cần, còn lại ném lỗi.
final class ScriptedAuthRepository implements AuthRepository {
  ScriptedAuthRepository({this.refreshResult, this.revokeResult});

  Result<AuthSession>? refreshResult;
  Result<void>? revokeResult;
  final revokedSessionIds = <String>[];
  int refreshCalls = 0;

  @override
  Future<Result<AuthSession>> refresh(String refreshToken) async {
    refreshCalls++;
    return refreshResult!;
  }

  @override
  Future<Result<void>> revokeSession(String sessionId) async {
    revokedSessionIds.add(sessionId);
    return revokeResult ?? const Success(null);
  }

  @override
  Future<Result<List<UserSession>>> listSessions() async => const Success([]);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

AuthSession fakeAuthSession({
  String accessToken = 'access-new',
  String? approvalStatus,
}) {
  return AuthSession(
    tokens: AuthTokens(accessToken: accessToken, refreshToken: 'refresh-new'),
    sessionId: 'session-1',
    approvalStatus: approvalStatus,
  );
}
