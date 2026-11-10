import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers/foundation_providers.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/result/result.dart';
import '../../application/use_cases/customer_ticket_use_cases.dart';
import '../../domain/entities/customer_ticket.dart';
import '../../domain/entities/customer_ticket_realtime_event.dart';
import '../../domain/repositories/customer_ticket_repository.dart';

final customerTicketListControllerProvider = StateNotifierProvider.autoDispose
    .family<CustomerTicketListController, CustomerTicketListState, String>((
      ref,
      workspaceId,
    ) {
      final loadProfile = ref.watch(loadProfileUseCaseProvider);
      return CustomerTicketListController(
        workspaceId: workspaceId,
        listTickets: ref.watch(listCustomerTicketsUseCaseProvider),
        watchTickets: ref.watch(watchCustomerTicketsUseCaseProvider),
        loadCurrentUserId: () async =>
            (await loadProfile.execute()).valueOrNull?.id,
      )..start();
    });

final class CustomerTicketListState {
  const CustomerTicketListState({
    this.filter = CustomerTicketFilter.unanswered,
    this.search = '',
    this.items = const [],
    this.counts = CustomerTicketCounts.empty,
    this.total = 0,
    this.page = 0,
    this.isLoading = false,
    this.isLoadingMore = false,
    this.errorMessage,
    this.loadMoreErrorMessage,
    this.forbidden = false,
    this.currentUserId,
  });

  final CustomerTicketFilter filter;
  final String search;
  final List<CustomerTicketSummary> items;
  final CustomerTicketCounts counts;
  final int total;

  /// Trang cuối đã tải (0 = chưa tải trang nào).
  final int page;
  final bool isLoading;
  final bool isLoadingMore;
  final String? errorMessage;
  final String? loadMoreErrorMessage;

  /// Máy chủ trả 403 (thiếu quyền / không phải máy chủ nội bộ).
  final bool forbidden;
  final String? currentUserId;

  bool get hasLoaded => page > 0;

  bool get hasMore => hasLoaded && items.length < total;

  CustomerTicketListState copyWith({
    CustomerTicketFilter? filter,
    String? search,
    List<CustomerTicketSummary>? items,
    CustomerTicketCounts? counts,
    int? total,
    int? page,
    bool? isLoading,
    bool? isLoadingMore,
    String? errorMessage,
    bool clearError = false,
    String? loadMoreErrorMessage,
    bool clearLoadMoreError = false,
    bool? forbidden,
    String? currentUserId,
  }) {
    return CustomerTicketListState(
      filter: filter ?? this.filter,
      search: search ?? this.search,
      items: items ?? this.items,
      counts: counts ?? this.counts,
      total: total ?? this.total,
      page: page ?? this.page,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
      loadMoreErrorMessage: clearLoadMoreError
          ? null
          : loadMoreErrorMessage ?? this.loadMoreErrorMessage,
      forbidden: forbidden ?? this.forbidden,
      currentUserId: currentUserId ?? this.currentUserId,
    );
  }
}

/// Danh sách ticket: lọc, tìm, cuộn tải thêm; tự tải lại khi có sự kiện
/// realtime của phòng ticket và mỗi 60 giây khi màn đang mở.
final class CustomerTicketListController
    extends StateNotifier<CustomerTicketListState> {
  CustomerTicketListController({
    required String workspaceId,
    required ListCustomerTicketsUseCase listTickets,
    required WatchCustomerTicketsUseCase watchTickets,
    required Future<String?> Function() loadCurrentUserId,
    Duration refreshInterval = const Duration(seconds: 60),
    Duration realtimeDebounce = const Duration(milliseconds: 400),
    CustomerTicketListState initialState = const CustomerTicketListState(),
  }) : _workspaceId = workspaceId.trim(),
       _listTickets = listTickets,
       _watchTickets = watchTickets,
       _loadCurrentUserId = loadCurrentUserId,
       _refreshInterval = refreshInterval,
       _realtimeDebounce = realtimeDebounce,
       super(initialState);

  /// Bộ dựng cho test: dùng use case thật trên repository giả; tắt hẹn giờ.
  @visibleForTesting
  factory CustomerTicketListController.forTesting({
    required CustomerTicketRepository repository,
    CustomerTicketRealtimeRepository? realtime,
    String workspaceId = 'workspace-1',
    String? currentUserId,
    Duration refreshInterval = Duration.zero,
    Duration realtimeDebounce = Duration.zero,
  }) {
    return CustomerTicketListController(
      workspaceId: workspaceId,
      listTickets: ListCustomerTicketsUseCase(repository),
      watchTickets: WatchCustomerTicketsUseCase(
        realtime ?? const _SilentRealtime(),
      ),
      loadCurrentUserId: () async => currentUserId,
      refreshInterval: refreshInterval,
      realtimeDebounce: realtimeDebounce,
    );
  }

  static const pageSize = customerTicketDefaultPageSize;

  /// Tải lại im lặng tối đa chừng này trang đã cuộn qua.
  static const _maxRefreshPages = 5;

  final String _workspaceId;
  final ListCustomerTicketsUseCase _listTickets;
  final WatchCustomerTicketsUseCase _watchTickets;
  final Future<String?> Function() _loadCurrentUserId;
  final Duration _refreshInterval;
  final Duration _realtimeDebounce;

  StreamSubscription<CustomerTicketRealtimeEvent>? _subscription;
  Timer? _refreshTimer;
  Timer? _debounceTimer;
  int _generation = 0;
  bool _refreshing = false;
  bool _refreshAgain = false;

  String get workspaceId => _workspaceId;

  void start() {
    _subscription ??= _watchTickets
        .execute(_workspaceId)
        .listen(_handleRealtime, onError: (Object _) {});
    if (_refreshInterval > Duration.zero) {
      _refreshTimer ??= Timer.periodic(
        _refreshInterval,
        (_) => unawaited(refresh()),
      );
    }
    unawaited(_loadUser());
    unawaited(load());
  }

  Future<void> _loadUser() async {
    final userId = await _loadCurrentUserId();
    if (mounted && userId != null && userId.trim().isNotEmpty) {
      state = state.copyWith(currentUserId: userId.trim());
    }
  }

  /// Tải lại từ trang 1 (đổi bộ lọc / tìm kiếm / thử lại).
  Future<void> load() async {
    final generation = ++_generation;
    state = state.copyWith(
      isLoading: true,
      isLoadingMore: false,
      clearError: true,
      clearLoadMoreError: true,
      forbidden: false,
    );
    final result = await _fetch(1);
    if (!mounted || generation != _generation) return;
    switch (result) {
      case Success(value: final page):
        state = state.copyWith(
          items: _unique(page.items),
          total: page.total,
          counts: _countsOr(page.counts),
          page: 1,
          isLoading: false,
        );
      case FailureResult(failure: final failure):
        state = state.copyWith(
          items: const [],
          total: 0,
          page: 0,
          isLoading: false,
          errorMessage: failure.message,
          forbidden: failure.kind == FailureKind.forbidden,
        );
    }
  }

  /// Tải lại im lặng (kéo làm mới, realtime, mỗi 60 giây): giữ danh sách cũ
  /// nếu lỗi mạng; tải lại đủ số trang đã cuộn qua (tối đa 5).
  Future<void> refresh() async {
    if (!state.hasLoaded || state.errorMessage != null) {
      if (!state.isLoading) await load();
      return;
    }
    if (_refreshing || state.isLoading || state.isLoadingMore) {
      _refreshAgain = true;
      return;
    }
    _refreshing = true;
    try {
      final generation = _generation;
      final pages = math.max(
        1,
        math.min((state.items.length / pageSize).ceil(), _maxRefreshPages),
      );
      final collected = <CustomerTicketSummary>[];
      CustomerTicketPage? last;
      for (var page = 1; page <= pages; page++) {
        final result = await _fetch(page);
        if (!mounted || generation != _generation) return;
        final value = result.valueOrNull;
        if (value == null) {
          final failure = result.failureOrNull;
          if (failure?.kind == FailureKind.forbidden) {
            state = state.copyWith(
              items: const [],
              total: 0,
              page: 0,
              errorMessage: failure!.message,
              forbidden: true,
            );
          }
          return;
        }
        collected.addAll(value.items);
        last = value;
        if (value.items.length < pageSize) break;
      }
      final page = last;
      if (page == null) return;
      state = state.copyWith(
        items: _unique(collected),
        total: page.total,
        counts: _countsOr(page.counts),
        page: (collected.length / pageSize).ceil().clamp(1, pages),
        clearError: true,
      );
    } finally {
      _refreshing = false;
      if (_refreshAgain && mounted) {
        _refreshAgain = false;
        unawaited(refresh());
      }
    }
  }

  Future<void> loadMore() async {
    if (!state.hasMore ||
        state.isLoading ||
        state.isLoadingMore ||
        state.loadMoreErrorMessage != null) {
      return;
    }
    await _loadNextPage();
  }

  /// Thử lại tải thêm sau khi lỗi.
  Future<void> retryLoadMore() async {
    if (!state.hasMore || state.isLoading || state.isLoadingMore) return;
    await _loadNextPage();
  }

  Future<void> _loadNextPage() async {
    final generation = _generation;
    final nextPage = state.page + 1;
    state = state.copyWith(isLoadingMore: true, clearLoadMoreError: true);
    final result = await _fetch(nextPage);
    if (!mounted || generation != _generation) return;
    switch (result) {
      case Success(value: final page):
        state = state.copyWith(
          items: _unique([...state.items, ...page.items]),
          total: page.total,
          counts: _countsOr(page.counts),
          page: nextPage,
          isLoadingMore: false,
        );
      case FailureResult(failure: final failure):
        state = state.copyWith(
          isLoadingMore: false,
          loadMoreErrorMessage: failure.message,
        );
    }
    if (_refreshAgain && mounted) {
      _refreshAgain = false;
      unawaited(refresh());
    }
  }

  Future<void> setFilter(CustomerTicketFilter filter) async {
    if (filter == state.filter && state.hasLoaded) return;
    state = state.copyWith(filter: filter, items: const [], page: 0);
    await load();
  }

  Future<void> setSearch(String query) async {
    final normalized = query.trim();
    if (normalized == state.search) return;
    state = state.copyWith(search: normalized, items: const [], page: 0);
    await load();
  }

  Future<Result<CustomerTicketPage>> _fetch(int page) {
    return _listTickets.execute(
      workspaceId: _workspaceId,
      filter: state.filter,
      search: state.search,
      page: page,
      perPage: pageSize,
    );
  }

  void _handleRealtime(CustomerTicketRealtimeEvent event) {
    if (!mounted) return;
    // Nháp AI lỗi không đổi danh sách.
    if (event.reason == CustomerTicketRealtimeReason.aiDraftFailed) return;
    final counts = event.counts;
    if (counts != null) {
      state = state.copyWith(counts: counts);
    }
    _debounceTimer?.cancel();
    if (_realtimeDebounce <= Duration.zero) {
      unawaited(refresh());
      return;
    }
    _debounceTimer = Timer(_realtimeDebounce, () => unawaited(refresh()));
  }

  CustomerTicketCounts _countsOr(CustomerTicketCounts counts) {
    final empty =
        counts.unanswered == 0 && counts.answered == 0 && counts.total == 0;
    return empty && state.hasLoaded ? state.counts : counts;
  }

  @override
  void dispose() {
    _generation++;
    _refreshTimer?.cancel();
    _debounceTimer?.cancel();
    unawaited(_subscription?.cancel());
    super.dispose();
  }
}

List<CustomerTicketSummary> _unique(List<CustomerTicketSummary> items) {
  final seen = <String>{};
  return [
    for (final item in items)
      if (seen.add(item.ticketId)) item,
  ];
}

final class _SilentRealtime implements CustomerTicketRealtimeRepository {
  const _SilentRealtime();

  @override
  Stream<CustomerTicketRealtimeEvent> watch({required String workspaceId}) {
    return const Stream.empty();
  }
}
