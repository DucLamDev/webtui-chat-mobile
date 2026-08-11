import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/core/notifications/push_notification_service.dart';
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

  test('same workspace/channel IDs from server A never match active B', () {
    const instanceA = '11111111-1111-4111-8111-111111111111';
    const instanceB = '22222222-2222-4222-8222-222222222222';
    final target = NotificationTarget.fromPayload(
      workspaceId: 'workspace-shared',
      channelId: 'channel-shared',
      data: const {'instance_id': instanceA},
    );

    expect(target.isBoundToInstance(instanceA), isTrue);
    expect(target.isBoundToInstance(instanceB), isFalse);
    expect(
      notificationInstanceMatches(
        payloadInstanceId: target.instanceId,
        activeInstanceId: instanceB,
      ),
      isFalse,
    );
    expect(
      notificationInstanceMatches(
        payloadInstanceId: null,
        activeInstanceId: instanceB,
      ),
      isFalse,
    );
  });
}
