import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/core/error/failure.dart';
import 'package:webtui_chat/core/result/result.dart';
import 'package:webtui_chat/features/conversations/application/use_cases/collaboration_task_use_cases.dart';
import 'package:webtui_chat/features/conversations/domain/entities/collaboration_room.dart';
import 'package:webtui_chat/features/conversations/domain/repositories/collaboration_task_repository.dart';

void main() {
  group('CreateChannelTaskUseCase', () {
    test('cắt khoảng trắng, bỏ người giao rỗng rồi mới gửi', () async {
      final repository = _FakeTaskRepository();
      final result = await CreateChannelTaskUseCase(repository).execute(
        workspaceId: 'ws-1',
        channelId: 'ch-1',
        draft: CollaborationTaskDraft(
          title: '  Gửi báo giá  ',
          description: '  cho khách A ',
          assigneeUserId: ' ',
          dueAt: DateTime.utc(2026, 11, 5, 10),
        ),
      );

      expect(result.isSuccess, isTrue);
      final draft = repository.createdDraft!;
      expect(draft.title, 'Gửi báo giá');
      expect(draft.description, 'cho khách A');
      expect(draft.assigneeUserId, isNull);
      expect(draft.dueAt, DateTime.utc(2026, 11, 5, 10));
    });

    test('tên trống hoặc quá 240 ký tự thì không gọi máy chủ', () async {
      final repository = _FakeTaskRepository();
      final useCase = CreateChannelTaskUseCase(repository);

      final empty = await useCase.execute(
        workspaceId: 'ws-1',
        channelId: 'ch-1',
        draft: const CollaborationTaskDraft(title: '   '),
      );
      final tooLong = await useCase.execute(
        workspaceId: 'ws-1',
        channelId: 'ch-1',
        draft: CollaborationTaskDraft(title: 'a' * 241),
      );

      expect(empty.failureOrNull?.code, 'TASK_TITLE_REQUIRED');
      expect(tooLong.failureOrNull?.code, 'TASK_TITLE_TOO_LONG');
      expect(repository.createdDraft, isNull);
    });
  });

  group('UpdateChannelTaskUseCase', () {
    test('mô tả quá 4000 ký tự bị chặn', () async {
      final repository = _FakeTaskRepository();
      final result = await UpdateChannelTaskUseCase(repository).execute(
        workspaceId: 'ws-1',
        channelId: 'ch-1',
        taskId: 't-1',
        changes: CollaborationTaskChanges(description: 'a' * 4001),
      );

      expect(result.failureOrNull?.code, 'TASK_DESCRIPTION_TOO_LONG');
      expect(repository.updatedChanges, isNull);
    });

    test('giữ nguyên ý nghĩa bỏ giao (chuỗi rỗng) và xoá hạn', () async {
      final repository = _FakeTaskRepository();
      await UpdateChannelTaskUseCase(repository).execute(
        workspaceId: 'ws-1',
        channelId: 'ch-1',
        taskId: 't-1',
        changes: const CollaborationTaskChanges(
          assigneeUserId: '',
          clearDueAt: true,
          status: CollaborationTaskStatus.inProgress,
        ),
      );

      final changes = repository.updatedChanges!;
      expect(changes.assigneeUserId, '');
      expect(changes.clearDueAt, isTrue);
      expect(changes.status, CollaborationTaskStatus.inProgress);
    });
  });

  group('DeleteChannelTaskUseCase', () {
    test('việc đã bị xoá ở nơi khác: coi như xong', () async {
      final repository = _FakeTaskRepository(
        failure: const Failure(
          kind: FailureKind.notFound,
          message: 'Không tìm thấy công việc.',
          code: 'TASK_NOT_FOUND',
        ),
      );

      final result = await DeleteChannelTaskUseCase(
        repository,
      ).execute(workspaceId: 'ws-1', channelId: 'ch-1', taskId: 't-1');

      expect(result.isSuccess, isTrue);
    });

    test('máy chủ cũ chưa có API xoá: báo cần cập nhật', () async {
      final repository = _FakeTaskRepository(
        failure: const Failure(
          kind: FailureKind.notFound,
          message: 'Không tìm thấy dữ liệu.',
        ),
      );

      final result = await DeleteChannelTaskUseCase(
        repository,
      ).execute(workspaceId: 'ws-1', channelId: 'ch-1', taskId: 't-1');

      expect(result.failureOrNull?.code, 'TASK_FEATURE_UNSUPPORTED');
      expect(result.failureOrNull?.message, taskFeatureUnsupportedMessage);
    });
  });

  test(
    'Việc của tôi: mặc định chỉ việc đang mở, có thể lấy cả việc xong',
    () async {
      final repository = _FakeTaskRepository();
      final useCase = ListAssignedTasksUseCase(repository);

      await useCase.execute(workspaceId: 'ws-1');
      await useCase.execute(workspaceId: 'ws-1', includeFinished: true);

      expect(repository.assignedStatuses, ['active', 'all']);
    },
  );
}

final class _FakeTaskRepository implements CollaborationTaskRepository {
  _FakeTaskRepository({this.failure});

  final Failure? failure;
  CollaborationTaskDraft? createdDraft;
  CollaborationTaskChanges? updatedChanges;
  final assignedStatuses = <String>[];

  CollaborationTask get _task => CollaborationTask(
    id: 't-1',
    title: 'Việc',
    status: 'open',
    createdAt: DateTime.utc(2026, 11, 2),
  );

  @override
  Future<Result<CollaborationTask>> createTask({
    required String workspaceId,
    required String channelId,
    required CollaborationTaskDraft draft,
  }) async {
    createdDraft = draft;
    return Success(_task);
  }

  @override
  Future<Result<CollaborationTask>> updateTask({
    required String workspaceId,
    required String channelId,
    required String taskId,
    required CollaborationTaskChanges changes,
  }) async {
    updatedChanges = changes;
    return Success(_task);
  }

  @override
  Future<Result<void>> deleteTask({
    required String workspaceId,
    required String channelId,
    required String taskId,
  }) async {
    if (failure case final failure?) return FailureResult(failure);
    return const Success(null);
  }

  @override
  Future<Result<List<CollaborationTask>>> listAssignedTasks({
    required String workspaceId,
    String status = 'active',
  }) async {
    assignedStatuses.add(status);
    return const Success([]);
  }

  @override
  Future<Result<List<CollaborationTask>>> listTasks({
    required String workspaceId,
    required String channelId,
  }) async => const Success([]);
}
