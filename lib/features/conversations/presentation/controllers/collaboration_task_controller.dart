import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers/foundation_providers.dart';
import '../../../../core/result/result.dart';
import '../../../workspace/presentation/controllers/workspace_controller.dart';
import '../../application/use_cases/channel_use_cases.dart';
import '../../application/use_cases/collaboration_task_use_cases.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/entities/collaboration_room.dart';
import '../../domain/repositories/collaboration_task_repository.dart';

/// Người dùng có quyền `channel.manage` trong workspace (chủ / admin): quản lý
/// mọi việc trong mọi phòng.
final canManageWorkspaceChannelsProvider = Provider<bool>((ref) {
  return ref.watch(
    workspaceControllerProvider.select(
      (state) => state.permissions?.allows('channel.manage') ?? false,
    ),
  );
});

/// Bộ lọc danh sách việc trong phòng.
enum TaskListFilter {
  all('Tất cả'),
  assignedToMe('Giao cho tôi'),
  createdByMe('Tôi giao'),
  overdue('Quá hạn');

  const TaskListFilter(this.label);

  final String label;
}

/// Phòng đang xem việc. `canManageRoom`: người tạo phòng hoặc có quyền
/// `channel.manage` (chủ / admin workspace) — được sửa / giao / xoá mọi việc.
final class CollaborationTaskScope {
  const CollaborationTaskScope({
    required this.workspaceId,
    required this.channelId,
    this.canManageRoom = false,
  });

  final String workspaceId;
  final String channelId;
  final bool canManageRoom;

  @override
  bool operator ==(Object other) =>
      other is CollaborationTaskScope &&
      other.workspaceId == workspaceId &&
      other.channelId == channelId &&
      other.canManageRoom == canManageRoom;

  @override
  int get hashCode => Object.hash(workspaceId, channelId, canManageRoom);
}

/// Người có thể nhận việc (thành viên đang hoạt động của phòng).
final class TaskAssigneeOption {
  const TaskAssigneeOption({
    required this.userId,
    required this.name,
    this.avatarUrl,
  });

  final String userId;
  final String name;
  final String? avatarUrl;
}

final class CollaborationTaskState {
  const CollaborationTaskState({
    this.tasks = const [],
    this.members = const [],
    this.isLoading = false,
    this.errorMessage,
    this.filter = TaskListFilter.all,
    this.currentUserId,
    this.canManageRoom = false,
    this.busyTaskIds = const {},
  });

  final List<CollaborationTask> tasks;
  final List<TaskAssigneeOption> members;
  final bool isLoading;
  final String? errorMessage;
  final TaskListFilter filter;
  final String? currentUserId;
  final bool canManageRoom;
  final Set<String> busyTaskIds;

  /// Người tạo việc, người tạo phòng, chủ / admin: sửa, giao lại, đổi hạn, xoá.
  bool canEdit(CollaborationTask task) {
    final me = currentUserId;
    return canManageRoom ||
        (me != null && me.isNotEmpty && task.createdBy == me);
  }

  /// Người được giao chỉ đổi trạng thái.
  bool canChangeStatus(CollaborationTask task) {
    final me = currentUserId;
    return canEdit(task) ||
        (me != null && me.isNotEmpty && task.assigneeUserId == me);
  }

  TaskAssigneeOption? member(String? userId) {
    if (userId == null || userId.isEmpty) return null;
    for (final member in members) {
      if (member.userId == userId) return member;
    }
    return null;
  }

  /// Việc theo bộ lọc, đã sắp: hạn gần nhất trước, không hạn sau cùng.
  List<CollaborationTask> visibleTasks(DateTime now) {
    final me = currentUserId;
    final filtered = tasks.where((task) {
      return switch (filter) {
        TaskListFilter.all => true,
        TaskListFilter.assignedToMe => me != null && task.assigneeUserId == me,
        TaskListFilter.createdByMe => me != null && task.createdBy == me,
        TaskListFilter.overdue => task.isOverdueAt(now),
      };
    }).toList()..sort(compareTasksByDue);
    return filtered;
  }

  CollaborationTaskState copyWith({
    List<CollaborationTask>? tasks,
    List<TaskAssigneeOption>? members,
    bool? isLoading,
    String? errorMessage,
    bool clearError = false,
    TaskListFilter? filter,
    String? currentUserId,
    Set<String>? busyTaskIds,
  }) {
    return CollaborationTaskState(
      tasks: tasks ?? this.tasks,
      members: members ?? this.members,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
      filter: filter ?? this.filter,
      currentUserId: currentUserId ?? this.currentUserId,
      canManageRoom: canManageRoom,
      busyTaskIds: busyTaskIds ?? this.busyTaskIds,
    );
  }
}

/// Hạn gần nhất trước, việc không hạn sau cùng, cùng hạn thì việc mới trước.
int compareTasksByDue(CollaborationTask left, CollaborationTask right) {
  final leftDue = left.dueAt;
  final rightDue = right.dueAt;
  if (leftDue != null && rightDue != null) {
    final byDue = leftDue.compareTo(rightDue);
    if (byDue != 0) return byDue;
  } else if (leftDue != null) {
    return -1;
  } else if (rightDue != null) {
    return 1;
  }
  return right.createdAt.compareTo(left.createdAt);
}

final collaborationTaskControllerProvider = StateNotifierProvider.autoDispose
    .family<
      CollaborationTaskController,
      CollaborationTaskState,
      CollaborationTaskScope
    >((ref, scope) {
      return CollaborationTaskController(
        scope: scope,
        listTasks: ref.watch(listChannelTasksUseCaseProvider),
        createTask: ref.watch(createChannelTaskUseCaseProvider),
        updateTask: ref.watch(updateChannelTaskUseCaseProvider),
        deleteTask: ref.watch(deleteChannelTaskUseCaseProvider),
        listMembers: ref.watch(listChannelMembersUseCaseProvider),
        loadCurrentUserId: () async =>
            (await ref.read(loadProfileUseCaseProvider).execute())
                .valueOrNull
                ?.id,
      )..load();
    });

final class CollaborationTaskController
    extends StateNotifier<CollaborationTaskState> {
  CollaborationTaskController({
    required CollaborationTaskScope scope,
    required ListChannelTasksUseCase listTasks,
    required CreateChannelTaskUseCase createTask,
    required UpdateChannelTaskUseCase updateTask,
    required DeleteChannelTaskUseCase deleteTask,
    required ListChannelMembersUseCase listMembers,
    required Future<String?> Function() loadCurrentUserId,
  }) : _scope = scope,
       _listTasks = listTasks,
       _createTask = createTask,
       _updateTask = updateTask,
       _deleteTask = deleteTask,
       _listMembers = listMembers,
       _loadCurrentUserId = loadCurrentUserId,
       super(CollaborationTaskState(canManageRoom: scope.canManageRoom));

  final CollaborationTaskScope _scope;
  final ListChannelTasksUseCase _listTasks;
  final CreateChannelTaskUseCase _createTask;
  final UpdateChannelTaskUseCase _updateTask;
  final DeleteChannelTaskUseCase _deleteTask;
  final ListChannelMembersUseCase _listMembers;
  final Future<String?> Function() _loadCurrentUserId;

  @visibleForTesting
  CollaborationTaskScope get scope => _scope;

  Future<void> load() async {
    state = state.copyWith(isLoading: true, clearError: true);
    final results = await Future.wait<Object?>([
      _listTasks.execute(
        workspaceId: _scope.workspaceId,
        channelId: _scope.channelId,
      ),
      _listMembers.execute(
        workspaceId: _scope.workspaceId,
        channelId: _scope.channelId,
      ),
      if (state.currentUserId == null)
        _loadCurrentUserId()
      else
        Future<String?>.value(state.currentUserId),
    ]);
    if (!mounted) return;
    final tasksResult = results[0]! as Result<List<CollaborationTask>>;
    final membersResult = results[1]! as Result<List<ChannelMember>>;
    final currentUserId = results[2] as String?;
    switch (tasksResult) {
      case Success(value: final tasks):
        state = state.copyWith(
          tasks: tasks,
          members: _assignees(membersResult.valueOrNull ?? const []),
          currentUserId: currentUserId,
          isLoading: false,
          clearError: true,
        );
      case FailureResult(failure: final failure):
        state = state.copyWith(
          isLoading: false,
          errorMessage: failure.message,
          currentUserId: currentUserId,
        );
    }
  }

  void setFilter(TaskListFilter filter) {
    state = state.copyWith(filter: filter);
  }

  /// Tạo việc; trả câu báo lỗi (null là xong).
  Future<String?> create(CollaborationTaskDraft draft) async {
    final result = await _createTask.execute(
      workspaceId: _scope.workspaceId,
      channelId: _scope.channelId,
      draft: draft,
    );
    if (!mounted) return result.failureOrNull?.message;
    switch (result) {
      case Success(value: final task):
        state = state.copyWith(tasks: [task, ...state.tasks]);
        return null;
      case FailureResult(failure: final failure):
        return failure.message;
    }
  }

  /// Sửa việc; trả câu báo lỗi (null là xong).
  Future<String?> update(
    CollaborationTask task,
    CollaborationTaskChanges changes,
  ) async {
    _setBusy(task.id, true);
    final result = await _updateTask.execute(
      workspaceId: _scope.workspaceId,
      channelId: _scope.channelId,
      taskId: task.id,
      changes: changes,
    );
    if (!mounted) return result.failureOrNull?.message;
    _setBusy(task.id, false);
    switch (result) {
      case Success(value: final updated):
        state = state.copyWith(
          tasks: [
            for (final item in state.tasks) item.id == task.id ? updated : item,
          ],
        );
        return null;
      case FailureResult(failure: final failure):
        return failure.message;
    }
  }

  Future<String?> changeStatus(
    CollaborationTask task,
    CollaborationTaskStatus status,
  ) {
    return update(task, CollaborationTaskChanges(status: status));
  }

  /// Xoá việc: ẩn ngay, lỗi thì trả lại đúng chỗ cũ.
  Future<String?> delete(CollaborationTask task) async {
    final index = state.tasks.indexWhere((item) => item.id == task.id);
    if (index < 0) return null;
    state = state.copyWith(
      tasks: [
        for (final item in state.tasks)
          if (item.id != task.id) item,
      ],
    );
    final result = await _deleteTask.execute(
      workspaceId: _scope.workspaceId,
      channelId: _scope.channelId,
      taskId: task.id,
    );
    if (!mounted) return result.failureOrNull?.message;
    switch (result) {
      case Success():
        return null;
      case FailureResult(failure: final failure):
        final restored = [...state.tasks]
          ..insert(index.clamp(0, state.tasks.length), task);
        state = state.copyWith(tasks: restored);
        return failure.message;
    }
  }

  void _setBusy(String taskId, bool busy) {
    final next = {...state.busyTaskIds};
    if (busy) {
      next.add(taskId);
    } else {
      next.remove(taskId);
    }
    state = state.copyWith(busyTaskIds: next);
  }
}

List<TaskAssigneeOption> _assignees(List<ChannelMember> members) {
  final result = <TaskAssigneeOption>[];
  for (final member in members) {
    if (member.status != 'active' && member.status != 'muted') continue;
    final name =
        [member.displayName, member.username, member.email.split('@').first]
            .map((value) => value.trim())
            .firstWhere(
              (value) => value.isNotEmpty,
              orElse: () => 'Người dùng',
            );
    final avatarUrl = member.avatarUrl?.trim();
    result.add(
      TaskAssigneeOption(
        userId: member.userId,
        name: name,
        avatarUrl: avatarUrl == null || avatarUrl.isEmpty ? null : avatarUrl,
      ),
    );
  }
  result.sort(
    (left, right) =>
        left.name.toLowerCase().compareTo(right.name.toLowerCase()),
  );
  return result;
}
