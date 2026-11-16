import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/features/conversations/domain/entities/chat_message.dart';
import 'package:webtui_chat/features/conversations/presentation/widgets/chat_call_history_card.dart';
import 'package:webtui_chat/features/conversations/presentation/widgets/message_cards/message_card_view.dart';

import 'chat_room_body_harness.dart';

const _ws = '11111111-1111-4111-8111-111111111111';
const _dm = '22222222-2222-4222-8222-222222222222';
const _caller = '33333333-3333-4333-8333-333333333333';

// Đúng dạng máy chủ gửi (notices/application/cards.go: missedCallCard).
ChatMessage _missedCallNotice() => ChatMessage(
  id: 'n1',
  workspaceId: _ws,
  channelId: 'bot',
  kind: 'bot',
  body: 'Cuộc gọi nhỡ từ An Nguyễn',
  createdAt: harnessTime(9, 0),
  senderId: null,
  isMine: false,
  metadata: {
    'card': {
      'version': 2,
      'title': 'Cuộc gọi thoại nhỡ',
      'status': 'warning',
      'status_label': 'Cuộc gọi nhỡ',
      'summary': 'An Nguyễn đã gọi cho bạn.',
      'actions': [
        {
          'type': 'open',
          'label': 'Gọi lại',
          'tone': 'primary',
          'target': {
            'target_type': 'call_back',
            'workspace_id': _ws,
            'channel_id': _dm,
            'user_id': _caller,
            'call_mode': 'audio',
          },
        },
        {
          'type': 'open',
          'label': 'Mở cuộc trò chuyện',
          'tone': 'neutral',
          'target': {
            'target_type': 'conversation',
            'workspace_id': _ws,
            'channel_id': _dm,
          },
        },
      ],
    },
  },
);

void main() {
  testWidgets(
    'bot thông báo: thẻ gọi nhỡ hiện tên người gọi, không thành thẻ cuộc gọi chung',
    (tester) async {
      final calls = <Object>[];
      await pumpChatRoom(
        tester,
        noticeBot: true,
        directChat: false,
        messages: [_missedCallNotice()],
        onCall: calls.add,
      );

      // Trước đây chữ "Cuộc gọi nhỡ từ …" bị đoán là tin cuộc gọi: mất tên, và
      // "Gọi lại" gọi ngay trong phòng bot (máy chủ báo chỉ gọi trong chat 1-1).
      expect(find.byType(ChatCallHistoryCard), findsNothing);
      expect(find.byType(MessageCardView), findsOneWidget);
      expect(find.text('An Nguyễn đã gọi cho bạn.'), findsOneWidget);
      expect(find.text('Gọi lại'), findsOneWidget);
      expect(calls, isEmpty);
    },
  );

  testWidgets('tin cuộc gọi nhỡ trong chat 1-1 vẫn là thẻ cuộc gọi', (
    tester,
  ) async {
    await pumpChatRoom(
      tester,
      messages: [
        harnessCall('c1', mine: false, at: harnessTime(9, 0), status: 'missed'),
      ],
    );
    expect(find.byType(ChatCallHistoryCard), findsOneWidget);
  });
}
