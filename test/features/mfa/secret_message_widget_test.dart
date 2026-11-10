import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/app/providers/foundation_providers.dart';
import 'package:webtui_chat/core/result/result.dart';
import 'package:webtui_chat/features/conversations/application/use_cases/secret_message_use_cases.dart';
import 'package:webtui_chat/features/conversations/domain/entities/chat_message.dart';
import 'package:webtui_chat/features/conversations/domain/repositories/secret_message_repository.dart';
import 'package:webtui_chat/features/conversations/presentation/widgets/message_parts/secret_message_widgets.dart';
import 'package:webtui_chat/features/mfa/application/mfa_use_cases.dart';
import 'package:webtui_chat/features/mfa/domain/mfa_repository.dart';

void main() {
  Future<void> reveal(WidgetTester tester, List<bool> secure) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('webtui/privacy'),
      (call) async {
        secure.add(call.arguments as bool);
        return null;
      },
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mfaUseCasesProvider.overrideWithValue(MfaUseCases(_Mfa())),
          secretMessageUseCasesProvider.overrideWithValue(
            SecretMessageUseCases(_Messages()),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SecretMessageBubble(
              message: ChatMessage(
                id: 'm',
                workspaceId: 'w',
                channelId: 'c',
                kind: 'text',
                body: '',
                isSecret: true,
                createdAt: DateTime.now(),
                expiresAt: DateTime.now().add(const Duration(hours: 24)),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Xem'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'test-password');
    await tester.tap(find.text('Xác nhận'));
    await tester.pumpAndSettle();
    expect(find.text('private-test-message'), findsOneWidget);
    expect(secure, [true]);
  }

  testWidgets('xem tin bật FLAG_SECURE và che sau 60 giây', (tester) async {
    final secure = <bool>[];
    await reveal(tester, secure);
    await tester.pump(const Duration(seconds: 61));
    await tester.pumpAndSettle();
    expect(find.text('private-test-message'), findsNothing);
    expect(secure, [true, false]);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('rời ứng dụng che nội dung ngay, quay lại cần xác thực', (
    tester,
  ) async {
    final secure = <bool>[];
    await reveal(tester, secure);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('private-test-message'), findsNothing);
    await tester.tap(find.text('Xem'));
    await tester.pumpAndSettle();
    expect(find.text('Xác thực lại'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}

class _Mfa implements MfaRepository {
  @override
  Future<Result<String>> reauthenticate({
    required String method,
    required String value,
  }) async => const Success('test-proof');
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Messages implements SecretMessageRepository {
  @override
  Future<Result<String>> reveal(
    String w,
    String c,
    String m,
    String token,
  ) async => const Success('private-test-message');
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
