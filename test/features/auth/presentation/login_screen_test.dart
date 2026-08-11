import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/app/flavor/app_config.dart';
import 'package:webtui_chat/app/flavor/app_flavor.dart';
import 'package:webtui_chat/app/providers/foundation_providers.dart';
import 'package:webtui_chat/core/error/failure.dart';
import 'package:webtui_chat/core/network/self_hosted_server_discovery.dart';
import 'package:webtui_chat/core/result/result.dart';
import 'package:webtui_chat/features/auth/application/use_cases/login_use_case.dart';
import 'package:webtui_chat/features/auth/application/use_cases/register_use_case.dart';
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
import 'package:webtui_chat/features/auth/presentation/controllers/login_controller.dart';
import 'package:webtui_chat/features/auth/presentation/screens/login_screen.dart';

void main() {
  testWidgets('shows login loading state', (tester) async {
    final completer = Completer<Result<AuthSession>>();
    await _pumpLogin(
      tester,
      authRepository: _WidgetAuthRepository(
        loginHandler: () => completer.future,
      ),
    );

    await _fillAndSubmit(tester);

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Đang đăng nhập...'), findsOneWidget);

    completer.complete(Success(_session()));
    await tester.pumpAndSettle();
  });

  testWidgets('shows login error state', (tester) async {
    await _pumpLogin(
      tester,
      authRepository: _WidgetAuthRepository(
        loginHandler: () async {
          return const FailureResult(
            Failure(
              kind: FailureKind.unauthorized,
              message: 'Email, username hoặc mật khẩu không đúng.',
            ),
          );
        },
      ),
    );

    await _fillAndSubmit(tester);
    await tester.pumpAndSettle();

    expect(
      find.text('Email, username hoặc mật khẩu không đúng.'),
      findsOneWidget,
    );
  });

  testWidgets('shows success state and notifies caller', (tester) async {
    var successCount = 0;
    await _pumpLogin(
      tester,
      authRepository: _WidgetAuthRepository(
        loginHandler: () async => Success(_session()),
      ),
      onLoginSuccess: () => successCount += 1,
    );

    await _fillAndSubmit(tester);
    await tester.pumpAndSettle();

    expect(find.text('Đăng nhập thành công.'), findsOneWidget);
    expect(successCount, 1);
  });

  testWidgets('switches to register form', (tester) async {
    await _pumpLogin(tester, authRepository: _WidgetAuthRepository());
    await _connectServer(tester);

    final registerLink = find.text('Đăng ký ngay');
    await tester.ensureVisible(registerLink);
    await tester.pumpAndSettle();
    await tester.tap(registerLink);
    await tester.pumpAndSettle();

    expect(find.text('Tạo tài khoản mới'), findsOneWidget);
    expect(find.text('Xác nhận mật khẩu'), findsOneWidget);
    expect(find.byKey(const Key('register_domain_field')), findsNothing);
    expect(find.text('Đổi máy chủ'), findsOneWidget);
    expect(
      find.byKey(const Key('register_invite_token_field')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('register_submit_button')), findsOneWidget);
  });

  testWidgets('registration requires one explicit acceptance for both links', (
    tester,
  ) async {
    await _pumpLogin(tester, authRepository: _WidgetAuthRepository());
    await _connectServer(tester);
    final registerLink = find.text('Đăng ký ngay');
    await tester.ensureVisible(registerLink);
    await tester.tap(registerLink);
    await tester.pumpAndSettle();

    final checkbox = find.byKey(
      const Key('register_legal_acceptance_checkbox'),
    );
    await tester.ensureVisible(checkbox);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('register_terms_link')), findsOneWidget);
    expect(find.byKey(const Key('register_privacy_link')), findsOneWidget);
    expect(tester.widget<Checkbox>(checkbox).value, isFalse);

    await tester.tap(checkbox);
    await tester.pump();
    expect(tester.widget<Checkbox>(checkbox).value, isTrue);
  });

  testWidgets('registration is fail-closed when legal discovery fails', (
    tester,
  ) async {
    var attempts = 0;
    await _pumpLogin(
      tester,
      authRepository: _WidgetAuthRepository(
        legalHandler: () async {
          attempts++;
          if (attempts == 1) {
            return const FailureResult(
              Failure(
                kind: FailureKind.network,
                message: 'Legal documents are unavailable.',
              ),
            );
          }
          return const Success(
            LegalDocumentVersions(
              termsVersion: '2026-08-07',
              privacyVersion: '2026-08-07',
            ),
          );
        },
      ),
    );
    await _connectServer(tester);
    final registerLink = find.text('Đăng ký ngay');
    await tester.ensureVisible(registerLink);
    await tester.tap(registerLink);
    await tester.pumpAndSettle();

    final checkbox = find.byKey(
      const Key('register_legal_acceptance_checkbox'),
    );
    expect(
      find.byKey(const Key('register_legal_versions_error')),
      findsOneWidget,
    );
    expect(tester.widget<Checkbox>(checkbox).onChanged, isNull);

    final retry = find.byKey(const Key('register_legal_versions_retry'));
    await tester.ensureVisible(retry);
    await tester.tap(retry);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('register_legal_versions_ready')),
      findsOneWidget,
    );
    expect(tester.widget<Checkbox>(checkbox).onChanged, isNotNull);
    expect(attempts, 2);
  });

  testWidgets('restores the selected server and organization branding', (
    tester,
  ) async {
    await _pumpLogin(
      tester,
      authRepository: const _WidgetAuthRepository(),
      initialDiscovery: SelfHostedServerDiscovery(
        instanceId: '11111111-1111-4111-8111-111111111111',
        discoveryVersion: '1',
        domain: 'localhost',
        name: 'Company Chat',
        apiBaseUri: Uri.parse('http://localhost:8080'),
        wsBaseUri: Uri.parse('ws://localhost:8080/ws'),
        registrationMode: 'open',
        appVersion: 'test',
        apiContractVersion: 1,
        serverVersion: 'test',
        minimumSupportedMobileVersion: '1.0.0',
        capabilities: const SelfHostedCapabilities(
          moderation: true,
          reporting: true,
          blocking: true,
          accountDeletion: true,
          legalAcceptance: true,
        ),
        logoUrl: 'https://cdn.example.com/company.png',
      ),
    );

    expect(find.byKey(const Key('server_domain_field')), findsNothing);
    expect(find.byKey(const Key('login_identifier_field')), findsOneWidget);
    expect(find.textContaining('Company Chat'), findsOneWidget);
  });

  testWidgets('live-bound durable session resumes exactly once', (
    tester,
  ) async {
    var successCount = 0;
    await _pumpLogin(
      tester,
      authRepository: const _WidgetAuthRepository(),
      initialDiscovery: _discovery(),
      tokenRepository: _WidgetTokenRepository(accessToken: 'stored-access'),
      onLoginSuccess: () => successCount += 1,
    );

    await tester.pumpAndSettle();

    expect(successCount, 1);
  });

  testWidgets('stale generation never resumes a stored session', (
    tester,
  ) async {
    var successCount = 0;
    await _pumpLogin(
      tester,
      authRepository: const _WidgetAuthRepository(),
      initialDiscovery: _discovery(),
      tokenRepository: _WidgetTokenRepository(
        accessToken: 'stale-access',
        current: false,
      ),
      onLoginSuccess: () => successCount += 1,
    );

    await tester.pumpAndSettle();

    expect(successCount, 0);
    expect(find.byKey(const Key('login_identifier_field')), findsOneWidget);
  });

  testWidgets('password recovery explains the self-hosted admin flow', (
    tester,
  ) async {
    await _pumpLogin(tester, authRepository: const _WidgetAuthRepository());
    await _connectServer(tester);

    final recoveryButton = find.byKey(const Key('forgot_password_button'));
    await tester.ensureVisible(recoveryButton);
    await tester.pumpAndSettle();
    await tester.tap(recoveryButton);
    await tester.pumpAndSettle();

    expect(find.text('Khôi phục mật khẩu'), findsOneWidget);
    expect(find.textContaining('liên hệ quản trị viên'), findsOneWidget);
  });
}

Future<void> _pumpLogin(
  WidgetTester tester, {
  required AuthRepository authRepository,
  VoidCallback? onLoginSuccess,
  SelfHostedServerDiscovery? initialDiscovery,
  AuthTokenRepository? tokenRepository,
}) async {
  final tokens = tokenRepository ?? _WidgetTokenRepository();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(authRepository),
        appConfigProvider.overrideWithValue(
          AppConfig(
            flavor: AppFlavor.dev,
            apiBaseUri: Uri.parse('http://localhost:8080'),
            wsBaseUri: Uri.parse('ws://localhost:8080/ws'),
            termsUrl: 'https://example.com/terms',
            privacyPolicyUrl: 'https://example.com/privacy',
          ),
        ),
        if (initialDiscovery != null)
          initialServerDiscoveryProvider.overrideWithValue(initialDiscovery),
        authTokenRepositoryProvider.overrideWithValue(tokens),
        serverConnectorProvider.overrideWithValue(
          (_) async => SelfHostedServerDiscovery(
            instanceId: '11111111-1111-4111-8111-111111111111',
            discoveryVersion: '1',
            domain: 'localhost',
            name: 'Company Chat',
            apiBaseUri: Uri.parse('http://localhost:8080'),
            wsBaseUri: Uri.parse('ws://localhost:8080/ws'),
            registrationMode: 'open',
            appVersion: 'test',
            apiContractVersion: 1,
            serverVersion: 'test',
            minimumSupportedMobileVersion: '1.0.0',
            capabilities: const SelfHostedCapabilities(
              moderation: true,
              reporting: true,
              blocking: true,
              accountDeletion: true,
              legalAcceptance: true,
            ),
          ),
        ),
        loginUseCaseProvider.overrideWithValue(
          LoginUseCase(
            authRepository: authRepository,
            tokenRepository: tokens,
            deviceIdentityRepository: _WidgetDeviceIdentityRepository(),
          ),
        ),
        registerUseCaseProvider.overrideWithValue(
          RegisterUseCase(
            authRepository: authRepository,
            tokenRepository: tokens,
            deviceIdentityRepository: _WidgetDeviceIdentityRepository(),
          ),
        ),
      ],
      child: MaterialApp(home: LoginScreen(onLoginSuccess: onLoginSuccess)),
    ),
  );
}

SelfHostedServerDiscovery _discovery() {
  return SelfHostedServerDiscovery(
    instanceId: '11111111-1111-4111-8111-111111111111',
    discoveryVersion: '1',
    domain: 'localhost',
    name: 'Company Chat',
    apiBaseUri: Uri.parse('http://localhost:8080'),
    wsBaseUri: Uri.parse('ws://localhost:8080/ws'),
    registrationMode: 'open',
    appVersion: 'test',
    apiContractVersion: 1,
    serverVersion: 'test',
    minimumSupportedMobileVersion: '1.0.0',
    capabilities: const SelfHostedCapabilities(
      moderation: true,
      reporting: true,
      blocking: true,
      accountDeletion: true,
      legalAcceptance: true,
    ),
  );
}

Future<void> _fillAndSubmit(WidgetTester tester) async {
  await _connectServer(tester);
  await tester.enterText(
    find.byKey(const Key('login_identifier_field')),
    'lam@example.com',
  );
  await tester.enterText(
    find.byKey(const Key('login_password_field')),
    'matkhau123',
  );
  await tester.pump();
  await tester.tap(find.byKey(const Key('login_submit_button')));
  await tester.pump();
}

Future<void> _connectServer(WidgetTester tester) async {
  await tester.enterText(
    find.byKey(const Key('server_domain_field')),
    'http://localhost:8080',
  );
  await tester.pump();
  await tester.tap(find.byKey(const Key('server_connect_button')));
  await tester.pumpAndSettle();
}

AuthSession _session() {
  return const AuthSession(
    user: AuthUser(
      id: 'user-1',
      email: 'lam@example.com',
      username: 'lam',
      displayName: 'Lâm',
      status: 'active',
    ),
    tokens: AuthTokens(
      accessToken: 'access-token',
      refreshToken: 'refresh-token',
    ),
    sessionId: 'session-1',
  );
}

final class _WidgetAuthRepository implements AuthRepository {
  const _WidgetAuthRepository({this.loginHandler, this.legalHandler});

  final Future<Result<AuthSession>> Function()? loginHandler;
  final Future<Result<LegalDocumentVersions>> Function()? legalHandler;

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
    return legalHandler?.call() ??
        const Success(
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
  }) {
    return loginHandler?.call() ?? Future.value(Success(_session()));
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
  }) {
    return loginHandler?.call() ?? Future.value(Success(_session()));
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
  }) {
    throw UnimplementedError();
  }

  @override
  Future<Result<AuthSession>> completeOidc({
    required String code,
    required String domain,
    required DeviceIdentity device,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<Result<AuthSession>> refresh(String refreshToken) {
    throw UnimplementedError();
  }

  @override
  Future<Result<void>> logout(String refreshToken) {
    throw UnimplementedError();
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

final class _WidgetTokenRepository implements AuthTokenRepository {
  _WidgetTokenRepository({this.accessToken, this.current = true});

  final String? accessToken;
  final bool current;
  static const _guard = AuthTokenMutationGuard(
    instanceScopeId: 'scope-widget',
    generation: 'generation-widget',
  );

  @override
  Future<AuthTokenMutationGuard?> captureMutationGuard() async =>
      current ? _guard : null;

  @override
  Future<void> clearTokens() async {}

  @override
  Future<bool> clearTokensIfCurrent(AuthTokenMutationGuard guard) async =>
      current && guard == _guard;

  @override
  Future<bool> isMutationGuardCurrent(AuthTokenMutationGuard guard) async =>
      current && guard == _guard;

  @override
  Future<String?> readAccessToken() async => current ? accessToken : null;

  @override
  Future<String?> readRefreshToken() async => null;

  @override
  Future<String?> readAccessTokenIfCurrent(
    AuthTokenMutationGuard guard,
  ) async => current && guard == _guard ? accessToken : null;

  @override
  Future<String?> readRefreshTokenIfCurrent(
    AuthTokenMutationGuard guard,
  ) async => null;

  @override
  Future<void> saveTokens(AuthTokens tokens) async {}

  @override
  Future<bool> saveTokensIfCurrent(
    AuthTokens tokens,
    AuthTokenMutationGuard guard, {
    AuthTokenPersistence? persistence,
  }) async => current && guard == _guard;
}

final class _WidgetDeviceIdentityRepository
    implements DeviceIdentityRepository {
  @override
  Future<DeviceIdentity> currentDevice() async {
    return const DeviceIdentity(
      id: 'device-1',
      platform: 'Android',
      displayName: 'WebTui Android',
    );
  }
}
