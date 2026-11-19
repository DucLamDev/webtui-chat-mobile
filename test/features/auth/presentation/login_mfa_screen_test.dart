import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/core/error/failure.dart';
import 'package:webtui_chat/core/result/result.dart';
import 'package:webtui_chat/design_system/theme/webtui_theme.dart';
import 'package:webtui_chat/features/auth/domain/entities/auth_session.dart';
import 'package:webtui_chat/features/auth/domain/entities/auth_tokens.dart';
import 'package:webtui_chat/features/auth/domain/entities/login_mfa.dart';
import 'package:webtui_chat/features/auth/presentation/controllers/login_mfa_controller.dart';
import 'package:webtui_chat/features/auth/presentation/screens/login_mfa_screen.dart';

LoginMfaChallenge _challenge(
  DateTime now, {
  List<LoginMfaMethod> methods = const [
    LoginMfaMethod.totp,
    LoginMfaMethod.recoveryCode,
  ],
}) => LoginMfaChallenge(
  mfaToken: 'mfa-token-1',
  methods: methods,
  expiresAt: now.add(const Duration(minutes: 5)),
  instanceScopeId: 'scope-a',
);

Failure _failure(String code, [Map<String, Object?> details = const {}]) =>
    Failure(
      kind: FailureKind.unauthorized,
      code: code,
      message: 'server',
      details: details,
    );

const _session = AuthSession(
  tokens: AuthTokens(accessToken: 'a', refreshToken: 'r'),
  sessionId: 's',
  approvalStatus: 'pending',
);

void main() {
  group('LoginMfaController', () {
    final now = DateTime.utc(2026, 11, 19, 8);

    test('wrong code shows attempts left and keeps the step open', () async {
      final calls = <String>[];
      final controller = LoginMfaController.forTesting(
        challenge: _challenge(now),
        clock: () => now,
        complete: ({required challenge, required method, required code}) async {
          calls.add('${method.apiValue}:$code');
          return FailureResult(
            _failure('MFA_INVALID_CODE', {'attempts_left': 2}),
          );
        },
      );

      controller.updateCode('12a3456789');
      expect(controller.state.code, '123456');
      await controller.submit();

      expect(calls, ['totp:123456']);
      expect(controller.state.errorMessage, contains('Còn 2 lần thử'));
      expect(controller.state.mustRestart, isFalse);
      expect(controller.state.code, isEmpty);
    });

    test('expired, too many attempts or zero attempts left go back to the '
        'password step', () async {
      for (final failure in [
        _failure('MFA_CHALLENGE_EXPIRED'),
        _failure('MFA_TOO_MANY_ATTEMPTS'),
        _failure('MFA_INVALID_CODE', {'attempts_left': 0}),
      ]) {
        final controller = LoginMfaController.forTesting(
          challenge: _challenge(now),
          clock: () => now,
          complete:
              ({required challenge, required method, required code}) async =>
                  FailureResult(failure),
        );
        controller.updateCode('123456');
        await controller.submit();
        expect(controller.state.mustRestart, isTrue, reason: failure.code);
        expect(controller.state.canSubmit, isFalse);
      }
    });

    test('correct code returns the session (device approval kept)', () async {
      final controller = LoginMfaController.forTesting(
        challenge: _challenge(now),
        clock: () => now,
        complete:
            ({required challenge, required method, required code}) async =>
                const Success(_session),
      );
      controller.selectMethod(LoginMfaMethod.recoveryCode);
      controller.updateCode('abcde-12345');
      expect(controller.state.code, 'ABCDE-12345');
      await controller.submit();

      expect(controller.state.session?.isPendingApproval, isTrue);
    });

    test('passkey-only accounts cannot submit in the app', () {
      final controller = LoginMfaController.forTesting(
        challenge: _challenge(now, methods: const [LoginMfaMethod.passkey]),
        clock: () => now,
        complete: ({required challenge, required method, required code}) =>
            throw StateError('không được gọi'),
      );
      controller.updateCode('123456');
      expect(controller.state.method, isNull);
      expect(controller.state.canSubmit, isFalse);
    });
  });

  group('LoginMfaScreen', () {
    Future<void> pumpScreen(
      WidgetTester tester,
      LoginMfaController controller,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            loginMfaControllerProvider.overrideWith((_) => controller),
          ],
          child: MaterialApp(
            theme: WebTuiTheme.light(),
            home: const LoginMfaScreen(),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets(
      'mã sai báo số lần còn lại, hết hạn chỉ còn nút đăng nhập lại',
      (tester) async {
        final now = DateTime.now().toUtc();
        final pending = <Completer<Result<AuthSession>>>[];
        final controller = LoginMfaController.forTesting(
          challenge: _challenge(now),
          complete: ({required challenge, required method, required code}) {
            final completer = Completer<Result<AuthSession>>();
            pending.add(completer);
            return completer.future;
          },
        );
        await pumpScreen(tester, controller);

        final submit = find.byKey(const Key('login_mfa_submit_button'));
        expect(tester.widget<FilledButton>(submit).onPressed, isNull);
        expect(find.text('Dùng mã khôi phục'), findsOneWidget);
        expect(
          tester
              .getSize(find.byKey(const Key('login_mfa_switch_method')))
              .height,
          greaterThanOrEqualTo(44),
        );

        await tester.enterText(
          find.byKey(const Key('login_mfa_code_field')),
          '123456',
        );
        await tester.pump();
        await tester.tap(submit);
        await tester.pump();
        expect(find.byType(CircularProgressIndicator), findsOneWidget);

        pending.last.complete(
          FailureResult(_failure('MFA_INVALID_CODE', {'attempts_left': 2})),
        );
        await tester.pump();
        expect(find.textContaining('Còn 2 lần thử'), findsOneWidget);

        await tester.enterText(
          find.byKey(const Key('login_mfa_code_field')),
          '654321',
        );
        await tester.pump();
        await tester.tap(submit);
        await tester.pump();
        pending.last.complete(FailureResult(_failure('MFA_CHALLENGE_EXPIRED')));
        await tester.pump();
        expect(
          find.textContaining('Lượt đăng nhập đã hết hạn'),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('login_mfa_restart_button')),
          findsOneWidget,
        );
        expect(submit, findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets('tài khoản chỉ có passkey được báo rõ', (tester) async {
      final now = DateTime.now().toUtc();
      final controller = LoginMfaController.forTesting(
        challenge: _challenge(now, methods: const [LoginMfaMethod.passkey]),
        complete: ({required challenge, required method, required code}) =>
            throw StateError('không được gọi'),
      );
      await pumpScreen(tester, controller);

      expect(find.byKey(const Key('login_mfa_passkey_only')), findsOneWidget);
      expect(find.textContaining('chưa hỗ trợ passkey'), findsOneWidget);
      expect(find.byKey(const Key('login_mfa_code_field')), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('không còn lượt chờ thì báo lỗi và cho quay lại', (
      tester,
    ) async {
      final controller = LoginMfaController.forTesting(
        challenge: null,
        complete: ({required challenge, required method, required code}) =>
            throw StateError('không được gọi'),
      );
      await pumpScreen(tester, controller);

      expect(find.text('Lượt xác thực không còn'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  });
}
