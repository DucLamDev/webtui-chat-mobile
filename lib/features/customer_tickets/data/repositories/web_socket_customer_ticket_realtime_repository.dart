import '../../../../core/network/api_response.dart';
import '../../../conversations/domain/entities/conversation_realtime_event.dart';
import '../../domain/entities/customer_ticket_realtime_event.dart';
import '../../domain/repositories/customer_ticket_repository.dart';
import '../datasources/customer_ticket_remote_data_source.dart';

typedef OrderTicketRoomSubscriber =
    Stream<ConversationRealtimeEvent> Function({required String workspaceId});

/// Nhận `OrderTicketUpdated` qua kết nối WebSocket sẵn có của app (phòng
/// `workspace:<ws>:order-tickets`) và đổi sang sự kiện của tính năng ticket.
final class WebSocketCustomerTicketRealtimeRepository
    implements CustomerTicketRealtimeRepository {
  const WebSocketCustomerTicketRealtimeRepository(this._subscribe);

  final OrderTicketRoomSubscriber _subscribe;

  @override
  Stream<CustomerTicketRealtimeEvent> watch({required String workspaceId}) {
    return _subscribe(workspaceId: workspaceId.trim())
        .map(customerTicketRealtimeEventFrom)
        .where((event) => event != null)
        .cast<CustomerTicketRealtimeEvent>();
  }
}

CustomerTicketRealtimeEvent? customerTicketRealtimeEventFrom(
  ConversationRealtimeEvent event,
) {
  if (event.type == ConversationRealtimeEventType.reconnected) {
    return const CustomerTicketRealtimeEvent.reconnected();
  }
  if (event.type != ConversationRealtimeEventType.orderTicketUpdated) {
    return null;
  }
  final payload = jsonMap(event.payload);
  final ids = field(payload, const ['ticket_ids', 'ticketIds']);
  return CustomerTicketRealtimeEvent(
    reason: customerTicketRealtimeReasonFromApi(
      stringField(payload, const ['reason']),
    ),
    ticketIds: ids is List
        ? ids
              .map((value) => value?.toString().trim() ?? '')
              .where((value) => value.isNotEmpty)
              .toList(growable: false)
        : const [],
    actorUserId: nullableStringField(payload, const [
      'actor_user_id',
      'actorUserId',
    ]),
    counts: customerTicketCountsFromJson(field(payload, const ['counts'])),
    error: nullableStringField(payload, const ['error']),
  );
}
