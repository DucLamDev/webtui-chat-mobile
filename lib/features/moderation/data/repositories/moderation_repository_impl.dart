import '../../../../core/result/result.dart';
import '../../../../core/result/result_guard.dart';
import '../../domain/entities/moderation.dart';
import '../../domain/repositories/moderation_repository.dart';
import '../datasources/moderation_remote_data_source.dart';

final class ModerationRepositoryImpl implements ModerationRepository {
  const ModerationRepositoryImpl(this._remote);

  final ModerationRemoteDataSource _remote;

  @override
  Future<Result<ModerationReport>> createReport({
    required String workspaceId,
    required ModerationTargetType targetType,
    required String targetId,
    required ModerationReportReason reason,
    String? details,
  }) {
    return guardResult(
      () => _remote.createReport(
        workspaceId: workspaceId,
        targetType: targetType,
        targetId: targetId,
        reason: reason,
        details: details,
      ),
    );
  }

  @override
  Future<Result<List<BlockedUser>>> listBlockedUsers({
    required String workspaceId,
  }) {
    return guardResult(
      () => _remote.listBlockedUsers(workspaceId: workspaceId),
    );
  }

  @override
  Future<Result<BlockedUser>> blockUser({
    required String workspaceId,
    required String blockedUserId,
    String? reason,
  }) {
    return guardResult(
      () => _remote.blockUser(
        workspaceId: workspaceId,
        blockedUserId: blockedUserId,
        reason: reason,
      ),
    );
  }

  @override
  Future<Result<void>> unblockUser({
    required String workspaceId,
    required String blockedUserId,
  }) {
    return guardResult(
      () => _remote.unblockUser(
        workspaceId: workspaceId,
        blockedUserId: blockedUserId,
      ),
    );
  }
}
