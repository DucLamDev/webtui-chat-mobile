import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/app/providers/foundation_providers.dart';
import 'package:webtui_chat/core/security/active_call_tracker.dart';
import 'package:webtui_chat/features/auth/application/use_cases/app_lock_use_cases.dart';
import 'package:webtui_chat/features/auth/domain/repositories/app_lock_repository.dart';
import 'package:webtui_chat/features/auth/presentation/widgets/app_lock_gate.dart';

void main() {
  late DateTime now;
  late _CallScreenProbe probe;

  setUp(() {
    now = DateTime(2026, 11, 10, 9);
    probe = _CallScreenProbe();
  });

  Future<ProviderContainer> pumpGate(
    WidgetTester tester, {
    int minutes = 30,
  }) async {
    final container = ProviderContainer(
      overrides: [
        isAppLockEnabledProvider.overrideWith((_) async => true),
        unlockAppUseCaseProvider.overrideWithValue(
          UnlockAppUseCase(_AcceptingAppLockRepository()),
        ),
        effectiveAppLockMinutesProvider.overrideWithValue(minutes),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: AppLockGate(
            protectSession: true,
            clock: () => now,
            idleCheckInterval: const Duration(seconds: 1),
            child: _FakeCallScreen(probe: probe),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  Future<void> unlock(WidgetTester tester) async {
    await tester.enterText(find.byKey(const Key('app_lock_pin_field')), '1234');
    await tester.tap(find.byKey(const Key('app_lock_unlock_button')));
    await tester.pumpAndSettle();
  }

  bool isLocked() =>
      find.byKey(const Key('app_lock_pin_field')).evaluate().isNotEmpty;

  testWidgets('lớp khoá phủ lên nội dung, không gỡ màn gọi bên dưới', (
    tester,
  ) async {
    await pumpGate(tester);

    expect(isLocked(), isTrue);
    expect(probe.initCount, 1);
    expect(probe.disposeCount, 0);
    expect(find.byType(_FakeCallScreen, skipOffstage: false), findsOneWidget);

    await unlock(tester);
    expect(isLocked(), isFalse);
    expect(probe.initCount, 1, reason: 'mở khoá không dựng lại màn gọi');
    expect(probe.disposeCount, 0);
  });

  testWidgets('chỉ inactive (kéo thanh thông báo) thì không khoá', (
    tester,
  ) async {
    await pumpGate(tester);
    await unlock(tester);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    now = now.add(const Duration(minutes: 5));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(isLocked(), isFalse);
    expect(probe.disposeCount, 0);
  });

  testWidgets('chạy nền quá N phút thì khoá, chưa quá thì không', (
    tester,
  ) async {
    await pumpGate(tester);
    await unlock(tester);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    now = now.add(const Duration(minutes: 10));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(isLocked(), isFalse);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    now = now.add(const Duration(minutes: 31));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(isLocked(), isTrue);
    expect(probe.disposeCount, 0);
  });

  testWidgets('không chạm vào app quá N phút thì khoá, chạm thì tính lại', (
    tester,
  ) async {
    await pumpGate(tester, minutes: 5);
    await unlock(tester);

    now = now.add(const Duration(minutes: 4));
    await tester.tap(find.text('Màn gọi'));
    now = now.add(const Duration(minutes: 4));
    await tester.pump(const Duration(seconds: 1));
    expect(isLocked(), isFalse);

    now = now.add(const Duration(minutes: 2));
    await tester.pump(const Duration(seconds: 1));
    expect(isLocked(), isTrue);
    expect(probe.disposeCount, 0);
  });

  testWidgets('đang gọi thì không tự khoá, gọi xong mới tính thời gian', (
    tester,
  ) async {
    final container = await pumpGate(tester, minutes: 5);
    await unlock(tester);

    container.read(activeCallTrackerProvider.notifier).begin('call-1');
    await tester.pump();

    now = now.add(const Duration(minutes: 20));
    await tester.pump(const Duration(seconds: 1));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    now = now.add(const Duration(minutes: 20));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(isLocked(), isFalse);

    container.read(activeCallTrackerProvider.notifier).end('call-1');
    await tester.pump();
    now = now.add(const Duration(minutes: 4));
    await tester.pump(const Duration(seconds: 1));
    expect(isLocked(), isFalse);
    now = now.add(const Duration(minutes: 2));
    await tester.pump(const Duration(seconds: 1));
    expect(isLocked(), isTrue);
    expect(probe.disposeCount, 0);
  });
}

final class _CallScreenProbe {
  int initCount = 0;
  int disposeCount = 0;
}

class _FakeCallScreen extends StatefulWidget {
  const _FakeCallScreen({required this.probe});

  final _CallScreenProbe probe;

  @override
  State<_FakeCallScreen> createState() => _FakeCallScreenState();
}

class _FakeCallScreenState extends State<_FakeCallScreen> {
  @override
  void initState() {
    super.initState();
    widget.probe.initCount += 1;
  }

  @override
  void dispose() {
    widget.probe.disposeCount += 1;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: Text('Màn gọi')));
  }
}

final class _AcceptingAppLockRepository implements AppLockRepository {
  @override
  Future<void> disable() async {}

  @override
  Future<void> enablePin(String pin) async {}

  @override
  Future<bool> isEnabled() async => true;

  @override
  Future<bool> verifyPin(String pin) async => true;
}
