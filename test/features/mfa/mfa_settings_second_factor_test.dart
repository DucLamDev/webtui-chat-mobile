import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/app/providers/foundation_providers.dart';
import 'package:webtui_chat/core/error/failure.dart';
import 'package:webtui_chat/core/result/result.dart';
import 'package:webtui_chat/design_system/theme/webtui_theme.dart';
import 'package:webtui_chat/features/mfa/application/mfa_use_cases.dart';
import 'package:webtui_chat/features/mfa/domain/mfa_repository.dart';
import 'package:webtui_chat/features/mfa/presentation/mfa_settings_screen.dart';

final class _Mfa implements MfaRepository {
  _Mfa({required this.totpEnabled});

  final bool totpEnabled;
  final reauthCalls = <String>[];
  final tokensUsed = <String>[];

  @override
  Future<Result<MfaStatus>> status() async =>
      Success(MfaStatus(enabled: true, totpEnabled: totpEnabled));

  @override
  Future<Result<String>> reauthenticate({
    required String method,
    required String value,
  }) async {
    reauthCalls.add(method);
    return Success('token-$method');
  }

  Result<void> _secondFactorRule(String token) {
    tokensUsed.add(token);
    return token == 'token-password'
        ? const FailureResult(
            Failure(
              kind: FailureKind.forbidden,
              code: 'REAUTH_SECOND_FACTOR_REQUIRED',
              message: 'Cần yếu tố thứ hai.',
            ),
          )
        : const Success(null);
  }

  @override
  Future<Result<TotpEnrollment>> enroll(String token) async {
    final rule = _secondFactorRule(token);
    if (rule case FailureResult<void>(:final failure)) {
      return FailureResult(failure);
    }
    return const Success(TotpEnrollment(secret: 'SECRET', uri: 'otpauth://x'));
  }

  @override
  Future<Result<void>> disable(String token) async => _secondFactorRule(token);

  @override
  Future<Result<List<String>>> confirm(String code) async => const Success([]);
}

Future<void> _pump(WidgetTester tester, _Mfa mfa) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [mfaUseCasesProvider.overrideWithValue(MfaUseCases(mfa))],
      child: MaterialApp(
        theme: WebTuiTheme.light(),
        home: const MfaSettingsScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('token chỉ bằng mật khẩu bị từ chối thì hỏi lại bằng mã', (
    tester,
  ) async {
    final mfa = _Mfa(totpEnabled: false);
    await _pump(tester, mfa);

    await tester.tap(find.text('Bật TOTP'));
    await tester.pumpAndSettle();
    expect(find.text('Mật khẩu'), findsWidgets);
    await tester.enterText(find.byKey(const Key('reauth_input')), 'mk');
    await tester.tap(find.byKey(const Key('reauth_confirm')));
    await tester.pumpAndSettle();

    // Lần hai: chỉ còn mã OTP / mã khôi phục.
    expect(find.byKey(const Key('reauth_input')), findsOneWidget);
    expect(find.text('Mật khẩu'), findsNothing);
    await tester.enterText(find.byKey(const Key('reauth_input')), '123456');
    await tester.tap(find.byKey(const Key('reauth_confirm')));
    await tester.pumpAndSettle();

    expect(mfa.reauthCalls, ['password', 'totp']);
    expect(mfa.tokensUsed, ['token-password', 'token-totp']);
    expect(find.text('SECRET'), findsOneWidget);
  });

  testWidgets('tắt TOTP hỏi thẳng yếu tố thứ hai, huỷ thì không gọi tắt', (
    tester,
  ) async {
    final mfa = _Mfa(totpEnabled: true);
    await _pump(tester, mfa);

    await tester.tap(find.text('Tắt TOTP'));
    await tester.pumpAndSettle();
    expect(find.text('Mật khẩu'), findsNothing);
    await tester.tap(find.byKey(const Key('reauth_cancel')));
    await tester.pumpAndSettle();

    expect(mfa.reauthCalls, isEmpty);
    expect(mfa.tokensUsed, isEmpty);
  });
}
