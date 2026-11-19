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
    this.gender,
    this.peerUserId,
    this.unreadCount = 0,
    this.favorite = false,
    this.muted = false,
    this.memberCount = 0,
    this.participantIds = const [],
    this.channelVisibility = ChannelVisibility.public,
    this.membershipStatus = MembershipStatus.none,
    this.canManage = false,
    this.canLeave = false,
    this.canDelete = false,
    this.privateSessionMode = false,
    this.isAutomation = false,
    this.noticeBot = false,
    this.slug,
    this.lastMessageAt,
  });

  final String id;
  final String workspaceId;
  final String channelId;
  final ConversationKind kind;
  final String title;
  final String preview;
  final String? avatarLabel;
  final String? avatarUrl;

  /// Giới tính người đối diện (chat 1-1): `male`, `female`, `unspecified`,
  /// thiếu = chưa chọn.
  final String? gender;
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

  /// Máy chủ cho người đang xem rời nhóm này (`can_leave`). Máy chủ cũ không
  /// trả cờ → `false` (ẩn nút "Rời nhóm").
  final bool canLeave;

  /// Máy chủ cho người đang xem xoá (lưu trữ) nhóm cho mọi thành viên
  /// (`can_delete`). Máy chủ cũ không trả cờ → `false`.
  final bool canDelete;
  final bool privateSessionMode;
  final bool isAutomation;

  /// Kênh chat riêng của bot thông báo (chỉ đọc).
  final bool noticeBot;

  /// Mã cố định của kênh do máy chủ đặt (ví dụ `orders`, `gia-han`); không đổi
  /// khi quản trị đổi tên kênh. Tin nhắn riêng và kênh người dùng tạo thường không có.
  final String? slug;

  /// Thời điểm tin (chưa xoá) mới nhất của kênh, máy chủ trả ở
  /// `last_message_at`. `null` khi kênh chưa có tin hoặc máy chủ cũ chưa trả
  /// trường này. Chat 1-1 không dùng (thời điểm tin cuối nằm ở [updatedAt]).
  final DateTime? lastMessageAt;

  /// Kênh đã có tin nhắn (theo [lastMessageAt]).
  bool get hasMessages => lastMessageAt != null;

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
    int? memberCount,
    String? preview,
    DateTime? updatedAt,
    DateTime? lastMessageAt,
    bool? favorite,
    bool? muted,
  }) {
    return ConversationSummary(
      id: id,
      workspaceId: workspaceId,
      channelId: channelId,
      kind: kind,
      title: title,
      preview: preview ?? this.preview,
      updatedAt: updatedAt ?? this.updatedAt,
      avatarLabel: avatarLabel,
      avatarUrl: avatarUrl,
      gender: gender,
      peerUserId: peerUserId,
      unreadCount: unreadCount ?? this.unreadCount,
      favorite: favorite ?? this.favorite,
      muted: muted ?? this.muted,
      memberCount: memberCount ?? this.memberCount,
      participantIds: participantIds,
      channelVisibility: channelVisibility,
      membershipStatus: membershipStatus ?? this.membershipStatus,
      canManage: canManage,
      canLeave: canLeave,
      canDelete: canDelete,
      privateSessionMode: privateSessionMode,
      isAutomation: isAutomation,
      noticeBot: noticeBot,
      slug: slug,
      lastMessageAt: lastMessageAt ?? this.lastMessageAt,
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
    this.isOffline = false,
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

  /// Không kết nối được máy chủ (mạng / hết giờ): danh sách là bản đã lưu
  /// trên máy, màn chỉ báo nhẹ, không hiện màn lỗi.
  final bool isOffline;
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
    this.gender,
    this.title,
    this.contactRequestId,
    this.contactStatus,
    this.contactDirection,
  });

  final String userId;
  final String displayName;
  final String username;
  final String email;
  final String status;
  final String? avatarUrl;
  final String? gender;
  final String? title;
  final String? contactRequestId;
  final String? contactStatus;
  final String? contactDirection;

  bool get hasContactRelationship =>
      contactStatus != null && contactStatus!.trim().isNotEmpty;

  bool get canOpenDirectConversation =>
      !hasContactRelationship || contactStatus?.trim() == 'accepted';

  bool get isPendingContactRequest => contactStatus?.trim() == 'pending';

  bool get isOutgoingContactRequest => contactDirection?.trim() == 'outgoing';

  String get searchableText =>
      '$displayName $username $email ${title ?? ''}'.toLowerCase();
}
