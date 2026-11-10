import '../../../../core/result/result.dart';
import '../entities/collaboration_room.dart';

/// Việc cần tạo mới trong phòng.
final class CollaborationTaskDraft {
  const CollaborationTaskDraft({
    required this.title,
    this.description = '',
    this.assigneeUserId,
    this.dueAt,
    this.sourceMessageId,
  });

  final String title;
  final String description;
  final String? assigneeUserId;
  final DateTime? dueAt;
  final String? sourceMessageId;
}

/// Thay đổi một việc. Trường `null` là giữ nguyên; `assigneeUserId == ''` là bỏ
/// giao; `clearDueAt` là xoá hạn.
final class CollaborationTaskChanges {
  const CollaborationTaskChanges({
    this.status,
    this.title,
    this.description,
    this.assigneeUserId,
    this.dueAt,
    this.clearDueAt = false,
  });

  final CollaborationTaskStatus? status;
  final String? title;
  final String? description;
  final String? assigneeUserId;
  final DateTime? dueAt;
  final bool clearDueAt;

  bool get changesDetails =>
      title != null ||
      description != null ||
      assigneeUserId != null ||
      dueAt != null ||
      clearDueAt;
}

abstract interface class CollaborationTaskRepository {
  Future<Result<List<CollaborationTask>>> listTasks({
    required String workspaceId,
    required String channelId,
  });

  Future<Result<CollaborationTask>> createTask({
    required String workspaceId,
    required String channelId,
    required CollaborationTaskDraft draft,
  });

  Future<Result<CollaborationTask>> updateTask({
    required String workspaceId,
    required String channelId,
    required String taskId,
    required CollaborationTaskChanges changes,
  });

  Future<Result<void>> deleteTask({
    required String workspaceId,
    required String channelId,
    required String taskId,
  });

  Future<Result<List<CollaborationTask>>> listAssignedTasks({
    required String workspaceId,
    String status = 'active',
  });
}
