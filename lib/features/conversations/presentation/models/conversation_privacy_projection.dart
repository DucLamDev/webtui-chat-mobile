import '../../domain/entities/conversation_summary.dart';

const blockedConversationPreview =
    'Đã ẩn nội dung từ người dùng bị chặn · Nhấn để quản lý';

final class ConversationPrivacyProjection {
  const ConversationPrivacyProjection({
    required this.preview,
    this.blockedPeerUserId,
  });

  factory ConversationPrivacyProjection.from(
    ConversationSummary conversation,
    Set<String> blockedUserIds, {
    String? currentUserId,
  }) {
    final blockedPeerUserId = blockedDirectPeerUserId(
      conversation,
      blockedUserIds,
      currentUserId: currentUserId,
    );
    return ConversationPrivacyProjection(
      preview: blockedPeerUserId == null
          ? conversation.preview
          : blockedConversationPreview,
      blockedPeerUserId: blockedPeerUserId,
    );
  }

  final String preview;
  final String? blockedPeerUserId;

  bool get isBlocked => blockedPeerUserId != null;
}

String? blockedDirectPeerUserId(
  ConversationSummary conversation,
  Set<String> blockedUserIds, {
  String? currentUserId,
}) {
  if (conversation.kind != ConversationKind.direct || blockedUserIds.isEmpty) {
    return null;
  }
  final normalizedBlockedIds = blockedUserIds
      .map((userId) => userId.trim())
      .where((userId) => userId.isNotEmpty)
      .toSet();
  final peerUserId = conversation.directCallTargetUserId(
    currentUserId: currentUserId,
  );
  if (peerUserId != null && normalizedBlockedIds.contains(peerUserId)) {
    return peerUserId;
  }

  // Some older conversation payloads omit peer_user_id and include both
  // participants. A blocked participant can still be identified without
  // guessing the current user's identity.
  final blockedParticipants = conversation.participantIds
      .map((userId) => userId.trim())
      .where(normalizedBlockedIds.contains)
      .toSet();
  return blockedParticipants.length == 1 ? blockedParticipants.first : null;
}

List<ConversationSummary> privacySafeConversationResults(
  List<ConversationSummary> filteredConversations,
  Set<String> blockedUserIds, {
  required String searchQuery,
}) {
  final query = searchQuery.trim().toLowerCase();
  if (query.isEmpty) {
    return filteredConversations;
  }
  return filteredConversations
      .where((conversation) {
        final projection = ConversationPrivacyProjection.from(
          conversation,
          blockedUserIds,
        );
        if (!projection.isBlocked) {
          return true;
        }
        return '${conversation.title} ${projection.preview}'
            .toLowerCase()
            .contains(query);
      })
      .toList(growable: false);
}
