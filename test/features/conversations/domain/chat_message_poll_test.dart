import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/features/conversations/domain/entities/chat_message.dart';

void main() {
  test('recognizes a poll event from message metadata', () {
    final message = ChatMessage(
      id: 'message-1',
      workspaceId: 'workspace-1',
      channelId: 'channel-1',
      kind: 'event',
      body: 'Chọn lịch họp',
      createdAt: DateTime.utc(2026, 7, 26),
      senderId: 'user-1',
      metadata: const {
        'message_type': 'poll',
        'poll': {
          'question': 'Chọn lịch họp',
          'options': [
            {'id': 'option-1', 'label': 'Thứ hai', 'reaction': '1️⃣'},
            {'id': 'option-2', 'label': 'Thứ ba', 'reaction': '2️⃣'},
          ],
        },
      },
    );

    expect(message.isPoll, isTrue);
  });

  test('does not treat a regular event as a poll', () {
    final message = ChatMessage(
      id: 'message-2',
      workspaceId: 'workspace-1',
      channelId: 'channel-1',
      kind: 'event',
      body: 'Cuộc gọi đã kết thúc',
      createdAt: DateTime.utc(2026, 7, 26),
      metadata: const {'message_type': 'call'},
    );

    expect(message.isPoll, isFalse);
  });

  test('recognizes a call event from message metadata', () {
    final message = ChatMessage(
      id: 'message-3',
      workspaceId: 'workspace-1',
      channelId: 'channel-1',
      kind: 'event',
      body: 'Cuộc gọi video đã kết thúc',
      createdAt: DateTime.utc(2026, 8, 25),
      metadata: const {
        'message_type': 'call',
        'call_mode': 'video',
        'call_status': 'completed',
        'duration_seconds': 277,
      },
    );

    expect(message.isCallEvent, isTrue);
    expect(message.callMode, 'video');
    expect(message.callStatus, 'completed');
    expect(message.callDurationSeconds, 277);
  });
}
