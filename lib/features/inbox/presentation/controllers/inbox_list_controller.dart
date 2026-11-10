import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers/foundation_providers.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/result/result.dart';
import '../../application/inbox_merge.dart';
import '../../domain/entities/inbox.dart';
import '../../domain/repositories/inbox_repository.dart';
import 'inbox_access_provider.dart';

final inboxListControllerProvider = StateNotifierProvider.autoDispose
    .family<InboxListController, InboxListState, String>((ref, workspaceId) {
      final controller = InboxListController(
        workspaceId: workspaceId,
        repository: ref.watch(inboxRepositoryProvider),
        realtime: ref.watch(inboxRealtimeRepositoryProvider),
        loadCurrentUserId: () => ref.read(inboxCurrentUserIdProvider.future),
      )..start();
      return controller;
    });

final class InboxListState {
  const InboxListState({
    this.status = InboxStatusFilter.open,
    this.assignee = InboxAssigneeFilter.all,
    this.items = const [],
    this.nextCursor,
    this.hasLoaded = false,
    this.isLoading = false,
    this.isLoadingMore = false,
    this.errorMessage,
    this.forbidden = false,
    this.currentUserId,
  });

  final InboxStatusFilter status;
  final InboxAssigneeFilter assignee;
  final List<InboxConversation> items;
  final String? nextCursor;
  final bool hasLoaded;
  final bool isLoading;
  final bool isLoadingMore;
  final String? errorMessage;

  /// Máy chủ trả 403: không có quyền xem.
  final bool forbidden;
  final String? currentUserId;

  bool get hasMore => nextCursor?.isNotEmpty == true;

  /// Hội thoại có thuộc bộ lọc hiện tại không (dùng khi nhận realtime).
  bool matches(InboxConversation conversation) {
    final wanted = status.status;
    if (wanted != null && conversation.status != wanted) return false;
    return switch (assignee) {
      InboxAssigneeFilter.all => true,
      InboxAssigneeFilter.unassigned => !conversation.isAssigned,
      InboxAssigneeFilter.mine => conversation.isAssignedTo(currentUserId),
    };
  }

  InboxListState copyWith({
    InboxStatusFilter? status,
    InboxAssigneeFilter? assignee,
    List<InboxConversation>? items,
    String? nextCursor,
    bool clearCursor = false,
    bool? hasLoaded,
    bool? isLoading,
    bool? isLoadingMore,
    String? errorMessage,
    bool clearError = false,
    bool? forbidden,
    String? currentUserId,
  }) {
    return InboxListState(
      status: status ?? this.status,
      assignee: assignee ?? this.assignee,
      items: items ?? this.items,
      nextCursor: clearCursor ? null : nextCursor ?? this.nextCursor,
      hasLoaded: hasLoaded ?? this.hasLoaded,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
      forbidden: forbidden ?? this.forbidden,
      currentUserId: currentUserId ?? this.currentUserId,
    );
  }
}

/// Danh sách hội thoại khách: lọc trạng thái / người xử lý, phân trang
/// `cursor`, cập nhật realtime (không trùng hội thoại).
final class InboxListController extends StateNotifier<InboxListState> {
  InboxListController({
    required String workspaceId,
    required InboxRepository repository,
    required InboxRealtimeRepository realtime,
    Future<String?> Function()? loadCurrentUserId,
  }) : _workspaceId = workspaceId.trim(),
       _repository = repository,
       _realtime = realtime,
       _loadCurrentUserId = loadCurrentUserId,
       super(const InboxListState());

  @visibleForTesting
  factory InboxListController.forTesting({
    required InboxRepository repository,
    required InboxRealtimeRepository realtime,
    String workspaceId = 'ws',
    String? currentUserId,
  }) {
    return InboxListController(
      workspaceId: workspaceId,
      repository: repository,
      realtime: realtime,
      loadCurrentUserId: () async => currentUserId,
    );
  }

  final String _workspaceId;
  final InboxRepository _repository;
  final InboxRealtimeRepository _realtime;
  final Future<String?> Function()? _loadCurrentUserId;
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
      // Không biết mã người dùng thì chỉ "Của tôi" không khớp realtime.
    }
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  Future<void> setFilters({
    InboxStatusFilter? status,
    InboxAssigneeFilter? assignee,
  }) async {
    final nextStatus = status ?? state.status;
    final nextAssignee = assignee ?? state.assignee;
    if (nextStatus == state.status && nextAssignee == state.assignee) return;
    state = state.copyWith(
      status: nextStatus,
      assignee: nextAssignee,
      items: const [],
      clearCursor: true,
      hasLoaded: false,
    );
    await load();
  }

  /// Tải lại từ đầu, có vòng quay tải (kéo để tải lại).
  Future<void> load() async {
    final generation = ++_generation;
    state = state.copyWith(
      isLoading: true,
      isLoadingMore: false,
      clearError: true,
      forbidden: false,
    );
    final result = await _repository.listConversations(
      workspaceId: _workspaceId,
      status: state.status,
      assignee: state.assignee,
    );
    if (!mounted || generation != _generation) return;
    switch (result) {
      case Success(value: final page):
        state = state.copyWith(
          items: page.items,
          nextCursor: page.nextCursor,
          clearCursor: page.nextCursor == null,
          hasLoaded: true,
          isLoading: false,
        );
      case FailureResult(failure: final failure):
        final forbidden = failure.kind == FailureKind.forbidden;
        state = state.copyWith(
          isLoading: false,
          hasLoaded: true,
          items: const [],
          forbidden: forbidden,
          errorMessage: forbidden ? null : failure.message,
        );
    }
  }

  /// Tải lại im lặng (nối lại realtime): lỗi mạng không xoá danh sách đang có.
  Future<void> refresh() async {
    if (state.isLoading || state.isLoadingMore) return;
    final generation = ++_generation;
    final status = state.status;
    final assignee = state.assignee;
    final result = await _repository.listConversations(
      workspaceId: _workspaceId,
      status: status,
      assignee: assignee,
    );
    if (!mounted ||
        generation != _generation ||
        status != state.status ||
        assignee != state.assignee) {
      return;
    }
    if (result case Success(value: final page)) {
      state = state.copyWith(
        items: page.items,
        nextCursor: page.nextCursor,
        clearCursor: page.nextCursor == null,
        hasLoaded: true,
        clearError: true,
        forbidden: false,
      );
    } else if (result case FailureResult(
      failure: final failure,
    ) when failure.kind == FailureKind.forbidden) {
      state = state.copyWith(forbidden: true, items: const []);
    }
  }

  Future<void> loadMore() async {
    final cursor = state.nextCursor;
    if (cursor == null || state.isLoading || state.isLoadingMore) return;
    final generation = _generation;
    state = state.copyWith(isLoadingMore: true);
    final result = await _repository.listConversations(
      workspaceId: _workspaceId,
      status: state.status,
      assignee: state.assignee,
      cursor: cursor,
    );
    if (!mounted || generation != _generation) return;
    switch (result) {
      case Success(value: final page):
        final known = state.items.map((item) => item.id).toSet();
        state = state.copyWith(
          items: [
            ...state.items,
            ...page.items.where((item) => !known.contains(item.id)),
          ],
          nextCursor: page.nextCursor,
          clearCursor: page.nextCursor == null,
          isLoadingMore: false,
        );
      case FailureResult(failure: final failure):
        state = state.copyWith(
          isLoadingMore: false,
          errorMessage: failure.message,
        );
    }
  }

  void _onEvent(InboxRealtimeEvent event) {
    if (!mounted) return;
    switch (event) {
      case InboxConversationUpdatedEvent(:final conversation):
        if (state.forbidden || !state.hasLoaded) return;
        if (conversation.workspaceId.isNotEmpty &&
            conversation.workspaceId != _workspaceId) {
          return;
        }
        state = state.copyWith(
          items: upsertInboxConversation(
            state.items,
            conversation,
            matches: state.matches,
          ),
        );
      case InboxRealtimeReconnected():
        unawaited(refresh());
      case InboxMessageCreatedEvent():
        // Hội thoại đi kèm sự kiện cập nhật riêng; không cần xử lý thêm.
        break;
    }
  }
}
