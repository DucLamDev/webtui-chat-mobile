import 'dart:async';

import 'package:dio/dio.dart';
import 'package:webtui_chat/core/error/failure.dart';
import 'package:webtui_chat/core/network/api_transport.dart';
import 'package:webtui_chat/core/result/result.dart';
import 'package:webtui_chat/features/inbox/domain/entities/inbox.dart';
import 'package:webtui_chat/features/inbox/domain/repositories/inbox_repository.dart';

Map<String, Object?> conversationJson({
  String id = 'c1',
  String status = 'open',
  String? assigneeId,
  int unread = 0,
  bool canReply = true,
  String blocked = '',
  String label = 'An · fb#vip',
  String preview = 'Xin chào shop',
  String lastAt = '2026-11-10T03:00:00Z',
}) => {
  'id': id,
  'workspace_id': 'ws',
  'source': {'id': 's1', 'kind': 'facebook', 'name': 'Trang A', 'code': 'fb'},
  'contact': {'id': 'k1', 'display_name': 'An'},
  'status': status,
  'assignee_id': assigneeId,
  'tags': [
    {'id': 't1', 'name': 'vip', 'color': '#2563eb'},
  ],
  'label': label,
  'last_message_preview': preview,
  'last_message_at': lastAt,
  'unread_count': unread,
  'can_reply': canReply,
  'reply_blocked_reason': blocked,
};

Map<String, Object?> messageJson({
  String id = 'm1',
  String direction = 'in',
  String kind = 'message',
  String body = 'Chào bạn',
  String delivery = 'received',
  String clientId = '',
  String at = '2026-11-10T03:00:00Z',
}) => {
  'id': id,
  'conversation_id': 'c1',
  'direction': direction,
  'kind': kind,
  'body': body,
  'delivery_status': delivery,
  'client_message_id': clientId,
  'created_at': at,
};

InboxConversation sampleConversation({
  String id = 'c1',
  InboxStatus status = InboxStatus.open,
  String? assigneeId,
  int unread = 0,
  bool canReply = true,
  String blocked = '',
  String label = 'An · fb#vip',
  DateTime? lastAt,
}) => InboxConversation(
  id: id,
  workspaceId: 'ws',
  source: const InboxSourceSummary(id: 's1', kind: 'facebook', code: 'fb'),
  contact: const InboxContact(displayName: 'An'),
  status: status,
  assigneeId: assigneeId,
  label: label,
  lastMessagePreview: 'Xin chào shop',
  lastMessageAt: lastAt ?? DateTime.utc(2026, 11, 10, 3),
  unreadCount: unread,
  canReply: canReply,
  replyBlockedReason: blocked,
);

InboxMessage sampleMessage({
  String id = 'm1',
  InboxDirection direction = InboxDirection.inbound,
  InboxMessageKind kind = InboxMessageKind.message,
  String body = 'Chào bạn',
  InboxDelivery delivery = InboxDelivery.received,
  String clientId = '',
  DateTime? at,
}) => InboxMessage(
  id: id,
  conversationId: 'c1',
  direction: direction,
  kind: kind,
  body: body,
  delivery: delivery,
  clientMessageId: clientId,
  createdAt: at ?? DateTime.utc(2026, 11, 10, 3),
);

/// Kho giả: ghi lại lời gọi, trả kết quả cấu hình sẵn.
final class FakeInboxRepository implements InboxRepository {
  List<InboxConversationPage> pages = [];
  Failure? listFailure;
  InboxConversation conversation = sampleConversation();
  Failure? conversationFailure;
  InboxMessagePage messagePage = const InboxMessagePage(items: []);
  List<Result<InboxMessage>> replyResults = [];
  Result<InboxMessage>? noteResult;
  List<InboxTag> tags = const [];

  final listCalls =
      <
        ({
          InboxStatusFilter status,
          InboxAssigneeFilter assignee,
          String? cursor,
        })
      >[];
  final sentReplies = <({String body, String clientId})>[];
  final notes = <String>[];
  final changes = <InboxConversationChange>[];
  var readCalls = 0;

  @override
  Future<Result<InboxConversationPage>> listConversations({
    required String workspaceId,
    InboxStatusFilter status = InboxStatusFilter.all,
    InboxAssigneeFilter assignee = InboxAssigneeFilter.all,
    String? cursor,
    int limit = 30,
  }) async {
    listCalls.add((status: status, assignee: assignee, cursor: cursor));
    final failure = listFailure;
    if (failure != null) return FailureResult(failure);
    if (pages.isEmpty) return const Success(InboxConversationPage(items: []));
    return Success(pages.length > 1 ? pages.removeAt(0) : pages.first);
  }

  @override
  Future<Result<InboxConversation>> getConversation({
    required String workspaceId,
    required String conversationId,
  }) async {
    final failure = conversationFailure;
    return failure != null ? FailureResult(failure) : Success(conversation);
  }

  @override
  Future<Result<InboxMessagePage>> listMessages({
    required String workspaceId,
    required String conversationId,
    String? cursor,
    int limit = 30,
  }) async => Success(messagePage);

  @override
  Future<Result<InboxMessage>> sendReply({
    required String workspaceId,
    required String conversationId,
    required String body,
    required String clientMessageId,
  }) async {
    sentReplies.add((body: body, clientId: clientMessageId));
    return replyResults.isEmpty
        ? Success(
            sampleMessage(
              id: 'srv-${sentReplies.length}',
              direction: InboxDirection.outbound,
              body: body,
              delivery: InboxDelivery.queued,
              clientId: clientMessageId,
              at: DateTime.now().toUtc(),
            ),
          )
        : replyResults.removeAt(0);
  }

  @override
  Future<Result<InboxMessage>> addNote({
    required String workspaceId,
    required String conversationId,
    required String body,
  }) async {
    notes.add(body);
    return noteResult ??
        Success(
          sampleMessage(
            id: 'note-${notes.length}',
            direction: InboxDirection.outbound,
            kind: InboxMessageKind.note,
            body: body,
            delivery: InboxDelivery.sent,
            at: DateTime.now().toUtc(),
          ),
        );
  }

  @override
  Future<Result<void>> markRead({
    required String workspaceId,
    required String conversationId,
  }) async {
    readCalls++;
    return const Success(null);
  }

  @override
  Future<Result<InboxConversation>> update({
    required String workspaceId,
    required String conversationId,
    required InboxConversationChange change,
  }) async {
    changes.add(change);
    return Success(
      sampleConversation(
        status: change.status ?? conversation.status,
        assigneeId: change.assigneeId == null
            ? conversation.assigneeId
            : (change.assigneeId!.isEmpty ? null : change.assigneeId),
      ),
    );
  }

  @override
  Future<Result<List<InboxTag>>> listTags({
    required String workspaceId,
  }) async => Success(tags);
}

final class FakeInboxRealtime implements InboxRealtimeRepository {
  final controller = StreamController<InboxRealtimeEvent>.broadcast();

  void emit(InboxRealtimeEvent event) => controller.add(event);

  @override
  Stream<InboxRealtimeEvent> watch({required String workspaceId}) =>
      controller.stream;
}

Failure failure(FailureKind kind, {String? code, String message = 'Lỗi'}) =>
    Failure(kind: kind, message: message, code: code);

/// HTTP giả: ghi đường dẫn, phương thức, body, query; trả dữ liệu cấu hình sẵn.
final class RecordingTransport implements ApiTransport {
  RecordingTransport(this.response);

  final Object? response;
  String? method;
  String? path;
  Object? body;
  Map<String, dynamic>? query;

  Future<Response<T>> _r<T>(
    String m,
    String p,
    Object? b,
    Map<String, dynamic>? q,
  ) async {
    method = m;
    path = p;
    body = b;
    query = q;
    return Response<T>(
      data: response as T?,
      requestOptions: RequestOptions(path: p),
      statusCode: 200,
    );
  }

  @override
  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) => _r('GET', path, null, queryParameters);

  @override
  Future<Response<T>> post<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) => _r('POST', path, data, queryParameters);

  @override
  Future<Response<T>> put<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) => _r('PUT', path, data, queryParameters);

  @override
  Future<Response<T>> patch<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) => _r('PATCH', path, data, queryParameters);

  @override
  Future<Response<T>> delete<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) => _r('DELETE', path, data, queryParameters);
}
