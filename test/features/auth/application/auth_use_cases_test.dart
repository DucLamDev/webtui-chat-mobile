import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/core/database/app_database.dart';
import 'package:webtui_chat/core/error/failure.dart';
import 'package:webtui_chat/core/result/result.dart';
import 'package:webtui_chat/core/security/instance_scope.dart';
import 'package:webtui_chat/core/security/secure_key_value_store.dart';
import 'package:webtui_chat/core/security/server_account_registry.dart';
import 'package:webtui_chat/features/auth/application/use_cases/login_use_case.dart';
import 'package:webtui_chat/features/auth/application/use_cases/logout_use_case.dart';
import 'package:webtui_chat/features/auth/application/use_cases/oidc_login_use_case.dart';
import 'package:webtui_chat/features/auth/application/use_cases/refresh_access_token_use_case.dart';
import 'package:webtui_chat/features/auth/application/use_cases/register_use_case.dart';
import 'package:webtui_chat/features/auth/data/repositories/local_session_state_repository.dart';
import 'package:webtui_chat/features/auth/data/repositories/secure_auth_token_repository.dart';
import 'package:webtui_chat/features/auth/domain/entities/auth_session.dart';
import 'package:webtui_chat/features/auth/domain/entities/auth_tokens.dart';
import 'package:webtui_chat/features/auth/domain/entities/auth_user.dart';
import 'package:webtui_chat/features/auth/domain/entities/device_identity.dart';
import 'package:webtui_chat/features/auth/domain/entities/legal_acceptance.dart';
import 'package:webtui_chat/features/auth/domain/entities/legal_document_versions.dart';
import 'package:webtui_chat/features/auth/domain/entities/oidc_provider.dart';
import 'package:webtui_chat/features/auth/domain/entities/user_session.dart';
import 'package:webtui_chat/features/auth/domain/repositories/auth_repository.dart';
import 'package:webtui_chat/features/auth/domain/repositories/auth_token_repository.dart';
import 'package:webtui_chat/features/auth/domain/repositories/device_identity_repository.dart';
import 'package:webtui_chat/features/auth/domain/repositories/session_state_repository.dart';

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
      expect(tokens.lastPersistence, AuthTokenPersistence.durable);
    });

    test('unchecked remember policy saves a process-session token', () async {
      final tokens = _FakeTokenRepository();
      final useCase = LoginUseCase(
        authRepository: _FakeAuthRepository(loginResult: Success(_session())),
        tokenRepository: tokens,
        deviceIdentityRepository: _FakeDeviceIdentityRepository(),
      );

      final result = await useCase.execute(
        const LoginCommand(
          identifier: 'lam',
          password: 'secret',
          remember: false,
        ),
      );

      expect(result, isA<Success<AuthSession>>());
      expect(tokens.lastPersistence, AuthTokenPersistence.sessionOnly);
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
          inviteToken: ' wti_invite-token ',
          termsAccepted: true,
          termsVersion: '2026-08-07',
          privacyAccepted: true,
          privacyVersion: '2026-08-07',
        ),
      );

      expect(result, isA<Success<AuthSession>>());
      expect(auth.registerCalls, 1);
      expect(auth.lastDisplayName, 'Lâm Đức');
      expect(auth.lastEmail, 'lam@example.com');
      expect(auth.lastUsername, 'lamduc');
      expect(auth.lastPassword, 'matkhau123');
      expect(auth.lastInviteToken, 'wti_invite-token');
      expect(auth.lastTermsAccepted, isTrue);
      expect(auth.lastTermsVersion, '2026-08-07');
      expect(auth.lastPrivacyAccepted, isTrue);
      expect(auth.lastPrivacyVersion, '2026-08-07');
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

    test('requires explicit legal acceptance before registration', () async {
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
          confirmPassword: 'matkhau123',
        ),
      );

      expect(result.failureOrNull?.code, 'REGISTER_LEGAL_ACCEPTANCE_REQUIRED');
      expect(auth.registerCalls, 0);
    });
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

  test('late A refresh success cannot overwrite server B tokens', () async {
    final completer = Completer<Result<AuthSession>>();
    final auth = _FakeAuthRepository(refreshHandler: (_) => completer.future);
    final tokens = _FakeTokenRepository(refreshToken: 'refresh-a')
      ..accessToken = 'access-a';
    final useCase = RefreshAccessTokenUseCase(
      authRepository: auth,
      tokenRepository: tokens,
    );

    final pending = useCase.execute();
    await Future<void>.delayed(Duration.zero);
    _switchFakeTokensToB(tokens);
    completer.complete(
      Success(_session(access: 'late-access-a', refresh: 'late-refresh-a')),
    );

    final result = await pending;
    expect(result.failureOrNull?.code, 'AUTH_INSTANCE_CHANGED');
    expect(tokens.accessToken, 'access-b');
    expect(tokens.refreshToken, 'refresh-b');
  });

  test('late A refresh 401 cannot clear server B tokens', () async {
    final completer = Completer<Result<AuthSession>>();
    final auth = _FakeAuthRepository(refreshHandler: (_) => completer.future);
    final tokens = _FakeTokenRepository(refreshToken: 'refresh-a')
      ..accessToken = 'access-a';
    final useCase = RefreshAccessTokenUseCase(
      authRepository: auth,
      tokenRepository: tokens,
    );

    final pending = useCase.execute();
    await Future<void>.delayed(Duration.zero);
    _switchFakeTokensToB(tokens);
    completer.complete(
      const FailureResult(
        Failure(
          kind: FailureKind.unauthorized,
          code: 'REFRESH_REJECTED',
          message: 'Expired',
        ),
      ),
    );

    await pending;
    expect(tokens.accessToken, 'access-b');
    expect(tokens.refreshToken, 'refresh-b');
  });

  test('late A login success cannot overwrite server B tokens', () async {
    final completer = Completer<Result<AuthSession>>();
    final auth = _FakeAuthRepository(loginFuture: completer.future);
    final tokens = _FakeTokenRepository()
      ..accessToken = 'access-a'
      ..refreshToken = 'refresh-a';
    final useCase = LoginUseCase(
      authRepository: auth,
      tokenRepository: tokens,
      deviceIdentityRepository: _FakeDeviceIdentityRepository(),
    );

    final pending = useCase.execute(
      const LoginCommand(identifier: 'user-a', password: 'password-a'),
    );
    await Future<void>.delayed(Duration.zero);
    _switchFakeTokensToB(tokens);
    completer.complete(
      Success(_session(access: 'late-access-a', refresh: 'late-refresh-a')),
    );

    expect((await pending).failureOrNull?.code, 'AUTH_STORAGE_FAILURE');
    expect(tokens.accessToken, 'access-b');
    expect(tokens.refreshToken, 'refresh-b');
  });

  test('late A registration cannot overwrite server B tokens', () async {
    final completer = Completer<Result<AuthSession>>();
    final auth = _FakeAuthRepository(registerFuture: completer.future);
    final tokens = _FakeTokenRepository();
    final useCase = RegisterUseCase(
      authRepository: auth,
      tokenRepository: tokens,
      deviceIdentityRepository: _FakeDeviceIdentityRepository(),
    );

    final pending = useCase.execute(
      const RegisterCommand(
        displayName: 'User A',
        email: 'a@example.com',
        username: 'user-a',
        password: 'password-a',
        confirmPassword: 'password-a',
        termsAccepted: true,
        termsVersion: '2026-08-07',
        privacyAccepted: true,
        privacyVersion: '2026-08-07',
      ),
    );
    await Future<void>.delayed(Duration.zero);
    _switchFakeTokensToB(tokens);
    completer.complete(
      Success(_session(access: 'late-access-a', refresh: 'late-refresh-a')),
    );

    expect((await pending).failureOrNull?.code, 'REGISTER_STORAGE_FAILURE');
    expect(tokens.accessToken, 'access-b');
    expect(tokens.refreshToken, 'refresh-b');
  });

  test('late A OIDC completion cannot overwrite server B tokens', () async {
    final completer = Completer<Result<AuthSession>>();
    final auth = _FakeAuthRepository(completeOidcFuture: completer.future);
    final tokens = _FakeTokenRepository();
    final useCase = OidcLoginUseCase(
      authRepository: auth,
      tokenRepository: tokens,
      deviceIdentityRepository: _FakeDeviceIdentityRepository(),
      loadExpectedServerOrigin: () => Uri.parse('https://server-a.example'),
    );

    expect(
      (await useCase.start(
        domain: 'server-a.example',
        providerId: 'provider-a',
      )).isSuccess,
      isTrue,
    );
    final returnTo = Uri.parse(auth.lastOidcReturnTo!);
    final pending = useCase.complete(
      code: 'code-a',
      domain: 'server-a.example',
      instanceScopeId: returnTo.queryParameters['instance_scope']!,
      attemptId: returnTo.queryParameters['attempt']!,
    );
    await Future<void>.delayed(Duration.zero);
    _switchFakeTokensToB(tokens);
    completer.complete(
      Success(_session(access: 'late-access-a', refresh: 'late-refresh-a')),
    );

    expect((await pending).failureOrNull?.code, 'OIDC_LOGIN_STORAGE_FAILURE');
    expect(tokens.accessToken, 'access-b');
    expect(tokens.refreshToken, 'refresh-b');
  });

  test(
    'OIDC callback from A is rejected after same-origin instance replacement',
    () async {
      final auth = _FakeAuthRepository();
      final tokens = _FakeTokenRepository();
      final useCase = OidcLoginUseCase(
        authRepository: auth,
        tokenRepository: tokens,
        deviceIdentityRepository: _FakeDeviceIdentityRepository(),
        loadExpectedServerOrigin: () => Uri.parse('https://shared.example'),
      );

      expect(
        (await useCase.start(
          domain: 'shared.example',
          providerId: 'provider-a',
        )).isSuccess,
        isTrue,
      );
      final returnTo = Uri.parse(auth.lastOidcReturnTo!);
      _switchFakeTokensToB(tokens);

      final result = await useCase.complete(
        code: 'one-time-code-from-a',
        domain: 'shared.example',
        instanceScopeId: returnTo.queryParameters['instance_scope']!,
        attemptId: returnTo.queryParameters['attempt']!,
      );

      expect(result.failureOrNull?.code, 'OIDC_LOGIN_STORAGE_FAILURE');
      expect(auth.completeOidcCalls, 0);
      expect(tokens.accessToken, 'access-b');
      expect(tokens.refreshToken, 'refresh-b');
    },
  );

  test('late A logout cannot clear server B token or workspace', () async {
    final completer = Completer<Result<void>>();
    final auth = _FakeAuthRepository(logoutFuture: completer.future);
    final tokens = _FakeTokenRepository(refreshToken: 'refresh-a')
      ..accessToken = 'access-a';
    final session = _FakeSessionStateRepository(
      currentGuard: tokens.mutationGuard,
      workspaceId: 'workspace-a',
    );
    final useCase = LogoutUseCase(
      authRepository: auth,
      tokenRepository: tokens,
      sessionStateRepository: session,
    );

    final pending = useCase.execute();
    await Future<void>.delayed(Duration.zero);
    _switchFakeTokensToB(tokens);
    session
      ..currentGuard = tokens.mutationGuard
      ..workspaceId = 'workspace-b';
    completer.complete(const Success(null));

    expect((await pending).isSuccess, isTrue);
    expect(tokens.accessToken, 'access-b');
    expect(tokens.refreshToken, 'refresh-b');
    expect(session.workspaceId, 'workspace-b');
    expect(session.guards, hasLength(1));
    expect(session.guards.single.instanceScopeId, 'scope-a');
  });

  test('tokens fail closed when live discovery validation is absent', () async {
    final store = _MemorySecureStore();
    const scopeId = 'scope-customer';
    await store.write(SecureStoreKey.activeInstanceScopeId, scopeId);
    await store.write(SecureStoreKey.sessionInstanceScopeId, scopeId);
    await store.write(SecureStoreKey.activeInstanceGeneration, 'generation-c');
    await store.write(SecureStoreKey.accessToken, 'customer-access');
    await store.write(SecureStoreKey.refreshToken, 'customer-refresh');
    final repository = SecureAuthTokenRepository(store);

    expect(await repository.readAccessToken(), isNull);
    expect(await repository.readRefreshToken(), isNull);
    expect(await repository.captureMutationGuard(), isNull);
    await expectLater(
      repository.saveTokens(_session().tokens),
      throwsStateError,
    );
  });

  test(
    'logout clears refresh token and workspace scoped local state',
    () async {
      final secureStore = _MemorySecureStore();
      final tokenRepository = SecureAuthTokenRepository(secureStore);
      final database = AppDatabase(createInMemoryDriftConnection());
      addTearDown(database.close);

      const serverUrl = 'https://chat.example';
      final instanceScope = InstanceScope(
        instanceId: '11111111-1111-4111-8111-111111111111',
        serverOrigin: Uri.parse(serverUrl),
      );
      final otherInstanceScope = InstanceScope(
        instanceId: '22222222-2222-4222-8222-222222222222',
        serverOrigin: Uri.parse('https://other.example'),
      );
      await secureStore.write(SecureStoreKey.instanceBaseUrl, serverUrl);
      await secureStore.write(
        SecureStoreKey.instanceId,
        instanceScope.instanceId,
      );
      await secureStore.write(
        SecureStoreKey.activeInstanceScopeId,
        instanceScope.storageId,
      );
      await secureStore.write(
        SecureStoreKey.liveDiscoveryValidatedScopeId,
        instanceScope.storageId,
      );
      await secureStore.write(
        SecureStoreKey.activeInstanceGeneration,
        'generation-a',
      );
      await tokenRepository.saveTokens(_session().tokens);
      final accountRegistry = SecureServerAccountRegistry(secureStore);
      await accountRegistry.rememberServer(
        instanceScope: instanceScope,
        wsBaseUrl: Uri.parse('wss://chat.example'),
        name: 'Chat example',
      );
      await accountRegistry.stashActiveSession();
      await secureStore.write(SecureStoreKey.activeWorkspaceId, 'workspace-1');
      await database.putKeyValue(
        scope: instanceScope.localScope('workspace:workspace-1'),
        key: 'cursor',
        value: 'cursor-1',
      );
      await database.putKeyValue(
        scope: instanceScope.localScope('session'),
        key: 'selected_tab',
        value: 'messages',
      );
      await database.putKeyValue(
        scope: otherInstanceScope.localScope('workspace:workspace-1'),
        key: 'cursor',
        value: 'other-server-cursor',
      );
      final cleanupEvents = <String>[];

      final useCase = LogoutUseCase(
        authRepository: _FakeAuthRepository(),
        tokenRepository: tokenRepository,
        sessionStateRepository: LocalSessionStateRepository(
          secureStore: secureStore,
          database: database,
          loadInstanceScope: () => instanceScope,
          clearNativeInstanceBinding: () async {
            cleanupEvents.add('binding');
          },
          terminateNativeCalls: (scope) async {
            expect(
              await secureStore.read(SecureStoreKey.sessionInstanceScopeId),
              isNull,
              reason: 'secure session must be invalid before native cleanup',
            );
            expect(scope, instanceScope);
            cleanupEvents.add('calls');
          },
          clearMessageNotifications: () async {
            cleanupEvents.add('messages');
          },
          clearScopedAttachmentFiles: (scope) async {
            expect(scope, instanceScope);
            cleanupEvents.add('files');
          },
          serverAccountRegistry: accountRegistry,
        ),
      );

      final result = await useCase.execute();

      expect(result.isSuccess, isTrue);
      expect(await tokenRepository.readAccessToken(), isNull);
      expect(await tokenRepository.readRefreshToken(), isNull);
      expect(await secureStore.read(SecureStoreKey.activeWorkspaceId), isNull);
      expect(cleanupEvents, ['binding', 'calls', 'messages', 'files']);
      expect(
        jsonDecode(
          (await secureStore.read(SecureStoreKey.serverAccounts))!,
        ).single,
        isNot(containsPair('refresh_token', anything)),
      );
      expect(
        await accountRegistry.activate(instanceScope),
        isFalse,
        reason: 'logout must not allow a cached refresh token to be restored',
      );
      expect(
        await database.readKeyValue(
          scope: instanceScope.localScope('workspace:workspace-1'),
          key: 'cursor',
        ),
        isNull,
      );
      expect(
        await database.readKeyValue(
          scope: instanceScope.localScope('session'),
          key: 'selected_tab',
        ),
        isNull,
      );
      expect(
        await database.readKeyValue(
          scope: otherInstanceScope.localScope('workspace:workspace-1'),
          key: 'cursor',
        ),
        'other-server-cursor',
        reason: 'logout from A must not delete B cache',
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
    this.loginFuture,
    this.registerFuture,
    this.completeOidcFuture,
    this.logoutFuture,
  });

  final Result<AuthSession>? loginResult;
  final Result<AuthSession>? registerResult;
  final Future<Result<AuthSession>> Function(String refreshToken)?
  refreshHandler;
  final Future<Result<AuthSession>>? loginFuture;
  final Future<Result<AuthSession>>? registerFuture;
  final Future<Result<AuthSession>>? completeOidcFuture;
  final Future<Result<void>>? logoutFuture;
  int loginCalls = 0;
  int registerCalls = 0;
  int refreshCalls = 0;
  int startOidcCalls = 0;
  int completeOidcCalls = 0;
  String? lastDisplayName;
  String? lastEmail;
  String? lastUsername;
  String? lastIdentifier;
  String? lastPassword;
  String? lastInviteToken;
  bool? lastTermsAccepted;
  String? lastTermsVersion;
  bool? lastPrivacyAccepted;
  String? lastPrivacyVersion;
  String? lastOidcReturnTo;

  @override
  Future<Result<LegalAcceptance>> loadLegalAcceptance({
    required String workspaceId,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<Result<LegalAcceptance>> acceptLegalDocuments({
    required String workspaceId,
    required String termsVersion,
    required String privacyVersion,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<Result<LegalDocumentVersions>> loadLegalDocumentVersions() async {
    return const Success(
      LegalDocumentVersions(
        termsVersion: '2026-08-07',
        privacyVersion: '2026-08-07',
      ),
    );
  }

  @override
  Future<Result<AuthSession>> login({
    required String identifier,
    required String password,
    required DeviceIdentity device,
  }) async {
    loginCalls += 1;
    lastIdentifier = identifier;
    lastPassword = password;
    if (loginFuture != null) return loginFuture!;
    return loginResult ?? Success(_session());
  }

  @override
  Future<Result<AuthSession>> register({
    required String displayName,
    required String email,
    required String username,
    required String password,
    String inviteToken = '',
    bool termsAccepted = false,
    String termsVersion = '',
    bool privacyAccepted = false,
    String privacyVersion = '',
    required DeviceIdentity device,
  }) async {
    registerCalls += 1;
    lastDisplayName = displayName;
    lastEmail = email;
    lastUsername = username;
    lastPassword = password;
    lastInviteToken = inviteToken;
    lastTermsAccepted = termsAccepted;
    lastTermsVersion = termsVersion;
    lastPrivacyAccepted = privacyAccepted;
    lastPrivacyVersion = privacyVersion;
    if (registerFuture != null) return registerFuture!;
    return registerResult ?? Success(_session());
  }

  @override
  Future<Result<List<OidcProvider>>> listOidcProviders(String domain) async {
    return const Success([]);
  }

  @override
  Future<Result<Uri>> startOidc({
    required String domain,
    required String providerId,
    required String returnTo,
    required DeviceIdentity device,
  }) async {
    startOidcCalls += 1;
    lastOidcReturnTo = returnTo;
    return Success(Uri.parse('https://identity.example/authorize'));
  }

  @override
  Future<Result<AuthSession>> completeOidc({
    required String code,
    required String domain,
    required DeviceIdentity device,
  }) {
    completeOidcCalls += 1;
    return completeOidcFuture ??
        Future<Result<AuthSession>>.value(Success(_session()));
  }

  @override
  Future<Result<AuthSession>> refresh(String refreshToken) {
    refreshCalls += 1;
    return refreshHandler?.call(refreshToken) ??
        Future<Result<AuthSession>>.value(Success(_session()));
  }

  @override
  Future<Result<void>> logout(String refreshToken) {
    return logoutFuture ?? Future<Result<void>>.value(const Success(null));
  }

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

final class _FakeTokenRepository implements AuthTokenRepository {
  _FakeTokenRepository({
    this.refreshToken,
    AuthTokenMutationGuard? mutationGuard,
  }) : mutationGuard =
           mutationGuard ??
           const AuthTokenMutationGuard(
             instanceScopeId: 'scope-a',
             generation: 'generation-a',
           );

  String? accessToken;
  String? refreshToken;
  AuthTokenMutationGuard? mutationGuard;
  AuthTokenPersistence? lastPersistence;

  @override
  Future<AuthTokenMutationGuard?> captureMutationGuard() async => mutationGuard;

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
  Future<bool> isMutationGuardCurrent(AuthTokenMutationGuard guard) async =>
      guard == mutationGuard;

  @override
  Future<String?> readAccessTokenIfCurrent(AuthTokenMutationGuard guard) async {
    return guard == mutationGuard ? accessToken : null;
  }

  @override
  Future<String?> readRefreshTokenIfCurrent(
    AuthTokenMutationGuard guard,
  ) async {
    return guard == mutationGuard ? refreshToken : null;
  }

  @override
  Future<void> saveTokens(AuthTokens tokens) async {
    accessToken = tokens.accessToken;
    refreshToken = tokens.refreshToken;
  }

  @override
  Future<bool> saveTokensIfCurrent(
    AuthTokens tokens,
    AuthTokenMutationGuard guard, {
    AuthTokenPersistence? persistence,
  }) async {
    if (guard != mutationGuard) return false;
    lastPersistence = persistence;
    await saveTokens(tokens);
    return true;
  }

  @override
  Future<bool> clearTokensIfCurrent(AuthTokenMutationGuard guard) async {
    if (guard != mutationGuard) return false;
    await clearTokens();
    return true;
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

final class _FakeSessionStateRepository implements SessionStateRepository {
  _FakeSessionStateRepository({
    required this.currentGuard,
    required this.workspaceId,
  });

  AuthTokenMutationGuard? currentGuard;
  String? workspaceId;
  final guards = <AuthTokenMutationGuard>[];

  @override
  Future<AuthTokenMutationGuard?> captureActiveSessionGuard() async =>
      currentGuard;

  @override
  Future<bool> hasAnySavedSession() async => workspaceId != null;

  @override
  Future<void> resetForLogout() async {
    workspaceId = null;
  }

  @override
  Future<bool> resetForLogoutIfCurrent(AuthTokenMutationGuard guard) async {
    guards.add(guard);
    if (guard != currentGuard) return false;
    workspaceId = null;
    return true;
  }

  @override
  Future<void> resetForServerSwitch() async {}
}

void _switchFakeTokensToB(_FakeTokenRepository tokens) {
  tokens
    ..mutationGuard = const AuthTokenMutationGuard(
      instanceScopeId: 'scope-b',
      generation: 'generation-b',
    )
    ..accessToken = 'access-b'
    ..refreshToken = 'refresh-b';
}

final class _MemorySecureStore implements SecureKeyValueStore {
  final _values = <SecureStoreKey, String>{};

  @override
  Future<void> clearSession() async {
    await Future.wait([
      delete(SecureStoreKey.accessToken),
      delete(SecureStoreKey.refreshToken),
      delete(SecureStoreKey.sessionInstanceScopeId),
      delete(SecureStoreKey.activeWorkspaceId),
      delete(SecureStoreKey.activeWorkspaceInstanceScopeId),
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
