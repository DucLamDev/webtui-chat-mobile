import '../../../../core/result/result.dart';
import '../entities/work_hub.dart';

abstract interface class WorkHubRepository {
  Future<Result<AppShortcutList>> listShortcuts({required String workspaceId});

  Future<Result<AppShortcut>> createShortcut({
    required String workspaceId,
    required AppShortcutDraft draft,
  });

  Future<Result<AppShortcut>> updateShortcut({
    required String workspaceId,
    required String shortcutId,
    required AppShortcutDraft draft,
  });

  Future<Result<void>> deleteShortcut({
    required String workspaceId,
    required String shortcutId,
  });

  Future<Result<List<AppShortcut>>> reorderShortcuts({
    required String workspaceId,
    required List<String> ids,
  });

  Future<Result<AssignedTaskSummary>> assignedTaskSummary({
    required String workspaceId,
  });

  Future<Result<List<UpcomingMeeting>>> upcomingMeetings({
    required String workspaceId,
    int days = 14,
    int limit = 50,
  });

  Future<Result<List<SharedFile>>> listFiles({
    required String workspaceId,
    int limit = 100,
  });

  Future<Result<SharedFileStreamLink>> createFileStreamLink({
    required String workspaceId,
    required String fileId,
  });
}
