import '../../../../core/network/api_response.dart';
import '../../../conversations/domain/entities/conversation_realtime_event.dart';
import '../../domain/entities/inbox.dart';
import '../../domain/repositories/inbox_repository.dart';
import '../datasources/inbox_remote_data_source.dart';

typedef InboxRoomSubscriber =
    Stream<ConversationRealtimeEvent> Function({required String workspaceId});

/// Nhận `InboxConversationUpdated` / `InboxMessageCreated` qua kết nối
/// WebSocket (phòng người dùng) và đổi sang sự kiện của hộp thư khách.
final class WebSocketInboxRealtimeRepository
    implements InboxRealtimeRepository {
  const WebSocketInboxRealtimeRepository(this._subscribe);

  final InboxRoomSubscriber _subscribe;

  @override
  Stream<InboxRealtimeEvent> watch({required String workspaceId}) {
    return _subscribe(workspaceId: workspaceId.trim())
        .map(inboxRealtimeEventFrom)
        .where((event) => event != null)
        .cast<InboxRealtimeEvent>();
  }
}

InboxRealtimeEvent? inboxRealtimeEventFrom(ConversationRealtimeEvent event) {
  switch (event.type) {
    case ConversationRealtimeEventType.reconnected:
      return const InboxRealtimeReconnected();
    case ConversationRealtimeEventType.inboxConversationUpdated:
      final map = jsonMap(field(event.payload, const ['conversation']));
      final conversation = inboxConversationFromMap(map);
      return conversation.id.isEmpty
          ? null
          : InboxConversationUpdatedEvent(conversation);
    case ConversationRealtimeEventType.inboxMessageCreated:
      final map = jsonMap(field(event.payload, const ['message']));
      final message = inboxMessageFromMap({
        ...map,
        if (nullableStringField(map, const ['conversation_id']) == null)
          'conversation_id': event.payload['conversation_id'],
      });
      return message.id.isEmpty ? null : InboxMessageCreatedEvent(message);
    default:
      return null;
  }
}
