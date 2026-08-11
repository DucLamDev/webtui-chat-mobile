import '../../../../core/result/result.dart';
import '../entities/moderation.dart';

abstract interface class ModerationRepository {
  Future<Result<ModerationReport>> createReport({
    required String workspaceId,
    required ModerationTargetType targetType,
    required String targetId,
    required ModerationReportReason reason,
    String? details,
  });

  Future<Result<List<BlockedUser>>> listBlockedUsers({
    required String workspaceId,
  });

  Future<Result<BlockedUser>> blockUser({
    required String workspaceId,
    required String blockedUserId,
    String? reason,
  });

  Future<Result<void>> unblockUser({
    required String workspaceId,
    required String blockedUserId,
  });
}
