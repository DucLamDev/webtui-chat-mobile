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
    DateTime Function()? now,
  }) : _decide = decide,
       _report = report,
       _now = now;

  /// Quyết định bấm lúc app tắt quá thời gian này thì không gửi nữa.
  static const maxDecisionAge = Duration(hours: 24);

  final DecideApprovalRequestUseCase _decide;
  final ApprovalActionReport _report;
  final DateTime Function()? _now;

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

  /// Gửi lần lượt các quyết định bấm trên thông báo. Mỗi quyết định đi theo
  /// workspace của chính nó (máy chủ kiểm quyền) nên không bị bỏ khi app đang
  /// mở workspace khác. Quyết định của máy chủ khác hoặc đã quá cũ không gửi
  /// đi mà báo rõ.
  Future<void> handleAll(
    Iterable<ApprovalNotificationDecision> decisions, {
    required String activeInstanceId,
  }) async {
    final active = activeInstanceId.trim().toLowerCase();
    final now = (_now ?? DateTime.now)().toUtc();
    for (final decision in decisions) {
      final instance = decision.instanceId?.trim().toLowerCase() ?? '';
      final decidedAt = decision.decidedAt;
      final String? reason;
      if (instance.isEmpty || instance != active) {
        reason = 'Yêu cầu thuộc máy chủ khác. Mở app trên máy chủ đó để xử lý.';
      } else if (decidedAt != null &&
          now.difference(decidedAt.toUtc()) > maxDecisionAge) {
        reason = 'Lần bấm đã quá 24 giờ nên chưa gửi. Mở yêu cầu để xử lý lại.';
      } else {
        reason = null;
      }
      if (reason != null) {
        await _report(
          approvalId: decision.approvalId,
          title: decision.approve ? 'Chưa duyệt được' : 'Chưa từ chối được',
          body: reason,
        );
        continue;
      }
      await handle(
        workspaceId: decision.workspaceId,
        approvalId: decision.approvalId,
        approve: decision.approve,
      );
    }
  }
}

/// Một quyết định Duyệt / Từ chối bấm trên thông báo, chờ gửi lên máy chủ.
typedef ApprovalNotificationDecision = ({
  String? instanceId,
  DateTime? decidedAt,
  String workspaceId,
  String approvalId,
  bool approve,
});
