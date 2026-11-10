import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../../app/providers/foundation_providers.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/result/result.dart';
import '../../application/inbox_merge.dart';
import '../../application/inbox_messages.dart';
import '../../domain/entities/inbox.dart';
import '../../domain/repositories/inbox_repository.dart';
import 'inbox_access_provider.dart';

typedef InboxConversationArgs = ({String workspaceId, String conversationId});

final inboxConversationControllerProvider = StateNotifierProvider.autoDispose
    .family<
      InboxConversationController,
      InboxConversationState,
      InboxConversationArgs
    >((ref, args) {
      return InboxConversationController(
        workspaceId: args.workspaceId,
        conversationId: args.conversationId,
        repository: ref.watch(inboxRepositoryProvider),
        realtime: ref.watch(inboxRealtimeRepositoryProvider),
        loadCurrentUserId: () => ref.read(inboxCurrentUserIdProvider.future),
      )..start();
    });

/// Ô nhập đang ở chế độ nào.
enum InboxComposeMode { reply, note }

final class InboxConversationState {
  const InboxConversationState({
    this.conversation,
    this.messages = const [],
    this.nextCursor,
    this.isLoading = false,
    this.isLoadingMore = false,
    this.errorMessage,
    this.forbidden = false,
    this.notFound = false,
    this.mode = InboxComposeMode.reply,
    this.isSendingNote = false,
    this.isUpdating = false,
    this.actionError,
    this.tags = const [],
    this.currentUserId,
  });

  final InboxConversation? conversation;

  /// Cũ → mới.
  final List<InboxMessage> messages;
  final String? nextCursor;
  final bool isLoading;
  final bool isLoadingMore;
  final String? errorMessage;
  final bool forbidden;
  final bool notFound;
  final InboxComposeMode mode;
  final bool isSendingNote;
  final bool isUpdating;

  /// Lỗi thao tác gần nhất (gửi ghi chú, đổi trạng thái...) để báo người dùng.
  final String? actionError;
  final List<InboxTag> tags;
  final String? currentUserId;

  bool get hasMore => nextCursor?.isNotEmpty == true;

  bool get assignedToMe => conversation?.isAssignedTo(currentUserId) ?? false;

  /// Cho phép gõ trả lời: máy chủ báo `can_reply`.
  bool get canReply => conversation?.canReply ?? false;

  InboxConversationState copyWith({
    InboxConversation? conversation,
    List<InboxMessage>? messages,
    String? nextCursor,
    bool clearCursor = false,
    bool? isLoading,
    bool? isLoadingMore,
    String? errorMessage,
    bool clearError = false,
    bool? forbidden,
    bool? notFound,
    InboxComposeMode? mode,
    bool? isSendingNote,
    bool? isUpdating,
    String? actionError,
    bool clearActionError = false,
    List<InboxTag>? tags,
    String? currentUserId,
  }) {
    return InboxConversationState(
      conversation: conversation ?? this.conversation,
      messages: messages ?? this.messages,
      nextCursor: clearCursor ? null : nextCursor ?? this.nextCursor,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
      forbidden: forbidden ?? this.forbidden,
      notFound: notFound ?? this.notFound,
      mode: mode ?? this.mode,
      isSendingNote: isSendingNote ?? this.isSendingNote,
      isUpdating: isUpdating ?? this.isUpdating,
      actionError: clearActionError ? null : actionError ?? this.actionError,
      tags: tags ?? this.tags,
      currentUserId: currentUserId ?? this.currentUserId,
    );
  }
}

/// Một hội thoại khách: tin nhắn phân trang, trả lời (gửi lại dùng cùng
/// `client_message_id`), ghi chú nội bộ, nhận / bỏ nhận, trạng thái, tag, và
/// cập nhật realtime không trùng tin.
final class InboxConversationController
    extends StateNotifier<InboxConversationState> {
  InboxConversationController({
    required String workspaceId,
    required String conversationId,
    required InboxRepository repository,
    required InboxRealtimeRepository realtime,
    Future<String?> Function()? loadCurrentUserId,
    String Function()? newClientMessageId,
    DateTime Function()? now,
  }) : _workspaceId = workspaceId.trim(),
       _conversationId = conversationId.trim(),
       _repository = repository,
       _realtime = realtime,
       _loadCurrentUserId = loadCurrentUserId,
       _newClientMessageId = newClientMessageId ?? (() => const Uuid().v4()),
       _now = now ?? DateTime.now,
       super(const InboxConversationState());

  @visibleForTesting
  factory InboxConversationController.forTesting({
    required InboxRepository repository,
    required InboxRealtimeRepository realtime,
    String workspaceId = 'ws',
    String conversationId = 'c1',
    String? currentUserId,
    String Function()? newClientMessageId,
  }) {
    return InboxConversationController(
      workspaceId: workspaceId,
      conversationId: conversationId,
      repository: repository,
      realtime: realtime,
      loadCurrentUserId: () async => currentUserId,
      newClientMessageId: newClientMessageId,
    );
  }

  final String _workspaceId;
  final String _conversationId;
  final InboxRepository _repository;
  final InboxRealtimeRepository _realtime;
  final Future<String?> Function()? _loadCurrentUserId;
  final String Function() _newClientMessageId;
  final DateTime Function() _now;
  StreamSubscription<InboxRealtimeEvent>? _subscription;
  int _generation = 0;

  void start() {
    unawaited(_loadUser());
    _subscription ??= _realtime
        .watch(workspaceId: _workspaceId)
        .listen(_onEvent, onError: (Object _) {});
    unawaited(load());
  }

  Future<void> _loadUser() async {
    final loader = _loadCurrentUserId;
    if (loader == null) return;
    try {
      final id = (await loader())?.trim();
      if (mounted && id != null && id.isNotEmpty) {
        state = state.copyWith(currentUserId: id);
      }
    } on Object {
      // Không biết mã người dùng thì không nhận được hội thoại (báo lỗi khi bấm).
    }
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  void setMode(InboxComposeMode mode) {
    if (mode == state.mode) return;
    state = state.copyWith(mode: mode);
  }

  void clearActionError() {
    if (state.actionError != null) {
      state = state.copyWith(clearActionError: true);
    }
  }

  /// Tải hội thoại + trang tin mới nhất, rồi đánh dấu đã đọc.
  Future<void> load() async {
    final generation = ++_generation;
    state = state.copyWith(
      isLoading: true,
      isLoadingMore: false,
      clearError: true,
      forbidden: false,
      notFound: false,
    );
    final results = await Future.wait([
      _repository.getConversation(
        workspaceId: _workspaceId,
        conversationId: _conversationId,
      ),
      _repository.listMessages(
        workspaceId: _workspaceId,
        conversationId: _conversationId,
      ),
    ]);
    if (!mounted || generation != _generation) return;
    final conversationResult = results[0] as Result<InboxConversation>;
    final messagesResult = results[1] as Result<InboxMessagePage>;
    final failure =
        conversationResult.failureOrNull ?? messagesResult.failureOrNull;
    if (failure != null) {
      state = state.copyWith(
        isLoading: false,
        forbidden: failure.kind == FailureKind.forbidden,
        notFound: failure.kind == FailureKind.notFound,
        errorMessage:
            failure.kind == FailureKind.forbidden ||
                failure.kind == FailureKind.notFound
            ? null
            : failure.message,
      );
      return;
    }
    final page = (messagesResult as Success<InboxMessagePage>).value;
    final local = state.messages.where((m) => m.isLocal);
    state = state.copyWith(
      conversation: (conversationResult as Success<InboxConversation>).value,
      messages: mergeInboxMessages(page.items, local),
      nextCursor: page.nextCursor,
      clearCursor: page.nextCursor == null,
      isLoading: false,
    );
    unawaited(markRead());
  }

  /// Tải lại im lặng sau khi nối lại realtime: giữ tin cục bộ chưa gửi xong.
  Future<void> refresh() async {
    final conversation = await _repository.getConversation(
      workspaceId: _workspaceId,
      conversationId: _conversationId,
    );
    final page = await _repository.listMessages(
      workspaceId: _workspaceId,
      conversationId: _conversationId,
    );
    if (!mounted) return;
    if (conversation case Success(value: final value)) {
      state = state.copyWith(conversation: value);
    }
    if (page case Success(value: final value)) {
      state = state.copyWith(
        messages: mergeInboxMessages(state.messages, value.items),
      );
    }
  }

  Future<void> loadOlder() async {
    final cursor = state.nextCursor;
    if (cursor == null || state.isLoading || state.isLoadingMore) return;
    final generation = _generation;
    state = state.copyWith(isLoadingMore: true);
    final result = await _repository.listMessages(
      workspaceId: _workspaceId,
      conversationId: _conversationId,
      cursor: cursor,
    );
    // Đã tải lại trong lúc chờ: bỏ trang cũ này (load() đã đặt lại trạng thái).
    if (!mounted || generation != _generation) return;
    switch (result) {
      case Success(value: final page):
        state = state.copyWith(
          messages: mergeInboxMessages(state.messages, page.items),
          nextCursor: page.nextCursor,
          clearCursor: page.nextCursor == null,
          isLoadingMore: false,
        );
      case FailureResult(failure: final failure):
        state = state.copyWith(
          isLoadingMore: false,
          actionError: inboxActionFailureMessage(failure),
        );
    }
  }

  Future<void> markRead() async {
    final result = await _repository.markRead(
      workspaceId: _workspaceId,
      conversationId: _conversationId,
    );
    final conversation = state.conversation;
    if (mounted && result.isSuccess && conversation != null) {
      state = state.copyWith(conversation: _withUnread(conversation, 0));
    }
  }

  /// Gửi trả lời cho khách. Tin hiện ngay ở trạng thái "Đang gửi"; lỗi thì
  /// thành "Gửi lỗi" và [retry] gửi lại với cùng `client_message_id`.
  Future<void> sendReply(String text) async {
    final body = text.trim();
    if (body.isEmpty || !state.canReply) return;
    final clientId = _newClientMessageId();
    final local = InboxMessage(
      id: '${InboxMessage.localIdPrefix}$clientId',
      conversationId: _conversationId,
      direction: InboxDirection.outbound,
      body: body,
      senderUserId: state.currentUserId,
      delivery: InboxDelivery.sending,
      clientMessageId: clientId,
      createdAt: _now(),
    );
    state = state.copyWith(
      messages: mergeInboxMessages(state.messages, [local]),
      clearActionError: true,
    );
    await _deliver(local);
  }

  /// Gửi lại tin lỗi, giữ nguyên `client_message_id` để không tạo tin thứ hai.
  Future<void> retry(String clientMessageId) async {
    final index = state.messages.indexWhere(
      (m) =>
          m.clientMessageId == clientMessageId &&
          m.delivery == InboxDelivery.failed &&
          m.isLocal,
    );
    if (index < 0) return;
    final sending = state.messages[index].copyWith(
      delivery: InboxDelivery.sending,
      error: '',
    );
    state = state.copyWith(
      messages: mergeInboxMessages(state.messages, [sending]),
    );
    await _deliver(sending);
  }

  Future<void> _deliver(InboxMessage local) async {
    final result = await _repository.sendReply(
      workspaceId: _workspaceId,
      conversationId: _conversationId,
      body: local.body,
      clientMessageId: local.clientMessageId,
    );
    if (!mounted) return;
    switch (result) {
      case Success(value: final message):
        state = state.copyWith(
          messages: mergeInboxMessages(state.messages, [
            _withClientId(message, local.clientMessageId),
          ]),
        );
      case FailureResult(failure: final failure):
        final failed = local.copyWith(
          delivery: InboxDelivery.failed,
          error: inboxActionFailureMessage(failure),
          retryable: !inboxFailureIsPermanent(failure),
        );
        state = state.copyWith(
          messages: mergeInboxMessages(state.messages, [failed]),
        );
    }
  }

  /// Thêm ghi chú nội bộ. Trả `true` khi thành công (màn xoá ô nhập); thất bại
  /// thì giữ chữ đã gõ và báo lỗi.
  Future<bool> addNote(String text) async {
    final body = text.trim();
    if (body.isEmpty || state.isSendingNote) return false;
    state = state.copyWith(isSendingNote: true, clearActionError: true);
    final result = await _repository.addNote(
      workspaceId: _workspaceId,
      conversationId: _conversationId,
      body: body,
    );
    if (!mounted) return false;
    switch (result) {
      case Success(value: final message):
        state = state.copyWith(
          isSendingNote: false,
          messages: mergeInboxMessages(state.messages, [message]),
        );
        return true;
      case FailureResult(failure: final failure):
        state = state.copyWith(
          isSendingNote: false,
          actionError: inboxActionFailureMessage(failure),
        );
        return false;
    }
  }

  Future<void> claim() async {
    final me = state.currentUserId;
    if (me == null || me.isEmpty) {
      state = state.copyWith(
        actionError: 'Chưa xác định được tài khoản của bạn.',
      );
      return;
    }
    await _update(InboxConversationChange(assigneeId: me));
  }

  Future<void> release() =>
      _update(const InboxConversationChange(assigneeId: ''));

  Future<void> setStatus(InboxStatus status) {
    if (status == InboxStatus.unknown || status == state.conversation?.status) {
      return Future.value();
    }
    return _update(InboxConversationChange(status: status));
  }

  Future<void> setTags(List<String> tagIds) =>
      _update(InboxConversationChange(tagIds: tagIds));

  /// Danh sách tag của workspace (tải một lần).
  Future<List<InboxTag>> loadTags() async {
    if (state.tags.isNotEmpty) return state.tags;
    final result = await _repository.listTags(workspaceId: _workspaceId);
    if (!mounted) return const [];
    switch (result) {
      case Success(value: final tags):
        state = state.copyWith(tags: tags);
        return tags;
      case FailureResult(failure: final failure):
        state = state.copyWith(actionError: inboxActionFailureMessage(failure));
        return const [];
    }
  }

  Future<void> _update(InboxConversationChange change) async {
    if (state.isUpdating) {
      state = state.copyWith(
        actionError: 'Đang cập nhật, thử lại sau giây lát.',
      );
      return;
    }
    state = state.copyWith(isUpdating: true, clearActionError: true);
    final result = await _repository.update(
      workspaceId: _workspaceId,
      conversationId: _conversationId,
      change: change,
    );
    if (!mounted) return;
    switch (result) {
      case Success(value: final conversation):
        state = state.copyWith(isUpdating: false, conversation: conversation);
      case FailureResult(failure: final failure):
        state = state.copyWith(
          isUpdating: false,
          actionError: inboxActionFailureMessage(failure),
        );
    }
  }

  void _onEvent(InboxRealtimeEvent event) {
    if (!mounted) return;
    switch (event) {
      case InboxConversationUpdatedEvent(:final conversation):
        if (conversation.id != _conversationId) return;
        // Đang mở màn thì không để số chưa đọc tăng lên.
        state = state.copyWith(
          conversation: conversation.unreadCount > 0
              ? _withUnread(conversation, 0)
              : conversation,
        );
      case InboxMessageCreatedEvent(:final message):
        if (message.conversationId != _conversationId) return;
        state = state.copyWith(
          messages: mergeInboxMessages(state.messages, [message]),
        );
        if (message.isFromCustomer) unawaited(markRead());
      case InboxRealtimeReconnected():
        unawaited(refresh());
    }
  }
}

/// Tin máy chủ trả về luôn mang `client_message_id` đã gửi (máy chủ cũ có thể
/// bỏ trống) để thay đúng tin cục bộ.
InboxMessage _withClientId(InboxMessage message, String clientMessageId) {
  if (message.clientMessageId.isNotEmpty) return message;
  return InboxMessage(
    id: message.id,
    conversationId: message.conversationId,
    direction: message.direction,
    kind: message.kind,
    body: message.body,
    senderUserId: message.senderUserId,
    senderName: message.senderName,
    delivery: message.delivery,
    error: message.error,
    clientMessageId: clientMessageId,
    createdAt: message.createdAt,
  );
}

InboxConversation _withUnread(InboxConversation c, int unread) {
  return InboxConversation(
    id: c.id,
    workspaceId: c.workspaceId,
    source: c.source,
    contact: c.contact,
    subject: c.subject,
    status: c.status,
    assigneeId: c.assigneeId,
    assigneeName: c.assigneeName,
    tags: c.tags,
    label: c.label,
    lastMessagePreview: c.lastMessagePreview,
    lastMessageAt: c.lastMessageAt,
    lastInboundAt: c.lastInboundAt,
    unreadCount: unread,
    canReply: c.canReply,
    replyBlockedReason: c.replyBlockedReason,
    createdAt: c.createdAt,
    updatedAt: c.updatedAt,
  );
}
