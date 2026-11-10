import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/core/result/result.dart';
import 'package:webtui_chat/design_system/theme/webtui_theme.dart';
import 'package:webtui_chat/features/auth/application/use_cases/qr_login_use_cases.dart';
import 'package:webtui_chat/features/auth/domain/entities/email_verification.dart';
import 'package:webtui_chat/features/auth/domain/entities/qr_login.dart';
import 'package:webtui_chat/features/auth/presentation/controllers/email_verification_controller.dart';
import 'package:webtui_chat/features/auth/presentation/controllers/qr_login_controller.dart';
import 'package:webtui_chat/features/auth/presentation/screens/email_verification_screen.dart';
import 'package:webtui_chat/features/auth/presentation/screens/qr_login_screen.dart';

void main() {
  testWidgets('QR hiển thị máy xin vào và không tự đồng ý', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var approved = 0;
    final controller = QrLoginController(
      readPayload: ReadQrLoginPayloadUseCase(
        loadServerOrigin: () => Uri.parse('https://chat.example.com'),
      ).execute,
      scan: (payload) async => Success(
        QrLoginScan(
          challengeId: payload.challengeId,
          status: 'scanned',
          requester: const QrLoginRequester(
            deviceName: 'Máy tính văn phòng',
            ipAddress: '203.0.113.7',
            userAgent: 'Chrome/130',
          ),
        ),
      ),
      decide: (_, {required approve}) async {
        if (approve) approved++;
        return Success(approve ? 'approved' : 'rejected');
      },
    );
    await controller.submitScannedValue(
      'vpsttt-login:v1?d=chat.example.com&c=challenge-123&s=secretsecret123456',
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [qrLoginControllerProvider.overrideWith((_) => controller)],
        child: MaterialApp(
          theme: WebTuiTheme.light(),
          home: const QrLoginScreen(openScannerOnStart: false),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Máy tính văn phòng'), findsOneWidget);
    expect(find.text('203.0.113.7'), findsOneWidget);
    expect(approved, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('màn email chặn gửi khi mã chưa đủ và chưa hết cooldown', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final now = DateTime.now();
    final ticket = EmailVerificationTicket(
      verificationId: 'verify-123',
      emailHint: 'a***@example.com',
      resendAvailableAt: now.add(const Duration(seconds: 60)),
    );
    final controller = EmailVerificationController(
      ticket: ticket,
      clock: () => now,
      verify: ({required verificationId, required code}) async =>
          throw StateError('Chưa gửi'),
      resend: (_) async => throw StateError('Chưa gửi'),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          emailVerificationControllerProvider(
            ticket,
          ).overrideWith((_) => controller),
        ],
        child: MaterialApp(
          theme: WebTuiTheme.light(),
          home: EmailVerificationScreen(ticket: ticket),
        ),
      ),
    );
    await tester.pump();
    final submit = find.byKey(const Key('email_code_submit_button'));
    expect(tester.widget<FilledButton>(submit).onPressed, isNull);
    expect(
      tester
          .widget<TextButton>(find.byKey(const Key('email_code_resend_button')))
          .onPressed,
      isNull,
    );
    await tester.enterText(find.byKey(const Key('email_code_field')), '123456');
    await tester.pump();
    expect(tester.widget<FilledButton>(submit).onPressed, isNotNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
