import 'package:webtui_chat/l10n/app_strings.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/result/result.dart';
import '../../domain/entities/approval.dart';
import '../../domain/repositories/approval_repository.dart';

/// Mã lỗi máy chủ khi quyết định không được nhận.
const approvalForbiddenCode = 'APPROVAL_FORBIDDEN';
const approvalNotPendingCode = 'APPROVAL_NOT_PENDING';
const approvalAlreadyDecidedCode = 'APPROVAL_ALREADY_DECIDED';

/// Câu báo lỗi tiếng Việt cho người dùng khi duyệt / từ chối không thành công
/// (403 / 409 không được nuốt im lặng).
String approvalDecisionFailureMessage(Failure failure) {
  if (failure.hasCode(approvalForbiddenCode) ||
      failure.kind == FailureKind.forbidden) {
    return tr(
      'Bạn không có quyền duyệt yêu cầu này.',
      'You don\'t have permission to approve this request.',
    );
  }
  if (failure.hasCode(approvalAlreadyDecidedCode)) {
    return tr(
      'Bạn đã quyết định yêu cầu này rồi.',
      'You\'ve already decided on this request.',
    );
  }
  if (failure.hasCode(approvalNotPendingCode) ||
      failure.kind == FailureKind.conflict) {
    return tr(
      'Yêu cầu không còn ở trạng thái chờ duyệt.',
      'The request is no longer pending approval.',
    );
  }
  return failure.message.trim().isEmpty
      ? tr(
          'Chưa gửi được quyết định, hãy thử lại.',
          'Couldn\'t send your decision. Try again.',
        )
      : failure.message;
}

final class ListApprovalsUseCase {
  const ListApprovalsUseCase(this._repository);

  final ApprovalRepository _repository;

  Future<Result<ApprovalPage>> execute({
    required String workspaceId,
    required ApprovalFilter filter,
    String? cursor,
  }) {
    return _repository.list(
      workspaceId: workspaceId,
      filter: filter,
      cursor: cursor,
    );
  }
}

final class LoadApprovalUseCase {
  const LoadApprovalUseCase(this._repository);

  final ApprovalRepository _repository;

  Future<Result<ApprovalRequest>> execute({
    required String workspaceId,
    required String approvalId,
  }) {
    return _repository.get(workspaceId: workspaceId, approvalId: approvalId);
  }
}

final class DecideApprovalRequestUseCase {
  const DecideApprovalRequestUseCase(this._repository);

  final ApprovalRepository _repository;

  Future<Result<ApprovalRequest>> execute({
    required String workspaceId,
    required String approvalId,
    required ApprovalDecisionKind decision,
    String comment = '',
  }) {
    return _repository.decide(
      workspaceId: workspaceId,
      approvalId: approvalId,
      decision: decision,
      comment: comment.trim(),
    );
  }
}
