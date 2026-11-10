import '../../../../core/result/result.dart';
import '../../../../core/result/result_guard.dart';
import '../../domain/entities/collaboration_room.dart';
import '../../domain/repositories/collaboration_task_repository.dart';
import '../datasources/conversation_remote_data_source.dart';

final class CollaborationTaskRepositoryImpl
    implements CollaborationTaskRepository {
  const CollaborationTaskRepositoryImpl(this._remote);

  final ConversationRemoteDataSource _remote;

  @override
  Future<Result<List<CollaborationTask>>> listTasks({
    required String workspaceId,
    required String channelId,
  }) {
    return guardResult(
      () => _remote.listCollaborationTasks(
        workspaceId: workspaceId,
        channelId: channelId,
      ),
    );
  }

  @override
  Future<Result<CollaborationTask>> createTask({
    required String workspaceId,
    required String channelId,
    required CollaborationTaskDraft draft,
  }) {
    return guardResult(
      () => _remote.createCollaborationTask(
        workspaceId: workspaceId,
        channelId: channelId,
        title: draft.title,
        description: draft.description.isEmpty ? null : draft.description,
        sourceMessageId: draft.sourceMessageId,
        assigneeUserId: draft.assigneeUserId,
        dueAt: draft.dueAt,
      ),
    );
  }

  @override
  Future<Result<CollaborationTask>> updateTask({
    required String workspaceId,
    required String channelId,
    required String taskId,
    required CollaborationTaskChanges changes,
  }) {
    return guardResult(
      () => _remote.updateCollaborationTask(
        workspaceId: workspaceId,
        channelId: channelId,
        taskId: taskId,
        status: changes.status?.apiValue,
        title: changes.title,
        description: changes.description,
        assigneeUserId: changes.assigneeUserId,
        dueAt: changes.dueAt,
        clearDueAt: changes.clearDueAt,
      ),
    );
  }

  @override
  Future<Result<void>> deleteTask({
    required String workspaceId,
    required String channelId,
    required String taskId,
  }) {
    return guardResult(
      () => _remote.deleteCollaborationTask(
        workspaceId: workspaceId,
        channelId: channelId,
        taskId: taskId,
      ),
    );
  }

  @override
  Future<Result<List<CollaborationTask>>> listAssignedTasks({
    required String workspaceId,
    String status = 'active',
  }) {
    return guardResult(
      () => _remote.listAssignedTasks(workspaceId: workspaceId, status: status),
    );
  }
}
