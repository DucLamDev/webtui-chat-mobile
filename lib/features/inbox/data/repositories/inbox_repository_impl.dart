import '../../../../core/result/result.dart';
import '../../../../core/result/result_guard.dart';
import '../../domain/entities/inbox.dart';
import '../../domain/repositories/inbox_repository.dart';
import '../datasources/inbox_remote_data_source.dart';

final class InboxRepositoryImpl implements InboxRepository {
  const InboxRepositoryImpl(this._remote);

  final InboxRemoteDataSource _remote;

  @override
  Future<Result<InboxConversationPage>> listConversations({
    required String workspaceId,
    InboxStatusFilter status = InboxStatusFilter.all,
    InboxAssigneeFilter assignee = InboxAssigneeFilter.all,
    String? cursor,
    int limit = 30,
  }) {
    return guardResult(
      () => _remote.listConversations(
        workspaceId: workspaceId,
        status: status,
        assignee: assignee,
        cursor: cursor,
        limit: limit,
      ),
    );
  }

  @override
  Future<Result<InboxConversation>> getConversation({
    required String workspaceId,
    required String conversationId,
  }) {
    return guardResult(
      () => _remote.getConversation(
        workspaceId: workspaceId,
        conversationId: conversationId,
      ),
    );
  }

  @override
  Future<Result<InboxMessagePage>> listMessages({
    required String workspaceId,
    required String conversationId,
    String? cursor,
    int limit = 30,
  }) {
    return guardResult(
      () => _remote.listMessages(
        workspaceId: workspaceId,
        conversationId: conversationId,
        cursor: cursor,
        limit: limit,
      ),
    );
  }

  @override
  Future<Result<InboxMessage>> sendReply({
    required String workspaceId,
    required String conversationId,
    required String body,
    required String clientMessageId,
  }) {
    return guardResult(
      () => _remote.sendReply(
        workspaceId: workspaceId,
        conversationId: conversationId,
        body: body,
        clientMessageId: clientMessageId,
      ),
    );
  }

  @override
  Future<Result<InboxMessage>> addNote({
    required String workspaceId,
    required String conversationId,
    required String body,
  }) {
    return guardResult(
      () => _remote.addNote(
        workspaceId: workspaceId,
        conversationId: conversationId,
        body: body,
      ),
    );
  }

  @override
  Future<Result<void>> markRead({
    required String workspaceId,
    required String conversationId,
  }) {
    return guardResult(
      () => _remote.markRead(
        workspaceId: workspaceId,
        conversationId: conversationId,
      ),
    );
  }

  @override
  Future<Result<InboxConversation>> update({
    required String workspaceId,
    required String conversationId,
    required InboxConversationChange change,
  }) {
    return guardResult(
      () => _remote.update(
        workspaceId: workspaceId,
        conversationId: conversationId,
        change: change,
      ),
    );
  }

  @override
  Future<Result<List<InboxTag>>> listTags({required String workspaceId}) {
    return guardResult(() => _remote.listTags(workspaceId: workspaceId));
  }
}
