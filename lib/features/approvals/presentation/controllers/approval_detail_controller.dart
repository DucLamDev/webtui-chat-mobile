import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers/foundation_providers.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/result/result.dart';
import '../../application/use_cases/approval_use_cases.dart';
import '../../domain/entities/approval.dart';
import '../../domain/repositories/approval_repository.dart';

typedef ApprovalDetailKey = ({String workspaceId, String approvalId});

final approvalDetailControllerProvider = StateNotifierProvider.autoDispose
    .family<ApprovalDetailController, ApprovalDetailState, ApprovalDetailKey>((
      ref,
      key,
    ) {
      return ApprovalDetailController(
        workspaceId: key.workspaceId,
        approvalId: key.approvalId,
        load: ref.watch(loadApprovalUseCaseProvider),
        decide: ref.watch(decideApprovalRequestUseCaseProvider),
      )..load();
    });

final class ApprovalDetailState {
  const ApprovalDetailState({
    this.approval,
    this.isLoading = false,
    this.isSubmitting = false,
    this.errorMessage,
    this.actionMessage,
    this.forbidden = false,
  });

  final ApprovalRequest? approval;
  final bool isLoading;
  final bool isSubmitting;
  final String? errorMessage;

  /// Kết quả / lỗi của lần duyệt gần nhất (hiện bằng SnackBar).
  final String? actionMessage;
  final bool forbidden;

  ApprovalDetailState copyWith({
    ApprovalRequest? approval,
    bool? isLoading,
    bool? isSubmitting,
    String? errorMessage,
    bool clearError = false,
    String? actionMessage,
    bool clearAction = false,
    bool? forbidden,
  }) {
    return ApprovalDetailState(
      approval: approval ?? this.approval,
      isLoading: isLoading ?? this.isLoading,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
      actionMessage: clearAction ? null : actionMessage ?? this.actionMessage,
      forbidden: forbidden ?? this.forbidden,
    );
  }
}

final class ApprovalDetailController
    extends StateNotifier<ApprovalDetailState> {
  ApprovalDetailController({
    required String workspaceId,
    required String approvalId,
    required LoadApprovalUseCase load,
    required DecideApprovalRequestUseCase decide,
  }) : _workspaceId = workspaceId,
       _approvalId = approvalId,
       _load = load,
       _decide = decide,
       super(const ApprovalDetailState());

  @visibleForTesting
  factory ApprovalDetailController.forTesting({
    required ApprovalRepository repository,
    String workspaceId = 'workspace-1',
    String approvalId = 'approval-1',
  }) {
    return ApprovalDetailController(
      workspaceId: workspaceId,
      approvalId: approvalId,
      load: LoadApprovalUseCase(repository),
      decide: DecideApprovalRequestUseCase(repository),
    );
  }

  final String _workspaceId;
  final String _approvalId;
  final LoadApprovalUseCase _load;
  final DecideApprovalRequestUseCase _decide;

  Future<void> load() async {
    state = state.copyWith(isLoading: true, clearError: true, forbidden: false);
    final result = await _load.execute(
      workspaceId: _workspaceId,
      approvalId: _approvalId,
    );
    if (!mounted) return;
    switch (result) {
      case Success(value: final approval):
        state = state.copyWith(approval: approval, isLoading: false);
      case FailureResult(failure: final failure):
        state = state.copyWith(
          isLoading: false,
          forbidden: failure.kind == FailureKind.forbidden,
          errorMessage: failure.message,
        );
    }
  }

  /// Gửi quyết định. Thành công thì cập nhật phiếu; lỗi 403 / 409 được báo
  /// qua [ApprovalDetailState.actionMessage] và tải lại phiếu khi đã bị xử lý.
  Future<bool> decide(
    ApprovalDecisionKind decision, {
    String comment = '',
  }) async {
    if (state.isSubmitting) return false;
    state = state.copyWith(isSubmitting: true, clearAction: true);
    final result = await _decide.execute(
      workspaceId: _workspaceId,
      approvalId: _approvalId,
      decision: decision,
      comment: comment,
    );
    if (!mounted) return result.isSuccess;
    switch (result) {
      case Success(value: final approval):
        state = state.copyWith(
          approval: approval,
          isSubmitting: false,
          actionMessage: decision == ApprovalDecisionKind.approve
              ? 'Đã duyệt yêu cầu.'
              : 'Đã từ chối yêu cầu.',
        );
        return true;
      case FailureResult(failure: final failure):
        state = state.copyWith(
          isSubmitting: false,
          actionMessage: approvalDecisionFailureMessage(failure),
        );
        if (failure.kind == FailureKind.conflict) await load();
        return false;
    }
  }
}
