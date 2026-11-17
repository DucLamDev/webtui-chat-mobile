import '../../domain/entities/chat_message.dart';
import '../../domain/entities/conversation_realtime_event.dart';

final class ConversationRealtimeState {
  const ConversationRealtimeState({
    required this.messages,
    this.typingUserIds = const {},
  });

  final List<ChatMessage> messages;
  final Set<String> typingUserIds;
}

/// Nhóm đổi thành viên / bị xoá theo sự kiện realtime.
enum ChannelMembershipChange {
  /// `ChannelArchived`: nhóm bị xoá cho mọi người → bỏ khỏi danh sách, đang mở
  /// thì đóng.
  archived,

  /// `ChannelMemberLeft` của chính mình (rời ở máy khác) → bỏ khỏi danh sách.
  leftByMe,

  /// `ChannelMemberLeft` của người khác → làm mới số thành viên / thông tin.
  memberLeft,
}

final class ConversationRealtimeReducer {
  const ConversationRealtimeReducer();

  /// Sự kiện rời / xoá nhóm ảnh hưởng thế nào tới danh sách nhóm của người
  /// đang dùng. `null` = không phải sự kiện loại này hoặc thiếu `channel_id`.
  /// Không biết người dùng hiện tại thì coi người rời là người khác (chỉ làm
  /// mới), không tự bỏ nhóm.
  ChannelMembershipChange? membershipChange(
    ConversationRealtimeEvent event, {
    required String? currentUserId,
  }) {
    if (event.channelId.trim().isEmpty) return null;
    switch (event.type) {
      case ConversationRealtimeEventType.channelArchived:
        return ChannelMembershipChange.archived;
      case ConversationRealtimeEventType.channelMemberLeft:
        final leaver = event.userId?.trim() ?? '';
        final me = currentUserId?.trim() ?? '';
        return leaver.isNotEmpty && leaver == me
            ? ChannelMembershipChange.leftByMe
            : ChannelMembershipChange.memberLeft;
      default:
        return null;
    }
  }

  /// Khung thread đang mở nhận cùng sự kiện: trả lời mới của luồng [rootId],
  /// sửa / thu hồi / reaction của tin đã có trong luồng. `null` = không đổi.
  List<ChatMessage>? reduceThread({
    required String rootId,
    required List<ChatMessage> messages,
    required ConversationRealtimeEvent event,
    required String? currentUserId,
  }) {
    final message = event.message;
    final messageId = event.messageId ?? message?.id;
    final inThread =
        message != null &&
        (message.parentId == rootId || message.threadRootId == rootId);
    final known =
        messageId != null && messages.any((item) => item.id == messageId);
    if (!inThread && !known) return null;
    return reduce(
      ConversationRealtimeState(messages: messages),
      event,
      currentUserId: currentUserId,
    ).messages;
  }

  ConversationRealtimeState reduce(
    ConversationRealtimeState state,
    ConversationRealtimeEvent event, {
    required String? currentUserId,
  }) {
    final message = event.message;
    final messageId = event.messageId ?? message?.id;
    return switch (event.type) {
      ConversationRealtimeEventType.messageCreated =>
        message == null
            ? state
            : state.copyWith(
                messages: _upsertMessage(
                  state.messages,
                  _withMine(message, currentUserId),
                ),
              ),
      ConversationRealtimeEventType.messageUpdated ||
      ConversationRealtimeEventType.reactionChanged =>
        message == null
            ? state
            : state.copyWith(
                messages: _upsertMessage(
                  state.messages,
                  _withMine(message, currentUserId),
                ),
              ),
      ConversationRealtimeEventType.messageDeleted =>
        messageId == null || messageId.isEmpty
            ? state
            : state.copyWith(messages: _markDeleted(state.messages, messageId)),
      ConversationRealtimeEventType.messagePinned =>
        message == null
            ? state
            : state.copyWith(
                messages: _upsertMessage(
                  state.messages,
                  _withMine(message, currentUserId).copyWith(isPinned: true),
                ),
              ),
      ConversationRealtimeEventType.messageUnpinned =>
        messageId == null || messageId.isEmpty
            ? state
            : state.copyWith(
                messages: _setPinned(state.messages, messageId, false),
              ),
      ConversationRealtimeEventType.attachmentCreated => state,
      // Ghép đoạn chữ do controller làm (cần tải lại tin khi thiếu đoạn).
      ConversationRealtimeEventType.messageDelta => state,
      ConversationRealtimeEventType.transcriptUpdated => state,
      // Vị trí đọc của người kia do bộ điều khiển "Đã xem" xử lý, không đổi tin.
      ConversationRealtimeEventType.channelReadUpdated => state,
      ConversationRealtimeEventType.typingStarted => _typing(
        state,
        event.userId,
        true,
        currentUserId,
      ),
      ConversationRealtimeEventType.typingStopped => _typing(
        state,
        event.userId,
        false,
        currentUserId,
      ),
      ConversationRealtimeEventType.callInvited ||
      ConversationRealtimeEventType.callAccepted ||
      ConversationRealtimeEventType.callReady ||
      ConversationRealtimeEventType.callOffer ||
      ConversationRealtimeEventType.callRenegotiate ||
      ConversationRealtimeEventType.callAnswer ||
      ConversationRealtimeEventType.callIceCandidate ||
      ConversationRealtimeEventType.callRejected ||
      ConversationRealtimeEventType.callCancelled ||
      ConversationRealtimeEventType.callEnded ||
      ConversationRealtimeEventType.callMissed ||
      ConversationRealtimeEventType.callAnsweredElsewhere ||
      ConversationRealtimeEventType.contactRequestCreated ||
      ConversationRealtimeEventType.contactRequestUpdated ||
      ConversationRealtimeEventType.contactRequestCancelled ||
      ConversationRealtimeEventType.noticeChannelCreated ||
      ConversationRealtimeEventType.channelMemberAdded ||
      ConversationRealtimeEventType.channelUpdated ||
      ConversationRealtimeEventType.channelMemberLeft ||
      ConversationRealtimeEventType.channelArchived ||
      ConversationRealtimeEventType.groupCallStarted ||
      ConversationRealtimeEventType.groupCallRingStopped ||
      ConversationRealtimeEventType.groupCallEnded => state,
      ConversationRealtimeEventType.reconnected ||
      ConversationRealtimeEventType.resyncRequired => state,
      ConversationRealtimeEventType.orderTicketUpdated ||
      ConversationRealtimeEventType.inboxConversationUpdated ||
      ConversationRealtimeEventType.inboxMessageCreated => state,
      // Lịch họp đổi: màn Lịch họp tự tải lại, không đổi tin nhắn.
      ConversationRealtimeEventType.meetingUpdated => state,
      // Sự kiện phiên / duyệt thiết bị do home shell xử lý, không đổi phòng chat.
      ConversationRealtimeEventType.sessionRevoked ||
      ConversationRealtimeEventType.deviceApprovalRequested => state,
      ConversationRealtimeEventType.unknown => state,
    };
  }
}

extension on ConversationRealtimeState {
  ConversationRealtimeState copyWith({
    List<ChatMessage>? messages,
    Set<String>? typingUserIds,
  }) {
    return ConversationRealtimeState(
      messages: messages ?? this.messages,
      typingUserIds: typingUserIds ?? this.typingUserIds,
    );
  }
}

List<ChatMessage> _upsertMessage(
  List<ChatMessage> messages,
  ChatMessage incoming,
) {
  final index = messages.indexWhere((message) {
    if (message.id == incoming.id) {
      return true;
    }
    return (message.isLocalOptimistic || incoming.isLocalOptimistic) &&
        incoming.clientMessageId.isNotEmpty &&
        message.clientMessageId == incoming.clientMessageId;
  });
  if (index == -1) {
    final next = [...messages, incoming];
    next.sort((left, right) => left.createdAt.compareTo(right.createdAt));
    return next;
  }
  final next = [...messages];
  final current = next[index];
  // Reaction / ghim / sửa: máy chủ trả tin không kèm danh sách tệp; giữ tệp đã
  // có để ảnh, voice không biến mất khỏi màn hình.
  final keepAttachments =
      incoming.attachments.isEmpty &&
      current.attachments.isNotEmpty &&
      !incoming.isDeleted;
  next[index] = incoming.copyWith(
    attachments: keepAttachments ? current.attachments : null,
    isPinned: incoming.isPinned || current.isPinned,
  );
  return next;
}

List<ChatMessage> _markDeleted(List<ChatMessage> messages, String messageId) {
  return messages
      .map(
        (message) => message.id == messageId
            ? message.copyWith(
                body: '',
                deletedAt: message.deletedAt ?? DateTime.now().toUtc(),
              )
            : message,
      )
      .toList(growable: false);
}

List<ChatMessage> _setPinned(
  List<ChatMessage> messages,
  String messageId,
  bool isPinned,
) {
  return messages
      .map(
        (message) => message.id == messageId
            ? message.copyWith(isPinned: isPinned)
            : message,
      )
      .toList(growable: false);
}

ConversationRealtimeState _typing(
  ConversationRealtimeState state,
  String? userId,
  bool active,
  String? currentUserId,
) {
  final normalized = userId?.trim();
  if (normalized == null ||
      normalized.isEmpty ||
      normalized == currentUserId?.trim()) {
    return state;
  }
  final next = {...state.typingUserIds};
  if (active) {
    next.add(normalized);
  } else {
    next.remove(normalized);
  }
  return state.copyWith(typingUserIds: next);
}

ChatMessage _withMine(ChatMessage message, String? currentUserId) {
  return message.copyWith(
    isMine:
        currentUserId != null &&
        currentUserId.trim().isNotEmpty &&
        message.senderId == currentUserId,
  );
}
