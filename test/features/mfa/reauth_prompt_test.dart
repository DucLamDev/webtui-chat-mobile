import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/app/providers/foundation_providers.dart';
import 'package:webtui_chat/core/error/failure.dart';
import 'package:webtui_chat/core/result/result.dart';
import 'package:webtui_chat/design_system/theme/webtui_theme.dart';
import 'package:webtui_chat/features/mfa/application/mfa_use_cases.dart';
import 'package:webtui_chat/features/mfa/domain/mfa_repository.dart';
import 'package:webtui_chat/features/mfa/presentation/reauth_prompt.dart';

final class _Mfa implements MfaRepository {
  final calls = <String>[];
  Completer<Result<String>>? pending;
  Result<String> next = const Success('proof');

  @override
  Future<Result<String>> reauthenticate({
    required String method,
    required String value,
  }) {
    calls.add('$method:$value');
    return pending?.future ?? Future.value(next);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  Future<({String? Function() result, _Mfa mfa})> open(
    WidgetTester tester,
  ) async {
    final mfa = _Mfa();
    String? result = 'chưa trả';
    await tester.pumpWidget(
      ProviderScope(
        overrides: [mfaUseCasesProvider.overrideWithValue(MfaUseCases(mfa))],
        child: MaterialApp(
          theme: WebTuiTheme.light(),
          home: Consumer(
            builder: (context, ref, _) => TextButton(
              onPressed: () async {
                result = await requestReauthToken(
                  context,
                  ref,
                  reason: 'Xem tin bí mật trong tối đa 60 giây',
                );
              },
              child: const Text('mở'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('mở'));
    await tester.pumpAndSettle();
    return (result: () => result, mfa: mfa);
  }

  testWidgets(
    'hộp khung chung: lý do, chọn cách xác thực, sai thì báo dưới ô',
    (tester) async {
      final opened = await open(tester);
      expect(find.text('Xác thực lại'), findsOneWidget);
      expect(find.text('Xem tin bí mật trong tối đa 60 giây'), findsOneWidget);
      expect(find.byType(DropdownButton<String>), findsNothing);
      expect(find.byKey(const Key('reauth_biometric')), findsOneWidget);

      // Mật khẩu ẩn mặc định, bấm mắt để hiện.
      expect(
        tester.widget<TextField>(find.byType(TextField)).obscureText,
        isTrue,
      );
      await tester.tap(find.byKey(const Key('reauth_toggle_password')));
      await tester.pump();
      expect(
        tester.widget<TextField>(find.byType(TextField)).obscureText,
        isFalse,
      );

      opened.mfa.next = const FailureResult(
        Failure(kind: FailureKind.unauthorized, message: 'Mật khẩu chưa đúng.'),
      );
      await tester.enterText(find.byType(TextField), 'sai');
      await tester.tap(find.byKey(const Key('reauth_confirm')));
      await tester.pumpAndSettle();
      expect(find.text('Mật khẩu chưa đúng.'), findsOneWidget);
      expect(opened.mfa.calls, ['password:sai']);

      await tester.tap(find.text('Mã OTP'));
      await tester.pump();
      expect(find.text('Mật khẩu chưa đúng.'), findsNothing);
      opened.mfa.next = const Success('proof-1');
      await tester.enterText(find.byType(TextField), '123456');
      await tester.tap(find.byKey(const Key('reauth_confirm')));
      await tester.pumpAndSettle();
      expect(opened.mfa.calls.last, 'totp:123456');
      expect(opened.result(), 'proof-1');
    },
  );

  testWidgets('đang xử lý hiện vòng xoay, Huỷ trả null', (tester) async {
    final opened = await open(tester);
    opened.mfa.pending = Completer();
    await tester.enterText(find.byType(TextField), 'mk');
    await tester.tap(find.byKey(const Key('reauth_confirm')));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    opened.mfa.pending!.complete(const Success('p'));
    await tester.pumpAndSettle();
    expect(opened.result(), 'p');

    await tester.tap(find.text('mở'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('reauth_cancel')));
    await tester.pumpAndSettle();
    expect(opened.result(), isNull);
  });

  testWidgets(
    'ô nhập giữ thuộc tính cũ: không gợi ý / tự sửa, khoá khi đang kiểm, vân tay đưa con trỏ vào ô',
    (tester) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('webtui/biometric'),
            (call) async => true,
          );
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel('webtui/biometric'),
              null,
            ),
      );
      final opened = await open(tester);
      TextField field() => tester.widget<TextField>(find.byType(TextField));
      expect(field().autocorrect, isFalse);
      expect(field().enableSuggestions, isFalse);
      expect(field().focusNode, isNotNull);

      // Bỏ con trỏ khỏi ô rồi bấm vân tay: ô được focus lại.
      field().focusNode!.unfocus();
      await tester.pump();
      expect(field().focusNode!.hasFocus, isFalse);
      await tester.tap(find.byKey(const Key('reauth_biometric')));
      await tester.pumpAndSettle();
      expect(field().focusNode!.hasFocus, isTrue);

      // Đang kiểm tra với máy chủ: ô bị khoá.
      opened.mfa.pending = Completer<Result<String>>();
      await tester.enterText(find.byType(TextField), 'mat-khau');
      await tester.tap(find.text('Xác nhận'));
      await tester.pump();
      expect(field().enabled, isFalse);
      opened.mfa.pending!.complete(const Success('proof'));
      await tester.pumpAndSettle();
    },
  );
}
