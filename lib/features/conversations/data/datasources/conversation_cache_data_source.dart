import 'dart:convert';

import '../../../../core/database/app_database.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/entities/conversation_summary.dart';

final class ConversationCacheDataSource {
  const ConversationCacheDataSource(this._database);

  final AppDatabase _database;

  Future<void> saveDirectConversations({
    required String workspaceId,
    required List<ConversationSummary> items,
  }) {
    return _writeConversationList(
      workspaceId: workspaceId,
      key: 'direct_conversations',
      items: items,
    );
  }

  Future<List<ConversationSummary>?> readDirectConversations({
    required String workspaceId,
  }) {
    return _readConversationList(
      workspaceId: workspaceId,
      key: 'direct_conversations',
    );
  }

  Future<void> saveChannels({
    required String workspaceId,
    required List<ConversationSummary> items,
  }) {
    return _writeConversationList(
      workspaceId: workspaceId,
      key: 'channels',
      items: items,
    );
  }

  Future<List<ConversationSummary>?> readChannels({
    required String workspaceId,
  }) {
    return _readConversationList(workspaceId: workspaceId, key: 'channels');
  }

  Future<void> saveLatestMessagePage({
    required String workspaceId,
    required String channelId,
    required MessagePage page,
  }) {
    return _database.putKeyValue(
      scope: _messageScope(workspaceId, channelId),
      key: 'latest_page',
      value: jsonEncode(_messagePageToJson(page)),
    );
  }

  Future<MessagePage?> readLatestMessagePage({
    required String workspaceId,
    required String channelId,
  }) async {
    final value = await _database.readKeyValue(
      scope: _messageScope(workspaceId, channelId),
      key: 'latest_page',
    );
    if (value == null) {
      return null;
    }
    try {
      final decoded = jsonDecode(value);
      if (decoded is! Map<String, Object?>) {
        return null;
      }
      return _messagePageFromJson(decoded);
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  Future<void> upsertLatestMessage({
    required String workspaceId,
    required String channelId,
    required ChatMessage message,
  }) async {
    final page = await readLatestMessagePage(
      workspaceId: workspaceId,
      channelId: channelId,
    );
    if (page == null) {
      await saveLatestMessagePage(
        workspaceId: workspaceId,
        channelId: channelId,
        page: MessagePage(messages: [message]),
      );
      return;
    }

    final messages = [...page.messages];
    final existingIndex = messages.indexWhere((item) => item.id == message.id);
    if (existingIndex == -1) {
      messages.insert(0, message);
    } else {
      messages[existingIndex] = message;
    }

    await saveLatestMessagePage(
      workspaceId: workspaceId,
      channelId: channelId,
      page: MessagePage(
        messages: messages,
        nextCursor: page.nextCursor,
        hasMore: page.hasMore,
      ),
    );
  }

  /// Reconciles a fresh server page with messages that this device has just
  /// sent successfully.
  ///
  /// A mobile user can leave and immediately re-open a channel while the
  /// original list request is still in flight. That older request (or a short
  /// lived stale proxy response) may not contain the newly committed message.
  /// Keep only recent, idempotent local sends during that small consistency
  /// window; all other server data remains authoritative.
  Future<MessagePage> reconcileLatestMessagePage({
    required String workspaceId,
    required String channelId,
    required MessagePage remotePage,
    DateTime? now,
  }) async {
    final cachedPage = await readLatestMessagePage(
      workspaceId: workspaceId,
      channelId: channelId,
    );
    if (cachedPage == null) {
      await saveLatestMessagePage(
        workspaceId: workspaceId,
        channelId: channelId,
        page: remotePage,
      );
      return remotePage;
    }

    final remoteIds = remotePage.messages.map((message) => message.id).toSet();
    final cutoff = (now ?? DateTime.now().toUtc()).subtract(
      const Duration(minutes: 5),
    );
    final recentLocalSends = cachedPage.messages.where((message) {
      return !remoteIds.contains(message.id) &&
          message.workspaceId == workspaceId &&
          message.channelId == channelId &&
          !message.createdAt.isBefore(cutoff) &&
          message.clientMessageId.isNotEmpty;
    });
    final messagesById = <String, ChatMessage>{
      for (final message in remotePage.messages) message.id: message,
      for (final message in recentLocalSends) message.id: message,
    };
    final reconciledMessages = messagesById.values.toList(growable: false)
      ..sort((left, right) {
        final byCreatedAt = right.createdAt.compareTo(left.createdAt);
        return byCreatedAt != 0 ? byCreatedAt : right.id.compareTo(left.id);
      });
    final reconciledPage = MessagePage(
      messages: reconciledMessages,
      nextCursor: remotePage.nextCursor,
      hasMore: remotePage.hasMore,
    );
    await saveLatestMessagePage(
      workspaceId: workspaceId,
      channelId: channelId,
      page: reconciledPage,
    );
    return reconciledPage;
  }

  Future<void> removeLatestMessage({
    required String workspaceId,
    required String channelId,
    required String messageId,
  }) async {
    final page = await readLatestMessagePage(
      workspaceId: workspaceId,
      channelId: channelId,
    );
    if (page == null) {
      return;
    }

    await saveLatestMessagePage(
      workspaceId: workspaceId,
      channelId: channelId,
      page: MessagePage(
        messages: [
          for (final message in page.messages)
            if (message.id != messageId) message,
        ],
        nextCursor: page.nextCursor,
        hasMore: page.hasMore,
      ),
    );
  }

  Future<void> updateLatestMessagePin({
    required String workspaceId,
    required String channelId,
    required String messageId,
    required bool isPinned,
  }) async {
    final page = await readLatestMessagePage(
      workspaceId: workspaceId,
      channelId: channelId,
    );
    if (page == null) {
      return;
    }

    await saveLatestMessagePage(
      workspaceId: workspaceId,
      channelId: channelId,
      page: MessagePage(
        messages: [
          for (final message in page.messages)
            if (message.id == messageId)
              message.copyWith(isPinned: isPinned)
            else
              message,
        ],
        nextCursor: page.nextCursor,
        hasMore: page.hasMore,
      ),
    );
  }

  Future<void> _writeConversationList({
    required String workspaceId,
    required String key,
    required List<ConversationSummary> items,
  }) {
    return _database.putKeyValue(
      scope: _conversationScope(workspaceId),
      key: key,
      value: jsonEncode({
        'items': items.map(_conversationToJson).toList(growable: false),
      }),
    );
  }

  Future<List<ConversationSummary>?> _readConversationList({
    required String workspaceId,
    required String key,
  }) async {
    final value = await _database.readKeyValue(
      scope: _conversationScope(workspaceId),
      key: key,
    );
    if (value == null) {
      return null;
    }
    try {
      final decoded = jsonDecode(value);
      if (decoded is! Map<String, Object?>) {
        return null;
      }
      final items = decoded['items'];
      if (items is! List) {
        return null;
      }
      return items
          .whereType<Map<String, Object?>>()
          .map(_conversationFromJson)
          .toList(growable: false);
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }
}

String _conversationScope(String workspaceId) {
  return 'conversation_cache:$workspaceId';
}

String _messageScope(String workspaceId, String channelId) {
  return 'message_cache:$workspaceId:$channelId';
}

Map<String, Object?> _conversationToJson(ConversationSummary item) {
  return {
    'id': item.id,
    'workspaceId': item.workspaceId,
    'channelId': item.channelId,
    'kind': item.kind.name,
    'title': item.title,
    'preview': item.preview,
    'avatarLabel': item.avatarLabel,
    'avatarUrl': item.avatarUrl,
    'peerUserId': item.peerUserId,
    'updatedAt': item.updatedAt.toUtc().toIso8601String(),
    'unreadCount': item.unreadCount,
    'favorite': item.favorite,
    'muted': item.muted,
    'memberCount': item.memberCount,
    'participantIds': item.participantIds,
    'channelVisibility': item.channelVisibility.name,
    'membershipStatus': item.membershipStatus.name,
    'canManage': item.canManage,
    'privateSessionMode': item.privateSessionMode,
  };
}

ConversationSummary _conversationFromJson(Map<String, Object?> json) {
  return ConversationSummary(
    id: _string(json['id']),
    workspaceId: _string(json['workspaceId']),
    channelId: _string(json['channelId']),
    kind: _enumByName(
      ConversationKind.values,
      _string(json['kind']),
      ConversationKind.channel,
    ),
    title: _string(json['title']),
    preview: _string(json['preview']),
    avatarLabel: _nullableString(json['avatarLabel']),
    avatarUrl: _nullableString(json['avatarUrl']),
    peerUserId: _nullableString(json['peerUserId']),
    updatedAt:
        _dateTime(json['updatedAt']) ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    unreadCount: _int(json['unreadCount']),
    favorite: _bool(json['favorite']),
    muted: _bool(json['muted']),
    memberCount: _int(json['memberCount']),
    participantIds: _stringList(json['participantIds']),
    channelVisibility: _enumByName(
      ChannelVisibility.values,
      _string(json['channelVisibility']),
      ChannelVisibility.public,
    ),
    membershipStatus: _enumByName(
      MembershipStatus.values,
      _string(json['membershipStatus']),
      MembershipStatus.none,
    ),
    canManage: _bool(json['canManage']),
    privateSessionMode: _bool(json['privateSessionMode']),
  );
}

Map<String, Object?> _messagePageToJson(MessagePage page) {
  return {
    'messages': page.messages.map(_messageToJson).toList(growable: false),
    'nextCursor': page.nextCursor,
    'hasMore': page.hasMore,
  };
}

MessagePage _messagePageFromJson(Map<String, Object?> json) {
  final messages = json['messages'];
  return MessagePage(
    messages: messages is List
        ? messages
              .whereType<Map<String, Object?>>()
              .map(_messageFromJson)
              .toList(growable: false)
        : const [],
    nextCursor: _nullableString(json['nextCursor']),
    hasMore: _bool(json['hasMore']),
  );
}

Map<String, Object?> _messageToJson(ChatMessage item) {
  return {
    'id': item.id,
    'workspaceId': item.workspaceId,
    'channelId': item.channelId,
    'kind': item.kind,
    'body': item.body,
    'createdAt': item.createdAt.toUtc().toIso8601String(),
    'senderId': item.senderId,
    'parentId': item.parentId,
    'threadRootId': item.threadRootId,
    'editedAt': item.editedAt?.toUtc().toIso8601String(),
    'deletedAt': item.deletedAt?.toUtc().toIso8601String(),
    'updatedAt': item.updatedAt?.toUtc().toIso8601String(),
    'mentions': item.mentions,
    'reactions': item.reactions.map(_reactionToJson).toList(growable: false),
    'metadata': item.metadata,
    'attachments': item.attachments
        .map(_attachmentToJson)
        .toList(growable: false),
    'isPinned': item.isPinned,
    'isMine': item.isMine,
  };
}

ChatMessage _messageFromJson(Map<String, Object?> json) {
  final reactions = json['reactions'];
  final attachments = json['attachments'];
  return ChatMessage(
    id: _string(json['id']),
    workspaceId: _string(json['workspaceId']),
    channelId: _string(json['channelId']),
    kind: _string(json['kind'], fallback: 'text'),
    body: _string(json['body']),
    createdAt:
        _dateTime(json['createdAt']) ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    senderId: _nullableString(json['senderId']),
    parentId: _nullableString(json['parentId']),
    threadRootId: _nullableString(json['threadRootId']),
    editedAt: _dateTime(json['editedAt']),
    deletedAt: _dateTime(json['deletedAt']),
    updatedAt: _dateTime(json['updatedAt']),
    mentions: _stringList(json['mentions']),
    reactions: reactions is List
        ? reactions
              .whereType<Map<String, Object?>>()
              .map(_reactionFromJson)
              .toList(growable: false)
        : const [],
    metadata: json['metadata'] is Map
        ? Map<String, Object?>.from(json['metadata']! as Map)
        : const {},
    attachments: attachments is List
        ? attachments
              .whereType<Map<String, Object?>>()
              .map(_attachmentFromJson)
              .toList(growable: false)
        : const [],
    isPinned: _bool(json['isPinned']),
    isMine: _bool(json['isMine']),
  );
}

Map<String, Object?> _reactionToJson(MessageReactionSummary reaction) {
  return {
    'emoji': reaction.emoji,
    'count': reaction.count,
    'reactedByMe': reaction.reactedByMe,
  };
}

MessageReactionSummary _reactionFromJson(Map<String, Object?> json) {
  return MessageReactionSummary(
    emoji: _string(json['emoji']),
    count: _int(json['count']),
    reactedByMe: _bool(json['reactedByMe']),
  );
}

Map<String, Object?> _attachmentToJson(MessageAttachment attachment) {
  return {
    'id': attachment.id,
    'workspaceId': attachment.workspaceId,
    'messageId': attachment.messageId,
    'fileId': attachment.fileId,
    'file': _uploadedFileToJson(attachment.file),
    'createdAt': attachment.createdAt.toUtc().toIso8601String(),
    'sortOrder': attachment.sortOrder,
  };
}

MessageAttachment _attachmentFromJson(Map<String, Object?> json) {
  final file = json['file'];
  return MessageAttachment(
    id: _string(json['id']),
    workspaceId: _string(json['workspaceId']),
    messageId: _string(json['messageId']),
    fileId: _string(json['fileId']),
    file: file is Map<String, Object?>
        ? _uploadedFileFromJson(file)
        : _emptyUploadedFile(_string(json['fileId'])),
    createdAt:
        _dateTime(json['createdAt']) ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    sortOrder: _int(json['sortOrder']),
  );
}

Map<String, Object?> _uploadedFileToJson(UploadedMessageFile file) {
  return {
    'id': file.id,
    'name': file.name,
    'mimeType': file.mimeType,
    'byteSize': file.byteSize,
    'downloadPath': file.downloadPath,
    'createdAt': file.createdAt.toUtc().toIso8601String(),
    'status': file.status,
  };
}

UploadedMessageFile _uploadedFileFromJson(Map<String, Object?> json) {
  return UploadedMessageFile(
    id: _string(json['id']),
    name: _string(json['name']),
    mimeType: _string(json['mimeType'], fallback: 'application/octet-stream'),
    byteSize: _int(json['byteSize']),
    downloadPath: _string(json['downloadPath']),
    createdAt:
        _dateTime(json['createdAt']) ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    status: _string(json['status'], fallback: 'ready'),
  );
}

UploadedMessageFile _emptyUploadedFile(String id) {
  return UploadedMessageFile(
    id: id,
    name: '',
    mimeType: 'application/octet-stream',
    byteSize: 0,
    downloadPath: '',
    createdAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
  );
}

T _enumByName<T extends Enum>(List<T> values, String name, T fallback) {
  for (final value in values) {
    if (value.name == name) {
      return value;
    }
  }
  return fallback;
}

String _string(Object? value, {String fallback = ''}) {
  return value is String ? value : fallback;
}

String? _nullableString(Object? value) {
  return value is String && value.isNotEmpty ? value : null;
}

int _int(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value) ?? 0;
  }
  return 0;
}

bool _bool(Object? value) {
  if (value is bool) {
    return value;
  }
  if (value is num) {
    return value != 0;
  }
  if (value is String) {
    return value == 'true' || value == '1';
  }
  return false;
}

DateTime? _dateTime(Object? value) {
  if (value is! String || value.isEmpty) {
    return null;
  }
  return DateTime.tryParse(value)?.toUtc();
}

List<String> _stringList(Object? value) {
  if (value is! List) {
    return const [];
  }
  return value.whereType<String>().toList(growable: false);
}
