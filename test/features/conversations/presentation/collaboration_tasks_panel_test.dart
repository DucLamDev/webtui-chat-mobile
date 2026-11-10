import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/core/error/failure.dart';
import 'package:webtui_chat/core/result/result.dart';
import 'package:webtui_chat/features/conversations/application/use_cases/channel_use_cases.dart';
import 'package:webtui_chat/features/conversations/application/use_cases/collaboration_task_use_cases.dart';
import 'package:webtui_chat/features/conversations/domain/entities/chat_message.dart';
import 'package:webtui_chat/features/conversations/domain/entities/collaboration_room.dart';
import 'package:webtui_chat/features/conversations/domain/repositories/collaboration_task_repository.dart';
import 'package:webtui_chat/features/conversations/domain/repositories/conversation_repository.dart';
import 'package:webtui_chat/features/conversations/presentation/controllers/collaboration_task_controller.dart';
import 'package:webtui_chat/features/conversations/presentation/models/task_due_label.dart';
import 'package:webtui_chat/features/conversations/presentation/widgets/collaboration_tasks_panel.dart';

const _me = 'u-me';
const _boss = 'u-boss';
const _other = 'u-other';

void main() {
  group('formatTaskDue', () {
    final now = DateTime(2026, 11, 4, 10); // thứ Tư

    test('hôm nay / ngày mai / hôm qua / thứ trong tuần / năm khác', () {
      expect(formatTaskDue(DateTime(2026, 11, 4, 17), now), 'Hôm nay 17:00');
      expect(formatTaskDue(DateTime(2026, 11, 5, 9), now), 'Ngày mai 09:00');
      expect(formatTaskDue(DateTime(2026, 11, 3, 8, 5), now), 'Hôm qua 08:05');
      expect(formatTaskDue(DateTime(2026, 11, 9, 9), now), 'T2, 09/11 09:00');
      expect(formatTaskDue(DateTime(2027, 1, 2, 9), now), '02/01/2027 09:00');
    });

    test('mức gấp: quá hạn, dưới 24 giờ, việc đã xong thì không tô', () {
      expect(
        taskDueUrgency(DateTime(2026, 11, 4, 9), now),
        TaskDueUrgency.overdue,
      );
      expect(
        taskDueUrgency(DateTime(2026, 11, 5, 8), now),
        TaskDueUrgency.soon,
      );
      expect(taskDueUrgency(DateTime(2026, 11, 9), now), TaskDueUrgency.none);
      expect(
        taskDueUrgency(DateTime(2026, 11, 4, 9), now, active: false),
        TaskDueUrgency.none,
      );
    });

    test('lựa chọn nhanh bỏ "Hôm nay 17:00" khi đã qua 17 giờ', () {
      expect(quickTaskDueOptions(now).map((option) => option.label), [
        'Hôm nay 17:00',
        'Ngày mai 09:00',
        'Thứ Hai tuần sau',
      ]);
      expect(
        quickTaskDueOptions(DateTime(2026, 11, 4, 18)).first.label,
        'Ngày mai 09:00',
      );
      expect(quickTaskDueOptions(now).last.value, DateTime(2026, 11, 9, 9));
    });
  });

  group('CollaborationTaskController', () {
    test(
      'quyền: người tạo / quản lý sửa được; người được giao chỉ đổi trạng thái',
      () async {
        final controller = _controller(_FakeTaskRepository(_tasks()));
        await controller.load();
        final state = controller.state;
        final mineCreated = state.tasks.firstWhere(
          (t) => t.id == 'created-by-me',
        );
        final assignedToMe = state.tasks.firstWhere(
          (t) => t.id == 'assigned-me',
        );
        final others = state.tasks.firstWhere((t) => t.id == 'others');

        expect(state.canEdit(mineCreated), isTrue);
        expect(state.canEdit(assignedToMe), isFalse);
        expect(state.canChangeStatus(assignedToMe), isTrue);
        expect(state.canChangeStatus(others), isFalse);
        // Thành viên đã rời phòng không có trong danh sách giao việc.
        expect(state.members.map((m) => m.userId), [_boss, _me]);
      },
    );

    test('bộ lọc: giao cho tôi, tôi giao, quá hạn', () async {
      final now = DateTime.utc(2026, 11, 4, 3);
      final controller = _controller(_FakeTaskRepository(_tasks(now: now)));
      await controller.load();

      List<String> ids(TaskListFilter filter) {
        controller.setFilter(filter);
        return controller.state.visibleTasks(now).map((t) => t.id).toList();
      }

      expect(ids(TaskListFilter.assignedToMe), ['assigned-me']);
      expect(ids(TaskListFilter.createdByMe), ['created-by-me']);
      expect(ids(TaskListFilter.overdue), ['assigned-me']);
      // Hạn gần nhất trước, không hạn sau cùng.
      expect(ids(TaskListFilter.all), [
        'assigned-me',
        'others',
        'created-by-me',
      ]);
    });

    test('quản lý phòng sửa được mọi việc', () async {
      final controller = _controller(
        _FakeTaskRepository(_tasks()),
        canManageRoom: true,
      );
      await controller.load();

      expect(controller.state.tasks.every(controller.state.canEdit), isTrue);
    });

    test('xoá lỗi thì việc trở lại đúng chỗ cũ', () async {
      final repository = _FakeTaskRepository(
        _tasks(),
        deleteFailure: const Failure(
          kind: FailureKind.network,
          message: 'Mất kết nối mạng.',
        ),
      );
      final controller = _controller(repository);
      await controller.load();
      final before = controller.state.tasks.map((t) => t.id).toList();

      final error = await controller.delete(controller.state.tasks[1]);

      expect(error, 'Mất kết nối mạng.');
      expect(controller.state.tasks.map((t) => t.id), before);
    });
  });

  group('Tab Task', () {
    testWidgets('giao việc mới: chọn người làm và hạn nhanh', (tester) async {
      final repository = _FakeTaskRepository(_tasks());
      await _pumpPanel(tester, repository);

      expect(find.text('Cần làm · 2'), findsOneWidget);
      expect(find.text('Sếp Lâm'), findsWidgets);

      await tester.tap(find.byKey(const Key('tasks_add')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('task_editor_title')),
        'Gọi lại khách',
      );
      await tester.tap(find.byKey(const Key('task_editor_assignee')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('task_assignee_$_boss')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ngày mai 09:00'));
      await tester.pump();
      await tester.ensureVisible(find.byKey(const Key('task_editor_save')));
      await tester.tap(find.byKey(const Key('task_editor_save')));
      await tester.pumpAndSettle();

      final draft = repository.createdDraft!;
      expect(draft.title, 'Gọi lại khách');
      expect(draft.assigneeUserId, _boss);
      expect(draft.dueAt?.hour, 9);
      expect(find.text('Đã giao việc.'), findsOneWidget);
      expect(find.text('Gọi lại khách'), findsOneWidget);
    });

    testWidgets('người được giao chỉ đổi trạng thái, không sửa được tên', (
      tester,
    ) async {
      final repository = _FakeTaskRepository(_tasks());
      await _pumpPanel(tester, repository);

      await tester.tap(find.text('Việc giao cho tôi'));
      await tester.pumpAndSettle();

      final title = tester.widget<TextField>(
        find.byKey(const Key('task_editor_title')),
      );
      expect(title.enabled, isFalse);
      expect(find.byKey(const Key('task_editor_delete')), findsNothing);

      await tester.ensureVisible(
        find.byKey(const Key('task_editor_status_in_progress')),
      );
      await tester.tap(find.byKey(const Key('task_editor_status_in_progress')));
      await tester.pump();
      await tester.ensureVisible(find.byKey(const Key('task_editor_save')));
      await tester.tap(find.byKey(const Key('task_editor_save')));
      await tester.pumpAndSettle();

      final changes = repository.updatedChanges!;
      expect(changes.status, CollaborationTaskStatus.inProgress);
      expect(changes.changesDetails, isFalse);
    });

    testWidgets('quá hạn hiện chữ "Quá hạn"', (tester) async {
      await _pumpPanel(tester, _FakeTaskRepository(_tasks()));

      expect(find.textContaining('Quá hạn ·'), findsOneWidget);
    });
  });
}

Future<void> _pumpPanel(
  WidgetTester tester,
  _FakeTaskRepository repository,
) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  const scope = CollaborationTaskScope(workspaceId: 'ws-1', channelId: 'ch-1');
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        collaborationTaskControllerProvider(
          scope,
        ).overrideWith((ref) => _controller(repository)..load()),
      ],
      child: const MaterialApp(
        home: Scaffold(body: CollaborationTasksPanel(scope: scope)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

CollaborationTaskController _controller(
  _FakeTaskRepository repository, {
  bool canManageRoom = false,
}) {
  return CollaborationTaskController(
    scope: CollaborationTaskScope(
      workspaceId: 'ws-1',
      channelId: 'ch-1',
      canManageRoom: canManageRoom,
    ),
    listTasks: ListChannelTasksUseCase(repository),
    createTask: CreateChannelTaskUseCase(repository),
    updateTask: UpdateChannelTaskUseCase(repository),
    deleteTask: DeleteChannelTaskUseCase(repository),
    listMembers: ListChannelMembersUseCase(_MembersRepository()),
    loadCurrentUserId: () async => _me,
  );
}

List<CollaborationTask> _tasks({DateTime? now}) {
  now ??= DateTime.now();
  return [
    CollaborationTask(
      id: 'created-by-me',
      title: 'Việc tôi tạo',
      status: 'open',
      createdBy: _me,
      assigneeUserId: _other,
      createdAt: DateTime.utc(2026, 11, 1),
    ),
    CollaborationTask(
      id: 'assigned-me',
      title: 'Việc giao cho tôi',
      status: 'open',
      createdBy: _boss,
      assigneeUserId: _me,
      dueAt: now.subtract(const Duration(hours: 2)),
      createdAt: DateTime.utc(2026, 11, 1),
    ),
    CollaborationTask(
      id: 'others',
      title: 'Việc người khác',
      status: 'in_progress',
      createdBy: _boss,
      assigneeUserId: _boss,
      dueAt: now.add(const Duration(days: 3)),
      createdAt: DateTime.utc(2026, 11, 1),
    ),
  ];
}

final class _FakeTaskRepository implements CollaborationTaskRepository {
  _FakeTaskRepository(this.tasks, {this.deleteFailure});

  final List<CollaborationTask> tasks;
  final Failure? deleteFailure;
  CollaborationTaskDraft? createdDraft;
  CollaborationTaskChanges? updatedChanges;

  @override
  Future<Result<List<CollaborationTask>>> listTasks({
    required String workspaceId,
    required String channelId,
  }) async => Success(tasks);

  @override
  Future<Result<CollaborationTask>> createTask({
    required String workspaceId,
    required String channelId,
    required CollaborationTaskDraft draft,
  }) async {
    createdDraft = draft;
    return Success(
      CollaborationTask(
        id: 'new',
        title: draft.title,
        status: 'open',
        createdBy: _me,
        assigneeUserId: draft.assigneeUserId,
        dueAt: draft.dueAt,
        createdAt: DateTime.now(),
      ),
    );
  }

  @override
  Future<Result<CollaborationTask>> updateTask({
    required String workspaceId,
    required String channelId,
    required String taskId,
    required CollaborationTaskChanges changes,
  }) async {
    updatedChanges = changes;
    final task = tasks.firstWhere((item) => item.id == taskId);
    return Success(
      CollaborationTask(
        id: task.id,
        title: changes.title ?? task.title,
        status: changes.status?.apiValue ?? task.status,
        createdBy: task.createdBy,
        assigneeUserId: task.assigneeUserId,
        dueAt: task.dueAt,
        createdAt: task.createdAt,
      ),
    );
  }

  @override
  Future<Result<void>> deleteTask({
    required String workspaceId,
    required String channelId,
    required String taskId,
  }) async {
    if (deleteFailure case final failure?) return FailureResult(failure);
    return const Success(null);
  }

  @override
  Future<Result<List<CollaborationTask>>> listAssignedTasks({
    required String workspaceId,
    String status = 'active',
  }) async => const Success([]);
}

final class _MembersRepository implements ConversationRepository {
  @override
  Future<Result<List<ChannelMember>>> listMembers({
    required String workspaceId,
    required String channelId,
  }) async {
    ChannelMember member(String id, String name, String status) =>
        ChannelMember(
          channelId: channelId,
          userId: id,
          email: '$id@vpsttt.test',
          username: id,
          displayName: name,
          status: status,
          joinedAt: DateTime.utc(2026, 11, 1),
        );
    return Success([
      member(_me, 'Tôi', 'active'),
      member(_boss, 'Sếp Lâm', 'active'),
      member(_other, 'Người đã rời', 'left'),
    ]);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}
