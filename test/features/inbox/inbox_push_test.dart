import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/core/notifications/scoped_local_notification_service.dart';
import 'package:webtui_chat/features/inbox/presentation/screens/inbox_list_screen.dart';
import 'package:webtui_chat/features/notifications/domain/entities/mobile_notification.dart';

Map<String, Object?> _push({bool withType = true, bool withLink = true}) => {
  'instance_id': '123e4567-e89b-42d3-a456-426614174000',
  if (withType) 'type': 'inbox_conversation',
  if (withType) 'event_type': 'inbox_conversation',
  'workspace_id': 'ws',
  'conversation_id': 'c1',
  'event_id': 'ev1',
  if (withLink) 'deep_link': 'webtui://inbox/ws/c1',
  'title': 'Khách mới',
  'body': 'Có tin nhắn mới',
};

void main() {
  group('Mở hộp thư khách từ thông báo đẩy', () {
    test('payload nhận ra hội thoại, không coi là kênh chat', () {
      final target = NotificationTarget.fromPayload(
        workspaceId: 'ws',
        data: _push(),
      );
      expect(target.isInboxConversation, isTrue);
      expect(target.inboxConversationId, 'c1');
      expect(target.channelId, isNull);
    });

    test('chỉ có deep link vẫn mở đúng hội thoại', () {
      final target = NotificationTarget.fromPayload(
        workspaceId: 'ws',
        data: {'deep_link': 'webtui://inbox/ws/c1'},
      );
      expect(target.isInboxConversation, isTrue);
      expect(target.inboxConversationId, 'c1');
      expect(target.channelId, isNull);
    });

    test(
      'dữ liệu định tuyến giữ type và conversation_id, không trả lời nhanh',
      () {
        final routing = scopedNotificationRoutingData(_push());
        expect(routing, isNotNull);
        expect(routing!['type'], 'inbox_conversation');
        expect(routing['conversation_id'], 'c1');
        final notification = ScopedLocalNotification.fromData(_push());
        expect(notification.canQuickReply, isFalse);
      },
    );

    test('đường dẫn mở màn hội thoại kèm workspace', () {
      expect(
        inboxConversationLocation(conversationId: 'c1', workspaceId: 'ws'),
        '/inbox/c1?workspaceId=ws',
      );
    });
  });
}
