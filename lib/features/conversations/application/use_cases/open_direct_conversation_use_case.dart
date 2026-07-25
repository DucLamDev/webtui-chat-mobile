import '../../../../core/error/failure.dart';
import '../../../../core/result/result.dart';
import '../../domain/entities/conversation_summary.dart';
import '../../domain/repositories/conversation_repository.dart';

final class OpenDirectConversationUseCase {
  const OpenDirectConversationUseCase(this._repository);

  final ConversationRepository _repository;

  Future<Result<ConversationSummary>> execute({
    required String workspaceId,
    required List<String> participantIds,
  }) async {
    final normalized = _normalizedParticipantIds(participantIds);
    if (normalized.isEmpty) {
      return const FailureResult(
        Failure(
          kind: FailureKind.validation,
          message: 'Bạn cần chọn ít nhất một người để mở hội thoại.',
          code: 'DIRECT_PARTICIPANTS_REQUIRED',
        ),
      );
    }

    final existingResult = await _repository.listDirectConversations(
      workspaceId: workspaceId,
    );
    if (existingResult case Success<List<ConversationSummary>>(
      value: final existing,
    )) {
      final match = DirectConversationDeduplicator.findExisting(
        existing,
        normalized,
      );
      if (match != null) {
        return Success(match);
      }
    }

    return _repository.createDirectConversation(
      workspaceId: workspaceId,
      participantIds: normalized,
    );
  }
}

final class DirectConversationDeduplicator {
  const DirectConversationDeduplicator._();

  static ConversationSummary? findExisting(
    List<ConversationSummary> conversations,
    List<String> participantIds,
  ) {
    final desired = _normalizedParticipantIds(participantIds);
    if (desired.length != 1) {
      return null;
    }

    final peerId = desired.single;
    for (final conversation in conversations) {
      if (conversation.kind != ConversationKind.direct) {
        continue;
      }
      if (conversation.participantIds.contains(peerId)) {
        return conversation;
      }
    }
    return null;
  }
}

List<String> _normalizedParticipantIds(List<String> participantIds) {
  final ids = participantIds
      .map((id) => id.trim())
      .where((id) => id.isNotEmpty)
      .toSet()
      .toList(growable: false);
  ids.sort();
  return ids;
}
