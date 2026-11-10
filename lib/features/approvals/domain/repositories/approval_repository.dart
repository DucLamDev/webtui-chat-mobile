import '../../../../core/result/result.dart';
import '../entities/approval.dart';

abstract interface class ApprovalRepository {
  Future<Result<ApprovalPage>> list({
    required String workspaceId,
    required ApprovalFilter filter,
    String? cursor,
    int limit = 50,
  });

  Future<Result<ApprovalRequest>> get({
    required String workspaceId,
    required String approvalId,
  });

  Future<Result<ApprovalRequest>> decide({
    required String workspaceId,
    required String approvalId,
    required ApprovalDecisionKind decision,
    String comment = '',
  });
}
