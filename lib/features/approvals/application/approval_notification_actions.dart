import '../../../core/result/result.dart';
import '../domain/entities/approval.dart';
import 'use_cases/approval_use_cases.dart';

/// Kết quả báo cho người dùng sau khi bấm Duyệt / Từ chối trên thông báo.
typedef ApprovalActionReport =
    Future<void> Function({
      required String approvalId,
      required String title,
      required String body,
    });

/// Xử lý nút Duyệt / Từ chối trên thông báo `approval_requested`: gọi máy chủ
/// rồi báo kết quả. Lỗi 403 / 409 được báo rõ, không nuốt im lặng.
final class ApprovalNotificationActionHandler {
  const ApprovalNotificationActionHandler({
    required DecideApprovalRequestUseCase decide,
    required ApprovalActionReport report,
  }) : _decide = decide,
       _report = report;

  final DecideApprovalRequestUseCase _decide;
  final ApprovalActionReport _report;

  /// `true` khi máy chủ nhận quyết định.
  Future<bool> handle({
    required String workspaceId,
    required String approvalId,
    required bool approve,
  }) async {
    final result = await _decide.execute(
      workspaceId: workspaceId,
      approvalId: approvalId,
      decision: approve
          ? ApprovalDecisionKind.approve
          : ApprovalDecisionKind.reject,
    );
    switch (result) {
      case Success(value: final approval):
        await _report(
          approvalId: approvalId,
          title: approve ? 'Đã duyệt yêu cầu' : 'Đã từ chối yêu cầu',
          body: approval.title,
        );
        return true;
      case FailureResult(failure: final failure):
        await _report(
          approvalId: approvalId,
          title: approve ? 'Chưa duyệt được' : 'Chưa từ chối được',
          body: approvalDecisionFailureMessage(failure),
        );
        return false;
    }
  }
}
