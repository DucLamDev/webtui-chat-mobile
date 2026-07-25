import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/features/conversations/application/use_cases/conversation_realtime_reducer.dart';
import 'package:webtui_chat/features/conversations/data/repositories/web_socket_conversation_realtime_repository.dart';
import 'package:webtui_chat/features/conversations/domain/entities/chat_message.dart';
import 'package:webtui_chat/features/conversations/domain/entities/conversation_realtime_event.dart';

void main() {
  test('merges message events by id without duplicates', () {
    const reducer = ConversationRealtimeReducer();
    final created = _message(id: 'm1', body: 'Xin chào');
    final edited = _message(
      id: 'm1',
      body: 'Xin chào team',
      editedAt: DateTime.utc(2026, 7, 17, 8, 1),
    );

    final afterCreate = reducer.reduce(
      const ConversationRealtimeState(messages: []),
      ConversationRealtimeEvent(
        type: ConversationRealtimeEventType.messageCreated,
        workspaceId: 'w1',
        channelId: 'c1',
        message: created,
      ),
      currentUserId: 'u1',
    );
    final afterDuplicate = reducer.reduce(
      afterCreate,
      ConversationRealtimeEvent(
        type: ConversationRealtimeEventType.messageCreated,
        workspaceId: 'w1',
        channelId: 'c1',
        message: created,
      ),
      currentUserId: 'u1',
    );
    final afterEdit = reducer.reduce(
      afterDuplicate,
      ConversationRealtimeEvent(
        type: ConversationRealtimeEventType.messageUpdated,
        workspaceId: 'w1',
        channelId: 'c1',
        message: edited,
      ),
      currentUserId: 'u1',
    );

    expect(afterEdit.messages, hasLength(1));
    expect(afterEdit.messages.single.body, 'Xin chào team');
    expect(afterEdit.messages.single.isMine, isTrue);
  });

  test('marks deleted and toggles typing users', () {
    const reducer = ConversationRealtimeReducer();
    final initial = ConversationRealtimeState(messages: [_message(id: 'm1')]);

    final deleted = reducer.reduce(
      initial,
      const ConversationRealtimeEvent(
        type: ConversationRealtimeEventType.messageDeleted,
        workspaceId: 'w1',
        channelId: 'c1',
        messageId: 'm1',
      ),
      currentUserId: 'u1',
    );
    final typing = reducer.reduce(
      deleted,
      const ConversationRealtimeEvent(
        type: ConversationRealtimeEventType.typingStarted,
        workspaceId: 'w1',
        channelId: 'c1',
        userId: 'u2',
      ),
      currentUserId: 'u1',
    );
    final stopped = reducer.reduce(
      typing,
      const ConversationRealtimeEvent(
        type: ConversationRealtimeEventType.typingStopped,
        workspaceId: 'w1',
        channelId: 'c1',
        userId: 'u2',
      ),
      currentUserId: 'u1',
    );

    expect(deleted.messages.single.isDeleted, isTrue);
    expect(typing.typingUserIds, {'u2'});
    expect(stopped.typingUserIds, isEmpty);
  });

  test('maps websocket payload to domain event', () {
    final event = ConversationRealtimeEventMapper.fromSocketData(
      jsonEncode({
        'type': 'ReactionChanged',
        'room': 'workspace:w1:channel:c1',
        'payload': {
          'message': {
            'id': 'm1',
            'workspace_id': 'w1',
            'channel_id': 'c1',
            'sender_id': 'u2',
            'kind': 'text',
            'body': 'Ok',
            'created_at': '2026-07-17T08:00:00Z',
            'reactions': [
              {'emoji': '👍', 'count': 2, 'reacted_by_me': true},
            ],
          },
        },
      }),
      fallbackWorkspaceId: 'w1',
      fallbackChannelId: 'c1',
    );

    expect(event?.type, ConversationRealtimeEventType.reactionChanged);
    expect(event?.message?.reactions.single.count, 2);
    expect(event?.message?.reactions.single.reactedByMe, isTrue);
  });

  test('maps attachment created event with message id', () {
    final event = ConversationRealtimeEventMapper.fromSocketData(
      jsonEncode({
        'type': 'AttachmentCreated',
        'room': 'workspace:w1:channel:c1',
        'payload': {'channel_id': 'c1', 'message_id': 'm-image'},
      }),
      fallbackWorkspaceId: 'w1',
      fallbackChannelId: 'c1',
    );

    expect(event?.type, ConversationRealtimeEventType.attachmentCreated);
    expect(event?.messageId, 'm-image');
  });

  test('maps validated call signaling payloads from the backend', () {
    final offer = ConversationRealtimeEventMapper.fromSocketData(
      jsonEncode({
        'type': 'CallOffer',
        'user_id': 'u1',
        'payload': {
          'call_id': 'call-1',
          'workspace_id': 'w1',
          'channel_id': 'c1',
          'signal': {
            'sdp': {'type': 'offer', 'sdp': 'v=0'},
          },
        },
      }),
      fallbackWorkspaceId: 'w1',
      fallbackChannelId: 'c1',
    );
    final ready = ConversationRealtimeEventMapper.fromSocketData(
      jsonEncode({
        'type': 'CallReady',
        'user_id': 'u2',
        'payload': {
          'call_id': 'call-1',
          'workspace_id': 'w1',
          'channel_id': 'c1',
          'signal': {},
        },
      }),
      fallbackWorkspaceId: 'w1',
      fallbackChannelId: 'c1',
    );

    expect(offer?.type, ConversationRealtimeEventType.callOffer);
    expect(offer?.callSdp, {'type': 'offer', 'sdp': 'v=0'});
    expect(ready?.type, ConversationRealtimeEventType.callReady);
    expect(ready?.callId, 'call-1');
  });

  test('builds websocket URL from public realtime endpoint', () {
    final base = defaultConversationRealtimeWsUri(
      Uri.parse('https://chat.vpsttt.com'),
    );
    final uri = conversationRealtimeWebSocketUri(base, 'access-token');

    expect(base.toString(), 'wss://chat.vpsttt.com/ws');
    expect(
      uri.toString(),
      'wss://chat.vpsttt.com/ws?access_token=access-token',
    );
  });

  test('preserves configured websocket endpoint query params', () {
    final uri = conversationRealtimeWebSocketUri(
      Uri.parse('wss://example.com/custom/ws?workspace_id=w1'),
      'access-token',
    );

    expect(
      uri.toString(),
      'wss://example.com/custom/ws?workspace_id=w1&access_token=access-token',
    );
  });
}

ChatMessage _message({
  required String id,
  String body = 'Xin chào',
  DateTime? editedAt,
}) {
  return ChatMessage(
    id: id,
    workspaceId: 'w1',
    channelId: 'c1',
    kind: 'text',
    body: body,
    senderId: 'u1',
    createdAt: DateTime.utc(2026, 7, 17, 8),
    editedAt: editedAt,
  );
}
