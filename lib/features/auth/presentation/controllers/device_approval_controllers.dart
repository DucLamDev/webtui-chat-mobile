import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers/foundation_providers.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/result/result.dart';
import '../../application/session_termination.dart';
import '../../application/use_cases/device_approval_use_cases.dart';
import '../../domain/entities/auth_session.dart';
import '../../domain/entities/device_approval.dart';

// ---------------------------------------------------------------------------
// Màn chờ duyệt (phiên của chính máy này đang `pending`).
// ---------------------------------------------------------------------------

enum PendingApprovalPhase {
  loading,
  waiting,

  /// Đã được duyệt, đang lấy token đầy đủ qua `/auth/refresh`.
  finishing,

  /// Đã có token đầy đủ: vào app.
  approved,

  /// Bị từ chối / hết hạn: phiên đã xoá, về đăng nhập.
  ended,
  error,
}

final class PendingApprovalState {
  const PendingApprovalState({
    this.phase = PendingApprovalPhase.loading,
    this.approval,
    this.errorMessage,
  });

  final PendingApprovalPhase phase;
  final MyDeviceApproval? approval;
  final String? errorMessage;

  PendingApprovalState copyWith({
    PendingApprovalPhase? phase,
    MyDeviceApproval? approval,
    String? errorMessage,
    bool clearError = false,
  }) {
    return PendingApprovalState(
      phase: phase ?? this.phase,
      approval: approval ?? this.approval,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    );
  }
}

/// Hỏi `GET /auth/device-approvals/me` mỗi [interval] (mặc định 3 giây).
/// `approved` → refresh lấy token đầy đủ; `rejected` / hết hạn → xoá phiên và
/// về đăng nhập. Lỗi mạng tạm thời không dừng vòng hỏi.
final class DeviceApprovalPendingController
    extends StateNotifier<PendingApprovalState> {
  DeviceApprovalPendingController({
    required Future<Result<MyDeviceApproval>> Function() loadApproval,
    required Future<Result<AuthSession>> Function() refreshSession,
    required Future<void> Function(SessionEndReason reason) endSession,
    DateTime Function()? clock,
    Duration interval = const Duration(seconds: 3),
  }) : _loadApproval = loadApproval,
       _refreshSession = refreshSession,
       _endSession = endSession,
       _clock = clock ?? DateTime.now,
       _interval = interval,
       super(const PendingApprovalState());

  final Future<Result<MyDeviceApproval>> Function() _loadApproval;
  final Future<Result<AuthSession>> Function() _refreshSession;
  final Future<void> Function(SessionEndReason reason) _endSession;
  final DateTime Function() _clock;
  final Duration _interval;
  Timer? _timer;
  bool _inFlight = false;

  void start() {
    _timer?.cancel();
    unawaited(poll());
    _timer = Timer.periodic(_interval, (_) => unawaited(poll()));
  }

  Future<void> poll() async {
    if (_inFlight || !mounted || _isFinal) {
      return;
    }
    _inFlight = true;
    try {
      final result = await _loadApproval();
      if (!mounted || _isFinal) return;
      switch (result) {
        case Success<MyDeviceApproval>(value: final approval):
          await _apply(approval);
        case FailureResult<MyDeviceApproval>(:final failure):
          if (failure.requiresLogin) {
            // Phiên đã bị thu hồi: bộ điều phối phiên đưa về đăng nhập.
            _stop(PendingApprovalPhase.ended);
            return;
          }
          state = state.copyWith(
            phase: state.approval == null
                ? PendingApprovalPhase.error
                : PendingApprovalPhase.waiting,
            errorMessage: failure.message,
          );
      }
    } finally {
      _inFlight = false;
    }
  }

  bool get _isFinal =>
      state.phase == PendingApprovalPhase.approved ||
      state.phase == PendingApprovalPhase.ended ||
      state.phase == PendingApprovalPhase.finishing;

  Future<void> _apply(MyDeviceApproval approval) async {
    final now = _clock();
    if (approval.isApproved) {
      _timer?.cancel();
      state = state.copyWith(
        phase: PendingApprovalPhase.finishing,
        approval: approval,
        clearError: true,
      );
      final refreshed = await _refreshSession();
      if (!mounted) return;
      switch (refreshed) {
        case Success<AuthSession>():
          _stop(PendingApprovalPhase.approved);
        case FailureResult<AuthSession>(:final failure):
          if (failure.requiresLogin) {
            _stop(PendingApprovalPhase.ended);
            return;
          }
          // Lỗi mạng: thử lại ở vòng sau.
          state = state.copyWith(
            phase: PendingApprovalPhase.waiting,
            errorMessage: failure.message,
          );
          _timer = Timer.periodic(_interval, (_) => unawaited(poll()));
      }
      return;
    }
    if (approval.isRejected) {
      _stop(PendingApprovalPhase.ended);
      await _endSession(SessionEndReason.approvalRejected);
      return;
    }
    if (approval.isExpiredAt(now)) {
      _stop(PendingApprovalPhase.ended);
      await _endSession(SessionEndReason.approvalExpired);
      return;
    }
    state = state.copyWith(
      phase: PendingApprovalPhase.waiting,
      approval: approval,
      clearError: true,
    );
  }

  void _stop(PendingApprovalPhase phase) {
    _timer?.cancel();
    _timer = null;
    if (mounted) {
      state = state.copyWith(phase: phase);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

final deviceApprovalPendingControllerProvider =
    StateNotifierProvider.autoDispose<
      DeviceApprovalPendingController,
      PendingApprovalState
    >((ref) {
      final controller = DeviceApprovalPendingController(
        loadApproval: () =>
            ref.read(loadMyDeviceApprovalUseCaseProvider).execute(),
        refreshSession: () =>
            ref.read(refreshAccessTokenUseCaseProvider).execute(),
        endSession: (reason) => ref
            .read(sessionTerminationCoordinatorProvider)
            .endSession(SessionEndedNotice(reason: reason)),
      )..start();
      return controller;
    });

// ---------------------------------------------------------------------------
// Danh sách chờ duyệt (Cài đặt → Phiên) và màn duyệt một thiết bị.
// ---------------------------------------------------------------------------

final pendingDeviceApprovalsProvider =
    FutureProvider.autoDispose<Result<List<DeviceApprovalRequest>>>((ref) {
      return ref.watch(listPendingDeviceApprovalsUseCaseProvider).execute();
    });

enum ReviewPhase { loading, ready, notFound, error, deciding, decided }

final class DeviceApprovalReviewState {
  const DeviceApprovalReviewState({
    this.phase = ReviewPhase.loading,
    this.request,
    this.errorMessage,
    this.resultStatus,
  });

  final ReviewPhase phase;
  final DeviceApprovalRequest? request;
  final String? errorMessage;

  /// Trạng thái sau quyết định: `approved`, `pending` (chờ người thứ hai),
  /// `rejected`.
  final String? resultStatus;

  DeviceApprovalReviewState copyWith({
    ReviewPhase? phase,
    DeviceApprovalRequest? request,
    String? errorMessage,
    bool clearError = false,
    String? resultStatus,
  }) {
    return DeviceApprovalReviewState(
      phase: phase ?? this.phase,
      request: request ?? this.request,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
      resultStatus: resultStatus ?? this.resultStatus,
    );
  }
}

final class DeviceApprovalReviewController
    extends StateNotifier<DeviceApprovalReviewState> {
  DeviceApprovalReviewController({
    required this.sessionId,
    required Future<Result<DeviceApprovalRequest?>> Function(String sessionId)
    findRequest,
    required Future<Result<DeviceApprovalResult>> Function(
      String sessionId, {
      required bool approve,
    })
    decide,
  }) : _findRequest = findRequest,
       _decide = decide,
       super(const DeviceApprovalReviewState());

  final String sessionId;
  final Future<Result<DeviceApprovalRequest?>> Function(String sessionId)
  _findRequest;
  final Future<Result<DeviceApprovalResult>> Function(
    String sessionId, {
    required bool approve,
  })
  _decide;

  Future<void> load() async {
    state = const DeviceApprovalReviewState();
    final result = await _findRequest(sessionId);
    if (!mounted) return;
    switch (result) {
      case Success<DeviceApprovalRequest?>(value: final request?):
        state = state.copyWith(phase: ReviewPhase.ready, request: request);
      case Success<DeviceApprovalRequest?>():
        state = state.copyWith(phase: ReviewPhase.notFound);
      case FailureResult<DeviceApprovalRequest?>(:final failure):
        state = state.copyWith(
          phase: ReviewPhase.error,
          errorMessage: deviceApprovalFailureMessage(failure),
        );
    }
  }

  Future<void> decide({required bool approve}) async {
    if (state.phase != ReviewPhase.ready) return;
    state = state.copyWith(phase: ReviewPhase.deciding, clearError: true);
    final result = await _decide(sessionId, approve: approve);
    if (!mounted) return;
    switch (result) {
      case Success<DeviceApprovalResult>(:final value):
        state = state.copyWith(
          phase: ReviewPhase.decided,
          resultStatus: value.approvalStatus,
        );
      case FailureResult<DeviceApprovalResult>(:final failure):
        final finished =
            failure.hasCode(DeviceApprovalErrorCode.alreadyDecided) ||
            failure.hasCode(DeviceApprovalErrorCode.notFound) ||
            failure.hasCode(DeviceApprovalErrorCode.expired);
        state = state.copyWith(
          phase: finished ? ReviewPhase.notFound : ReviewPhase.ready,
          errorMessage: deviceApprovalFailureMessage(failure),
        );
    }
  }
}

final deviceApprovalReviewControllerProvider = StateNotifierProvider.autoDispose
    .family<DeviceApprovalReviewController, DeviceApprovalReviewState, String>((
      ref,
      sessionId,
    ) {
      final controller = DeviceApprovalReviewController(
        sessionId: sessionId,
        findRequest: (id) =>
            ref.read(findDeviceApprovalRequestUseCaseProvider).execute(id),
        decide: (id, {required approve}) => ref
            .read(decideDeviceApprovalUseCaseProvider)
            .execute(id, approve: approve),
      );
      unawaited(controller.load());
      return controller;
    });

/// Câu mô tả bước chờ theo chế độ duyệt.
String pendingApprovalExplanation(MyDeviceApproval? approval) {
  final mode = approval?.mode ?? 'self';
  final hasTrusted = approval?.hasTrustedDevice ?? true;
  if (!hasTrusted) {
    return 'Tài khoản chưa có thiết bị tin cậy nào khác. Quản trị viên của '
        'tổ chức sẽ duyệt thiết bị này.';
  }
  if (mode == 'two_person') {
    return 'Mở ứng dụng trên thiết bị bạn đã đăng nhập trước đó để duyệt, sau '
        'đó quản trị viên duyệt thêm một lần nữa.';
  }
  return 'Mở ứng dụng trên thiết bị bạn đã đăng nhập trước đó (điện thoại hoặc '
      'máy tính) và bấm Đồng ý để cho phép thiết bị này.';
}

/// Lỗi tải danh sách chờ duyệt (403 coi như không có quyền xem).
String pendingListFailureMessage(Failure failure) {
  return deviceApprovalFailureMessage(failure);
}
