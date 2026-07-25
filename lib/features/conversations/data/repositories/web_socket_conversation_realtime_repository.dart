import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../../../core/network/api_response.dart';
import '../../../auth/domain/repositories/auth_token_repository.dart';
import '../../domain/entities/call_session.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/entities/conversation_realtime_event.dart';
import '../../domain/repositories/conversation_repository.dart';

final class WebSocketConversationRealtimeRepository
    implements ConversationRealtimeRepository {
  WebSocketConversationRealtimeRepository({
    required Uri apiBaseUri,
    Uri? wsBaseUri,
    required AuthTokenRepository tokenRepository,
  }) : _wsBaseUri = wsBaseUri ?? defaultConversationRealtimeWsUri(apiBaseUri),
       _tokenRepository = tokenRepository;

  final Uri _wsBaseUri;
  final AuthTokenRepository _tokenRepository;

  WebSocket? _socket;
  StreamController<ConversationRealtimeEvent>? _controller;
  String? _room;
  bool _disposed = false;
  int _reconnectAttempt = 0;

  @override
  Stream<ConversationRealtimeEvent> subscribeToChannel({
    required String workspaceId,
    required String channelId,
  }) {
    _disposed = false;
    final nextRoom = _roomFor(workspaceId, channelId);
    if (_room != null && _room != nextRoom) {
      _closeCurrentConnection(leaveRoom: true, closeController: true);
    }
    _room = nextRoom;
    _controller ??= StreamController<ConversationRealtimeEvent>.broadcast(
      onListen: () {
        unawaited(_connect(workspaceId: workspaceId, channelId: channelId));
      },
      onCancel: () {
        if (_controller?.hasListener == false) {
          unawaited(disconnect());
        }
      },
    );
    return _controller!.stream;
  }

  @override
  Future<void> sendTyping({
    required String workspaceId,
    required String channelId,
    required bool isTyping,
  }) async {
    final socket = _socket;
    if (socket == null || socket.readyState != WebSocket.open) {
      return;
    }
    socket.add(
      jsonEncode({
        'type': isTyping ? 'TypingStarted' : 'TypingStopped',
        'room': _roomFor(workspaceId, channelId),
      }),
    );
  }

  @override
  Future<void> disconnect() async {
    _disposed = true;
    _closeCurrentConnection(leaveRoom: true, closeController: true);
  }

  Future<void> _connect({
    required String workspaceId,
    required String channelId,
  }) async {
    if (_disposed) {
      return;
    }
    final token = (await _tokenRepository.readAccessToken())?.trim();
    if (token == null || token.isEmpty) {
      return;
    }
    final room = _roomFor(workspaceId, channelId);
    try {
      final socket = await WebSocket.connect(_webSocketUri(token).toString());
      if (_disposed || _room != room) {
        await socket.close();
        return;
      }
      _socket = socket;
      _reconnectAttempt = 0;
      socket.add(jsonEncode({'type': 'join', 'room': room}));
      socket.listen(
        (data) => _handleSocketData(data, workspaceId, channelId),
        onError: (_) => _scheduleReconnect(workspaceId, channelId),
        onDone: () => _scheduleReconnect(workspaceId, channelId),
        cancelOnError: true,
      );
    } on Object {
      _scheduleReconnect(workspaceId, channelId);
    }
  }

  void _handleSocketData(Object? data, String workspaceId, String channelId) {
    final event = ConversationRealtimeEventMapper.fromSocketData(
      data,
      fallbackWorkspaceId: workspaceId,
      fallbackChannelId: channelId,
    );
    if (event != null && !(_controller?.isClosed ?? true)) {
      _controller?.add(event);
    }
  }

  void _scheduleReconnect(String workspaceId, String channelId) {
    if (_disposed ||
        (_controller?.isClosed ?? true) ||
        _room != _roomFor(workspaceId, channelId)) {
      return;
    }
    final delay = Duration(
      seconds: _reconnectAttempt < 5 ? 1 << _reconnectAttempt : 16,
    );
    _reconnectAttempt += 1;
    Timer(delay, () {
      if (!_disposed && _room == _roomFor(workspaceId, channelId)) {
        unawaited(_connect(workspaceId: workspaceId, channelId: channelId));
      }
    });
  }

  void _closeCurrentConnection({
    required bool leaveRoom,
    required bool closeController,
  }) {
    final room = _room;
    final socket = _socket;
    if (leaveRoom &&
        socket != null &&
        socket.readyState == WebSocket.open &&
        room != null) {
      socket.add(jsonEncode({'type': 'leave', 'room': room}));
    }
    unawaited(socket?.close());
    _socket = null;
    if (closeController) {
      unawaited(_controller?.close());
      _controller = null;
    }
  }

  Uri _webSocketUri(String accessToken) {
    return conversationRealtimeWebSocketUri(_wsBaseUri, accessToken);
  }
}

Uri defaultConversationRealtimeWsUri(Uri apiBaseUri) {
  final scheme = apiBaseUri.scheme == 'https' ? 'wss' : 'ws';
  return Uri(
    scheme: scheme,
    userInfo: apiBaseUri.userInfo,
    host: apiBaseUri.host,
    port: apiBaseUri.hasPort ? apiBaseUri.port : null,
    path: '/ws',
  );
}

Uri conversationRealtimeWebSocketUri(Uri wsBaseUri, String accessToken) {
  return wsBaseUri.replace(
    queryParameters: {
      ...wsBaseUri.queryParameters,
      'access_token': accessToken,
    },
  );
}

final class ConversationRealtimeEventMapper {
  const ConversationRealtimeEventMapper._();

  static ConversationRealtimeEvent? fromSocketData(
    Object? data, {
    required String fallbackWorkspaceId,
    required String fallbackChannelId,
  }) {
    final decoded = switch (data) {
      final String value => jsonDecode(value),
      final List<int> value => jsonDecode(utf8.decode(value)),
      final Map value => value,
      _ => null,
    };
    final map = jsonMap(decoded);
    if (map.isEmpty) {
      return null;
    }
    final payload = jsonMap(field(map, const ['payload']));
    final signal = jsonMap(field(payload, const ['signal']));
    final signalPayload = signal.isEmpty ? payload : signal;
    final messageMap = jsonMap(field(payload, const ['message']));
    final message = messageMap.isEmpty
        ? null
        : _messageFromMap(messageMap, fallbackWorkspaceId, fallbackChannelId);
    final type = _eventType(stringField(map, const ['type']));
    final callStatus = _callStatusForEvent(type);
    return ConversationRealtimeEvent(
      type: type,
      workspaceId:
          message?.workspaceId ??
          stringField(payload, const [
            'workspace_id',
            'workspaceId',
          ], fallback: fallbackWorkspaceId),
      channelId:
          message?.channelId ??
          stringField(payload, const [
            'channel_id',
            'channelId',
          ], fallback: fallbackChannelId),
      message: message,
      messageId:
          message?.id ??
          nullableStringField(messageMap, const ['id']) ??
          nullableStringField(payload, const ['message_id', 'messageId']),
      userId:
          nullableStringField(map, const ['user_id', 'userId']) ??
          nullableStringField(payload, const ['user_id', 'userId']),
      timestamp: nullableDateTimeField(map, const ['timestamp']),
      callId: nullableStringField(payload, const ['call_id', 'callId']),
      callMode: _callMode(nullableStringField(payload, const ['mode'])),
      callStatus: callStatus,
      callInitiatorUserId: nullableStringField(payload, const [
        'initiator_user_id',
        'initiatorUserId',
      ]),
      callTargetUserId: nullableStringField(payload, const [
        'target_user_id',
        'targetUserId',
      ]),
      reason: nullableStringField(payload, const ['reason']),
      callSdp: jsonMap(field(signalPayload, const ['sdp'])),
      callCandidate: jsonMap(field(signalPayload, const ['candidate'])),
    );
  }
}

ConversationRealtimeEventType _eventType(String value) {
  return switch (value.trim()) {
    'MessageCreated' => ConversationRealtimeEventType.messageCreated,
    'MessageUpdated' => ConversationRealtimeEventType.messageUpdated,
    'MessageDeleted' => ConversationRealtimeEventType.messageDeleted,
    'MessagePinned' => ConversationRealtimeEventType.messagePinned,
    'MessageUnpinned' => ConversationRealtimeEventType.messageUnpinned,
    'ReactionChanged' => ConversationRealtimeEventType.reactionChanged,
    'AttachmentCreated' => ConversationRealtimeEventType.attachmentCreated,
    'TypingStarted' => ConversationRealtimeEventType.typingStarted,
    'TypingStopped' => ConversationRealtimeEventType.typingStopped,
    'CallInvited' => ConversationRealtimeEventType.callInvited,
    'CallAccepted' => ConversationRealtimeEventType.callAccepted,
    'CallReady' => ConversationRealtimeEventType.callReady,
    'CallOffer' => ConversationRealtimeEventType.callOffer,
    'CallAnswer' => ConversationRealtimeEventType.callAnswer,
    'CallIceCandidate' => ConversationRealtimeEventType.callIceCandidate,
    'CallRejected' => ConversationRealtimeEventType.callRejected,
    'CallCancelled' => ConversationRealtimeEventType.callCancelled,
    'CallEnded' => ConversationRealtimeEventType.callEnded,
    'CallMissed' => ConversationRealtimeEventType.callMissed,
    _ => ConversationRealtimeEventType.unknown,
  };
}

CallMode? _callMode(String? value) {
  return switch (value?.trim().toLowerCase()) {
    'audio' => CallMode.audio,
    'video' => CallMode.video,
    _ => null,
  };
}

CallStatus? _callStatusForEvent(ConversationRealtimeEventType type) {
  return switch (type) {
    ConversationRealtimeEventType.callInvited => CallStatus.ringing,
    ConversationRealtimeEventType.callAccepted => CallStatus.accepted,
    ConversationRealtimeEventType.callRejected => CallStatus.rejected,
    ConversationRealtimeEventType.callCancelled => CallStatus.cancelled,
    ConversationRealtimeEventType.callEnded => CallStatus.ended,
    ConversationRealtimeEventType.callMissed => CallStatus.missed,
    _ => null,
  };
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

String _e(String value) => Uri.encodeComponent(value);

MessageReactionSummary _reactionFromMap(JsonMap map) {
  return MessageReactionSummary(
    emoji: stringField(map, const ['emoji']),
    count: intField(map, const ['count']),
    reactedByMe: boolField(map, const ['reacted_by_me', 'reactedByMe']),
  );
}

String _roomFor(String workspaceId, String channelId) {
  return 'workspace:$workspaceId:channel:$channelId';
}
