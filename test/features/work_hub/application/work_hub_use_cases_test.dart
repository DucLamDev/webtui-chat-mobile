import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/core/error/failure.dart';
import 'package:webtui_chat/features/conversations/domain/entities/collaboration_room.dart';
import 'package:webtui_chat/features/work_hub/application/use_cases/work_hub_use_cases.dart';
import 'package:webtui_chat/features/work_hub/domain/entities/work_hub.dart';

import '../work_hub_fakes.dart';

void main() {
  group('kiểm tra lối tắt trước khi gửi', () {
    test('tên: bỏ khoảng trắng, 1–40 ký tự (đếm ký tự, không phải byte)', () {
      expect(validateShortcutTitle('   '), isNotNull);
      expect(validateShortcutTitle(' Máy chủ '), isNull);
      expect(validateShortcutTitle('đ' * 40), isNull);
      expect(validateShortcutTitle('đ' * 41), isNotNull);
    });

    test('đường dẫn: chỉ https, có địa chỉ, không user:pass', () {
      expect(validateShortcutUrl('https://panel.example.com/a?b=1'), isNull);
      expect(
        validateShortcutUrl('http://panel.example.com'),
        'Đường dẫn phải bắt đầu bằng https://',
      );
      expect(validateShortcutUrl('panel.example.com'), isNotNull);
      expect(validateShortcutUrl('javascript:alert(1)'), isNotNull);
      expect(validateShortcutUrl('https://'), isNotNull);
      expect(validateShortcutUrl('https://u:p@panel.example.com'), isNotNull);
      expect(validateShortcutUrl('https://a.example/${'x' * 2048}'), isNotNull);
    });
  });

  test('lưu lối tắt sai thì không gọi máy chủ', () async {
    final repository = FakeWorkHubRepository();
    final result = await SaveAppShortcutUseCase(repository).execute(
      workspaceId: 'ws',
      draft: const AppShortcutDraft(title: 'A', url: 'http://a.example'),
    );
    expect(result.failureOrNull?.code, 'SHORTCUT_URL_INVALID');
    expect(repository.calls, isEmpty);
  });

  test(
    'lưu lối tắt: cắt khoảng trắng, thêm hoặc sửa theo shortcutId',
    () async {
      final repository = FakeWorkHubRepository();
      final useCase = SaveAppShortcutUseCase(repository);
      await useCase.execute(
        workspaceId: 'ws',
        draft: const AppShortcutDraft(title: ' A ', url: ' https://a.example '),
      );
      await useCase.execute(
        workspaceId: 'ws',
        shortcutId: 's9',
        draft: const AppShortcutDraft(title: 'B', url: 'https://b.example'),
      );
      expect(repository.calls, ['createShortcut', 'updateShortcut:s9']);
      expect(repository.savedDrafts.first.title, 'A');
      expect(repository.savedDrafts.first.url, 'https://a.example');
    },
  );

  test('lỗi máy chủ của lối tắt có câu tiếng Việt dễ hiểu', () async {
    Future<String> messageFor(Failure failure) async {
      final result =
          await SaveAppShortcutUseCase(
            FakeWorkHubRepository(saveFailure: failure),
          ).execute(
            workspaceId: 'ws',
            draft: const AppShortcutDraft(title: 'A', url: 'https://a.example'),
          );
      return result.failureOrNull!.message;
    }

    expect(
      await messageFor(
        const Failure(kind: FailureKind.forbidden, message: 'Forbidden'),
      ),
      contains('quản trị'),
    );
    expect(
      await messageFor(
        const Failure(
          kind: FailureKind.conflict,
          message: 'limit',
          code: 'SHORTCUT_LIMIT_REACHED',
        ),
      ),
      contains('24'),
    );
    expect(
      await messageFor(
        const Failure(kind: FailureKind.validation, message: 'bad request'),
      ),
      contains('chưa hợp lệ'),
    );
  });

  test('tự đếm khi máy chủ cũ: xong tính trong 7 ngày, bỏ việc đã huỷ', () {
    final now = DateTime.utc(2026, 11, 14, 12);
    final summary = countAssignedTasks([
      fakeTask('1', 'a', CollaborationTaskStatus.open),
      fakeTask('2', 'b', CollaborationTaskStatus.inProgress),
      fakeTask('3', 'c', CollaborationTaskStatus.inProgress),
      fakeTask(
        '4',
        'd',
        CollaborationTaskStatus.done,
        completedAt: DateTime.utc(2026, 11, 10),
      ),
      fakeTask(
        '5',
        'e',
        CollaborationTaskStatus.done,
        completedAt: DateTime.utc(2026, 11, 1),
      ),
      fakeTask('6', 'f', CollaborationTaskStatus.cancelled),
    ], now);
    expect(summary.open, 1);
    expect(summary.inProgress, 2);
    expect(summary.doneLast7Days, 1);
  });

  test('isRecentlyDone: chỉ việc đã xong, trong 7 ngày, có giờ hoàn thành', () {
    final now = DateTime.utc(2026, 11, 14, 12);
    CollaborationTask done(DateTime? at) =>
        fakeTask('x', 'x', CollaborationTaskStatus.done, completedAt: at);
    expect(isRecentlyDone(done(DateTime.utc(2026, 11, 14, 11)), now), isTrue);
    expect(isRecentlyDone(done(DateTime.utc(2026, 11, 7, 13)), now), isTrue);
    expect(isRecentlyDone(done(DateTime.utc(2026, 11, 7, 11)), now), isFalse);
    expect(isRecentlyDone(done(null), now), isFalse);
    expect(
      isRecentlyDone(
        fakeTask(
          'y',
          'y',
          CollaborationTaskStatus.inProgress,
          completedAt: DateTime.utc(2026, 11, 14),
        ),
        now,
      ),
      isFalse,
    );
  });

  test('tối đa 3 việc chưa xong, hạn gần nhất trước, không hạn xếp cuối', () {
    final tasks = [
      fakeTask(
        'late',
        'Muộn',
        CollaborationTaskStatus.open,
        dueAt: DateTime.utc(2026, 11, 20),
      ),
      fakeTask('none', 'Không hạn', CollaborationTaskStatus.open),
      fakeTask(
        'soon',
        'Sớm',
        CollaborationTaskStatus.inProgress,
        dueAt: DateTime.utc(2026, 11, 15),
      ),
      fakeTask(
        'done',
        'Xong',
        CollaborationTaskStatus.done,
        dueAt: DateTime.utc(2026, 11, 1),
      ),
      fakeTask(
        'mid',
        'Giữa',
        CollaborationTaskStatus.open,
        dueAt: DateTime.utc(2026, 11, 17),
      ),
    ];
    expect(nearestDueTasks(tasks).map((task) => task.id), [
      'soon',
      'mid',
      'late',
    ]);
  });

  test(
    'máy chủ có work_hub: đếm bằng API, danh sách chỉ lấy việc chưa xong',
    () async {
      final workHub = FakeWorkHubRepository(
        summary: const AssignedTaskSummary(
          open: 7,
          inProgress: 8,
          doneLast7Days: 9,
        ),
      );
      final tasks = FakeTaskRepository([
        fakeTask('1', 'a', CollaborationTaskStatus.open),
      ]);
      final result = await LoadMyTasksOverviewUseCase(
        workHub,
        tasks,
      ).execute(workspaceId: 'ws', serverSummary: true);
      final overview = result.valueOrNull!;
      expect(overview.summary.open, 7);
      expect(overview.summary.doneLast7Days, 9);
      expect(tasks.listStatuses, ['active']);
      expect(workHub.calls, ['assignedTaskSummary']);
    },
  );

  test('máy chủ cũ: không gọi API đếm, tự đếm từ status=all', () async {
    final workHub = FakeWorkHubRepository();
    final tasks = FakeTaskRepository([
      fakeTask('1', 'a', CollaborationTaskStatus.open),
      fakeTask('2', 'b', CollaborationTaskStatus.inProgress),
    ]);
    final result = await LoadMyTasksOverviewUseCase(
      workHub,
      tasks,
    ).execute(workspaceId: 'ws', serverSummary: false);
    expect(result.valueOrNull!.summary.open, 1);
    expect(result.valueOrNull!.summary.inProgress, 1);
    expect(tasks.listStatuses, ['all']);
    expect(workHub.calls, isEmpty);
  });
}
