import '../../../../core/result/result.dart';
import '../entities/channel_file.dart';
import '../entities/chat_message.dart';
import '../entities/conversation_realtime_event.dart';
import '../entities/conversation_summary.dart';

abstract interface class ConversationRepository {
  Future<Result<List<ConversationSummary>>> listDirectConversations({
    required String workspaceId,
  });

  Future<Result<List<ConversationSummary>>> listChannels({
    required String workspaceId,
  });

  Future<Result<List<ContactSummary>>> listContacts();

  Future<Result<List<ContactSummary>>> listWorkspaceMembers({
    required String workspaceId,
  });

  Future<Result<List<PresenceSummary>>> listPresence({
    required String workspaceId,
  });

  Future<Result<void>> updatePresence({
    required String workspaceId,
    required String deviceId,
    required ConversationPresence status,
    required String platform,
  });

  Future<Result<ConversationSummary>> getChannel({
    required String workspaceId,
    required String channelId,
  });

  Future<Result<ConversationSummary>> createChannel({
    required String workspaceId,
    required String slug,
    required String name,
    required String description,
    required ChannelVisibility visibility,
  });

  Future<Result<ChannelMember>> requestJoinChannel({
    required String workspaceId,
    required String channelId,
  });

  Future<Result<ConversationSummary>> openPrivateSession({
    required String workspaceId,
    required String channelId,
  });

  Future<Result<ConversationSummary>> createDirectConversation({
    required String workspaceId,
    required List<String> participantIds,
  });

  Future<Result<void>> markRead({
    required String workspaceId,
    required String channelId,
    required String lastReadMessageId,
  });

  Future<Result<List<ChannelMember>>> listMembers({
    required String workspaceId,
    required String channelId,
  });

  Future<Result<ChannelMember>> addMember({
    required String workspaceId,
    required String channelId,
    required String userId,
  });

  Future<Result<List<ChannelMember>>> listJoinRequests({
    required String workspaceId,
    required String channelId,
  });

  Future<Result<ChannelMember>> approveJoinRequest({
    required String workspaceId,
    required String channelId,
    required String userId,
  });

  Future<Result<void>> rejectJoinRequest({
    required String workspaceId,
    required String channelId,
    required String userId,
  });

  Future<Result<List<ChatMessage>>> listMessages({
    required String workspaceId,
    required String channelId,
    int limit = 50,
    String? beforeId,
  });

  Future<Result<MessagePage>> listMessagePage({
    required String workspaceId,
    required String channelId,
    int limit = 50,
    String? beforeId,
  });

  Future<Result<List<ChatMessage>>> searchMessages({
    required String workspaceId,
    required String query,
    String? channelId,
    String? senderId,
    String? kind,
    DateTime? dateFrom,
    DateTime? dateTo,
    int limit = 30,
  });

  Future<Result<MessagePage>> searchMessagePage({
    required String workspaceId,
    required String query,
    String? channelId,
    String? senderId,
    String? kind,
    DateTime? dateFrom,
    DateTime? dateTo,
    int limit = 30,
  });

  Future<Result<MessagePage>> listThread({
    required String workspaceId,
    required String channelId,
    required String messageId,
    int limit = 50,
  });

  Future<Result<List<ChatMessage>>> listPins({
    required String workspaceId,
    required String channelId,
  });

  Future<Result<ChatMessage>> sendMessage({
    required String workspaceId,
    required String channelId,
    required String body,
    String? clientMessageId,
    String? parentId,
  });

  Future<Result<ChatMessage>> editMessage({
    required String workspaceId,
    required String channelId,
    required String messageId,
    required String body,
  });

  Future<Result<void>> deleteMessage({
    required String workspaceId,
    required String channelId,
    required String messageId,
  });

  Future<Result<ChatMessage>> addReaction({
    required String workspaceId,
    required String channelId,
    required String messageId,
    required String emoji,
  });

  Future<Result<ChatMessage>> removeReaction({
    required String workspaceId,
    required String channelId,
    required String messageId,
    required String emoji,
  });

  Future<Result<ChatMessage>> pinMessage({
    required String workspaceId,
    required String channelId,
    required String messageId,
  });

  Future<Result<void>> unpinMessage({
    required String workspaceId,
    required String channelId,
    required String messageId,
  });

  Future<Result<ChatMessage>> forwardMessage({
    required String workspaceId,
    required String channelId,
    required String messageId,
    required String targetChannelId,
  });

  Future<Result<List<ChannelFile>>> listFiles({
    required String workspaceId,
    int limit = 40,
  });
}

abstract interface class ConversationRealtimeRepository {
  Stream<ConversationRealtimeEvent> subscribeToChannel({
    required String workspaceId,
    required String channelId,
  });

  Future<void> sendTyping({
    required String workspaceId,
    required String channelId,
    required bool isTyping,
  });

  Future<void> disconnect();
}

abstract interface class ConversationDraftRepository {
  Future<String> readDraft({
    required String workspaceId,
    required String channelId,
  });

  Future<void> saveDraft({
    required String workspaceId,
    required String channelId,
    required String body,
  });

  Future<void> clearDraft({
    required String workspaceId,
    required String channelId,
  });
}
