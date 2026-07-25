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

    final registerLink = find.text('Đăng ký ngay');
    await tester.ensureVisible(registerLink);
    await tester.pumpAndSettle();
    await tester.tap(registerLink);
    await tester.pumpAndSettle();

    expect(find.text('Tạo tài khoản mới'), findsOneWidget);
    expect(find.text('Xác nhận mật khẩu'), findsOneWidget);
    expect(find.text('Địa chỉ server'), findsOneWidget);
    expect(find.byKey(const Key('register_submit_button')), findsOneWidget);
  });
}

Future<void> _pumpLogin(
  WidgetTester tester, {
  required AuthRepository authRepository,
  VoidCallback? onLoginSuccess,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appConfigProvider.overrideWithValue(
          AppConfig(
            flavor: AppFlavor.dev,
            apiBaseUri: Uri.parse('http://localhost:8080'),
            wsBaseUri: Uri.parse('ws://localhost:8080/ws'),
          ),
        ),
        serverConnectorProvider.overrideWithValue(
          (_) async => SelfHostedServerDiscovery(
            domain: 'localhost',
            name: 'Company Chat',
            apiBaseUri: Uri.parse('http://localhost:8080'),
            wsBaseUri: Uri.parse('ws://localhost:8080/ws'),
            registrationMode: 'open',
            appVersion: 'test',
          ),
        ),
        loginUseCaseProvider.overrideWithValue(
          LoginUseCase(
            authRepository: authRepository,
            tokenRepository: _WidgetTokenRepository(),
            deviceIdentityRepository: _WidgetDeviceIdentityRepository(),
          ),
        ),
        registerUseCaseProvider.overrideWithValue(
          RegisterUseCase(
            authRepository: authRepository,
            tokenRepository: _WidgetTokenRepository(),
            deviceIdentityRepository: _WidgetDeviceIdentityRepository(),
          ),
        ),
      ],
      child: MaterialApp(home: LoginScreen(onLoginSuccess: onLoginSuccess)),
    ),
  );
}

Future<void> _fillAndSubmit(WidgetTester tester) async {
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
  const _WidgetAuthRepository({this.loginHandler});

  final Future<Result<AuthSession>> Function()? loginHandler;

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
    required DeviceIdentity device,
  }) {
    return loginHandler?.call() ?? Future.value(Success(_session()));
  }

  @override
  Future<Result<AuthSession>> loginWithGoogle({
    required String credential,
    required DeviceIdentity device,
  }) {
    return loginHandler?.call() ?? Future.value(Success(_session()));
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
  @override
  Future<void> clearTokens() async {}

  @override
  Future<String?> readAccessToken() async => null;

  @override
  Future<String?> readRefreshToken() async => null;

  @override
  Future<void> saveTokens(AuthTokens tokens) async {}
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
