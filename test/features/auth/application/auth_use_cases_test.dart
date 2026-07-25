import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/core/database/app_database.dart';
import 'package:webtui_chat/core/error/failure.dart';
import 'package:webtui_chat/core/result/result.dart';
import 'package:webtui_chat/core/security/secure_key_value_store.dart';
import 'package:webtui_chat/features/auth/application/use_cases/google_login_use_case.dart';
import 'package:webtui_chat/features/auth/application/use_cases/login_use_case.dart';
import 'package:webtui_chat/features/auth/application/use_cases/logout_use_case.dart';
import 'package:webtui_chat/features/auth/application/use_cases/refresh_access_token_use_case.dart';
import 'package:webtui_chat/features/auth/application/use_cases/register_use_case.dart';
import 'package:webtui_chat/features/auth/data/repositories/local_session_state_repository.dart';
import 'package:webtui_chat/features/auth/data/repositories/secure_auth_token_repository.dart';
import 'package:webtui_chat/features/auth/domain/entities/auth_session.dart';
import 'package:webtui_chat/features/auth/domain/entities/auth_tokens.dart';
import 'package:webtui_chat/features/auth/domain/entities/auth_user.dart';
import 'package:webtui_chat/features/auth/domain/entities/device_identity.dart';
import 'package:webtui_chat/features/auth/domain/entities/user_session.dart';
import 'package:webtui_chat/features/auth/domain/repositories/auth_repository.dart';
import 'package:webtui_chat/features/auth/domain/repositories/auth_token_repository.dart';
import 'package:webtui_chat/features/auth/domain/repositories/device_identity_repository.dart';
import 'package:webtui_chat/features/auth/domain/repositories/google_identity_provider.dart';

void main() {
  group('LoginUseCase', () {
    test('logs in with email or username and saves token policy', () async {
      final auth = _FakeAuthRepository(loginResult: Success(_session()));
      final tokens = _FakeTokenRepository();
      final device = _FakeDeviceIdentityRepository();
      final useCase = LoginUseCase(
        authRepository: auth,
        tokenRepository: tokens,
        deviceIdentityRepository: device,
      );

      final result = await useCase.execute(
        const LoginCommand(identifier: ' lam ', password: ' secret '),
      );

      expect(result, isA<Success<AuthSession>>());
      expect(auth.loginCalls, 1);
      expect(auth.lastIdentifier, 'lam');
      expect(auth.lastPassword, 'secret');
      expect(tokens.accessToken, 'access-token');
      expect(tokens.refreshToken, 'refresh-token');
    });

    test('returns validation failure before calling repository', () async {
      final auth = _FakeAuthRepository(loginResult: Success(_session()));
      final useCase = LoginUseCase(
        authRepository: auth,
        tokenRepository: _FakeTokenRepository(),
        deviceIdentityRepository: _FakeDeviceIdentityRepository(),
      );

      final result = await useCase.execute(
        const LoginCommand(identifier: '', password: ''),
      );

      expect(result.failureOrNull?.kind, FailureKind.validation);
      expect(auth.loginCalls, 0);
    });
  });

  group('RegisterUseCase', () {
    test('registers through backend repository and saves tokens', () async {
      final auth = _FakeAuthRepository(registerResult: Success(_session()));
      final tokens = _FakeTokenRepository();
      final useCase = RegisterUseCase(
        authRepository: auth,
        tokenRepository: tokens,
        deviceIdentityRepository: _FakeDeviceIdentityRepository(),
      );

      final result = await useCase.execute(
        const RegisterCommand(
          displayName: ' Lâm Đức ',
          email: ' lam@example.com ',
          username: ' lamduc ',
          password: ' matkhau123 ',
          confirmPassword: ' matkhau123 ',
        ),
      );

      expect(result, isA<Success<AuthSession>>());
      expect(auth.registerCalls, 1);
      expect(auth.lastDisplayName, 'Lâm Đức');
      expect(auth.lastEmail, 'lam@example.com');
      expect(auth.lastUsername, 'lamduc');
      expect(auth.lastPassword, 'matkhau123');
      expect(tokens.accessToken, 'access-token');
      expect(tokens.refreshToken, 'refresh-token');
    });

    test('validates password confirmation before calling repository', () async {
      final auth = _FakeAuthRepository();
      final useCase = RegisterUseCase(
        authRepository: auth,
        tokenRepository: _FakeTokenRepository(),
        deviceIdentityRepository: _FakeDeviceIdentityRepository(),
      );

      final result = await useCase.execute(
        const RegisterCommand(
          displayName: 'Lâm Đức',
          email: 'lam@example.com',
          username: 'lamduc',
          password: 'matkhau123',
          confirmPassword: 'matkhau456',
        ),
      );

      expect(result.failureOrNull?.kind, FailureKind.validation);
      expect(auth.registerCalls, 0);
    });
  });

  test('GoogleLoginUseCase exchanges an ID token with the backend', () async {
    final auth = _FakeAuthRepository();
    final tokens = _FakeTokenRepository();
    final useCase = GoogleLoginUseCase(
      identityProvider: const _FakeGoogleIdentityProvider(),
      authRepository: auth,
      tokenRepository: tokens,
      deviceIdentityRepository: _FakeDeviceIdentityRepository(),
    );

    final result = await useCase.execute();

    expect(result, isA<Success<AuthSession>>());
    expect(auth.googleLoginCalls, 1);
    expect(auth.lastGoogleCredential, 'google-id-token');
    expect(tokens.accessToken, 'access-token');
  });

  test('refresh queue fans out concurrent 401 refreshes to one call', () async {
    final completer = Completer<Result<AuthSession>>();
    final auth = _FakeAuthRepository(
      refreshHandler: (_) {
        return completer.future;
      },
    );
    final tokens = _FakeTokenRepository(refreshToken: 'old-refresh');
    final useCase = RefreshAccessTokenUseCase(
      authRepository: auth,
      tokenRepository: tokens,
    );

    final futures = [useCase.execute(), useCase.execute(), useCase.execute()];
    await Future<void>.delayed(Duration.zero);

    expect(auth.refreshCalls, 1);
    completer.complete(
      Success(_session(access: 'new-access', refresh: 'new-refresh')),
    );

    final results = await Future.wait(futures);
    expect(results.every((result) => result.isSuccess), isTrue);
    expect(tokens.accessToken, 'new-access');
    expect(tokens.refreshToken, 'new-refresh');
  });

  test(
    'logout clears refresh token and workspace scoped local state',
    () async {
      final secureStore = _MemorySecureStore();
      final tokenRepository = SecureAuthTokenRepository(secureStore);
      final database = AppDatabase(createInMemoryDriftConnection());
      addTearDown(database.close);

      await tokenRepository.saveTokens(_session().tokens);
      await secureStore.write(SecureStoreKey.activeWorkspaceId, 'workspace-1');
      await database.putKeyValue(
        scope: 'workspace:workspace-1',
        key: 'cursor',
        value: 'cursor-1',
      );
      await database.putKeyValue(
        scope: 'session',
        key: 'selected_tab',
        value: 'messages',
      );

      final useCase = LogoutUseCase(
        authRepository: _FakeAuthRepository(),
        tokenRepository: tokenRepository,
        sessionStateRepository: LocalSessionStateRepository(
          secureStore: secureStore,
          database: database,
        ),
      );

      final result = await useCase.execute();

      expect(result.isSuccess, isTrue);
      expect(await tokenRepository.readAccessToken(), isNull);
      expect(await tokenRepository.readRefreshToken(), isNull);
      expect(await secureStore.read(SecureStoreKey.activeWorkspaceId), isNull);
      expect(
        await database.readKeyValue(
          scope: 'workspace:workspace-1',
          key: 'cursor',
        ),
        isNull,
      );
      expect(
        await database.readKeyValue(scope: 'session', key: 'selected_tab'),
        isNull,
      );
    },
  );
}

AuthSession _session({
  String access = 'access-token',
  String refresh = 'refresh-token',
}) {
  return AuthSession(
    user: const AuthUser(
      id: 'user-1',
      email: 'lam@example.com',
      username: 'lam',
      displayName: 'Lâm',
      status: 'active',
    ),
    tokens: AuthTokens(accessToken: access, refreshToken: refresh),
    sessionId: 'session-1',
  );
}

final class _FakeAuthRepository implements AuthRepository {
  _FakeAuthRepository({
    this.loginResult,
    this.registerResult,
    this.refreshHandler,
  });

  final Result<AuthSession>? loginResult;
  final Result<AuthSession>? registerResult;
  final Future<Result<AuthSession>> Function(String refreshToken)?
  refreshHandler;
  int loginCalls = 0;
  int registerCalls = 0;
  int refreshCalls = 0;
  int googleLoginCalls = 0;
  String? lastDisplayName;
  String? lastEmail;
  String? lastUsername;
  String? lastIdentifier;
  String? lastPassword;
  String? lastGoogleCredential;

  @override
  Future<Result<AuthSession>> login({
    required String identifier,
    required String password,
    required DeviceIdentity device,
  }) async {
    loginCalls += 1;
    lastIdentifier = identifier;
    lastPassword = password;
    return loginResult ?? Success(_session());
  }

  @override
  Future<Result<AuthSession>> register({
    required String displayName,
    required String email,
    required String username,
    required String password,
    required DeviceIdentity device,
  }) async {
    registerCalls += 1;
    lastDisplayName = displayName;
    lastEmail = email;
    lastUsername = username;
    lastPassword = password;
    return registerResult ?? Success(_session());
  }

  @override
  Future<Result<AuthSession>> loginWithGoogle({
    required String credential,
    required DeviceIdentity device,
  }) async {
    googleLoginCalls += 1;
    lastGoogleCredential = credential;
    return Success(_session());
  }

  @override
  Future<Result<AuthSession>> refresh(String refreshToken) {
    refreshCalls += 1;
    return refreshHandler?.call(refreshToken) ??
        Future<Result<AuthSession>>.value(Success(_session()));
  }

  @override
  Future<Result<void>> logout(String refreshToken) async => const Success(null);

  @override
  Future<Result<List<UserSession>>> listSessions() {
    throw UnimplementedError();
  }

  @override
  Future<Result<void>> revokeAllSessions() {
    throw UnimplementedError();
  }

  @override
  Future<Result<void>> revokeSession(String sessionId) {
    throw UnimplementedError();
  }
}

final class _FakeGoogleIdentityProvider implements GoogleIdentityProvider {
  const _FakeGoogleIdentityProvider();

  @override
  Future<Result<String>> authenticate() async {
    return const Success('google-id-token');
  }
}

final class _FakeTokenRepository implements AuthTokenRepository {
  _FakeTokenRepository({this.refreshToken});

  String? accessToken;
  String? refreshToken;

  @override
  Future<void> clearTokens() async {
    accessToken = null;
    refreshToken = null;
  }

  @override
  Future<String?> readAccessToken() async => accessToken;

  @override
  Future<String?> readRefreshToken() async => refreshToken;

  @override
  Future<void> saveTokens(AuthTokens tokens) async {
    accessToken = tokens.accessToken;
    refreshToken = tokens.refreshToken;
  }
}

final class _FakeDeviceIdentityRepository implements DeviceIdentityRepository {
  @override
  Future<DeviceIdentity> currentDevice() async {
    return const DeviceIdentity(
      id: 'device-1',
      platform: 'Android',
      displayName: 'WebTui Android',
    );
  }
}

final class _MemorySecureStore implements SecureKeyValueStore {
  final _values = <SecureStoreKey, String>{};

  @override
  Future<void> clearSession() async {
    await Future.wait([
      delete(SecureStoreKey.refreshToken),
      delete(SecureStoreKey.activeWorkspaceId),
    ]);
  }

  @override
  Future<void> delete(SecureStoreKey key) async {
    _values.remove(key);
  }

  @override
  Future<String?> read(SecureStoreKey key) async {
    return _values[key];
  }

  @override
  Future<void> write(SecureStoreKey key, String value) async {
    _values[key] = value;
  }
}
