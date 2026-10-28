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

final class ConversationRealtimeReducer {
  const ConversationRealtimeReducer();

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
      ConversationRealtimeEventType.callAnswer ||
      ConversationRealtimeEventType.callIceCandidate ||
      ConversationRealtimeEventType.callRejected ||
      ConversationRealtimeEventType.callCancelled ||
      ConversationRealtimeEventType.callEnded ||
      ConversationRealtimeEventType.callMissed ||
      ConversationRealtimeEventType.contactRequestCreated ||
      ConversationRealtimeEventType.contactRequestUpdated ||
      ConversationRealtimeEventType.contactRequestCancelled => state,
      ConversationRealtimeEventType.reconnected => state,
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
