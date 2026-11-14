import 'package:webtui_chat/core/error/failure.dart';
import 'package:webtui_chat/core/result/result.dart';
import 'package:webtui_chat/features/conversations/domain/entities/collaboration_room.dart';
import 'package:webtui_chat/features/conversations/domain/repositories/collaboration_task_repository.dart';
import 'package:webtui_chat/features/work_hub/domain/entities/work_hub.dart';
import 'package:webtui_chat/features/work_hub/domain/repositories/work_hub_repository.dart';

CollaborationTask fakeTask(
  String id,
  String title,
  CollaborationTaskStatus status, {
  DateTime? dueAt,
  DateTime? completedAt,
  String channelName = 'Nhóm Kỹ thuật',
}) {
  return CollaborationTask(
    id: id,
    workspaceId: 'ws',
    channelId: 'ch-$id',
    title: title,
    status: status.apiValue,
    createdAt: DateTime.utc(2026, 11, 1),
    dueAt: dueAt,
    completedAt: completedAt,
    channelName: channelName,
  );
}

final class FakeWorkHubRepository implements WorkHubRepository {
  FakeWorkHubRepository({
    this.shortcuts = const [],
    this.canManage = false,
    this.summary = const AssignedTaskSummary(),
    this.meetings = const [],
    this.files = const [],
    this.shortcutsFailure,
    this.saveFailure,
  });

  List<AppShortcut> shortcuts;
  bool canManage;
  AssignedTaskSummary summary;
  List<UpcomingMeeting> meetings;
  List<SharedFile> files;
  Failure? shortcutsFailure;
  Failure? saveFailure;
  final calls = <String>[];
  final savedDrafts = <AppShortcutDraft>[];
  List<String>? lastOrder;

  @override
  Future<Result<AppShortcutList>> listShortcuts({
    required String workspaceId,
  }) async {
    calls.add('listShortcuts');
    final failure = shortcutsFailure;
    if (failure != null) return FailureResult(failure);
    return Success(AppShortcutList(shortcuts: shortcuts, canManage: canManage));
  }

  @override
  Future<Result<AppShortcut>> createShortcut({
    required String workspaceId,
    required AppShortcutDraft draft,
  }) async {
    calls.add('createShortcut');
    savedDrafts.add(draft);
    final failure = saveFailure;
    if (failure != null) return FailureResult(failure);
    final created = AppShortcut(
      id: 'new',
      title: draft.title,
      url: draft.url,
      icon: draft.icon,
      color: draft.color,
    );
    shortcuts = [...shortcuts, created];
    return Success(created);
  }

  @override
  Future<Result<AppShortcut>> updateShortcut({
    required String workspaceId,
    required String shortcutId,
    required AppShortcutDraft draft,
  }) async {
    calls.add('updateShortcut:$shortcutId');
    savedDrafts.add(draft);
    final failure = saveFailure;
    if (failure != null) return FailureResult(failure);
    return Success(
      AppShortcut(
        id: shortcutId,
        title: draft.title,
        url: draft.url,
        icon: draft.icon,
        color: draft.color,
      ),
    );
  }

  @override
  Future<Result<void>> deleteShortcut({
    required String workspaceId,
    required String shortcutId,
  }) async {
    calls.add('deleteShortcut:$shortcutId');
    shortcuts = [
      for (final item in shortcuts)
        if (item.id != shortcutId) item,
    ];
    return const Success(null);
  }

  @override
  Future<Result<List<AppShortcut>>> reorderShortcuts({
    required String workspaceId,
    required List<String> ids,
  }) async {
    calls.add('reorderShortcuts');
    lastOrder = ids;
    shortcuts = [
      for (final id in ids) shortcuts.firstWhere((item) => item.id == id),
    ];
    return Success(shortcuts);
  }

  @override
  Future<Result<AssignedTaskSummary>> assignedTaskSummary({
    required String workspaceId,
  }) async {
    calls.add('assignedTaskSummary');
    return Success(summary);
  }

  @override
  Future<Result<List<UpcomingMeeting>>> upcomingMeetings({
    required String workspaceId,
    int days = 14,
    int limit = 50,
  }) async {
    calls.add('upcomingMeetings');
    return Success(meetings);
  }

  @override
  Future<Result<List<SharedFile>>> listFiles({
    required String workspaceId,
    int limit = 100,
  }) async {
    calls.add('listFiles');
    return Success(files);
  }

  Failure? streamLinkFailure;

  @override
  Future<Result<SharedFileStreamLink>> createFileStreamLink({
    required String workspaceId,
    required String fileId,
  }) async {
    calls.add('streamLink:$fileId');
    final failure = streamLinkFailure;
    if (failure != null) return FailureResult(failure);
    return Success(
      SharedFileStreamLink(
        url: '/api/v1/media/workspaces/$workspaceId/files/$fileId/stream?t=1',
        expiresAt: DateTime.utc(2099),
      ),
    );
  }
}

final class FakeTaskRepository implements CollaborationTaskRepository {
  FakeTaskRepository(this.tasks, {this.listFailure});

  List<CollaborationTask> tasks;
  Failure? listFailure;
  final statusRequests = <String>[];
  final listStatuses = <String>[];

  @override
  Future<Result<List<CollaborationTask>>> listAssignedTasks({
    required String workspaceId,
    String status = 'active',
  }) async {
    listStatuses.add(status);
    final failure = listFailure;
    if (failure != null) return FailureResult(failure);
    return Success(
      status == 'active'
          ? [
              for (final task in tasks)
                if (task.isActive) task,
            ]
          : tasks,
    );
  }

  @override
  Future<Result<CollaborationTask>> updateTask({
    required String workspaceId,
    required String channelId,
    required String taskId,
    required CollaborationTaskChanges changes,
  }) async {
    statusRequests.add('$taskId:${changes.status?.apiValue}');
    final index = tasks.indexWhere((task) => task.id == taskId);
    final old = tasks[index];
    final updated = CollaborationTask(
      id: old.id,
      workspaceId: old.workspaceId,
      channelId: old.channelId,
      title: old.title,
      status: changes.status!.apiValue,
      createdAt: old.createdAt,
      dueAt: old.dueAt,
      channelName: old.channelName,
      completedAt: changes.status == CollaborationTaskStatus.done
          ? DateTime.now().toUtc()
          : null,
    );
    tasks = [...tasks]..[index] = updated;
    return Success(updated);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
