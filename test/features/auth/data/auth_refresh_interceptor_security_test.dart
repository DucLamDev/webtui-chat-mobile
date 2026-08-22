import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/core/security/instance_scope.dart';
import 'package:webtui_chat/features/auth/application/use_cases/refresh_access_token_use_case.dart';
import 'package:webtui_chat/features/auth/data/network/auth_refresh_interceptor.dart';
import 'package:webtui_chat/features/auth/domain/entities/auth_tokens.dart';
import 'package:webtui_chat/features/auth/domain/repositories/auth_repository.dart';
import 'package:webtui_chat/features/auth/domain/repositories/auth_token_repository.dart';

void main() {
  final instanceA = InstanceScope(
    instanceId: '11111111-1111-4111-8111-111111111111',
    serverOrigin: Uri.parse('https://server-a.example'),
  );

  test('Bearer is attached only to the exact active instance origin', () async {
    final guard = AuthTokenMutationGuard(
      instanceScopeId: instanceA.storageId,
      generation: 'generation-a',
    );
    final tokens = _TokenRepository(guard: guard, accessToken: 'token-a');
    final adapter = _RecordingAdapter();
    final dio = Dio(
      BaseOptions(baseUrl: instanceA.origin.toString(), followRedirects: false),
    )..httpClientAdapter = adapter;
    dio.interceptors.add(
      AuthRefreshInterceptor(
        dio: dio,
        expectedInstanceScope: instanceA,
        tokenRepository: tokens,
        refreshAccessTokenUseCase: RefreshAccessTokenUseCase(
          authRepository: _NeverAuthRepository(),
          tokenRepository: tokens,
        ),
      ),
    );

    await dio.get<void>(
      '/api/v1/profile',
      options: Options(headers: {'Authorization': 'Bearer stale-a'}),
    );
    await dio.getUri<void>(
      Uri.parse('https://evil.example/file'),
      options: Options(headers: {'Authorization': 'Bearer caller-token'}),
    );

    expect(adapter.requests[0].headers['Authorization'], 'Bearer token-a');
    expect(
      adapter.requests[1].headers.keys.any(
        (key) => key.toLowerCase() == 'authorization',
      ),
      isFalse,
    );
    dio.close(force: true);
  });

  test('old server A Dio never attaches active server B token', () async {
    final guardB = const AuthTokenMutationGuard(
      instanceScopeId: 'scope-b',
      generation: 'generation-b',
    );
    final tokens = _TokenRepository(guard: guardB, accessToken: 'token-b');
    final adapter = _RecordingAdapter();
    final dio = Dio(
      BaseOptions(baseUrl: instanceA.origin.toString(), followRedirects: false),
    )..httpClientAdapter = adapter;
    dio.interceptors.add(
      AuthRefreshInterceptor(
        dio: dio,
        expectedInstanceScope: instanceA,
        tokenRepository: tokens,
        refreshAccessTokenUseCase: RefreshAccessTokenUseCase(
          authRepository: _NeverAuthRepository(),
          tokenRepository: tokens,
        ),
      ),
    );

    await dio.get<void>(
      '/api/v1/profile',
      options: Options(headers: {'Authorization': 'Bearer stale-a'}),
    );

    expect(
      adapter.requests.single.headers.keys.any(
        (key) => key.toLowerCase() == 'authorization',
      ),
      isFalse,
    );
    dio.close(force: true);
  });
}

final class _RecordingAdapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(jsonEncode(const <String, Object?>{}), 200);
  }

  @override
  void close({bool force = false}) {}
}

final class _TokenRepository implements AuthTokenRepository {
  _TokenRepository({required this.guard, required this.accessToken});

  AuthTokenMutationGuard? guard;
  String? accessToken;

  @override
  Future<AuthTokenMutationGuard?> captureMutationGuard() async => guard;

  @override
  Future<void> clearTokens() async => accessToken = null;

  @override
  Future<bool> clearTokensIfCurrent(AuthTokenMutationGuard guard) async {
    if (guard != this.guard) return false;
    accessToken = null;
    return true;
  }

  @override
  Future<bool> isMutationGuardCurrent(AuthTokenMutationGuard guard) async =>
      guard == this.guard;

  @override
  Future<String?> readAccessToken() async => accessToken;

  @override
  Future<String?> readAccessTokenIfCurrent(
    AuthTokenMutationGuard guard,
  ) async => guard == this.guard ? accessToken : null;

  @override
  Future<String?> readRefreshToken() async => null;

  @override
  Future<String?> readRefreshTokenIfCurrent(
    AuthTokenMutationGuard guard,
  ) async => null;

  @override
  Future<void> saveTokens(AuthTokens tokens) async {
    accessToken = tokens.accessToken;
  }

  @override
  Future<bool> saveTokensIfCurrent(
    AuthTokens tokens,
    AuthTokenMutationGuard guard, {
    AuthTokenPersistence? persistence,
  }) async {
    if (guard != this.guard) return false;
    accessToken = tokens.accessToken;
    return true;
  }
}

final class _NeverAuthRepository implements AuthRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw StateError('Refresh must not run in this test.');
  }
}
