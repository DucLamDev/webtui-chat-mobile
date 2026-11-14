import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/features/conversations/domain/entities/chat_message.dart';
import 'package:webtui_chat/features/conversations/presentation/controllers/message_sender_directory.dart';

import 'chat_room_body_harness.dart';

void main() {
  testWidgets(
    'nhắn riêng: tên người kia hiện trên tin đầu cụm, kể cả thẻ cuộc gọi',
    (tester) async {
      await pumpChatRoom(
        tester,
        senderDirectory: MessageSenderDirectory.fromMembers([
          ChannelMember(
            channelId: 'ch',
            userId: 'peer',
            email: '',
            username: '',
            displayName: 'An Nguyễn',
            status: 'active',
            joinedAt: DateTime.utc(2026),
          ),
        ]),
        messages: [
          harnessCall(
            'c1',
            mine: false,
            at: harnessTime(9, 0),
            status: 'ended',
          ),
          harnessText('t1', 'Chào bạn', mine: false, at: harnessTime(9, 1)),
          harnessText('t2', 'Mình của tôi', mine: true, at: harnessTime(9, 2)),
          harnessText('t3', 'Tin sau', mine: false, at: harnessTime(9, 3)),
        ],
      );
      // Tên hiện ở tin đầu cụm (thẻ cuộc gọi) và sau khi mình chen vào; tin liền
      // sau cùng người trong 5 phút thì không lặp.
      expect(find.text('An Nguyễn'), findsNWidgets(2));
    },
  );
}
