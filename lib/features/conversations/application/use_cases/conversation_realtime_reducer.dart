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
      ConversationRealtimeEventType.callMissed => state,
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
  final index = messages.indexWhere((message) => message.id == incoming.id);
  if (index == -1) {
    final next = [...messages, incoming];
    next.sort((left, right) => left.createdAt.compareTo(right.createdAt));
    return next;
  }
  final next = [...messages];
  next[index] = incoming.copyWith(
    isPinned: incoming.isPinned || next[index].isPinned,
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
