import '../../../../core/network/api_response.dart';
import '../../../../core/network/api_transport.dart';
import '../../domain/entities/inbox.dart';

/// Hộp thư khách: `/api/v1/workspaces/{ws}/inbox/...`.
final class InboxRemoteDataSource {
  const InboxRemoteDataSource(this._api);

  final ApiTransport _api;

  Future<InboxConversationPage> listConversations({
    required String workspaceId,
    InboxStatusFilter status = InboxStatusFilter.all,
    InboxAssigneeFilter assignee = InboxAssigneeFilter.all,
    String? cursor,
    int limit = 30,
  }) async {
    final response = await _api.get<Object>(
      '${_base(workspaceId)}/conversations',
      queryParameters: {
        'status': ?status.apiValue,
        'assignee': ?assignee.apiValue,
        'limit': limit,
        if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
      },
    );
    final data = jsonMap(envelopeData(response.data));
    return InboxConversationPage(
      items: jsonMapList(field(data, const ['items']))
          .map(inboxConversationFromMap)
          .where((item) => item.id.isNotEmpty)
          .toList(growable: false),
      nextCursor: nullableStringField(data, const ['next_cursor']),
    );
  }

  Future<InboxConversation> getConversation({
    required String workspaceId,
    required String conversationId,
  }) async {
    final response = await _api.get<Object>(_item(workspaceId, conversationId));
    return inboxConversationFromMap(jsonMap(envelopeData(response.data)));
  }

  Future<InboxMessagePage> listMessages({
    required String workspaceId,
    required String conversationId,
    String? cursor,
    int limit = 30,
  }) async {
    final response = await _api.get<Object>(
      '${_item(workspaceId, conversationId)}/messages',
      queryParameters: {
        'limit': limit,
        if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
      },
    );
    final data = jsonMap(envelopeData(response.data));
    return InboxMessagePage(
      items: jsonMapList(field(data, const ['items']))
          .map(inboxMessageFromMap)
          .where((item) => item.id.isNotEmpty)
          .toList(growable: false),
      nextCursor: nullableStringField(data, const ['next_cursor']),
    );
  }

  Future<InboxMessage> sendReply({
    required String workspaceId,
    required String conversationId,
    required String body,
    required String clientMessageId,
  }) async {
    final response = await _api.post<Object>(
      '${_item(workspaceId, conversationId)}/messages',
      data: {'body': body, 'client_message_id': clientMessageId},
    );
    return inboxMessageFromMap(jsonMap(envelopeData(response.data)));
  }

  Future<InboxMessage> addNote({
    required String workspaceId,
    required String conversationId,
    required String body,
  }) async {
    final response = await _api.post<Object>(
      '${_item(workspaceId, conversationId)}/notes',
      data: {'body': body},
    );
    return inboxMessageFromMap(jsonMap(envelopeData(response.data)));
  }

  Future<void> markRead({
    required String workspaceId,
    required String conversationId,
  }) async {
    await _api.post<Object>('${_item(workspaceId, conversationId)}/read');
  }

  Future<InboxConversation> update({
    required String workspaceId,
    required String conversationId,
    required InboxConversationChange change,
  }) async {
    final response = await _api.patch<Object>(
      _item(workspaceId, conversationId),
      data: change.toJson(),
    );
    return inboxConversationFromMap(jsonMap(envelopeData(response.data)));
  }

  Future<List<InboxTag>> listTags({required String workspaceId}) async {
    final response = await _api.get<Object>('${_base(workspaceId)}/tags');
    final data = jsonMap(envelopeData(response.data));
    return _tags(field(data, const ['items']));
  }

  String _base(String workspaceId) =>
      '/api/v1/workspaces/${Uri.encodeComponent(workspaceId.trim())}/inbox';

  String _item(String workspaceId, String conversationId) =>
      '${_base(workspaceId)}/conversations/'
      '${Uri.encodeComponent(conversationId.trim())}';
}

List<InboxTag> _tags(Object? value) {
  return jsonMapList(value)
      .map(
        (tag) => InboxTag(
          id: stringField(tag, const ['id']),
          name: stringField(tag, const ['name']),
          color: stringField(tag, const ['color']),
        ),
      )
      .where((tag) => tag.id.isNotEmpty)
      .toList(growable: false);
}

DateTime? _time(Object? value) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? null : DateTime.tryParse(text)?.toLocal();
}

/// Đọc hội thoại chịu lỗi: trường thiếu / null / sai kiểu không làm crash.
InboxConversation inboxConversationFromMap(JsonMap map) {
  final source = jsonMap(field(map, const ['source']));
  final contact = jsonMap(field(map, const ['contact']));
  final assignee = nullableStringField(map, const ['assignee_id']);
  return InboxConversation(
    id: stringField(map, const ['id']),
    workspaceId: stringField(map, const ['workspace_id']),
    source: InboxSourceSummary(
      id: stringField(source, const ['id']),
      kind: stringField(source, const ['kind']).trim().toLowerCase(),
      name: stringField(source, const ['name']),
      code: stringField(source, const ['code']),
    ),
    contact: InboxContact(
      id: stringField(contact, const ['id']),
      displayName: stringField(contact, const ['display_name']),
      email: stringField(contact, const ['email']),
      phone: stringField(contact, const ['phone']),
      avatarUrl: stringField(contact, const ['avatar_url']),
    ),
    subject: stringField(map, const ['subject']),
    status: InboxStatus.fromApi(stringField(map, const ['status'])),
    assigneeId: assignee,
    assigneeName: stringField(map, const ['assignee_name']),
    tags: _tags(field(map, const ['tags'])),
    label: stringField(map, const ['label']),
    lastMessagePreview: stringField(map, const ['last_message_preview']),
    lastMessageAt: _time(field(map, const ['last_message_at'])),
    lastInboundAt: _time(field(map, const ['last_inbound_at'])),
    unreadCount: intField(map, const ['unread_count']).clamp(0, 1 << 30),
    canReply: boolField(map, const ['can_reply']),
    replyBlockedReason: stringField(map, const ['reply_blocked_reason']),
    createdAt: _time(field(map, const ['created_at'])),
    updatedAt: _time(field(map, const ['updated_at'])),
  );
}

InboxMessage inboxMessageFromMap(JsonMap map) {
  final direction = stringField(map, const ['direction']).trim().toLowerCase();
  final kind = stringField(map, const ['kind']).trim().toLowerCase();
  return InboxMessage(
    id: stringField(map, const ['id']),
    conversationId: stringField(map, const ['conversation_id']),
    direction: direction == 'out'
        ? InboxDirection.outbound
        : InboxDirection.inbound,
    kind: kind == 'note' ? InboxMessageKind.note : InboxMessageKind.message,
    body: stringField(map, const ['body']),
    senderUserId: nullableStringField(map, const ['sender_user_id']),
    senderName: stringField(map, const ['sender_name']),
    delivery: InboxDelivery.fromApi(
      stringField(map, const ['delivery_status']),
    ),
    error: stringField(map, const ['error']),
    clientMessageId: stringField(map, const ['client_message_id']),
    createdAt:
        _time(field(map, const ['created_at'])) ??
        DateTime.fromMillisecondsSinceEpoch(0),
  );
}
