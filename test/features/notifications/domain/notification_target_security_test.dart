import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/features/notifications/domain/entities/mobile_notification.dart';

void main() {
  test('accepts internal conversation deep link target', () {
    final target = NotificationTarget.fromPayload(
      workspaceId: 'workspace-1',
      data: const {
        'deep_link':
            'webtui://chat/conversations/channel-1?messageId=message-1',
      },
    );

    expect(target.workspaceId, 'workspace-1');
    expect(target.channelId, 'channel-1');
    expect(target.messageId, 'message-1');
    expect(target.canOpenConversation, isTrue);
  });

  test('ignores external deep link target from push payload', () {
    final target = NotificationTarget.fromPayload(
      workspaceId: 'workspace-1',
      data: const {
        'deep_link':
            'https://evil.example/conversations/channel-1?messageId=message-1',
      },
    );

    expect(target.workspaceId, 'workspace-1');
    expect(target.channelId, isNull);
    expect(target.messageId, isNull);
    expect(target.deepLink, isNull);
    expect(target.canOpenConversation, isFalse);
  });
}
