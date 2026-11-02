import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/features/notifications/domain/entities/mobile_notification.dart';

void main() {
  test('thông báo giao việc mở tab Task, kèm mã việc', () {
    final target = NotificationTarget.fromPayload(
      workspaceId: 'ws-1',
      channelId: 'ch-1',
      data: const {
        'target_type': 'task',
        'event_type': 'task_assigned',
        'task_id': 'task-1',
      },
    );

    expect(target.opensTasks, isTrue);
    expect(target.taskId, 'task-1');
    expect(target.canOpenConversation, isTrue);
  });

  test(
    'deep link webtui://chat/conversations/..?tool=tasks cũng mở tab Task',
    () {
      final target = NotificationTarget.fromPayload(
        workspaceId: 'ws-1',
        data: const {
          'deep_link':
              'webtui://chat/conversations/ch-1?workspaceId=ws-1&tool=tasks&taskId=task-2',
        },
      );

      expect(target.channelId, 'ch-1');
      expect(target.opensTasks, isTrue);
      expect(target.taskId, 'task-2');
    },
  );

  test('thông báo tin nhắn thường không mở tab Task', () {
    final target = NotificationTarget.fromPayload(
      workspaceId: 'ws-1',
      channelId: 'ch-1',
      data: const {'target_type': 'message'},
    );

    expect(target.opensTasks, isFalse);
    expect(target.taskId, isNull);
  });
}
