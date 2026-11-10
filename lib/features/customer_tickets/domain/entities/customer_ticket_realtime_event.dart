import 'customer_ticket.dart';

/// Lý do máy chủ báo hộp thư ticket đổi (`OrderTicketUpdated.reason`).
enum CustomerTicketRealtimeReason {
  messages,
  replied,
  status,
  claim,
  created,
  aiDraft,
  aiDraftFailed,

  /// Kết nối realtime vừa nối lại: sự kiện lúc mất mạng không được gửi lại.
  reconnected,
  unknown,
}

CustomerTicketRealtimeReason customerTicketRealtimeReasonFromApi(String value) {
  return switch (value.trim().toLowerCase()) {
    'messages' => CustomerTicketRealtimeReason.messages,
    'replied' => CustomerTicketRealtimeReason.replied,
    'status' => CustomerTicketRealtimeReason.status,
    'claim' => CustomerTicketRealtimeReason.claim,
    'created' => CustomerTicketRealtimeReason.created,
    'ai_draft' => CustomerTicketRealtimeReason.aiDraft,
    'ai_draft_failed' => CustomerTicketRealtimeReason.aiDraftFailed,
    _ => CustomerTicketRealtimeReason.unknown,
  };
}

final class CustomerTicketRealtimeEvent {
  const CustomerTicketRealtimeEvent({
    required this.reason,
    this.ticketIds = const [],
    this.actorUserId,
    this.counts,
    this.error,
  });

  const CustomerTicketRealtimeEvent.reconnected()
    : reason = CustomerTicketRealtimeReason.reconnected,
      ticketIds = const [],
      actorUserId = null,
      counts = null,
      error = null;

  final CustomerTicketRealtimeReason reason;
  final List<String> ticketIds;
  final String? actorUserId;
  final CustomerTicketCounts? counts;
  final String? error;

  /// Sự kiện không ghi ticket nào (nối lại, đồng bộ chung) coi như liên quan
  /// mọi ticket đang mở.
  bool concerns(String ticketId) {
    return ticketIds.isEmpty || ticketIds.contains(ticketId.trim());
  }

  bool isFromUser(String? userId) {
    final actor = actorUserId?.trim();
    final me = userId?.trim();
    return actor != null && actor.isNotEmpty && actor == me;
  }
}
