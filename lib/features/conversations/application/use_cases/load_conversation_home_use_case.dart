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

    final directsFuture = _conversationRepository.listDirectConversations(
      workspaceId: activeWorkspaceId,
    );
    final channelsFuture = _conversationRepository.listChannels(
      workspaceId: activeWorkspaceId,
    );
    final contactsFuture = _conversationRepository.listContacts();
    final contactRequestsFuture = _conversationRepository.listContactRequests();
    final membersFuture = _conversationRepository.listWorkspaceMembers(
      workspaceId: activeWorkspaceId,
    );
    final presenceFuture = _conversationRepository.listPresence(
      workspaceId: activeWorkspaceId,
    );

    // All home sections are independent. Fetching them together keeps the
    // first useful content to a single network round trip on mobile.
    final directsResult = await directsFuture;
    if (directsResult case FailureResult<List<ConversationSummary>>()) {
      return FailureResult(directsResult.failure);
    }

    final channelsResult = await channelsFuture;
    if (channelsResult case FailureResult<List<ConversationSummary>>()) {
      return FailureResult(channelsResult.failure);
    }

    final contactsResult = await contactsFuture;
    final contactRequestsResult = await contactRequestsFuture;
    final membersResult = await membersFuture;
    final presenceResult = await presenceFuture;

    return Success(
      ConversationHomeData(
        workspaceId: activeWorkspaceId,
        conversations: _sortByUpdated(directsResult.valueOrNull ?? const []),
        channels: _sortByUpdated(channelsResult.valueOrNull ?? const []),
        contacts: _mergeContactRelationships(
          contactsResult.valueOrNull ?? const [],
          contactRequestsResult.valueOrNull ?? const [],
        ),
        workspaceMembers: membersResult.valueOrNull ?? const [],
        presenceByUserId: _presenceByUser(
          presenceResult.valueOrNull ?? const [],
        ),
        contactsErrorMessage:
            contactsResult.failureOrNull?.message ??
            contactRequestsResult.failureOrNull?.message,
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

List<ContactSummary> _mergeContactRelationships(
  List<ContactSummary> contacts,
  List<ContactSummary> requests,
) {
  final byUserId = <String, ContactSummary>{};
  for (final contact in contacts) {
    byUserId[contact.userId] = contact;
  }
  for (final request in requests) {
    final current = byUserId[request.userId];
    if (current == null || current.contactStatus != 'accepted') {
      byUserId[request.userId] = request;
    }
  }
  final merged = byUserId.values.toList(growable: false);
  final priority = {'accepted': 0, 'pending': 1, 'rejected': 2, 'cancelled': 3};
  merged.sort((left, right) {
    final leftPriority = priority[left.contactStatus] ?? 4;
    final rightPriority = priority[right.contactStatus] ?? 4;
    if (leftPriority != rightPriority) {
      return leftPriority.compareTo(rightPriority);
    }
    return left.displayName.toLowerCase().compareTo(
      right.displayName.toLowerCase(),
    );
  });
  return merged;
}

List<ConversationSummary> _sortByUpdated(List<ConversationSummary> items) {
  final sorted = [...items];
  sorted.sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
  return sorted;
}
