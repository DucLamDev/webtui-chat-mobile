import '../../../../core/result/result.dart';
import '../../../../core/result/result_guard.dart';
import '../../domain/entities/work_hub.dart';
import '../../domain/repositories/work_hub_repository.dart';
import '../datasources/work_hub_remote_data_source.dart';

final class WorkHubRepositoryImpl implements WorkHubRepository {
  const WorkHubRepositoryImpl(this._remote);

  final WorkHubRemoteDataSource _remote;

  @override
  Future<Result<AppShortcutList>> listShortcuts({
    required String workspaceId,
  }) => guardResult(() => _remote.listShortcuts(workspaceId: workspaceId));

  @override
  Future<Result<AppShortcut>> createShortcut({
    required String workspaceId,
    required AppShortcutDraft draft,
  }) => guardResult(
    () => _remote.createShortcut(workspaceId: workspaceId, draft: draft),
  );

  @override
  Future<Result<AppShortcut>> updateShortcut({
    required String workspaceId,
    required String shortcutId,
    required AppShortcutDraft draft,
  }) => guardResult(
    () => _remote.updateShortcut(
      workspaceId: workspaceId,
      shortcutId: shortcutId,
      draft: draft,
    ),
  );

  @override
  Future<Result<void>> deleteShortcut({
    required String workspaceId,
    required String shortcutId,
  }) => guardResult(
    () => _remote.deleteShortcut(
      workspaceId: workspaceId,
      shortcutId: shortcutId,
    ),
  );

  @override
  Future<Result<List<AppShortcut>>> reorderShortcuts({
    required String workspaceId,
    required List<String> ids,
  }) => guardResult(
    () => _remote.reorderShortcuts(workspaceId: workspaceId, ids: ids),
  );

  @override
  Future<Result<AssignedTaskSummary>> assignedTaskSummary({
    required String workspaceId,
  }) =>
      guardResult(() => _remote.assignedTaskSummary(workspaceId: workspaceId));

  @override
  Future<Result<List<UpcomingMeeting>>> upcomingMeetings({
    required String workspaceId,
    int days = 14,
    int limit = 50,
  }) => guardResult(
    () => _remote.upcomingMeetings(
      workspaceId: workspaceId,
      days: days,
      limit: limit,
    ),
  );

  @override
  Future<Result<List<SharedFile>>> listFiles({
    required String workspaceId,
    int limit = 100,
  }) => guardResult(
    () => _remote.listFiles(workspaceId: workspaceId, limit: limit),
  );

  @override
  Future<Result<SharedFileStreamLink>> createFileStreamLink({
    required String workspaceId,
    required String fileId,
  }) => guardResult(
    () =>
        _remote.createFileStreamLink(workspaceId: workspaceId, fileId: fileId),
  );
}
