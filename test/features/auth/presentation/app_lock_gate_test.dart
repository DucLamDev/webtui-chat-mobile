import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/app/providers/foundation_providers.dart';
import 'package:webtui_chat/features/auth/application/use_cases/app_lock_use_cases.dart';
import 'package:webtui_chat/features/auth/domain/repositories/app_lock_repository.dart';
import 'package:webtui_chat/features/auth/presentation/widgets/app_lock_gate.dart';

void main() {
  testWidgets('PIN input automatically re-enables after the lockout', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          isAppLockEnabledProvider.overrideWith((_) async => true),
          unlockAppUseCaseProvider.overrideWithValue(
            UnlockAppUseCase(_RejectingAppLockRepository()),
          ),
        ],
        child: const MaterialApp(
          home: AppLockGate(
            protectSession: true,
            child: Text('Nội dung riêng tư'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    for (var attempt = 0; attempt < 5; attempt += 1) {
      await tester.enterText(
        find.byKey(const Key('app_lock_pin_field')),
        '1234',
      );
      await tester.tap(find.byKey(const Key('app_lock_unlock_button')));
      await tester.pump();
    }

    expect(find.textContaining('Thử lại sau'), findsOneWidget);
    expect(_unlockButton(tester).onPressed, isNull);

    await tester.pump(const Duration(seconds: 30));
    await tester.pump();

    expect(find.textContaining('Thử lại sau'), findsNothing);
    expect(_unlockButton(tester).onPressed, isNotNull);
  });
}

FilledButton _unlockButton(WidgetTester tester) {
  return tester.widget<FilledButton>(
    find.byKey(const Key('app_lock_unlock_button')),
  );
}

final class _RejectingAppLockRepository implements AppLockRepository {
  @override
  Future<void> disable() async {}

  @override
  Future<void> enablePin(String pin) async {}

  @override
  Future<bool> isEnabled() async => true;

  @override
  Future<bool> verifyPin(String pin) async => false;
}
