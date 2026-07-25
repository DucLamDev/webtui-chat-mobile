import '../../domain/entities/channel_file.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/entities/conversation_summary.dart';

final class ChannelDto {
  const ChannelDto({
    required this.id,
    required this.workspaceId,
    required this.name,
    required this.type,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    required this.membershipStatus,
    required this.isMember,
    required this.canManage,
    required this.memberCount,
    required this.privateSessionMode,
    this.slug,
    this.description,
  });

  final String id;
  final String workspaceId;
  final String name;
  final String type;
  final String status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String membershipStatus;
  final bool isMember;
  final bool canManage;
  final int memberCount;
  final bool privateSessionMode;
  final String? slug;
  final String? description;

  factory ChannelDto.fromJson(Map<String, dynamic> json) {
    return ChannelDto(
      id: _string(json['id']),
      workspaceId: _string(json['workspace_id']),
      name: _string(json['name']),
      type: _string(json['type'], fallback: 'public'),
      status: _string(json['status'], fallback: 'active'),
      createdAt: _date(json['created_at']),
      updatedAt: _date(json['updated_at']),
      membershipStatus: _string(json['membership_status'], fallback: 'none'),
      isMember: json['is_member'] == true,
      canManage: json['can_manage'] == true,
      memberCount: _int(json['member_count']),
      privateSessionMode: json['private_session_mode'] == true,
      slug: _nullableString(json['slug']),
      description: _nullableString(json['description']),
    );
  }

  ConversationSummary toDomain() {
    final visibility = _visibilityFrom(type);
    return ConversationSummary(
      id: id,
      workspaceId: workspaceId,
      channelId: id,
      kind: ConversationKind.channel,
      title: name,
      preview: description ?? _channelPreview(visibility, privateSessionMode),
      avatarLabel: name,
      updatedAt: updatedAt,
      muted: membershipStatus == 'muted',
      memberCount: memberCount,
      channelVisibility: visibility,
      membershipStatus: _membershipFrom(membershipStatus),
      canManage: canManage,
      privateSessionMode: privateSessionMode,
    );
  }
}

final class DirectConversationDto {
  const DirectConversationDto({
    required this.id,
    required this.workspaceId,
    required this.channelId,
    required this.conversationType,
    required this.participantIds,
    required this.participants,
    required this.unreadCount,
    required this.createdAt,
    required this.updatedAt,
    this.user,
    this.lastMessage,
  });

  final String id;
  final String workspaceId;
  final String channelId;
  final String conversationType;
  final List<String> participantIds;
  final List<MemberDto> participants;
  final MemberDto? user;
  final MessageSummaryDto? lastMessage;
  final int unreadCount;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory DirectConversationDto.fromJson(Map<String, dynamic> json) {
    final userValue = json['user'];
    final lastMessageValue = json['last_message'];
    return DirectConversationDto(
      id: _string(json['id']),
      workspaceId: _string(json['workspace_id']),
      channelId: _string(json['channel_id']),
      conversationType: _string(
        json['conversation_type'],
        fallback: 'one_to_one',
      ),
      participantIds: _stringList(json['participant_ids']),
      participants: _listOf(
        json['participants'],
      ).map(MemberDto.fromJson).toList(growable: false),
      user: userValue is Map ? MemberDto.fromJson(_mapOf(userValue)) : null,
      lastMessage: lastMessageValue is Map
          ? MessageSummaryDto.fromJson(_mapOf(lastMessageValue))
          : null,
      unreadCount: _int(json['unread_count']),
      createdAt: _date(json['created_at']),
      updatedAt: _date(json['updated_at']),
    );
  }

  ConversationSummary toDomain() {
    final peer = user;
    final title =
        peer?.displayName ??
        participants
            .where((member) => member.displayName.isNotEmpty)
            .map((member) => member.displayName)
            .take(3)
            .join(', ');
    final message = lastMessage;
    return ConversationSummary(
      id: id,
      workspaceId: workspaceId,
      channelId: channelId,
      kind: ConversationKind.direct,
      title: title.isEmpty ? 'Hội thoại riêng' : title,
      preview: message?.body.trim().isNotEmpty == true
          ? message!.body
          : 'Chưa có tin nhắn',
      avatarLabel: title.isEmpty ? 'Hội thoại riêng' : title,
      updatedAt: message?.createdAt ?? updatedAt,
      unreadCount: unreadCount,
      peerUserId: peer?.userId,
      memberCount: participantIds.length,
      participantIds: participantIds,
      channelVisibility: ChannelVisibility.direct,
      membershipStatus: MembershipStatus.active,
    );
  }
}

final class MessageSummaryDto {
  const MessageSummaryDto({
    required this.id,
    required this.workspaceId,
    required this.channelId,
    required this.kind,
    required this.body,
    required this.createdAt,
    required this.updatedAt,
    this.senderId,
  });

  final String id;
  final String workspaceId;
  final String channelId;
  final String kind;
  final String body;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? senderId;

  factory MessageSummaryDto.fromJson(Map<String, dynamic> json) {
    return MessageSummaryDto(
      id: _string(json['id']),
      workspaceId: _string(json['workspace_id']),
      channelId: _string(json['channel_id']),
      kind: _string(json['kind'], fallback: 'text'),
      body: _string(json['body']),
      createdAt: _date(json['created_at']),
      updatedAt: _date(json['updated_at']),
      senderId: _nullableString(json['sender_id']),
    );
  }
}

final class MessageDto {
  const MessageDto({
    required this.id,
    required this.workspaceId,
    required this.channelId,
    required this.kind,
    required this.body,
    required this.createdAt,
    required this.updatedAt,
    required this.reactions,
    this.senderId,
    this.parentId,
    this.threadRootId,
    this.editedAt,
    this.deletedAt,
  });

  final String id;
  final String workspaceId;
  final String channelId;
  final String kind;
  final String body;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<ReactionDto> reactions;
  final String? senderId;
  final String? parentId;
  final String? threadRootId;
  final DateTime? editedAt;
  final DateTime? deletedAt;

  factory MessageDto.fromJson(Map<String, dynamic> json) {
    return MessageDto(
      id: _string(json['id']),
      workspaceId: _string(json['workspace_id']),
      channelId: _string(json['channel_id']),
      kind: _string(json['kind'], fallback: 'text'),
      body: _string(json['body']),
      createdAt: _date(json['created_at']),
      updatedAt: _date(json['updated_at']),
      reactions: _listOf(
        json['reactions'],
      ).map(ReactionDto.fromJson).toList(growable: false),
      senderId: _nullableString(json['sender_id']),
      parentId: _nullableString(json['parent_id']),
      threadRootId: _nullableString(json['thread_root_id']),
      editedAt: _nullableDate(json['edited_at']),
      deletedAt: _nullableDate(json['deleted_at']),
    );
  }

  ChatMessage toDomain({bool isMine = false}) {
    return ChatMessage(
      id: id,
      workspaceId: workspaceId,
      channelId: channelId,
      kind: kind,
      body: deletedAt == null ? body : 'Tin nhắn đã được thu hồi',
      createdAt: createdAt,
      senderId: senderId,
      parentId: parentId,
      threadRootId: threadRootId,
      editedAt: editedAt,
      deletedAt: deletedAt,
      reactions: reactions.map((reaction) => reaction.toDomain()).toList(),
      isMine: isMine,
    );
  }
}

final class ReactionDto {
  const ReactionDto({
    required this.emoji,
    required this.count,
    required this.reactedByMe,
  });

  final String emoji;
  final int count;
  final bool reactedByMe;

  factory ReactionDto.fromJson(Map<String, dynamic> json) {
    return ReactionDto(
      emoji: _string(json['emoji']),
      count: _int(json['count']),
      reactedByMe: json['reacted_by_me'] == true,
    );
  }

  MessageReactionSummary toDomain() {
    return MessageReactionSummary(
      emoji: emoji,
      count: count,
      reactedByMe: reactedByMe,
    );
  }
}

final class MemberDto {
  const MemberDto({
    required this.channelId,
    required this.userId,
    required this.email,
    required this.username,
    required this.displayName,
    required this.status,
    required this.joinedAt,
    this.lastReadMessageId,
  });

  final String channelId;
  final String userId;
  final String email;
  final String username;
  final String displayName;
  final String status;
  final DateTime joinedAt;
  final String? lastReadMessageId;

  factory MemberDto.fromJson(Map<String, dynamic> json) {
    return MemberDto(
      channelId: _string(json['channel_id']),
      userId: _string(json['user_id']),
      email: _string(json['email']),
      username: _string(json['username']),
      displayName: _string(json['display_name']),
      status: _string(json['status'], fallback: 'active'),
      joinedAt: _date(json['joined_at']),
      lastReadMessageId: _nullableString(json['last_read_message_id']),
    );
  }

  ChannelMember toDomain() {
    return ChannelMember(
      channelId: channelId,
      userId: userId,
      email: email,
      username: username,
      displayName: displayName,
      status: status,
      joinedAt: joinedAt,
      lastReadMessageId: lastReadMessageId,
    );
  }
}

final class ContactDto {
  const ContactDto({
    required this.id,
    required this.user,
    required this.status,
  });

  final String id;
  final ContactUserDto user;
  final String status;

  factory ContactDto.fromJson(Map<String, dynamic> json) {
    return ContactDto(
      id: _string(json['id']),
      user: ContactUserDto.fromJson(_mapOf(json['user'])),
      status: _string(json['status'], fallback: 'accepted'),
    );
  }

  ContactSummary toDomain() {
    return user.toDomain(statusOverride: status);
  }
}

final class ContactUserDto {
  const ContactUserDto({
    required this.id,
    required this.email,
    required this.username,
    required this.displayName,
    required this.status,
    this.avatarUrl,
    this.title,
  });

  final String id;
  final String email;
  final String username;
  final String displayName;
  final String status;
  final String? avatarUrl;
  final String? title;

  factory ContactUserDto.fromJson(Map<String, dynamic> json) {
    return ContactUserDto(
      id: _string(json['id'] ?? json['user_id']),
      email: _string(json['email']),
      username: _string(json['username']),
      displayName: _string(json['display_name']),
      status: _string(json['status'], fallback: 'active'),
      avatarUrl: _nullableString(json['avatar_url']),
      title: _nullableString(json['title']),
    );
  }

  ContactSummary toDomain({String? statusOverride}) {
    return ContactSummary(
      userId: id,
      displayName: displayName.isEmpty ? username : displayName,
      username: username,
      email: email,
      status: statusOverride ?? status,
      avatarUrl: avatarUrl,
      title: title,
    );
  }
}

final class WorkspaceMemberDto {
  const WorkspaceMemberDto({
    required this.userId,
    required this.email,
    required this.username,
    required this.displayName,
    required this.status,
    this.title,
  });

  final String userId;
  final String email;
  final String username;
  final String displayName;
  final String status;
  final String? title;

  factory WorkspaceMemberDto.fromJson(Map<String, dynamic> json) {
    return WorkspaceMemberDto(
      userId: _string(json['user_id']),
      email: _string(json['email']),
      username: _string(json['username']),
      displayName: _string(json['display_name']),
      status: _string(json['status'], fallback: 'active'),
      title: _nullableString(json['title']),
    );
  }

  ContactSummary toDomain() {
    return ContactSummary(
      userId: userId,
      displayName: displayName.isEmpty ? username : displayName,
      username: username,
      email: email,
      status: status,
      title: title,
    );
  }
}

final class ChannelFileDto {
  const ChannelFileDto({
    required this.id,
    required this.name,
    required this.mimeType,
    required this.byteSize,
    required this.createdAt,
  });

  final String id;
  final String name;
  final String mimeType;
  final int byteSize;
  final DateTime createdAt;

  factory ChannelFileDto.fromJson(Map<String, dynamic> json) {
    return ChannelFileDto(
      id: _string(json['id']),
      name: _string(json['original_name'] ?? json['name']),
      mimeType: _string(json['mime_type']),
      byteSize: _int(json['byte_size']),
      createdAt: _date(json['created_at']),
    );
  }

  ChannelFile toDomain() {
    return ChannelFile(
      id: id,
      name: name,
      mimeType: mimeType,
      byteSize: byteSize,
      createdAt: createdAt,
    );
  }
}

List<ChannelDto> channelsFromEnvelope(Object? envelope) {
  final data = _unwrapDataMap(envelope);
  return _listOf(
    data['channels'],
  ).map(ChannelDto.fromJson).toList(growable: false);
}

ChannelDto channelFromEnvelope(Object? envelope) {
  return ChannelDto.fromJson(_unwrapDataMap(envelope));
}

List<DirectConversationDto> directConversationsFromEnvelope(Object? envelope) {
  final data = _unwrapDataMap(envelope);
  return _listOf(
    data['direct_conversations'],
  ).map(DirectConversationDto.fromJson).toList(growable: false);
}

DirectConversationDto directConversationFromEnvelope(Object? envelope) {
  return DirectConversationDto.fromJson(_unwrapDataMap(envelope));
}

List<MessageDto> messagesFromEnvelope(Object? envelope) {
  final data = _unwrapDataMap(envelope);
  return _listOf(
    data['messages'],
  ).map(MessageDto.fromJson).toList(growable: false);
}

MessageDto messageFromEnvelope(Object? envelope) {
  return MessageDto.fromJson(_unwrapDataMap(envelope));
}

List<MemberDto> membersFromEnvelope(Object? envelope, String key) {
  final data = _unwrapDataMap(envelope);
  return _listOf(data[key]).map(MemberDto.fromJson).toList(growable: false);
}

MemberDto memberFromEnvelope(Object? envelope) {
  return MemberDto.fromJson(_unwrapDataMap(envelope));
}

List<ContactDto> contactsFromEnvelope(Object? envelope) {
  final data = _unwrapDataMap(envelope);
  return _listOf(
    data['contacts'],
  ).map(ContactDto.fromJson).toList(growable: false);
}

List<WorkspaceMemberDto> workspaceMembersFromEnvelope(Object? envelope) {
  final data = _unwrapDataMap(envelope);
  return _listOf(
    data['members'],
  ).map(WorkspaceMemberDto.fromJson).toList(growable: false);
}

List<ChannelFileDto> filesFromEnvelope(Object? envelope) {
  final data = _unwrapDataMap(envelope);
  return _listOf(
    data['files'],
  ).map(ChannelFileDto.fromJson).toList(growable: false);
}

Map<String, dynamic> _unwrapDataMap(Object? envelope) {
  final root = _mapOf(envelope);
  final data = root.containsKey('data') ? root['data'] : root;
  return _mapOf(data);
}

List<Map<String, dynamic>> _listOf(Object? value) {
  if (value is! List) {
    return const [];
  }
  return value.map(_mapOf).toList(growable: false);
}

Map<String, dynamic> _mapOf(Object? value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return Map<String, dynamic>.from(value);
  }
  throw const FormatException('Expected JSON object.');
}

String _string(Object? value, {String fallback = ''}) {
  return value?.toString() ?? fallback;
}

String? _nullableString(Object? value) {
  final text = value?.toString().trim();
  if (text == null || text.isEmpty) {
    return null;
  }
  return text;
}

int _int(Object? value) {
  if (value is int) {
    return value;
  }
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

List<String> _stringList(Object? value) {
  if (value is! List) {
    return const [];
  }
  return value.map((item) => item.toString()).toList(growable: false);
}

DateTime _date(Object? value) {
  return _nullableDate(value) ??
      DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
}

DateTime? _nullableDate(Object? value) {
  final text = value?.toString();
  if (text == null || text.isEmpty) {
    return null;
  }
  return DateTime.tryParse(text)?.toUtc();
}

ChannelVisibility _visibilityFrom(String value) {
  return switch (value) {
    'private' => ChannelVisibility.private,
    'direct' => ChannelVisibility.direct,
    _ => ChannelVisibility.public,
  };
}

MembershipStatus _membershipFrom(String value) {
  return switch (value) {
    'active' => MembershipStatus.active,
    'muted' => MembershipStatus.muted,
    'invited' => MembershipStatus.invited,
    'left' => MembershipStatus.left,
    'removed' => MembershipStatus.removed,
    _ => MembershipStatus.none,
  };
}

String _channelPreview(ChannelVisibility visibility, bool privateSessionMode) {
  if (privateSessionMode) {
    return 'Kênh tạo phiên riêng cho từng người dùng';
  }
  return switch (visibility) {
    ChannelVisibility.private => 'Kênh riêng tư trong workspace',
    ChannelVisibility.direct => 'Hội thoại riêng',
    ChannelVisibility.public => 'Kênh công khai trong workspace',
  };
}
