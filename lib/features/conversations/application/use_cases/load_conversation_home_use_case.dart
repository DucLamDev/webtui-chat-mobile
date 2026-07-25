import '../../../../core/error/failure.dart';
import '../../../../core/result/result.dart';
import '../../../workspace/domain/repositories/workspace_session_repository.dart';
import '../../domain/entities/conversation_summary.dart';
import '../../domain/repositories/conversation_repository.dart';

final class LoadConversationHomeUseCase {
  const LoadConversationHomeUseCase({
    required ConversationRepository conversationRepository,
    required WorkspaceSessionRepository workspaceSessionRepository,
  }) : _conversationRepository = conversationRepository,
       _workspaceSessionRepository = workspaceSessionRepository;

  final ConversationRepository _conversationRepository;
  final WorkspaceSessionRepository _workspaceSessionRepository;

  Future<Result<ConversationHomeData>> execute({String? workspaceId}) async {
    final activeWorkspaceId =
        workspaceId ??
        await _workspaceSessionRepository.readActiveWorkspaceId();
    if (activeWorkspaceId == null || activeWorkspaceId.isEmpty) {
      return const FailureResult(
        Failure(
          kind: FailureKind.validation,
          message: 'Bạn cần chọn workspace trước khi mở hội thoại.',
          code: 'WORKSPACE_REQUIRED',
        ),
      );
    }

    final directsResult = await _conversationRepository.listDirectConversations(
      workspaceId: activeWorkspaceId,
    );
    if (directsResult case FailureResult<List<ConversationSummary>>()) {
      return FailureResult(directsResult.failure);
    }

    final channelsResult = await _conversationRepository.listChannels(
      workspaceId: activeWorkspaceId,
    );
    if (channelsResult case FailureResult<List<ConversationSummary>>()) {
      return FailureResult(channelsResult.failure);
    }

    final contactsFuture = _conversationRepository.listContacts();
    final membersFuture = _conversationRepository.listWorkspaceMembers(
      workspaceId: activeWorkspaceId,
    );
    final presenceFuture = _conversationRepository.listPresence(
      workspaceId: activeWorkspaceId,
    );
    final contactsResult = await contactsFuture;
    final membersResult = await membersFuture;
    final presenceResult = await presenceFuture;

    return Success(
      ConversationHomeData(
        workspaceId: activeWorkspaceId,
        conversations: _sortByUpdated(directsResult.valueOrNull ?? const []),
        channels: _sortByUpdated(channelsResult.valueOrNull ?? const []),
        contacts: contactsResult.valueOrNull ?? const [],
        workspaceMembers: membersResult.valueOrNull ?? const [],
        presenceByUserId: _presenceByUser(
          presenceResult.valueOrNull ?? const [],
        ),
        contactsErrorMessage: contactsResult.failureOrNull?.message,
        membersErrorMessage:
            membersResult.failureOrNull?.kind == FailureKind.forbidden
            ? 'Bạn chưa có quyền xem danh sách thành viên workspace.'
            : membersResult.failureOrNull?.message,
        presenceErrorMessage: presenceResult.failureOrNull?.message,
      ),
    );
  }
}

Map<String, ConversationPresence> _presenceByUser(List<PresenceSummary> items) {
  final result = <String, ConversationPresence>{};
  for (final item in items) {
    final current = result[item.userId];
    if (current == ConversationPresence.online) {
      continue;
    }
    if (item.status == ConversationPresence.online ||
        current == null ||
        (current == ConversationPresence.offline &&
            item.status == ConversationPresence.away)) {
      result[item.userId] = item.status;
    }
  }
  return Map.unmodifiable(result);
}

List<ConversationSummary> _sortByUpdated(List<ConversationSummary> items) {
  final sorted = [...items];
  sorted.sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
  return sorted;
}
