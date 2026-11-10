import '../../../../core/error/failure.dart';
import '../../../../core/result/result.dart';
import '../../domain/entities/collaboration_room.dart';
import '../../domain/repositories/collaboration_task_repository.dart';

const maxTaskTitleLength = 240;
const maxTaskDescriptionLength = 4000;

/// Máy chủ bản cũ chưa có API xoá việc / "Việc của tôi": trả 404 không kèm mã của việc.
const taskFeatureUnsupportedMessage =
    'Máy chủ chưa hỗ trợ chức năng này. Hãy nhờ quản trị cập nhật máy chủ.';

Failure? _validateTitle(String title) {
  if (title.isEmpty) {
    return const Failure(
      kind: FailureKind.validation,
      message: 'Hãy nhập tên công việc.',
      code: 'TASK_TITLE_REQUIRED',
    );
  }
  if (title.runes.length > maxTaskTitleLength) {
    return const Failure(
      kind: FailureKind.validation,
      message: 'Tên công việc tối đa 240 ký tự.',
      code: 'TASK_TITLE_TOO_LONG',
    );
  }
  return null;
}

Failure? _validateDescription(String description) {
  if (description.runes.length > maxTaskDescriptionLength) {
    return const Failure(
      kind: FailureKind.validation,
      message: 'Mô tả công việc tối đa 4000 ký tự.',
      code: 'TASK_DESCRIPTION_TOO_LONG',
    );
  }
  return null;
}

/// 404 không phải TASK_NOT_FOUND (đường dẫn chưa có trên máy chủ cũ) → câu báo
/// cần cập nhật máy chủ.
Result<T> _mapUnsupported<T>(Result<T> result) {
  return switch (result) {
    FailureResult<T>(failure: final failure)
        when failure.kind == FailureKind.notFound &&
            failure.code != 'TASK_NOT_FOUND' =>
      FailureResult(
        failure.copyWith(
          code: 'TASK_FEATURE_UNSUPPORTED',
          message: taskFeatureUnsupportedMessage,
        ),
      ),
    _ => result,
  };
}

final class ListChannelTasksUseCase {
  const ListChannelTasksUseCase(this._repository);

  final CollaborationTaskRepository _repository;

  Future<Result<List<CollaborationTask>>> execute({
    required String workspaceId,
    required String channelId,
  }) {
    return _repository.listTasks(
      workspaceId: workspaceId,
      channelId: channelId,
    );
  }
}

final class CreateChannelTaskUseCase {
  const CreateChannelTaskUseCase(this._repository);

  final CollaborationTaskRepository _repository;

  Future<Result<CollaborationTask>> execute({
    required String workspaceId,
    required String channelId,
    required CollaborationTaskDraft draft,
  }) async {
    final title = draft.title.trim();
    final description = draft.description.trim();
    final invalid = _validateTitle(title) ?? _validateDescription(description);
    if (invalid != null) return FailureResult(invalid);
    final assignee = draft.assigneeUserId?.trim();
    return _repository.createTask(
      workspaceId: workspaceId,
      channelId: channelId,
      draft: CollaborationTaskDraft(
        title: title,
        description: description,
        assigneeUserId: assignee == null || assignee.isEmpty ? null : assignee,
        dueAt: draft.dueAt,
        sourceMessageId: draft.sourceMessageId,
      ),
    );
  }
}

final class UpdateChannelTaskUseCase {
  const UpdateChannelTaskUseCase(this._repository);

  final CollaborationTaskRepository _repository;

  Future<Result<CollaborationTask>> execute({
    required String workspaceId,
    required String channelId,
    required String taskId,
    required CollaborationTaskChanges changes,
  }) async {
    final title = changes.title?.trim();
    final description = changes.description?.trim();
    final invalid =
        (title == null ? null : _validateTitle(title)) ??
        (description == null ? null : _validateDescription(description));
    if (invalid != null) return FailureResult(invalid);
    return _repository.updateTask(
      workspaceId: workspaceId,
      channelId: channelId,
      taskId: taskId,
      changes: CollaborationTaskChanges(
        status: changes.status,
        title: title,
        description: description,
        assigneeUserId: changes.assigneeUserId?.trim(),
        dueAt: changes.dueAt,
        clearDueAt: changes.clearDueAt,
      ),
    );
  }
}

final class DeleteChannelTaskUseCase {
  const DeleteChannelTaskUseCase(this._repository);

  final CollaborationTaskRepository _repository;

  Future<Result<void>> execute({
    required String workspaceId,
    required String channelId,
    required String taskId,
  }) async {
    final result = await _repository.deleteTask(
      workspaceId: workspaceId,
      channelId: channelId,
      taskId: taskId,
    );
    // Việc đã bị xoá ở thiết bị khác: coi như xong.
    if (result case FailureResult<void>(
      failure: Failure(code: 'TASK_NOT_FOUND'),
    )) {
      return const Success(null);
    }
    return _mapUnsupported(result);
  }
}

final class ListAssignedTasksUseCase {
  const ListAssignedTasksUseCase(this._repository);

  final CollaborationTaskRepository _repository;

  Future<Result<List<CollaborationTask>>> execute({
    required String workspaceId,
    bool includeFinished = false,
  }) async {
    return _mapUnsupported(
      await _repository.listAssignedTasks(
        workspaceId: workspaceId,
        status: includeFinished ? 'all' : 'active',
      ),
    );
  }
}
