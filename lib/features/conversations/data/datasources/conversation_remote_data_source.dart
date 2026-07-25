import 'package:dio/dio.dart';

import '../../../../core/network/api_response.dart';
import '../../../../core/network/api_transport.dart';
import '../../domain/entities/channel_file.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/entities/conversation_summary.dart';

final class ConversationRemoteDataSource {
  const ConversationRemoteDataSource(this._api);

  final ApiTransport _api;

  Future<List<ConversationSummary>> listDirectConversations({
    required String workspaceId,
  }) async {
    final response = await _api.get<Object>(
      '/api/v1/workspaces/${_e(workspaceId)}/direct-conversations',
    );
    return envelopeList(
      response.data,
      'direct_conversations',
    ).map(_directConversationFromMap).toList(growable: false);
  }

  Future<List<ConversationSummary>> listChannels({
    required String workspaceId,
  }) async {
    final response = await _api.get<Object>(
      '/api/v1/workspaces/${_e(workspaceId)}/channels',
    );
    return envelopeList(
      response.data,
      'channels',
    ).map(_channelFromMap).toList(growable: false);
  }

  Future<List<ContactSummary>> listContacts() async {
    final response = await _api.get<Object>('/api/v1/contacts');
    return envelopeList(
      response.data,
      'contacts',
    ).map(_contactFromMap).toList(growable: false);
  }

  Future<List<ContactSummary>> listWorkspaceMembers({
    required String workspaceId,
  }) async {
    final response = await _api.get<Object>(
      '/api/v1/workspaces/${_e(workspaceId)}/members',
    );
    return envelopeList(
      response.data,
      'members',
    ).map(_workspaceMemberFromMap).toList(growable: false);
  }

  Future<List<PresenceSummary>> listPresence({
    required String workspaceId,
  }) async {
    final response = await _api.get<Object>(
      '/api/v1/workspaces/${_e(workspaceId)}/presence',
      queryParameters: const {'limit': 200},
    );
    return envelopeList(
      response.data,
      'presence',
    ).map(_presenceFromMap).toList(growable: false);
  }

  Future<void> updatePresence({
    required String workspaceId,
    required String deviceId,
    required ConversationPresence status,
    required String platform,
  }) async {
    await _api.put<Object>(
      '/api/v1/workspaces/${_e(workspaceId)}/presence/heartbeat',
      data: {
        'device_id': deviceId,
        'status': status.name,
        'metadata': {'platform': platform},
      },
    );
  }

  Future<ConversationSummary> getChannel({
    required String workspaceId,
    required String channelId,
  }) async {
    final response = await _api.get<Object>(
      '/api/v1/workspaces/${_e(workspaceId)}/channels/${_e(channelId)}',
    );
    return _channelFromMap(envelopeItem(response.data, 'channel'));
  }

  Future<ConversationSummary> createChannel({
    required String workspaceId,
    required String slug,
    required String name,
    required String description,
    required ChannelVisibility visibility,
  }) async {
    final response = await _api.post<Object>(
      '/api/v1/workspaces/${_e(workspaceId)}/channels',
      data: compactMap({
        'slug': slug,
        'name': name,
        'description': description,
        'type': _visibilityToApi(visibility),
      }),
    );
    return _channelFromMap(envelopeItem(response.data, 'channel'));
  }

  Future<ChannelMember> requestJoinChannel({
    required String workspaceId,
    required String channelId,
  }) async {
    final response = await _api.post<Object>(
      '/api/v1/workspaces/${_e(workspaceId)}/channels/${_e(channelId)}/join-requests',
      data: const {},
    );
    return _channelMemberFromMap(
      envelopeItem(response.data, 'member'),
      channelId: channelId,
    );
  }

  Future<ConversationSummary> openPrivateSession({
    required String workspaceId,
    required String channelId,
  }) async {
    final response = await _api.post<Object>(
      '/api/v1/workspaces/${_e(workspaceId)}/channels/${_e(channelId)}/private-session',
      data: const {},
    );
    return _channelFromMap(envelopeItem(response.data, 'channel'));
  }

  Future<ConversationSummary> createDirectConversation({
    required String workspaceId,
    required List<String> participantIds,
  }) async {
    final response = await _api.post<Object>(
      '/api/v1/workspaces/${_e(workspaceId)}/direct-conversations',
      data: {'participant_ids': participantIds},
    );
    return _directConversationFromMap(
      envelopeItem(response.data, 'direct_conversation'),
    );
  }

  Future<void> markRead({
    required String workspaceId,
    required String channelId,
    required String lastReadMessageId,
  }) async {
    await _api.put<Object>(
      '/api/v1/workspaces/${_e(workspaceId)}/channels/${_e(channelId)}/read-state',
      data: {'last_read_message_id': lastReadMessageId},
    );
  }

  Future<List<ChannelMember>> listMembers({
    required String workspaceId,
    required String channelId,
  }) async {
    final response = await _api.get<Object>(
      '/api/v1/workspaces/${_e(workspaceId)}/channels/${_e(channelId)}/members',
    );
    return envelopeList(response.data, 'members')
        .map((map) => _channelMemberFromMap(map, channelId: channelId))
        .toList(growable: false);
  }

  Future<ChannelMember> addMember({
    required String workspaceId,
    required String channelId,
    required String userId,
  }) async {
    final response = await _api.post<Object>(
      '/api/v1/workspaces/${_e(workspaceId)}/channels/${_e(channelId)}/members',
      data: {'user_id': userId},
    );
    return _channelMemberFromMap(
      envelopeItem(response.data, 'member'),
      channelId: channelId,
    );
  }

  Future<List<ChannelMember>> listJoinRequests({
    required String workspaceId,
    required String channelId,
  }) async {
    final response = await _api.get<Object>(
      '/api/v1/workspaces/${_e(workspaceId)}/channels/${_e(channelId)}/join-requests',
    );
    return envelopeList(response.data, 'join_requests')
        .map((map) => _channelMemberFromMap(map, channelId: channelId))
        .toList(growable: false);
  }

  Future<ChannelMember> approveJoinRequest({
    required String workspaceId,
    required String channelId,
    required String userId,
  }) async {
    final response = await _api.post<Object>(
      '/api/v1/workspaces/${_e(workspaceId)}/channels/${_e(channelId)}/join-requests/${_e(userId)}/approve',
      data: const {},
    );
    return _channelMemberFromMap(
      envelopeItem(response.data, 'member'),
      channelId: channelId,
    );
  }

  Future<void> rejectJoinRequest({
    required String workspaceId,
    required String channelId,
    required String userId,
  }) async {
    await _api.delete<Object>(
      '/api/v1/workspaces/${_e(workspaceId)}/channels/${_e(channelId)}/join-requests/${_e(userId)}',
    );
  }

  Future<List<ChatMessage>> listMessages({
    required String workspaceId,
    required String channelId,
    int limit = 50,
    String? beforeId,
  }) async {
    final page = await listMessagePage(
      workspaceId: workspaceId,
      channelId: channelId,
      limit: limit,
      beforeId: beforeId,
    );
    return page.messages;
  }

  Future<MessagePage> listMessagePage({
    required String workspaceId,
    required String channelId,
    int limit = 50,
    String? beforeId,
  }) async {
    final response = await _api.get<Object>(
      '/api/v1/workspaces/${_e(workspaceId)}/channels/${_e(channelId)}/messages',
      queryParameters: compactMap({'limit': limit, 'before': beforeId}),
    );
    return _messagePageFromResponse(response.data, workspaceId, channelId);
  }

  Future<List<ChatMessage>> searchMessages({
    required String workspaceId,
    required String query,
    String? channelId,
    String? senderId,
    String? kind,
    DateTime? dateFrom,
    DateTime? dateTo,
    int limit = 30,
  }) async {
    final page = await searchMessagePage(
      workspaceId: workspaceId,
      query: query,
      channelId: channelId,
      senderId: senderId,
      kind: kind,
      dateFrom: dateFrom,
      dateTo: dateTo,
      limit: limit,
    );
    return page.messages;
  }

  Future<MessagePage> searchMessagePage({
    required String workspaceId,
    required String query,
    String? channelId,
    String? senderId,
    String? kind,
    DateTime? dateFrom,
    DateTime? dateTo,
    int limit = 30,
  }) async {
    final response = await _api.get<Object>(
      '/api/v1/workspaces/${_e(workspaceId)}/messages/search',
      queryParameters: compactMap({
        'q': query,
        'channel_id': channelId,
        'sender_id': senderId,
        'kind': kind,
        'date_from': _dateParam(dateFrom),
        'date_to': _dateParam(dateTo),
        'limit': limit,
      }),
    );
    return _messagePageFromResponse(
      response.data,
      workspaceId,
      channelId ?? '',
    );
  }

  Future<MessagePage> listThread({
    required String workspaceId,
    required String channelId,
    required String messageId,
    int limit = 50,
  }) async {
    final response = await _api.get<Object>(
      '/api/v1/workspaces/${_e(workspaceId)}/channels/${_e(channelId)}/messages/${_e(messageId)}/thread',
      queryParameters: {'limit': limit},
    );
    return _messagePageFromResponse(response.data, workspaceId, channelId);
  }

  Future<List<ChatMessage>> listPins({
    required String workspaceId,
    required String channelId,
  }) async {
    final response = await _api.get<Object>(
      '/api/v1/workspaces/${_e(workspaceId)}/channels/${_e(channelId)}/pins',
    );
    return envelopeList(response.data, 'messages')
        .map((map) => _messageFromMap(map, workspaceId, channelId))
        .toList(growable: false);
  }

  Future<ChatMessage> sendMessage({
    required String workspaceId,
    required String channelId,
    required String body,
    String? clientMessageId,
    String? parentId,
  }) async {
    final response = await _api.post<Object>(
      '/api/v1/workspaces/${_e(workspaceId)}/channels/${_e(channelId)}/messages',
      data: compactMap({
        'body': body,
        'kind': 'text',
        'parent_id': parentId,
        'client_message_id': clientMessageId,
        'mentioned_user_ids': _mentionedUserIds(body),
      }),
      options: clientMessageId == null || clientMessageId.isEmpty
          ? null
          : Options(headers: {'Idempotency-Key': clientMessageId}),
    );
    return _messageFromMap(
      envelopeItem(response.data, 'message'),
      workspaceId,
      channelId,
    );
  }

  Future<ChatMessage> editMessage({
    required String workspaceId,
    required String channelId,
    required String messageId,
    required String body,
  }) async {
    final response = await _api.patch<Object>(
      '/api/v1/workspaces/${_e(workspaceId)}/channels/${_e(channelId)}/messages/${_e(messageId)}',
      data: {'body': body},
    );
    return _messageFromMap(
      envelopeItem(response.data, 'message'),
      workspaceId,
      channelId,
    );
  }

  Future<void> deleteMessage({
    required String workspaceId,
    required String channelId,
    required String messageId,
  }) async {
    await _api.delete<Object>(
      '/api/v1/workspaces/${_e(workspaceId)}/channels/${_e(channelId)}/messages/${_e(messageId)}',
    );
  }

  Future<ChatMessage> addReaction({
    required String workspaceId,
    required String channelId,
    required String messageId,
    required String emoji,
  }) async {
    final response = await _api.post<Object>(
      '/api/v1/workspaces/${_e(workspaceId)}/channels/${_e(channelId)}/messages/${_e(messageId)}/reactions',
      data: {'emoji': emoji},
    );
    return _messageFromMap(
      envelopeItem(response.data, 'message'),
      workspaceId,
      channelId,
    );
  }

  Future<ChatMessage> removeReaction({
    required String workspaceId,
    required String channelId,
    required String messageId,
    required String emoji,
  }) async {
    final response = await _api.delete<Object>(
      '/api/v1/workspaces/${_e(workspaceId)}/channels/${_e(channelId)}/messages/${_e(messageId)}/reactions/${_e(emoji)}',
    );
    return _messageFromMap(
      envelopeItem(response.data, 'message'),
      workspaceId,
      channelId,
    );
  }

  Future<ChatMessage> pinMessage({
    required String workspaceId,
    required String channelId,
    required String messageId,
  }) async {
    final response = await _api.post<Object>(
      '/api/v1/workspaces/${_e(workspaceId)}/channels/${_e(channelId)}/messages/${_e(messageId)}/pin',
      data: const {},
    );
    return _messageFromMap(
      envelopeItem(response.data, 'message'),
      workspaceId,
      channelId,
    ).copyWith(isPinned: true);
  }

  Future<void> unpinMessage({
    required String workspaceId,
    required String channelId,
    required String messageId,
  }) async {
    await _api.delete<Object>(
      '/api/v1/workspaces/${_e(workspaceId)}/channels/${_e(channelId)}/messages/${_e(messageId)}/pin',
    );
  }

  Future<ChatMessage> forwardMessage({
    required String workspaceId,
    required String channelId,
    required String messageId,
    required String targetChannelId,
  }) async {
    final response = await _api.post<Object>(
      '/api/v1/workspaces/${_e(workspaceId)}/channels/${_e(channelId)}/messages/${_e(messageId)}/forward',
      data: {'target_channel_id': targetChannelId},
    );
    return _messageFromMap(
      envelopeItem(response.data, 'message'),
      workspaceId,
      targetChannelId,
    );
  }

  Future<List<ChannelFile>> listFiles({
    required String workspaceId,
    int limit = 40,
  }) async {
    final response = await _api.get<Object>(
      '/api/v1/workspaces/${_e(workspaceId)}/files',
      queryParameters: {'limit': limit},
    );
    return envelopeList(
      response.data,
      'files',
    ).map(_fileFromMap).toList(growable: false);
  }
}

MessagePage _messagePageFromResponse(
  Object? response,
  String workspaceId,
  String channelId,
) {
  final messages = envelopeList(response, 'messages')
      .map((map) {
        final resolvedChannelId = stringField(map, const [
          'channel_id',
          'channelId',
        ], fallback: channelId);
        return _messageFromMap(map, workspaceId, resolvedChannelId);
      })
      .toList(growable: false);
  final meta = _metaMap(response);
  return MessagePage(
    messages: messages,
    nextCursor: nullableStringField(meta, const ['next_cursor', 'nextCursor']),
    hasMore: boolField(meta, const ['has_more', 'hasMore']),
  );
}

JsonMap _metaMap(Object? response) {
  final map = jsonMap(response);
  return jsonMap(field(map, const ['meta']));
}

ConversationSummary _channelFromMap(JsonMap map) {
  final channelId = stringField(map, const ['id', 'channel_id', 'channelId']);
  final workspaceId = stringField(map, const ['workspace_id', 'workspaceId']);
  final visibility = _visibilityFromApi(
    stringField(map, const ['type', 'kind'], fallback: 'public'),
  );
  return ConversationSummary(
    id: channelId,
    workspaceId: workspaceId,
    channelId: channelId,
    kind: visibility == ChannelVisibility.direct
        ? ConversationKind.direct
        : ConversationKind.channel,
    title: stringField(map, const ['name', 'title'], fallback: channelId),
    preview: stringField(map, const ['description', 'preview']),
    avatarLabel: _avatarLabel(stringField(map, const ['name', 'title'])),
    avatarUrl: nullableStringField(map, const ['avatar_url', 'avatarUrl']),
    updatedAt: dateTimeField(map, const ['updated_at', 'updatedAt']),
    unreadCount: intField(map, const ['unread_count', 'unreadCount']),
    favorite: boolField(map, const ['is_favorite', 'favorite']),
    muted:
        stringField(map, const ['membership_status', 'membershipStatus']) ==
        'muted',
    memberCount: intField(map, const ['member_count', 'memberCount']),
    channelVisibility: visibility,
    membershipStatus: _membershipFromApi(
      stringField(map, const ['membership_status', 'membershipStatus']),
    ),
    canManage: boolField(map, const ['can_manage', 'canManage']),
    privateSessionMode: boolField(map, const [
      'private_session_mode',
      'privateSessionMode',
    ]),
  );
}

ConversationSummary _directConversationFromMap(JsonMap map) {
  final userMap = jsonMap(field(map, const ['user']));
  final participantMaps = jsonMapList(field(map, const ['participants']));
  final firstParticipant = participantMaps.isEmpty
      ? const <String, dynamic>{}
      : participantMaps.first;
  final displaySource = userMap.isNotEmpty ? userMap : firstParticipant;
  final lastMessage = jsonMap(
    field(map, const ['last_message', 'lastMessage']),
  );
  final lastMessageCreatedAt = nullableDateTimeField(lastMessage, const [
    'created_at',
    'createdAt',
    'sent_at',
    'sentAt',
  ]);
  final channelId = stringField(map, const ['channel_id', 'channelId', 'id']);
  final workspaceId = stringField(map, const ['workspace_id', 'workspaceId']);
  final participantIds = <String>{
    for (final participant in participantMaps)
      stringField(participant, const ['user_id', 'userId', 'id']),
    stringField(displaySource, const ['user_id', 'userId', 'id']),
  }..removeWhere((id) => id.isEmpty);

  return ConversationSummary(
    id: stringField(map, const ['id'], fallback: channelId),
    workspaceId: workspaceId,
    channelId: channelId,
    kind: ConversationKind.direct,
    title: stringField(displaySource, const [
      'display_name',
      'displayName',
      'username',
      'email',
    ], fallback: 'Tin nhắn riêng'),
    preview: stringField(lastMessage, const ['body']),
    avatarLabel: _avatarLabel(
      stringField(displaySource, const [
        'display_name',
        'displayName',
        'username',
        'email',
      ]),
    ),
    avatarUrl: nullableStringField(displaySource, const [
      'avatar_url',
      'avatarUrl',
    ]),
    peerUserId: nullableStringField(displaySource, const [
      'user_id',
      'userId',
      'id',
    ]),
    updatedAt:
        lastMessageCreatedAt ??
        dateTimeField(map, const ['updated_at', 'updatedAt']),
    unreadCount: intField(map, const ['unread_count', 'unreadCount']),
    participantIds: participantIds.toList(growable: false),
    channelVisibility: ChannelVisibility.direct,
    membershipStatus: MembershipStatus.active,
  );
}

PresenceSummary _presenceFromMap(JsonMap map) {
  return PresenceSummary(
    userId: stringField(map, const ['user_id', 'userId']),
    status: switch (stringField(map, const [
      'status',
    ], fallback: 'offline').toLowerCase()) {
      'online' => ConversationPresence.online,
      'away' => ConversationPresence.away,
      _ => ConversationPresence.offline,
    },
    lastHeartbeatAt: dateTimeField(map, const [
      'last_heartbeat_at',
      'lastHeartbeatAt',
    ]),
  );
}

ContactSummary _contactFromMap(JsonMap map) {
  final userMap = jsonMap(field(map, const ['user']));
  final source = userMap.isEmpty ? map : userMap;
  return ContactSummary(
    userId: stringField(source, const [
      'id',
      'user_id',
      'userId',
    ], fallback: stringField(map, const ['requester_id', 'receiver_id'])),
    displayName: stringField(source, const [
      'display_name',
      'displayName',
      'username',
      'email',
    ]),
    username: stringField(source, const ['username']),
    email: stringField(source, const ['email']),
    status: stringField(source, const ['status'], fallback: 'active'),
    avatarUrl: nullableStringField(source, const ['avatar_url', 'avatarUrl']),
    title: nullableStringField(source, const ['title', 'role']),
  );
}

ContactSummary _workspaceMemberFromMap(JsonMap map) {
  final userMap = jsonMap(field(map, const ['user']));
  final source = userMap.isEmpty ? map : {...userMap, ...map};
  return ContactSummary(
    userId: stringField(source, const ['user_id', 'userId', 'id']),
    displayName: stringField(source, const [
      'display_name',
      'displayName',
      'username',
      'email',
    ]),
    username: stringField(source, const ['username']),
    email: stringField(source, const ['email']),
    status: stringField(source, const ['status'], fallback: 'active'),
    avatarUrl: nullableStringField(source, const ['avatar_url', 'avatarUrl']),
    title: nullableStringField(source, const ['title', 'role']),
  );
}

ChannelMember _channelMemberFromMap(JsonMap map, {required String channelId}) {
  final userMap = jsonMap(field(map, const ['user']));
  final source = userMap.isEmpty ? map : {...userMap, ...map};
  return ChannelMember(
    channelId: stringField(source, const [
      'channel_id',
      'channelId',
    ], fallback: channelId),
    userId: stringField(source, const ['user_id', 'userId', 'id']),
    email: stringField(source, const ['email']),
    username: stringField(source, const ['username']),
    displayName: stringField(source, const [
      'display_name',
      'displayName',
      'username',
      'email',
    ]),
    status: stringField(source, const ['status'], fallback: 'active'),
    joinedAt: dateTimeField(source, const ['joined_at', 'joinedAt']),
    avatarUrl: nullableStringField(source, const ['avatar_url', 'avatarUrl']),
    lastReadMessageId: nullableStringField(source, const [
      'last_read_message_id',
      'lastReadMessageId',
    ]),
  );
}

ChatMessage _messageFromMap(JsonMap map, String workspaceId, String channelId) {
  final messageId = stringField(map, const ['id']);
  final resolvedWorkspaceId = stringField(map, const [
    'workspace_id',
    'workspaceId',
  ], fallback: workspaceId);
  return ChatMessage(
    id: messageId,
    workspaceId: resolvedWorkspaceId,
    channelId: stringField(map, const [
      'channel_id',
      'channelId',
    ], fallback: channelId),
    kind: stringField(map, const ['kind'], fallback: 'text'),
    body: stringField(map, const ['body']),
    createdAt: dateTimeField(map, const ['created_at', 'sent_at', 'createdAt']),
    senderId: nullableStringField(map, const [
      'sender_id',
      'author_id',
      'senderId',
      'authorId',
    ]),
    parentId: nullableStringField(map, const ['parent_id', 'parentId']),
    threadRootId: nullableStringField(map, const [
      'thread_root_id',
      'threadRootId',
    ]),
    editedAt: nullableDateTimeField(map, const ['edited_at', 'editedAt']),
    deletedAt: nullableDateTimeField(map, const ['deleted_at', 'deletedAt']),
    updatedAt: nullableDateTimeField(map, const ['updated_at', 'updatedAt']),
    mentions: field(map, const ['mentions']) is List
        ? (field(map, const ['mentions']) as List)
              .map((value) => value.toString())
              .where((value) => value.trim().isNotEmpty)
              .toList(growable: false)
        : const [],
    reactions: jsonMapList(
      field(map, const ['reactions']),
    ).map(_reactionFromMap).toList(growable: false),
    attachments: _messageAttachmentsFromMap(
      map,
      workspaceId: resolvedWorkspaceId,
      messageId: messageId,
    ),
  );
}

List<MessageAttachment> _messageAttachmentsFromMap(
  JsonMap map, {
  required String workspaceId,
  required String messageId,
}) {
  return jsonMapList(field(map, const ['attachments', 'message_attachments']))
      .map(
        (attachmentMap) => _messageAttachmentFromMap(
          attachmentMap,
          workspaceId: workspaceId,
          messageId: messageId,
        ),
      )
      .toList(growable: false);
}

MessageAttachment _messageAttachmentFromMap(
  JsonMap map, {
  required String workspaceId,
  required String messageId,
}) {
  final fileMap = jsonMap(field(map, const ['file']));
  final file = _uploadedMessageFileFromMap(
    fileMap.isEmpty ? map : fileMap,
    fallbackWorkspaceId: workspaceId,
  );
  final resolvedMessageId = stringField(map, const [
    'message_id',
    'messageId',
  ], fallback: messageId);
  final fileId = stringField(map, const [
    'file_id',
    'fileId',
  ], fallback: file.id);
  return MessageAttachment(
    id: stringField(map, const [
      'id',
      'attachment_id',
      'attachmentId',
    ], fallback: '$resolvedMessageId:$fileId'),
    workspaceId: stringField(map, const [
      'workspace_id',
      'workspaceId',
    ], fallback: workspaceId),
    messageId: resolvedMessageId,
    fileId: fileId,
    file: file,
    sortOrder: intField(map, const ['sort_order', 'sortOrder']),
    createdAt: dateTimeField(map, const ['created_at', 'createdAt']),
  );
}

UploadedMessageFile _uploadedMessageFileFromMap(
  JsonMap map, {
  required String fallbackWorkspaceId,
}) {
  final id = stringField(map, const ['id', 'file_id', 'fileId']);
  final workspaceId = stringField(map, const [
    'workspace_id',
    'workspaceId',
  ], fallback: fallbackWorkspaceId);
  return UploadedMessageFile(
    id: id,
    name: stringField(map, const [
      'name',
      'file_name',
      'original_name',
      'originalName',
    ], fallback: 'file'),
    mimeType: stringField(map, const [
      'mime_type',
      'mimeType',
    ], fallback: 'application/octet-stream'),
    byteSize: intField(map, const ['byte_size', 'byteSize', 'size']),
    downloadPath: stringField(map, const [
      'download_url',
      'downloadUrl',
      'url',
    ], fallback: _downloadPathFallback(workspaceId, id)),
    status: stringField(map, const ['status'], fallback: 'ready'),
    createdAt: dateTimeField(map, const ['created_at', 'createdAt']),
  );
}

String _downloadPathFallback(String workspaceId, String fileId) {
  if (workspaceId.isEmpty || fileId.isEmpty) {
    return '';
  }
  return '/api/v1/workspaces/${_e(workspaceId)}/files/${_e(fileId)}/download';
}

MessageReactionSummary _reactionFromMap(JsonMap map) {
  return MessageReactionSummary(
    emoji: stringField(map, const ['emoji']),
    count: intField(map, const ['count']),
    reactedByMe: boolField(map, const ['reacted_by_me', 'reactedByMe']),
  );
}

ChannelFile _fileFromMap(JsonMap map) {
  return ChannelFile(
    id: stringField(map, const ['id', 'file_id']),
    name: stringField(map, const [
      'name',
      'file_name',
      'original_name',
    ], fallback: 'file'),
    mimeType: stringField(map, const [
      'mime_type',
      'mimeType',
    ], fallback: 'application/octet-stream'),
    byteSize: intField(map, const ['byte_size', 'size_bytes', 'size']),
    createdAt: dateTimeField(map, const ['created_at', 'createdAt']),
  );
}

ChannelVisibility _visibilityFromApi(String value) {
  return switch (value.trim().toLowerCase()) {
    'private' => ChannelVisibility.private,
    'direct' => ChannelVisibility.direct,
    _ => ChannelVisibility.public,
  };
}

String _visibilityToApi(ChannelVisibility visibility) {
  return switch (visibility) {
    ChannelVisibility.private => 'private',
    ChannelVisibility.direct => 'direct',
    ChannelVisibility.public => 'public',
  };
}

MembershipStatus _membershipFromApi(String value) {
  return switch (value.trim().toLowerCase()) {
    'active' => MembershipStatus.active,
    'muted' => MembershipStatus.muted,
    'invited' => MembershipStatus.invited,
    'left' => MembershipStatus.left,
    'removed' => MembershipStatus.removed,
    _ => MembershipStatus.none,
  };
}

String _avatarLabel(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return '';
  }
  final words = trimmed.split(RegExp(r'\s+'));
  if (words.length == 1) {
    return _prefix(words.first, 2).toUpperCase();
  }
  return '${_prefix(words.first, 1)}${_prefix(words.last, 1)}'.toUpperCase();
}

String _e(String value) => Uri.encodeComponent(value);

String? _dateParam(DateTime? value) {
  if (value == null) {
    return null;
  }
  final utc = value.toUtc();
  return '${utc.year.toString().padLeft(4, '0')}-'
      '${utc.month.toString().padLeft(2, '0')}-'
      '${utc.day.toString().padLeft(2, '0')}';
}

List<String> _mentionedUserIds(String body) {
  final matches = RegExp(
    r'<@([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})>',
  ).allMatches(body);
  return {
    for (final match in matches)
      if (match.group(1) != null) match.group(1)!,
  }.toList(growable: false);
}

String _prefix(String value, int length) {
  if (value.length <= length) {
    return value;
  }
  return value.substring(0, length);
}
