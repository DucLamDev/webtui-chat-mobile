enum ConversationKind { direct, channel }

enum ChannelVisibility { public, private, direct }

enum MembershipStatus { active, muted, invited, left, removed, none }

enum ConversationPresence { online, away, offline }

final class ConversationSummary {
  const ConversationSummary({
    required this.id,
    required this.workspaceId,
    required this.channelId,
    required this.kind,
    required this.title,
    required this.preview,
    required this.updatedAt,
    this.avatarLabel,
    this.avatarUrl,
    this.peerUserId,
    this.unreadCount = 0,
    this.favorite = false,
    this.muted = false,
    this.memberCount = 0,
    this.participantIds = const [],
    this.channelVisibility = ChannelVisibility.public,
    this.membershipStatus = MembershipStatus.none,
    this.canManage = false,
    this.privateSessionMode = false,
  });

  final String id;
  final String workspaceId;
  final String channelId;
  final ConversationKind kind;
  final String title;
  final String preview;
  final String? avatarLabel;
  final String? avatarUrl;
  final String? peerUserId;
  final DateTime updatedAt;
  final int unreadCount;
  final bool favorite;
  final bool muted;
  final int memberCount;
  final List<String> participantIds;
  final ChannelVisibility channelVisibility;
  final MembershipStatus membershipStatus;
  final bool canManage;
  final bool privateSessionMode;

  bool get isUnread => unreadCount > 0;
  bool get isMember =>
      membershipStatus == MembershipStatus.active ||
      membershipStatus == MembershipStatus.muted;
  String? directCallTargetUserId({String? currentUserId}) {
    if (kind != ConversationKind.direct) {
      return null;
    }
    final current = currentUserId?.trim();
    final peer = peerUserId?.trim();
    if (peer != null && peer.isNotEmpty && peer != current) {
      return peer;
    }
    final candidates = participantIds
        .map((participantId) => participantId.trim())
        .where((participantId) => participantId.isNotEmpty)
        .toSet();
    if (current == null || current.isEmpty) {
      return candidates.length == 1 ? candidates.first : null;
    }
    for (final candidate in candidates) {
      if (candidate != current) {
        return candidate;
      }
    }
    return null;
  }

  ConversationSummary copyWith({
    int? unreadCount,
    MembershipStatus? membershipStatus,
  }) {
    return ConversationSummary(
      id: id,
      workspaceId: workspaceId,
      channelId: channelId,
      kind: kind,
      title: title,
      preview: preview,
      updatedAt: updatedAt,
      avatarLabel: avatarLabel,
      avatarUrl: avatarUrl,
      peerUserId: peerUserId,
      unreadCount: unreadCount ?? this.unreadCount,
      favorite: favorite,
      muted: muted,
      memberCount: memberCount,
      participantIds: participantIds,
      channelVisibility: channelVisibility,
      membershipStatus: membershipStatus ?? this.membershipStatus,
      canManage: canManage,
      privateSessionMode: privateSessionMode,
    );
  }
}

final class ConversationHomeData {
  const ConversationHomeData({
    required this.workspaceId,
    required this.conversations,
    required this.channels,
    required this.contacts,
    required this.workspaceMembers,
    this.presenceByUserId = const {},
    this.contactsErrorMessage,
    this.membersErrorMessage,
    this.presenceErrorMessage,
  });

  final String workspaceId;
  final List<ConversationSummary> conversations;
  final List<ConversationSummary> channels;
  final List<ContactSummary> contacts;
  final List<ContactSummary> workspaceMembers;
  final Map<String, ConversationPresence> presenceByUserId;
  final String? contactsErrorMessage;
  final String? membersErrorMessage;
  final String? presenceErrorMessage;
}

final class PresenceSummary {
  const PresenceSummary({
    required this.userId,
    required this.status,
    required this.lastHeartbeatAt,
  });

  final String userId;
  final ConversationPresence status;
  final DateTime lastHeartbeatAt;
}

final class ContactSummary {
  const ContactSummary({
    required this.userId,
    required this.displayName,
    required this.username,
    required this.email,
    required this.status,
    this.avatarUrl,
    this.title,
  });

  final String userId;
  final String displayName;
  final String username;
  final String email;
  final String status;
  final String? avatarUrl;
  final String? title;

  String get searchableText =>
      '$displayName $username $email ${title ?? ''}'.toLowerCase();
}
