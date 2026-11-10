import '../../../../core/result/result.dart';
import '../entities/inbox.dart';

abstract interface class InboxRepository {
  Future<Result<InboxConversationPage>> listConversations({
    required String workspaceId,
    InboxStatusFilter status = InboxStatusFilter.all,
    InboxAssigneeFilter assignee = InboxAssigneeFilter.all,
    String? cursor,
    int limit = 30,
  });

  Future<Result<InboxConversation>> getConversation({
    required String workspaceId,
    required String conversationId,
  });

  Future<Result<InboxMessagePage>> listMessages({
    required String workspaceId,
    required String conversationId,
    String? cursor,
    int limit = 30,
  });

  /// Gửi lại với cùng [clientMessageId] khi lỗi mạng: máy chủ trả lại tin cũ.
  Future<Result<InboxMessage>> sendReply({
    required String workspaceId,
    required String conversationId,
    required String body,
    required String clientMessageId,
  });

  Future<Result<InboxMessage>> addNote({
    required String workspaceId,
    required String conversationId,
    required String body,
  });

  Future<Result<void>> markRead({
    required String workspaceId,
    required String conversationId,
  });

  Future<Result<InboxConversation>> update({
    required String workspaceId,
    required String conversationId,
    required InboxConversationChange change,
  });

  Future<Result<List<InboxTag>>> listTags({required String workspaceId});
}

abstract interface class InboxRealtimeRepository {
  Stream<InboxRealtimeEvent> watch({required String workspaceId});
}
