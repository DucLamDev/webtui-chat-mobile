import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/app/providers/foundation_providers.dart';
import 'package:webtui_chat/core/error/failure.dart';
import 'package:webtui_chat/core/platform/external_url_launcher.dart';
import 'package:webtui_chat/core/result/result.dart';
import 'package:webtui_chat/design_system/theme/webtui_theme.dart';
import 'package:webtui_chat/features/auth/domain/entities/auth_session.dart';
import 'package:webtui_chat/features/auth/domain/entities/auth_tokens.dart';
import 'package:webtui_chat/features/auth/domain/entities/login_mfa.dart';
import 'package:webtui_chat/features/auth/presentation/controllers/auth_flow_providers.dart';
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
    final now = DateTime.utc(2026, 11, 20, 8);

    LoginMfaController controllerFor({
      List<LoginMfaMethod> methods = const [
        LoginMfaMethod.totp,
        LoginMfaMethod.recoveryCode,
        LoginMfaMethod.passkey,
      ],
      Duration left = const Duration(minutes: 5),
      List<Completer<Result<AuthSession>>>? pending,
    }) {
      return LoginMfaController.forTesting(
        challenge: LoginMfaChallenge(
          mfaToken: 'mfa-token-1',
          methods: methods,
          expiresAt: now.add(left),
          instanceScopeId: 'scope-a',
        ),
        clock: () => now,
        complete: ({required challenge, required method, required code}) {
          final completer = Completer<Result<AuthSession>>();
          pending?.add(completer);
          return completer.future;
        },
      );
    }

    Future<void> pumpScreen(
      WidgetTester tester,
      LoginMfaController controller, {
      String? identifier = 'lam@congty.vn',
      ExternalUrlLauncher? launcher,
      Size size = const Size(390, 844),
      ThemeData? theme,
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            loginMfaControllerProvider.overrideWith((_) => controller),
            pendingLoginMfaIdentifierProvider.overrideWith((_) => identifier),
            activeServerUriProvider.overrideWithValue(
              Uri.parse('https://chat.example.com/api/v1'),
            ),
            if (launcher != null)
              externalUrlLauncherProvider.overrideWithValue(launcher),
          ],
          child: MaterialApp(
            theme: theme ?? WebTuiTheme.light(),
            home: const LoginMfaScreen(),
          ),
        ),
      );
      await tester.pump();
    }

    final codeField = find.byKey(const Key('login_mfa_code_field'));
    final submit = find.byKey(const Key('login_mfa_submit_button'));

    testWidgets('đủ 6 số thì tự gửi một lần; sai mã thì báo số lần còn lại, '
        'xoá ô và focus lại', (tester) async {
      final pending = <Completer<Result<AuthSession>>>[];
      final controller = controllerFor(pending: pending);
      await pumpScreen(tester, controller);

      expect(find.text('Nhập mã xác thực'), findsOneWidget);
      expect(find.text('lam@congty.vn'), findsOneWidget);
      // Đủ thời gian thì không hiện đồng hồ.
      expect(find.byKey(const Key('login_mfa_countdown')), findsNothing);

      await tester.enterText(codeField, '123 456');
      await tester.pump();
      expect(pending, hasLength(1));
      expect(find.text('Đang xác minh…'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      // Đang gửi: bấm nút không gửi thêm lần nữa.
      await tester.tap(submit);
      await tester.pump();
      expect(pending, hasLength(1));

      pending.last.complete(
        FailureResult(_failure('MFA_INVALID_CODE', {'attempts_left': 2})),
      );
      await tester.pump();
      await tester.pump();
      expect(
        find.text('Mã không đúng hoặc đã dùng. Còn 2 lần thử.'),
        findsOneWidget,
      );
      expect(tester.widget<TextField>(codeField).controller!.text, isEmpty);
      expect(tester.widget<TextField>(codeField).focusNode!.hasFocus, isTrue);

      // Gõ lại thì dòng lỗi tắt.
      await tester.enterText(codeField, '65');
      await tester.pump();
      expect(find.byKey(const Key('login_mfa_error')), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('bấm Xác minh khi mã chưa đủ thì nhắc tại chỗ, không gửi', (
      tester,
    ) async {
      final pending = <Completer<Result<AuthSession>>>[];
      await pumpScreen(tester, controllerFor(pending: pending));

      final button = tester.widget<FilledButton>(submit);
      expect(button.onPressed, isNotNull);
      expect(tester.getSize(submit).height, greaterThanOrEqualTo(48));
      await tester.enterText(codeField, '1234');
      await tester.pump();
      await tester.tap(submit);
      await tester.pump();
      expect(find.text('Nhập đủ 6 số.'), findsOneWidget);
      expect(pending, isEmpty);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('Thử cách khác: liệt kê các cách, passkey chỉ giải thích, '
        'chọn mã khôi phục thì đổi màn', (tester) async {
      await pumpScreen(tester, controllerFor());

      final other = find.byKey(const Key('login_mfa_switch_method'));
      expect(tester.getSize(other).height, greaterThanOrEqualTo(48));
      await tester.tap(other);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Ứng dụng xác thực'), findsOneWidget);
      expect(find.text('Mã khôi phục'), findsOneWidget);
      expect(find.text('Passkey'), findsOneWidget);
      for (final key in ['totp', 'recovery_code', 'passkey']) {
        expect(
          tester.getSize(find.byKey(Key('login_mfa_method_$key'))).height,
          greaterThanOrEqualTo(48),
        );
      }

      await tester.tap(find.byKey(const Key('login_mfa_method_passkey')));
      await tester.pump();
      expect(
        find.byKey(const Key('login_mfa_passkey_explanation')),
        findsOneWidget,
      );
      expect(find.text('Chọn cách xác minh'), findsOneWidget);

      await tester.tap(find.byKey(const Key('login_mfa_method_recovery_code')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Chọn cách xác minh'), findsNothing);
      expect(find.text('Nhập mã khôi phục'), findsOneWidget);

      await tester.enterText(codeField, 'ab3k9q7x2m');
      await tester.pump();
      expect(
        tester.widget<TextField>(codeField).controller!.text,
        'AB3K9-Q7X2M',
      );
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('chỉ còn dưới 60 giây mới hiện đồng hồ', (tester) async {
      await pumpScreen(
        tester,
        controllerFor(left: const Duration(seconds: 45)),
      );
      expect(find.text('Còn 0:45 để nhập mã'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('hết hạn thì thay bằng trạng thái rõ ràng, chỉ còn đăng nhập '
        'lại', (tester) async {
      final pending = <Completer<Result<AuthSession>>>[];
      await pumpScreen(tester, controllerFor(pending: pending));
      await tester.enterText(codeField, '654321');
      await tester.pump();
      pending.last.complete(FailureResult(_failure('MFA_CHALLENGE_EXPIRED')));
      await tester.pump();

      expect(find.text('Lượt xác minh đã hết hạn'), findsOneWidget);
      expect(find.textContaining('chỉ có 5 phút'), findsOneWidget);
      expect(find.byKey(const Key('login_mfa_restart_button')), findsOneWidget);
      expect(submit, findsNothing);
      expect(codeField, findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('đồng hồ về 0 cũng hiện trạng thái hết hạn', (tester) async {
      await pumpScreen(tester, controllerFor(left: Duration.zero));
      expect(find.byKey(const Key('login_mfa_expired')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('quá số lần thử thì báo câu sẵn có và cho đăng nhập lại', (
      tester,
    ) async {
      final pending = <Completer<Result<AuthSession>>>[];
      await pumpScreen(tester, controllerFor(pending: pending));
      await tester.enterText(codeField, '111111');
      await tester.pump();
      pending.last.complete(FailureResult(_failure('MFA_TOO_MANY_ATTEMPTS')));
      await tester.pump();

      expect(find.text('Cần đăng nhập lại'), findsOneWidget);
      expect(find.textContaining('nhập sai quá nhiều lần'), findsOneWidget);
      expect(find.byKey(const Key('login_mfa_restart_button')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('tài khoản chỉ có passkey: mở trang đăng nhập web của máy '
        'chủ đang dùng', (tester) async {
      final launcher = _RecordingLauncher();
      await pumpScreen(
        tester,
        controllerFor(methods: const [LoginMfaMethod.passkey]),
        launcher: launcher,
        theme: WebTuiTheme.dark(),
      );

      expect(find.byKey(const Key('login_mfa_passkey_only')), findsOneWidget);
      expect(find.text('Tài khoản này dùng passkey'), findsOneWidget);
      expect(find.textContaining('chưa hỗ trợ passkey'), findsOneWidget);
      expect(codeField, findsNothing);
      expect(find.byKey(const Key('login_mfa_restart_button')), findsOneWidget);

      await tester.tap(find.byKey(const Key('login_mfa_open_web_button')));
      await tester.pump();
      expect(launcher.opened, ['https://chat.example.com/']);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('lượt SSO không có email thì hiện "Tài khoản công ty"; màn '
        'nhỏ khi bàn phím mở vẫn không tràn', (tester) async {
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await pumpScreen(
        tester,
        controllerFor(),
        identifier: null,
        size: const Size(360, 640),
      );
      expect(find.text('Tài khoản công ty'), findsOneWidget);
      expect(tester.takeException(), isNull);
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
      expect(find.byKey(const Key('login_mfa_restart_button')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  });
}

final class _RecordingLauncher implements ExternalUrlLauncher {
  final opened = <String>[];

  @override
  Future<bool> open(String url) async {
    opened.add(url);
    return true;
  }
}
