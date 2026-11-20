import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:webtui_chat/app/providers/foundation_providers.dart';
import 'package:webtui_chat/features/ide_mobile/application/ide_access_controller.dart';
import 'package:webtui_chat/features/ide_mobile/domain/ide_device_security.dart';
import 'package:webtui_chat/features/ide_mobile/domain/ide_ready.dart';
import 'package:webtui_chat/features/ide_mobile/presentation/screens/ide_screen.dart';
import 'package:webtui_chat/features/ide_mobile/presentation/widgets/ide_access_gate.dart';

import 'support/fakes.dart';

void main() {
  group('IdeAccessController', () {
    test('đổi phiên (đăng xuất / người khác đăng nhập): khoá lại', () async {
      final token = StateProvider<String?>((_) => 'tok-a');
      final c = ProviderContainer(
        overrides: [
          authAccessTokenProvider.overrideWith((ref) async => ref.watch(token)),
          ideDeviceSecurityProvider.overrideWithValue(FakeIdeSecurity()),
        ],
      );
      addTearDown(c.dispose);
      await c.read(authAccessTokenProvider.future);
      final first = c.read(ideAccessControllerProvider);
      await first.ensureUnlocked('x');
      c.read(ideCapabilitiesProvider.notifier).state = const IdeReady(
        ops: {'fs.list'},
      );
      expect(c.read(ideAccessControllerProvider).unlocked, isTrue);

      c.read(token.notifier).state = 'tok-b';
      await c.read(authAccessTokenProvider.future);
      // Riverpod dựng lại khi có người đọc; bộ cũ bị khoá lúc bỏ.
      expect(c.read(ideAccessControllerProvider).unlocked, isFalse);
      expect(first.unlocked, isFalse);
      expect(c.read(ideCapabilitiesProvider), isNull);
    });

    test('nhớ trong lúc dùng, hỏi lại sau khi ra nền đủ 5 phút', () async {
      var now = DateTime(2026, 11, 19, 9);
      final security = FakeIdeSecurity();
      final c = IdeAccessController(security, now: () => now);
      expect(await c.ensureUnlocked('r'), DeviceOwnerAuthResult.ok);
      expect(await c.ensureUnlocked('r'), DeviceOwnerAuthResult.ok);
      expect(security.authCalls, 1);

      c.onBackground();
      now = now.add(const Duration(minutes: 4, seconds: 59));
      security.uptime = 299000;
      expect(await c.onForeground(), isTrue);
      await c.ensureUnlocked('r');
      expect(security.authCalls, 1);

      c.onBackground();
      now = now.add(const Duration(minutes: 5));
      security.uptime = 599000;
      expect(await c.onForeground(), isFalse);
      await c.ensureUnlocked('r');
      expect(security.authCalls, 2);
    });

    test(
      'chỉnh lùi giờ máy không qua được cổng (đo bằng đồng hồ native)',
      () async {
        var now = DateTime(2026, 11, 19, 9);
        final security = FakeIdeSecurity();
        final c = IdeAccessController(security, now: () => now);
        await c.ensureUnlocked('r');

        // Ở nền 30 phút nhưng giờ máy bị chỉnh lại chỉ cách 1 phút.
        c.onBackground();
        now = now.add(const Duration(minutes: 1));
        security.uptime = 30 * 60 * 1000;
        expect(await c.onForeground(), isFalse);
        expect(c.unlocked, isFalse);

        // Giờ máy lùi ra trước lúc vào nền: khoá.
        await c.ensureUnlocked('r');
        c.onBackground();
        now = now.subtract(const Duration(minutes: 10));
        expect(await c.onForeground(), isFalse);
      },
    );

    test(
      'không đọc được đồng hồ native thì khoá; đang kiểm thì coi như khoá',
      () async {
        final security = FakeIdeSecurity();
        final c = IdeAccessController(security);
        await c.ensureUnlocked('r');
        c.onBackground();
        final pending = c.onForeground();
        expect(c.unlocked, isFalse);
        expect(await pending, isTrue);
        expect(c.unlocked, isTrue);

        c.onBackground();
        security.uptime = null;
        expect(await c.onForeground(), isFalse);
        expect(c.unlocked, isFalse);
      },
    );

    test(
      'khoá trong lúc đang hỏi vân tay thì kết quả cũ không mở cổng',
      () async {
        final security = FakeIdeSecurity();
        final c = IdeAccessController(security);
        final asking = c.ensureUnlocked('r');
        c.lock();
        expect(await asking, DeviceOwnerAuthResult.cancelled);
        expect(c.unlocked, isFalse);
      },
    );

    test('hộp xác thực treo thì hết hạn, lần sau hỏi lại', () async {
      final security = FakeIdeSecurity()..hangAuth = true;
      final c = IdeAccessController(
        security,
        authTimeout: const Duration(milliseconds: 10),
      );
      expect(await c.ensureUnlocked('r'), DeviceOwnerAuthResult.unavailable);
      expect(c.unlocked, isFalse);
      await c.ensureUnlocked('r');
      expect(security.authCalls, 2);
    });

    test('huỷ hoặc chưa đặt khoá màn hình thì không mở', () async {
      final security = FakeIdeSecurity(auth: DeviceOwnerAuthResult.cancelled);
      final c = IdeAccessController(security);
      expect(await c.ensureUnlocked('r'), DeviceOwnerAuthResult.cancelled);
      expect(c.unlocked, isFalse);
      security.auth = DeviceOwnerAuthResult.notEnrolled;
      expect(await c.ensureUnlocked('r'), DeviceOwnerAuthResult.notEnrolled);
      expect(c.unlocked, isFalse);
    });

    test('nhiều nơi hỏi cùng lúc chỉ hiện một hộp', () async {
      final security = FakeIdeSecurity();
      final c = IdeAccessController(security);
      await Future.wait([c.ensureUnlocked('r'), c.ensureUnlocked('r')]);
      expect(security.authCalls, 1);
    });
  });

  group('IdeAccessGate với vân tay giả', () {
    Future<GoRouter> pump(WidgetTester tester, FakeIdeSecurity security) async {
      final router = GoRouter(
        routes: [
          GoRoute(path: '/', builder: (_, _) => const Text('trang chủ')),
          GoRoute(
            path: '/ide',
            builder: (_, _) => const IdeAccessGate(child: Text('trong IDE')),
          ),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [ideDeviceSecurityProvider.overrideWithValue(security)],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      router.go('/ide');
      await tester.pumpAndSettle();
      return router;
    }

    testWidgets('xác thực được thì vào IDE', (tester) async {
      await pump(tester, FakeIdeSecurity());
      expect(find.text('trong IDE'), findsOneWidget);
    });

    testWidgets('chưa đặt khoá màn hình: hiện hướng dẫn', (tester) async {
      await pump(
        tester,
        FakeIdeSecurity(auth: DeviceOwnerAuthResult.notEnrolled),
      );
      expect(find.text('trong IDE'), findsNothing);
      expect(
        find.text('Hãy đặt khoá màn hình cho điện thoại để dùng IDE'),
        findsOneWidget,
      );
    });

    testWidgets('huỷ: quay lại trang trước', (tester) async {
      await pump(
        tester,
        FakeIdeSecurity(auth: DeviceOwnerAuthResult.cancelled),
      );
      expect(find.text('trong IDE'), findsNothing);
      expect(find.text('trang chủ'), findsOneWidget);
    });
  });

  test('tab chỉ hiện khi có op tương ứng', () {
    expect(visibleIdeTabs(null), isEmpty);
    final tabs = visibleIdeTabs(
      const IdeReady(ops: {'ai.sessions', 'files.get'}),
    );
    expect(tabs.map((t) => t.name), ['ai', 'files']);
    expect(
      visibleIdeTabs(const IdeReady(ops: {'files.get'})).map((t) => t.name),
      ['files'],
    );
    expect(visibleIdeTabs(const IdeReady()), isEmpty);
  });
}
