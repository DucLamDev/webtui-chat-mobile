import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/features/auth/domain/entities/user_session.dart';
import 'package:webtui_chat/features/settings/presentation/screens/privacy_sessions_screen.dart';

void main() {
  final now = DateTime.now();

  UserSession session(
    String id, {
    required Duration lastSeenAgo,
    bool current = false,
    bool revoked = false,
    bool expired = false,
  }) {
    return UserSession(
      id: id,
      deviceName: 'Thiết bị $id',
      createdAt: now.subtract(const Duration(days: 30)),
      lastSeenAt: now.subtract(lastSeenAgo),
      expiresAt: expired
          ? now.subtract(const Duration(hours: 1))
          : now.add(const Duration(days: 30)),
      revokedAt: revoked ? now.subtract(const Duration(hours: 2)) : null,
      isCurrent: current,
    );
  }

  final sessions = [
    session('cu-1', lastSeenAgo: const Duration(days: 20)),
    session(
      'thu-hoi-moi',
      lastSeenAgo: const Duration(minutes: 5),
      revoked: true,
    ),
    session('may-nay', lastSeenAgo: const Duration(days: 1), current: true),
    session('moi-nhat', lastSeenAgo: const Duration(minutes: 1)),
    session('het-han', lastSeenAgo: const Duration(minutes: 2), expired: true),
    session('hom-qua', lastSeenAgo: const Duration(hours: 13)),
    session('cu-2', lastSeenAgo: const Duration(days: 9)),
  ];

  group('sessionsForDisplay', () {
    test(
      'thu gọn: máy này + phiên còn dùng gần nhất, tối đa 3, ẩn phiên thu hồi / hết hạn',
      () {
        final display = sessionsForDisplay(sessions, expanded: false);

        expect(display.visible.map((item) => item.id), [
          'may-nay',
          'moi-nhat',
          'hom-qua',
        ]);
        expect(display.hiddenCount, sessions.length - 3);
      },
    );

    test('mở rộng: hiện tất cả, phiên thu hồi / hết hạn xếp cuối', () {
      final display = sessionsForDisplay(sessions, expanded: true);

      expect(display.visible.map((item) => item.id), [
        'may-nay',
        'moi-nhat',
        'hom-qua',
        'cu-2',
        'cu-1',
        'het-han',
        'thu-hoi-moi',
      ]);
      expect(display.hiddenCount, 0);
    });

    test('ít phiên: không ẩn phiên còn dùng, chỉ ẩn phiên đã thu hồi', () {
      final display = sessionsForDisplay([
        session('may-nay', lastSeenAgo: Duration.zero, current: true),
        session(
          'thu-hoi',
          lastSeenAgo: const Duration(hours: 1),
          revoked: true,
        ),
      ], expanded: false);

      expect(display.visible.map((item) => item.id), ['may-nay']);
      expect(display.hiddenCount, 1);
    });

    test('máy này luôn hiện dù hoạt động cũ hơn các phiên khác', () {
      final display = sessionsForDisplay([
        session('a', lastSeenAgo: const Duration(minutes: 1)),
        session('b', lastSeenAgo: const Duration(minutes: 2)),
        session('c', lastSeenAgo: const Duration(minutes: 3)),
        session('may-nay', lastSeenAgo: const Duration(days: 3), current: true),
      ], expanded: false);

      expect(display.visible.first.id, 'may-nay');
      expect(display.visible, hasLength(3));
    });
  });

  testWidgets('bấm "Xem tất cả" hiện phiên ẩn, "Thu gọn" ẩn lại', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: SessionListSection(sessions: sessions),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Thiết bị moi-nhat'), findsOneWidget);
    expect(find.text('Thiết bị cu-1'), findsNothing);
    expect(find.text('Thiết bị thu-hoi-moi'), findsNothing);

    await tester.tap(find.text('Xem tất cả 7 phiên'));
    await tester.pumpAndSettle();
    expect(find.text('Thiết bị cu-1'), findsOneWidget);
    expect(find.text('Thiết bị thu-hoi-moi'), findsOneWidget);

    await tester.tap(find.text('Thu gọn'));
    await tester.pumpAndSettle();
    expect(find.text('Thiết bị cu-1'), findsNothing);
    expect(find.text('Xem tất cả 7 phiên'), findsOneWidget);
  });

  testWidgets('không có phiên nào để ẩn thì không hiện nút', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: SessionListSection(
              sessions: [
                session('may-nay', lastSeenAgo: Duration.zero, current: true),
                session('khac', lastSeenAgo: const Duration(hours: 1)),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('session-list-toggle')), findsNothing);
  });
}
