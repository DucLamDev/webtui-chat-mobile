import 'call_session.dart';
import 'chat_message.dart';

enum ConversationRealtimeEventType {
  messageCreated,
  messageUpdated,
  messageDeleted,
  messagePinned,
  messageUnpinned,
  reactionChanged,
  attachmentCreated,
  typingStarted,
  typingStopped,
  callInvited,
  callAccepted,
  callReady,
  callOffer,
  callAnswer,
  callIceCandidate,
  callRejected,
  callCancelled,
  callEnded,
  callMissed,

  /// Cuộc gọi đã được nhận ở một máy khác của chính người dùng (gửi vào room cá
  /// nhân của người nhận). Máy khác mã [ConversationRealtimeEvent.answeredDeviceId]
  /// thì tắt chuông, không ghi "cuộc gọi nhỡ".
  callAnsweredElsewhere,
  contactRequestCreated,
  contactRequestUpdated,
  contactRequestCancelled,

  /// Hộp thư ticket khách đổi (phòng `workspace:<ws>:order-tickets`); chi tiết
  /// nằm trong [ConversationRealtimeEvent.payload].
  orderTicketUpdated,

  /// Kết nối realtime vừa nối lại sau khi rớt: tin trong lúc mất kết nối không
  /// được đẩy lại nên màn hình phải tự tải lại.
  reconnected,

  /// Máy chủ sắp ngắt kết nối vì máy này nhận sự kiện quá chậm: phải đồng bộ bù
  /// (`/sync`) rồi nối lại. Kho realtime tự đóng và nối lại kết nối.
  resyncRequired,
  unknown,
}

final class ConversationRealtimeEvent {
  const ConversationRealtimeEvent({
    required this.type,
    required this.workspaceId,
    required this.channelId,
    this.message,
    this.messageId,
    this.userId,
    this.timestamp,
    this.callId,
    this.callMode,
    this.callStatus,
    this.callInitiatorUserId,
    this.callTargetUserId,
    this.reason,
    this.callSdp = const {},
    this.callCandidate = const {},
    this.payload = const {},
    this.eventId,
    this.targetDeviceId,
    this.answeredDeviceId,
    this.initiatorDeviceId,
  });

  final ConversationRealtimeEventType type;
  final String workspaceId;
  final String channelId;
  final ChatMessage? message;
  final String? messageId;
  final String? userId;
  final DateTime? timestamp;
  final String? callId;
  final CallMode? callMode;
  final CallStatus? callStatus;
  final String? callInitiatorUserId;
  final String? callTargetUserId;
  final String? reason;
  final Map<String, dynamic> callSdp;
  final Map<String, dynamic> callCandidate;

  /// Payload gốc, chỉ có với sự kiện ngoài hội thoại
  /// ([ConversationRealtimeEventType.orderTicketUpdated]).
  final Map<String, dynamic> payload;

  /// Mã duy nhất của sự kiện (máy chủ mới) để bỏ sự kiện trùng.
  final String? eventId;

  /// Máy đích của tín hiệu WebRTC do máy chủ điền: khác máy này thì bỏ qua.
  final String? targetDeviceId;

  /// Máy đã nhận cuộc gọi (CallAccepted / CallAnsweredElsewhere).
  final String? answeredDeviceId;
  final String? initiatorDeviceId;

  bool get isCallEvent => switch (type) {
    ConversationRealtimeEventType.callInvited ||
    ConversationRealtimeEventType.callAccepted ||
    ConversationRealtimeEventType.callReady ||
    ConversationRealtimeEventType.callOffer ||
    ConversationRealtimeEventType.callAnswer ||
    ConversationRealtimeEventType.callIceCandidate ||
    ConversationRealtimeEventType.callRejected ||
    ConversationRealtimeEventType.callCancelled ||
    ConversationRealtimeEventType.callEnded ||
    ConversationRealtimeEventType.callMissed ||
    ConversationRealtimeEventType.callAnsweredElsewhere => true,
    _ => false,
  };

  bool get isContactEvent => switch (type) {
    ConversationRealtimeEventType.contactRequestCreated ||
    ConversationRealtimeEventType.contactRequestUpdated ||
    ConversationRealtimeEventType.contactRequestCancelled => true,
    _ => false,
  };

  bool belongsTo({required String workspaceId, required String channelId}) {
    return this.workspaceId == workspaceId && this.channelId == channelId;
  }
}
