import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers/foundation_providers.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/result/result.dart';
import '../../application/use_cases/approval_use_cases.dart';
import '../../domain/entities/approval.dart';
import '../../domain/repositories/approval_repository.dart';

final approvalListControllerProvider = StateNotifierProvider.autoDispose
    .family<ApprovalListController, ApprovalListState, String>((
      ref,
      workspaceId,
    ) {
      return ApprovalListController(
        workspaceId: workspaceId,
        list: ref.watch(listApprovalsUseCaseProvider),
      )..start();
    });

/// Chu kỳ tải lại danh sách khi màn đang mở.
const approvalRefreshInterval = Duration(seconds: 30);

final class ApprovalListState {
  const ApprovalListState({
    this.filter = ApprovalFilter.pending,
    this.items = const [],
    this.nextCursor,
    this.hasLoaded = false,
    this.isLoading = false,
    this.isLoadingMore = false,
    this.errorMessage,
    this.forbidden = false,
  });

  final ApprovalFilter filter;
  final List<ApprovalRequest> items;
  final String? nextCursor;
  final bool hasLoaded;
  final bool isLoading;
  final bool isLoadingMore;
  final String? errorMessage;

  /// Máy chủ trả 403: không có quyền xem.
  final bool forbidden;

  bool get hasMore => nextCursor?.isNotEmpty == true;

  ApprovalListState copyWith({
    ApprovalFilter? filter,
    List<ApprovalRequest>? items,
    String? nextCursor,
    bool clearCursor = false,
    bool? hasLoaded,
    bool? isLoading,
    bool? isLoadingMore,
    String? errorMessage,
    bool clearError = false,
    bool? forbidden,
  }) {
    return ApprovalListState(
      filter: filter ?? this.filter,
      items: items ?? this.items,
      nextCursor: clearCursor ? null : nextCursor ?? this.nextCursor,
      hasLoaded: hasLoaded ?? this.hasLoaded,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
      forbidden: forbidden ?? this.forbidden,
    );
  }
}

/// Danh sách phê duyệt: hai tab Đang chờ / Đã xử lý, tải thêm theo `cursor`,
/// tự tải lại im lặng mỗi 30 giây (và khi gọi [refresh] lúc quay lại màn).
final class ApprovalListController extends StateNotifier<ApprovalListState> {
  ApprovalListController({
    required String workspaceId,
    required ListApprovalsUseCase list,
    Duration refreshInterval = approvalRefreshInterval,
  }) : _workspaceId = workspaceId.trim(),
       _list = list,
       _refreshInterval = refreshInterval,
       super(const ApprovalListState());

  @visibleForTesting
  factory ApprovalListController.forTesting({
    required ApprovalRepository repository,
    String workspaceId = 'workspace-1',
    Duration refreshInterval = Duration.zero,
  }) {
    return ApprovalListController(
      workspaceId: workspaceId,
      list: ListApprovalsUseCase(repository),
      refreshInterval: refreshInterval,
    );
  }

  final String _workspaceId;
  final ListApprovalsUseCase _list;
  final Duration _refreshInterval;
  Timer? _timer;
  int _generation = 0;

  String get workspaceId => _workspaceId;

  void start() {
    if (_refreshInterval > Duration.zero) {
      _timer ??= Timer.periodic(_refreshInterval, (_) => unawaited(refresh()));
    }
    unawaited(load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> setFilter(ApprovalFilter filter) async {
    if (filter == state.filter) return;
    state = state.copyWith(
      filter: filter,
      items: const [],
      clearCursor: true,
      hasLoaded: false,
    );
    await load();
  }

  /// Tải lại từ đầu, có vòng quay tải.
  Future<void> load() async {
    final generation = ++_generation;
    state = state.copyWith(
      isLoading: true,
      isLoadingMore: false,
      clearError: true,
      forbidden: false,
    );
    final result = await _list.execute(
      workspaceId: _workspaceId,
      filter: state.filter,
    );
    if (!mounted || generation != _generation) return;
    _apply(result);
  }

  /// Tải lại im lặng (hẹn giờ / quay lại màn): lỗi mạng không xoá danh sách đang có.
  Future<void> refresh() async {
    if (state.isLoading || state.isLoadingMore) return;
    final generation = ++_generation;
    final filter = state.filter;
    final result = await _list.execute(
      workspaceId: _workspaceId,
      filter: filter,
    );
    if (!mounted || generation != _generation || filter != state.filter) return;
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
    final result = await _list.execute(
      workspaceId: _workspaceId,
      filter: state.filter,
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

  void _apply(Result<ApprovalPage> result) {
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
        state = state.copyWith(
          isLoading: false,
          hasLoaded: true,
          items: const [],
          forbidden: failure.kind == FailureKind.forbidden,
          errorMessage: failure.kind == FailureKind.forbidden
              ? null
              : failure.message,
        );
    }
  }
}
