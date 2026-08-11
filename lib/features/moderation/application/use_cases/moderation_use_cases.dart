import '../../../../core/error/failure.dart';
import '../../../../core/result/result.dart';
import '../../domain/entities/moderation.dart';
import '../../domain/repositories/moderation_repository.dart';

final class CreateModerationReportUseCase {
  const CreateModerationReportUseCase(this._repository);

  final ModerationRepository _repository;

  Future<Result<ModerationReport>> execute({
    required String workspaceId,
    required ModerationTargetType targetType,
    required String targetId,
    required ModerationReportReason reason,
    String? details,
  }) {
    final normalizedWorkspaceId = workspaceId.trim();
    final normalizedTargetId = targetId.trim();
    final normalizedDetails = details?.trim();
    if (normalizedWorkspaceId.isEmpty || normalizedTargetId.isEmpty) {
      return Future.value(
        const FailureResult(
          Failure(
            kind: FailureKind.validation,
            message: 'Không xác định được nội dung cần báo cáo.',
            code: 'MODERATION_TARGET_REQUIRED',
          ),
        ),
      );
    }
    if ((normalizedDetails?.length ?? 0) > 2000) {
      return Future.value(
        const FailureResult(
          Failure(
            kind: FailureKind.validation,
            message: 'Chi tiết báo cáo không được vượt quá 2.000 ký tự.',
            code: 'MODERATION_DETAILS_TOO_LONG',
          ),
        ),
      );
    }
    return _repository.createReport(
      workspaceId: normalizedWorkspaceId,
      targetType: targetType,
      targetId: normalizedTargetId,
      reason: reason,
      details: normalizedDetails,
    );
  }
}

final class ListBlockedUsersUseCase {
  const ListBlockedUsersUseCase(this._repository);

  final ModerationRepository _repository;

  Future<Result<List<BlockedUser>>> execute(String workspaceId) {
    final normalizedWorkspaceId = workspaceId.trim();
    if (normalizedWorkspaceId.isEmpty) {
      return Future.value(
        const FailureResult(
          Failure(
            kind: FailureKind.validation,
            message: 'Chưa chọn workspace.',
            code: 'MODERATION_WORKSPACE_REQUIRED',
          ),
        ),
      );
    }
    return _repository.listBlockedUsers(workspaceId: normalizedWorkspaceId);
  }
}

final class BlockUserUseCase {
  const BlockUserUseCase(this._repository);

  final ModerationRepository _repository;

  Future<Result<BlockedUser>> execute({
    required String workspaceId,
    required String userId,
    String? reason,
  }) {
    final normalizedWorkspaceId = workspaceId.trim();
    final normalizedUserId = userId.trim();
    if (normalizedWorkspaceId.isEmpty || normalizedUserId.isEmpty) {
      return Future.value(
        const FailureResult(
          Failure(
            kind: FailureKind.validation,
            message: 'Không xác định được người dùng cần chặn.',
            code: 'BLOCK_TARGET_REQUIRED',
          ),
        ),
      );
    }
    return _repository.blockUser(
      workspaceId: normalizedWorkspaceId,
      blockedUserId: normalizedUserId,
      reason: reason?.trim(),
    );
  }
}

final class UnblockUserUseCase {
  const UnblockUserUseCase(this._repository);

  final ModerationRepository _repository;

  Future<Result<void>> execute({
    required String workspaceId,
    required String userId,
  }) {
    final normalizedWorkspaceId = workspaceId.trim();
    final normalizedUserId = userId.trim();
    if (normalizedWorkspaceId.isEmpty || normalizedUserId.isEmpty) {
      return Future.value(
        const FailureResult(
          Failure(
            kind: FailureKind.validation,
            message: 'Không xác định được người dùng cần bỏ chặn.',
            code: 'UNBLOCK_TARGET_REQUIRED',
          ),
        ),
      );
    }
    return _repository.unblockUser(
      workspaceId: normalizedWorkspaceId,
      blockedUserId: normalizedUserId,
    );
  }
}
