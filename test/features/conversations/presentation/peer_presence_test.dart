import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/features/conversations/domain/entities/conversation_summary.dart';
import 'package:webtui_chat/features/conversations/presentation/controllers/peer_presence.dart';

import 'chat_room_body_harness.dart';

PresenceSummary _presence(ConversationPresence status, DateTime beat) =>
    PresenceSummary(userId: 'peer', status: status, lastHeartbeatAt: beat);

void main() {
  final now = DateTime(2026, 11, 14, 15, 0);

  group('peerPresenceLabel', () {
    test('online: "Đang hoạt động" + chấm xanh', () {
      final label = peerPresenceLabel(
        _presence(ConversationPresence.online, now),
        now,
      );
      expect(label?.text, 'Đang hoạt động');
      expect(label?.online, isTrue);
    });

    test('không có dữ liệu: ẩn dòng phụ và chấm', () {
      expect(peerPresenceLabel(null, now), isNull);
    });

    test('vừa rời: phút, giờ, hôm qua, ngày; không chấm xanh', () {
      String? text(ConversationPresence s, DateTime beat) =>
          peerPresenceLabel(_presence(s, beat), now)?.text;
      const off = ConversationPresence.offline;
      expect(
        text(off, now.subtract(const Duration(seconds: 20))),
        'Vừa hoạt động',
      );
      expect(
        text(off, now.subtract(const Duration(minutes: 12))),
        'Hoạt động 12 phút trước',
      );
      expect(
        text(ConversationPresence.away, now.subtract(const Duration(hours: 3))),
        'Hoạt động 3 giờ trước',
      );
      expect(text(off, DateTime(2026, 11, 13, 23, 0)), 'Hoạt động hôm qua');
      expect(text(off, DateTime(2026, 11, 10, 9, 0)), 'Hoạt động 4 ngày trước');
      expect(text(off, DateTime(2026, 10, 1, 9, 0)), 'Hoạt động 01/10/2026');
      expect(
        peerPresenceLabel(
          _presence(off, now.subtract(const Duration(minutes: 5))),
          now,
        )?.online,
        isFalse,
      );
    });

    test('mốc rỗng (năm cũ) coi như không có dữ liệu', () {
      expect(
        peerPresenceLabel(
          _presence(ConversationPresence.offline, DateTime.utc(1970)),
          now,
        ),
        isNull,
      );
    });
  });

  group('đầu trang theo hiện diện', () {
    testWidgets('không có dữ liệu: không dòng phụ', (tester) async {
      await pumpChatRoom(
        tester,
        messages: const [],
        withAppBar: true,
        presence: null,
      );
      expect(find.text('Đang hoạt động'), findsNothing);
      expect(find.textContaining('Hoạt động'), findsNothing);
    });

    testWidgets('vừa rời: hiện nhãn, không chấm xanh', (tester) async {
      await pumpChatRoom(
        tester,
        messages: const [],
        withAppBar: true,
        presence: const PeerPresenceLabel(
          text: 'Hoạt động 5 phút trước',
          online: false,
        ),
      );
      expect(find.text('Hoạt động 5 phút trước'), findsOneWidget);
      expect(
        find.byType(Container).evaluate().where((e) {
          final w = e.widget as Container;
          final d = w.decoration;
          return d is BoxDecoration && d.color == const Color(0xFF21A875);
        }),
        isEmpty,
      );
    });
  });
}
