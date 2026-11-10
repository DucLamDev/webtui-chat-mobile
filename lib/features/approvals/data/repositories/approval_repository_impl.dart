import '../../../../core/result/result.dart';
import '../../../../core/result/result_guard.dart';
import '../../domain/entities/approval.dart';
import '../../domain/repositories/approval_repository.dart';
import '../datasources/approval_remote_data_source.dart';

final class ApprovalRepositoryImpl implements ApprovalRepository {
  const ApprovalRepositoryImpl(this._remote);

  final ApprovalRemoteDataSource _remote;

  @override
  Future<Result<ApprovalPage>> list({
    required String workspaceId,
    required ApprovalFilter filter,
    String? cursor,
    int limit = 50,
  }) {
    return guardResult(
      () => _remote.list(
        workspaceId: workspaceId,
        filter: filter,
        cursor: cursor,
        limit: limit,
      ),
    );
  }

  @override
  Future<Result<ApprovalRequest>> get({
    required String workspaceId,
    required String approvalId,
  }) {
    return guardResult(
      () => _remote.get(workspaceId: workspaceId, approvalId: approvalId),
    );
  }

  @override
  Future<Result<ApprovalRequest>> decide({
    required String workspaceId,
    required String approvalId,
    required ApprovalDecisionKind decision,
    String comment = '',
  }) {
    return guardResult(
      () => _remote.decide(
        workspaceId: workspaceId,
        approvalId: approvalId,
        decision: decision,
        comment: comment,
      ),
    );
  }
}
