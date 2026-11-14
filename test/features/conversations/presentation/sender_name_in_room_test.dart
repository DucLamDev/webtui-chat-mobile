import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/design_system/components/webtui_avatar.dart';
import 'package:webtui_chat/features/conversations/domain/entities/chat_message.dart';
import 'package:webtui_chat/features/conversations/presentation/controllers/message_sender_directory.dart';

import 'chat_room_body_harness.dart';

final _directory = MessageSenderDirectory.fromMembers([
  ChannelMember(
    channelId: 'ch',
    userId: 'peer',
    email: '',
    username: '',
    displayName: 'An Nguyễn',
    status: 'active',
    joinedAt: DateTime.utc(2026),
  ),
]);

List<ChatMessage> _messages() => [
  harnessCall('c1', mine: false, at: harnessTime(9, 0), status: 'ended'),
  harnessText('t1', 'Chào bạn', mine: false, at: harnessTime(9, 1)),
  harnessText('t2', 'Mình của tôi', mine: true, at: harnessTime(9, 2)),
  harnessText('t3', 'Tin sau', mine: false, at: harnessTime(9, 3)),
];

void main() {
  testWidgets(
    'nhắn riêng: chỉ hiện avatar người kia ở tin đầu cụm, không hiện tên',
    (tester) async {
      await pumpChatRoom(
        tester,
        senderDirectory: _directory,
        messages: _messages(),
      );
      expect(find.text('An Nguyễn'), findsNothing);
      // Avatar ở tin đầu cụm (thẻ cuộc gọi) và sau khi mình chen vào; tin liền
      // sau cùng người trong 5 phút thì không lặp.
      expect(find.byType(WebTuiAvatar), findsNWidgets(2));
    },
  );

  testWidgets('nhóm: tên người gửi hiện trên tin đầu cụm, kể cả thẻ cuộc gọi', (
    tester,
  ) async {
    await pumpChatRoom(
      tester,
      directChat: false,
      showSenderNames: true,
      senderDirectory: _directory,
      messages: _messages(),
    );
    expect(find.text('An Nguyễn'), findsNWidgets(2));
    expect(find.byType(WebTuiAvatar), findsNWidgets(2));
  });
}
