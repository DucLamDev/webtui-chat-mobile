import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers/foundation_providers.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/result/result.dart';
import '../../application/use_cases/customer_ticket_use_cases.dart';
import '../../domain/entities/customer_ticket.dart';
import '../../domain/entities/customer_ticket_realtime_event.dart';
import '../../domain/repositories/customer_ticket_repository.dart';

typedef CustomerTicketDetailArgs = ({String workspaceId, String ticketId});

final customerTicketDetailControllerProvider = StateNotifierProvider.autoDispose
    .family<
      CustomerTicketDetailController,
      CustomerTicketDetailState,
      CustomerTicketDetailArgs
    >((ref, args) {
      final loadProfile = ref.watch(loadProfileUseCaseProvider);
      return CustomerTicketDetailController(
        workspaceId: args.workspaceId,
        ticketId: args.ticketId,
        loadTicket: ref.watch(loadCustomerTicketUseCaseProvider),
        replyTicket: ref.watch(replyCustomerTicketUseCaseProvider),
        setStatus: ref.watch(setCustomerTicketStatusUseCaseProvider),
        claimTicket: ref.watch(claimCustomerTicketUseCaseProvider),
        requestAiDraft: ref.watch(requestCustomerTicketAiDraftUseCaseProvider),
        watchTickets: ref.watch(watchCustomerTicketsUseCaseProvider),
        pickImages: ref.watch(pickCustomerTicketImagesUseCaseProvider),
        loadCurrentUserId: () async =>
            (await loadProfile.execute()).valueOrNull?.id,
      )..start();
    });

final class CustomerTicketDetailState {
  const CustomerTicketDetailState({
    this.detail,
    this.isLoading = false,
    this.errorMessage,
    this.forbidden = false,
    this.isSending = false,
    this.isUpdatingStatus = false,
    this.isClaiming = false,
    this.isPickingImages = false,
    this.images = const [],
    this.draftPendingSince,
    this.aiErrorMessage,
    this.currentUserId,
  });

  final CustomerTicketDetail? detail;
  final bool isLoading;
  final String? errorMessage;
  final bool forbidden;
  final bool isSending;
  final bool isUpdatingStatus;
  final bool isClaiming;
  final bool isPickingImages;

  /// Ảnh đã chọn, chờ gửi kèm câu trả lời.
  final List<CustomerTicketImageUpload> images;

  /// Đang chờ AI soạn nháp (từ lúc bấm, tối đa 120 giây).
  final DateTime? draftPendingSince;
  final String? aiErrorMessage;
  final String? currentUserId;

  bool get isDraftPending => draftPendingSince != null;

  CustomerTicketAssignee? get assignee => detail?.assignee;

  bool get assignedToMe => assignee?.isUser(currentUserId) ?? false;

  /// Người khác đang nhận xử lý (gửi trả lời sẽ cần xác nhận).
  bool get heldByOther => assignee != null && !assignedToMe;

  CustomerTicketDetailState copyWith({
    CustomerTicketDetail? detail,
    bool? isLoading,
    String? errorMessage,
    bool clearError = false,
    bool? forbidden,
    bool? isSending,
    bool? isUpdatingStatus,
    bool? isClaiming,
    bool? isPickingImages,
    List<CustomerTicketImageUpload>? images,
    DateTime? draftPendingSince,
    bool clearDraftPending = false,
    String? aiErrorMessage,
    bool clearAiError = false,
    String? currentUserId,
  }) {
    return CustomerTicketDetailState(
      detail: detail ?? this.detail,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
      forbidden: forbidden ?? this.forbidden,
      isSending: isSending ?? this.isSending,
      isUpdatingStatus: isUpdatingStatus ?? this.isUpdatingStatus,
      isClaiming: isClaiming ?? this.isClaiming,
      isPickingImages: isPickingImages ?? this.isPickingImages,
      images: images ?? this.images,
      draftPendingSince: clearDraftPending
          ? null
          : draftPendingSince ?? this.draftPendingSince,
      aiErrorMessage: clearAiError
          ? null
          : aiErrorMessage ?? this.aiErrorMessage,
      currentUserId: currentUserId ?? this.currentUserId,
    );
  }
}

enum CustomerTicketActionStatus { done, claimedByOther, failed }

/// Kết quả một thao tác để màn hình báo / hỏi lại người dùng.
final class CustomerTicketActionOutcome {
  const CustomerTicketActionOutcome.done([this.message])
    : status = CustomerTicketActionStatus.done,
      holderName = null;

  const CustomerTicketActionOutcome.claimedByOther(String this.holderName)
    : status = CustomerTicketActionStatus.claimedByOther,
      message = null;

  const CustomerTicketActionOutcome.failed(String this.message)
    : status = CustomerTicketActionStatus.failed,
      holderName = null;

  final CustomerTicketActionStatus status;
  final String? message;

  /// Người đang xử lý ticket khi máy chủ trả `TICKET_CLAIMED`.
  final String? holderName;
}

/// Chi tiết một ticket: luồng tin, nháp AI, trả lời, nhận xử lý, đổi trạng
/// thái. Tự tải lại khi có sự kiện realtime của ticket này và mỗi 60 giây.
final class CustomerTicketDetailController
    extends StateNotifier<CustomerTicketDetailState> {
  CustomerTicketDetailController({
    required String workspaceId,
    required String ticketId,
    required LoadCustomerTicketUseCase loadTicket,
    required ReplyCustomerTicketUseCase replyTicket,
    required SetCustomerTicketStatusUseCase setStatus,
    required ClaimCustomerTicketUseCase claimTicket,
    required RequestCustomerTicketAiDraftUseCase requestAiDraft,
    required WatchCustomerTicketsUseCase watchTickets,
    required PickCustomerTicketImagesUseCase pickImages,
    required Future<String?> Function() loadCurrentUserId,
    Duration refreshInterval = const Duration(seconds: 60),
    Duration realtimeDebounce = const Duration(milliseconds: 300),
    Duration draftPollInterval = const Duration(seconds: 5),
    Duration draftTimeout = const Duration(seconds: 120),
    DateTime Function() now = DateTime.now,
  }) : _workspaceId = workspaceId.trim(),
       _ticketId = ticketId.trim(),
       _loadTicket = loadTicket,
       _replyTicket = replyTicket,
       _setStatus = setStatus,
       _claimTicket = claimTicket,
       _requestAiDraft = requestAiDraft,
       _watchTickets = watchTickets,
       _pickImages = pickImages,
       _loadCurrentUserId = loadCurrentUserId,
       _refreshInterval = refreshInterval,
       _realtimeDebounce = realtimeDebounce,
       _draftPollInterval = draftPollInterval,
       _draftTimeout = draftTimeout,
       _now = now,
       super(const CustomerTicketDetailState());

  /// Bộ dựng cho test: use case thật trên repository giả; tắt hẹn giờ trừ khi
  /// truyền vào.
  @visibleForTesting
  factory CustomerTicketDetailController.forTesting({
    required CustomerTicketRepository repository,
    CustomerTicketRealtimeRepository? realtime,
    CustomerTicketImagePickerRepository? picker,
    String workspaceId = 'workspace-1',
    String ticketId = '1001',
    String? currentUserId,
    Duration refreshInterval = Duration.zero,
    Duration realtimeDebounce = Duration.zero,
    Duration draftPollInterval = Duration.zero,
    Duration draftTimeout = const Duration(seconds: 120),
  }) {
    return CustomerTicketDetailController(
      workspaceId: workspaceId,
      ticketId: ticketId,
      loadTicket: LoadCustomerTicketUseCase(repository),
      replyTicket: ReplyCustomerTicketUseCase(repository),
      setStatus: SetCustomerTicketStatusUseCase(repository),
      claimTicket: ClaimCustomerTicketUseCase(repository),
      requestAiDraft: RequestCustomerTicketAiDraftUseCase(repository),
      watchTickets: WatchCustomerTicketsUseCase(
        realtime ?? const _SilentRealtime(),
      ),
      pickImages: PickCustomerTicketImagesUseCase(
        picker ?? const _NoImagePicker(),
      ),
      loadCurrentUserId: () async => currentUserId,
      refreshInterval: refreshInterval,
      realtimeDebounce: realtimeDebounce,
      draftPollInterval: draftPollInterval,
      draftTimeout: draftTimeout,
    );
  }

  final String _workspaceId;
  final String _ticketId;
  final LoadCustomerTicketUseCase _loadTicket;
  final ReplyCustomerTicketUseCase _replyTicket;
  final SetCustomerTicketStatusUseCase _setStatus;
  final ClaimCustomerTicketUseCase _claimTicket;
  final RequestCustomerTicketAiDraftUseCase _requestAiDraft;
  final WatchCustomerTicketsUseCase _watchTickets;
  final PickCustomerTicketImagesUseCase _pickImages;
  final Future<String?> Function() _loadCurrentUserId;
  final Duration _refreshInterval;
  final Duration _realtimeDebounce;
  final Duration _draftPollInterval;
  final Duration _draftTimeout;
  final DateTime Function() _now;

  StreamSubscription<CustomerTicketRealtimeEvent>? _subscription;
  Timer? _refreshTimer;
  Timer? _debounceTimer;
  Timer? _draftPollTimer;
  Timer? _draftTimeoutTimer;
  int _generation = 0;

  /// Nháp AI có sẵn lúc bấm "Soạn" (để biết khi nào nháp mới đến).
  DateTime? _draftBaselineCreatedAt;
  String? _draftBaselineText;

  String get ticketId => _ticketId;

  void start() {
    _subscription ??= _watchTickets
        .execute(_workspaceId)
        .listen(_handleRealtime, onError: (Object _) {});
    if (_refreshInterval > Duration.zero) {
      _refreshTimer ??= Timer.periodic(
        _refreshInterval,
        (_) => unawaited(load(silent: true)),
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

  /// [silent]: tải lại nền (realtime, hẹn giờ, sau thao tác) — giữ nội dung
  /// đang hiện nếu lỗi mạng.
  Future<void> load({bool silent = false}) async {
    final generation = ++_generation;
    if (!silent) {
      state = state.copyWith(isLoading: true, clearError: true);
    }
    final result = await _loadTicket.execute(
      workspaceId: _workspaceId,
      ticketId: _ticketId,
    );
    if (!mounted || generation != _generation) return;
    switch (result) {
      case Success(value: final detail):
        state = state.copyWith(
          detail: detail,
          isLoading: false,
          clearError: true,
          forbidden: false,
        );
        _checkDraftArrived(detail);
      case FailureResult(failure: final failure):
        final forbidden = failure.kind == FailureKind.forbidden;
        if (silent && state.detail != null && !forbidden) return;
        state = state.copyWith(
          isLoading: false,
          errorMessage: failure.message,
          forbidden: forbidden,
        );
        if (forbidden) _stopDraftPending();
    }
  }

  Future<CustomerTicketActionOutcome> reply(
    String message, {
    bool force = false,
  }) async {
    if (state.isSending) {
      return const CustomerTicketActionOutcome.failed(
        'Đang gửi câu trả lời trước.',
      );
    }
    state = state.copyWith(isSending: true);
    final result = await _replyTicket.execute(
      workspaceId: _workspaceId,
      ticketId: _ticketId,
      message: message,
      images: state.images,
      force: force,
    );
    if (!mounted) return const CustomerTicketActionOutcome.done();
    switch (result) {
      case Success(value: final reply):
        state = state.copyWith(isSending: false, images: const []);
        unawaited(load(silent: true));
        return CustomerTicketActionOutcome.done(
          reply.duplicate
              ? 'Câu trả lời này đã được gửi trước đó.'
              : 'Đã gửi trả lời cho khách.',
        );
      case FailureResult(failure: final failure):
        state = state.copyWith(isSending: false);
        return _outcomeFor(failure, allowForce: !force);
    }
  }

  Future<CustomerTicketActionOutcome> setStatus(
    CustomerTicketStatus status,
  ) async {
    if (state.isUpdatingStatus) {
      return const CustomerTicketActionOutcome.done();
    }
    state = state.copyWith(isUpdatingStatus: true);
    final result = await _setStatus.execute(
      workspaceId: _workspaceId,
      ticketId: _ticketId,
      status: status,
    );
    if (!mounted) return const CustomerTicketActionOutcome.done();
    switch (result) {
      case Success(value: final saved):
        final detail = state.detail;
        state = state.copyWith(
          isUpdatingStatus: false,
          detail: detail == null ? null : _withStatus(detail, saved),
        );
        unawaited(load(silent: true));
        return CustomerTicketActionOutcome.done(
          saved == CustomerTicketStatus.answered
              ? 'Đã đánh dấu ticket là đã xử lý.'
              : 'Đã mở lại ticket.',
        );
      case FailureResult(failure: final failure):
        state = state.copyWith(isUpdatingStatus: false);
        return CustomerTicketActionOutcome.failed(failure.message);
    }
  }

  /// Nhận xử lý; [force] để nhận lại khi người khác đang giữ (đã hỏi lại).
  Future<CustomerTicketActionOutcome> claim({bool force = false}) {
    return _changeClaim(release: false, force: force);
  }

  Future<CustomerTicketActionOutcome> release() {
    return _changeClaim(release: true, force: false);
  }

  Future<CustomerTicketActionOutcome> _changeClaim({
    required bool release,
    required bool force,
  }) async {
    if (state.isClaiming) return const CustomerTicketActionOutcome.done();
    state = state.copyWith(isClaiming: true);
    final result = await _claimTicket.execute(
      workspaceId: _workspaceId,
      ticketId: _ticketId,
      release: release,
      force: force,
    );
    if (!mounted) return const CustomerTicketActionOutcome.done();
    switch (result) {
      case Success(value: final assignee):
        final detail = state.detail;
        state = state.copyWith(
          isClaiming: false,
          detail: detail == null ? null : _withAssignee(detail, assignee),
        );
        unawaited(load(silent: true));
        return CustomerTicketActionOutcome.done(
          release ? 'Đã bỏ nhận ticket.' : 'Bạn đã nhận xử lý ticket.',
        );
      case FailureResult(failure: final failure):
        state = state.copyWith(isClaiming: false);
        return _outcomeFor(failure, allowForce: !force && !release);
    }
  }

  /// Nhờ AI soạn nháp (chạy nền trên máy chủ); nháp đến qua realtime hoặc
  /// tải lại mỗi 5 giây, tối đa 120 giây.
  Future<CustomerTicketActionOutcome> requestAiDraft({
    String instruction = '',
  }) async {
    if (state.isDraftPending) {
      return const CustomerTicketActionOutcome.done();
    }
    // Ghi nháp hiện có trước khi gửi: realtime có thể báo nháp mới trước khi
    // yêu cầu trả về.
    final baseline = state.detail?.aiDraft;
    _draftBaselineCreatedAt = baseline?.createdAt;
    _draftBaselineText = baseline?.text;
    state = state.copyWith(draftPendingSince: _now(), clearAiError: true);
    final result = await _requestAiDraft.execute(
      workspaceId: _workspaceId,
      ticketId: _ticketId,
      instruction: instruction,
    );
    if (!mounted) return const CustomerTicketActionOutcome.done();
    switch (result) {
      case Success():
        if (state.isDraftPending) _startDraftTimers();
        return const CustomerTicketActionOutcome.done(
          'AI đang soạn câu trả lời...',
        );
      case FailureResult(failure: final failure):
        _stopDraftPending();
        state = state.copyWith(aiErrorMessage: failure.message);
        return CustomerTicketActionOutcome.failed(failure.message);
    }
  }

  /// Chọn thêm ảnh (tổng tối đa 3); trả câu báo nếu có ảnh bị bỏ / lỗi.
  Future<String?> pickImages(CustomerTicketImageSource source) async {
    if (state.isPickingImages || state.isSending) return null;
    state = state.copyWith(isPickingImages: true);
    final result = await _pickImages.execute(
      source: source,
      alreadySelected: state.images.length,
    );
    if (!mounted) return null;
    switch (result) {
      case Success(value: final pick):
        state = state.copyWith(
          isPickingImages: false,
          images: [
            ...state.images,
            ...pick.images,
          ].take(customerTicketMaxImages).toList(growable: false),
        );
        return pick.rejectedReason;
      case FailureResult(failure: final failure):
        state = state.copyWith(isPickingImages: false);
        return failure.message;
    }
  }

  void removeImage(int index) {
    if (index < 0 || index >= state.images.length || state.isSending) return;
    state = state.copyWith(images: [...state.images]..removeAt(index));
  }

  void dismissAiError() {
    state = state.copyWith(clearAiError: true);
  }

  CustomerTicketActionOutcome _outcomeFor(
    Failure failure, {
    required bool allowForce,
  }) {
    if (allowForce && isCustomerTicketClaimedFailure(failure)) {
      final holder = state.heldByOther ? state.assignee?.name : null;
      return CustomerTicketActionOutcome.claimedByOther(
        customerTicketHolderName(failure, fallback: holder),
      );
    }
    return CustomerTicketActionOutcome.failed(failure.message);
  }

  void _handleRealtime(CustomerTicketRealtimeEvent event) {
    if (!mounted || !event.concerns(_ticketId)) return;
    if (event.reason == CustomerTicketRealtimeReason.aiDraftFailed) {
      if (event.isFromUser(state.currentUserId)) {
        _stopDraftPending();
        state = state.copyWith(
          aiErrorMessage: event.error?.trim().isNotEmpty == true
              ? event.error!.trim()
              : 'AI chưa soạn được câu trả lời. Thử lại sau.',
        );
      } else if (state.isDraftPending) {
        // Máy chủ chỉ chạy một lượt soạn cho mỗi ticket: lượt mình đang chờ
        // chính là lượt vừa lỗi của người khác. Dừng chờ, không báo lỗi.
        _stopDraftPending();
      }
      return;
    }
    _debounceTimer?.cancel();
    if (_realtimeDebounce <= Duration.zero) {
      unawaited(load(silent: true));
      return;
    }
    _debounceTimer = Timer(
      _realtimeDebounce,
      () => unawaited(load(silent: true)),
    );
  }

  void _startDraftTimers() {
    _draftPollTimer?.cancel();
    _draftTimeoutTimer?.cancel();
    if (_draftPollInterval > Duration.zero) {
      _draftPollTimer = Timer.periodic(
        _draftPollInterval,
        (_) => unawaited(load(silent: true)),
      );
    }
    _draftTimeoutTimer = Timer(_draftTimeout, () {
      if (!mounted || !state.isDraftPending) return;
      _stopDraftPending();
      state = state.copyWith(
        aiErrorMessage: 'AI chưa soạn xong. Thử lại sau ít phút.',
      );
    });
  }

  void _checkDraftArrived(CustomerTicketDetail detail) {
    if (!state.isDraftPending) return;
    final draft = detail.aiDraft;
    if (draft == null) return;
    final changed =
        draft.createdAt != _draftBaselineCreatedAt ||
        draft.text != _draftBaselineText;
    if (changed) _stopDraftPending();
  }

  void _stopDraftPending() {
    _draftPollTimer?.cancel();
    _draftPollTimer = null;
    _draftTimeoutTimer?.cancel();
    _draftTimeoutTimer = null;
    if (mounted && state.isDraftPending) {
      state = state.copyWith(clearDraftPending: true);
    }
  }

  @override
  void dispose() {
    _generation++;
    _refreshTimer?.cancel();
    _debounceTimer?.cancel();
    _draftPollTimer?.cancel();
    _draftTimeoutTimer?.cancel();
    unawaited(_subscription?.cancel());
    super.dispose();
  }
}

CustomerTicketDetail _withStatus(
  CustomerTicketDetail detail,
  CustomerTicketStatus status,
) {
  final ticket = detail.ticket;
  return CustomerTicketDetail(
    ticket: CustomerTicketInfo(
      ticketId: ticket.ticketId,
      status: status,
      service: ticket.service,
      createdAt: ticket.createdAt,
      messageCount: ticket.messageCount,
      truncated: ticket.truncated,
      adminUrl: ticket.adminUrl,
    ),
    customer: detail.customer,
    messages: detail.messages,
    assignee: detail.assignee,
    aiDraft: detail.aiDraft,
  );
}

CustomerTicketDetail _withAssignee(
  CustomerTicketDetail detail,
  CustomerTicketAssignee? assignee,
) {
  return CustomerTicketDetail(
    ticket: detail.ticket,
    customer: detail.customer,
    messages: detail.messages,
    assignee: assignee,
    aiDraft: detail.aiDraft,
  );
}

final class _SilentRealtime implements CustomerTicketRealtimeRepository {
  const _SilentRealtime();

  @override
  Stream<CustomerTicketRealtimeEvent> watch({required String workspaceId}) {
    return const Stream.empty();
  }
}

final class _NoImagePicker implements CustomerTicketImagePickerRepository {
  const _NoImagePicker();

  @override
  Future<Result<List<CustomerTicketImageUpload>>> pick({
    required CustomerTicketImageSource source,
    required int limit,
  }) async {
    return const Success([]);
  }
}
