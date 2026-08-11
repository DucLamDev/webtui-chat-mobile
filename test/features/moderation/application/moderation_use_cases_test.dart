import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/core/result/result.dart';
import 'package:webtui_chat/features/moderation/application/use_cases/moderation_use_cases.dart';
import 'package:webtui_chat/features/moderation/domain/entities/moderation.dart';
import 'package:webtui_chat/features/moderation/domain/repositories/moderation_repository.dart';

void main() {
  test(
    'rejects reports with missing targets before the repository call',
    () async {
      final repository = _FakeModerationRepository();
      final useCase = CreateModerationReportUseCase(repository);

      final result = await useCase.execute(
        workspaceId: 'workspace-1',
        targetType: ModerationTargetType.message,
        targetId: ' ',
        reason: ModerationReportReason.spam,
      );

      expect(result.isSuccess, isFalse);
      expect(result.failureOrNull?.code, 'MODERATION_TARGET_REQUIRED');
      expect(repository.reportCalls, 0);
    },
  );

  test('enforces the backend details limit', () async {
    final repository = _FakeModerationRepository();
    final useCase = CreateModerationReportUseCase(repository);

    final result = await useCase.execute(
      workspaceId: 'workspace-1',
      targetType: ModerationTargetType.user,
      targetId: 'user-1',
      reason: ModerationReportReason.other,
      details: 'x' * 2001,
    );

    expect(result.failureOrNull?.code, 'MODERATION_DETAILS_TOO_LONG');
    expect(repository.reportCalls, 0);
  });

  test('normalizes block targets before calling the repository', () async {
    final repository = _FakeModerationRepository();
    final useCase = BlockUserUseCase(repository);

    final result = await useCase.execute(
      workspaceId: ' workspace-1 ',
      userId: ' user-2 ',
      reason: ' safety ',
    );

    expect(result.isSuccess, isTrue);
    expect(repository.lastWorkspaceId, 'workspace-1');
    expect(repository.lastUserId, 'user-2');
    expect(repository.lastReason, 'safety');
  });
}

final class _FakeModerationRepository implements ModerationRepository {
  int reportCalls = 0;
  String? lastWorkspaceId;
  String? lastUserId;
  String? lastReason;

  @override
  Future<Result<BlockedUser>> blockUser({
    required String workspaceId,
    required String blockedUserId,
    String? reason,
  }) async {
    lastWorkspaceId = workspaceId;
    lastUserId = blockedUserId;
    lastReason = reason;
    return Success(
      BlockedUser(
        blockedUserId: blockedUserId,
        createdAt: DateTime.utc(2026, 8, 7),
        reason: reason,
      ),
    );
  }

  @override
  Future<Result<ModerationReport>> createReport({
    required String workspaceId,
    required ModerationTargetType targetType,
    required String targetId,
    required ModerationReportReason reason,
    String? details,
  }) async {
    reportCalls += 1;
    return Success(
      ModerationReport(
        id: 'report-1',
        workspaceId: workspaceId,
        targetType: targetType,
        targetId: targetId,
        reason: reason,
        status: 'pending',
        createdAt: DateTime.utc(2026, 8, 7),
      ),
    );
  }

  @override
  Future<Result<List<BlockedUser>>> listBlockedUsers({
    required String workspaceId,
  }) async => const Success([]);

  @override
  Future<Result<void>> unblockUser({
    required String workspaceId,
    required String blockedUserId,
  }) async => const Success(null);
}
