import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/core/error/failure.dart';
import 'package:webtui_chat/features/conversations/domain/entities/collaboration_room.dart';
import 'package:webtui_chat/features/work_hub/domain/entities/work_hub.dart';

import '../../work_hub/presentation/work_hub_harness.dart';
import '../../work_hub/work_hub_fakes.dart';

void main() {
  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(390, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  final threeTasks = [
    fakeTask(
      'a',
      'Viết tài liệu API',
      CollaborationTaskStatus.open,
      dueAt: DateTime(2026, 11, 18, 9),
    ),
    fakeTask(
      'b',
      'Kiểm tra cụm lưu trữ',
      CollaborationTaskStatus.inProgress,
      dueAt: DateTime(2026, 11, 16, 9),
    ),
    fakeTask(
      'c',
      'Cập nhật bảng giá',
      CollaborationTaskStatus.inProgress,
      dueAt: DateTime(2026, 11, 17, 9),
      channelName: 'Nhóm Kinh doanh',
    ),
  ];

  Future<void> pumpTab(
    WidgetTester tester, {
    FakeWorkHubRepository? repository,
    FakeTaskRepository? tasks,
    bool workHub = true,
    bool myNotes = true,
    FakeLauncher? launcher,
  }) async {
    phone(tester);
    await tester.pumpWidget(
      workHubApp(
        repository:
            repository ??
            FakeWorkHubRepository(
              summary: const AssignedTaskSummary(
                open: 1,
                inProgress: 2,
                doneLast7Days: 4,
              ),
            ),
        tasks: tasks ?? FakeTaskRepository(threeTasks),
        workHub: workHub,
        myNotes: myNotes,
        launcher: launcher,
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('thẻ Việc của tôi: 3 ô đếm của máy chủ và 3 việc gần hạn', (
    tester,
  ) async {
    await pumpTab(tester);

    expect(find.text('Công việc'), findsOneWidget);
    expect(find.text('Việc của tôi'), findsOneWidget);
    expect(
      find.text('Tự gom từ bảng việc trong các cuộc trò chuyện'),
      findsOne,
    );
    expect(find.text('Xem tất cả'), findsOneWidget);
    for (final (key, number, label) in [
      ('count_open', '1', 'Chưa nhận'),
      ('count_in_progress', '2', 'Đã nhận'),
      ('count_done', '4', 'Hoàn thành'),
    ]) {
      final tile = find.byKey(Key(key));
      expect(find.descendant(of: tile, matching: find.text(number)), findsOne);
      expect(find.descendant(of: tile, matching: find.text(label)), findsOne);
    }
    // Hạn gần nhất lên trước.
    final titles = [
      'Kiểm tra cụm lưu trữ',
      'Cập nhật bảng giá',
      'Viết tài liệu API',
    ];
    final tops = [for (final t in titles) tester.getTopLeft(find.text(t)).dy];
    expect(tops, orderedEquals([...tops]..sort()));
    expect(find.text('Nhóm Kỹ thuật · Hạn 16/11'), findsOneWidget);
    expect(find.text('Nhóm Kinh doanh · Hạn 17/11'), findsOneWidget);
  });

  testWidgets('chỉ lấy tối đa 3 việc dù có nhiều hơn', (tester) async {
    await pumpTab(
      tester,
      tasks: FakeTaskRepository([
        ...threeTasks,
        fakeTask('d', 'Việc thứ tư', CollaborationTaskStatus.open),
      ]),
    );
    expect(find.text('Việc thứ tư'), findsNothing);
    expect(find.byKey(const Key('task_row_a')), findsOneWidget);
  });

  testWidgets('chưa có việc: báo rỗng', (tester) async {
    await pumpTab(
      tester,
      repository: FakeWorkHubRepository(),
      tasks: FakeTaskRepository([]),
    );
    expect(find.text('Chưa có việc nào được giao cho bạn'), findsOneWidget);
  });

  testWidgets('lỗi tải việc: hiện câu báo và Thử lại tải lại được', (
    tester,
  ) async {
    final tasks = FakeTaskRepository(
      threeTasks,
      listFailure: const Failure(
        kind: FailureKind.network,
        message: 'Không thể kết nối máy chủ.',
      ),
    );
    await pumpTab(tester, tasks: tasks);
    expect(find.text('Không thể kết nối máy chủ.'), findsOneWidget);

    tasks.listFailure = null;
    await tester.tap(find.text('Thử lại'));
    await tester.pumpAndSettle();
    expect(find.text('Kiểm tra cụm lưu trữ'), findsOneWidget);
  });

  testWidgets('bấm ô: chưa nhận → đã nhận, có Hoàn tác trả về như cũ', (
    tester,
  ) async {
    final tasks = FakeTaskRepository(threeTasks);
    await pumpTab(tester, tasks: tasks);

    await tester.tap(find.byKey(const Key('task_box_a')));
    await tester.pumpAndSettle();
    expect(tasks.statusRequests, ['a:in_progress']);
    expect(find.text('Hoàn tác'), findsOneWidget);

    await tester.tap(find.text('Hoàn tác'));
    await tester.pumpAndSettle();
    expect(tasks.statusRequests, ['a:in_progress', 'a:open']);
  });

  testWidgets('bấm ô: đã nhận → hoàn thành, việc rời khỏi danh sách', (
    tester,
  ) async {
    final tasks = FakeTaskRepository(threeTasks);
    await pumpTab(tester, tasks: tasks);

    await tester.tap(find.byKey(const Key('task_box_b')));
    await tester.pumpAndSettle();
    expect(tasks.statusRequests, ['b:done']);
    expect(find.text('Kiểm tra cụm lưu trữ'), findsNothing);
  });

  testWidgets('bấm dòng việc mở việc trong kênh', (tester) async {
    await pumpTab(tester);
    await tester.tap(find.byKey(const Key('task_row_b')));
    await tester.pumpAndSettle();
    expect(find.text('kênh ch-b tasks b'), findsOneWidget);
  });

  testWidgets('Xem tất cả và nút tìm mở màn Việc của tôi', (tester) async {
    await pumpTab(tester);
    await tester.tap(find.byKey(const Key('my_tasks_see_all')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('my_tasks_search')), findsNothing);
    expect(find.text('Chưa nhận'), findsOneWidget);

    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('work_search')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('my_tasks_search')), findsOneWidget);
  });

  testWidgets('My Note: mở /my-notes; tắt theo máy chủ thì ẩn', (tester) async {
    await pumpTab(tester);
    expect(find.text('My Note'), findsOneWidget);
    expect(find.text('Ghi chú riêng, chỉ mình bạn xem'), findsOneWidget);
    await tester.ensureVisible(
      find.byKey(const Key('workspace_module_my_notes')),
    );
    await tester.tap(find.byKey(const Key('workspace_module_my_notes')));
    await tester.pumpAndSettle();
    expect(find.text('màn My Note'), findsOneWidget);

    await pumpTab(tester, myNotes: false);
    expect(find.text('My Note'), findsNothing);
  });

  testWidgets(
    'khối Ứng dụng khi can_manage: Lịch họp, Tệp, lối tắt, Thêm, Quản lý',
    (tester) async {
      final launcher = FakeLauncher();
      await pumpTab(
        tester,
        launcher: launcher,
        repository: FakeWorkHubRepository(
          canManage: true,
          shortcuts: const [
            AppShortcut(
              id: 's1',
              title: 'Máy chủ',
              url: 'https://panel.example.com',
              icon: 'server',
              color: 'violet',
            ),
          ],
        ),
      );
      await tester.scrollUntilVisible(
        find.text('Quản lý'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Ứng dụng'), findsOneWidget);
      expect(find.text('Quản lý'), findsOneWidget);
      for (final text in ['Lịch họp', 'Tệp chia sẻ', 'Máy chủ', 'Thêm']) {
        expect(find.text(text), findsOneWidget);
      }

      await tester.tap(find.byKey(const Key('app_shortcut_s1')));
      await tester.pumpAndSettle();
      expect(launcher.opened, ['https://panel.example.com']);
    },
  );

  testWidgets('lối tắt có đường dẫn không phải https thì không mở', (
    tester,
  ) async {
    final launcher = FakeLauncher();
    await pumpTab(
      tester,
      launcher: launcher,
      repository: FakeWorkHubRepository(
        shortcuts: const [
          AppShortcut(id: 's1', title: 'Xấu', url: 'http://bad.example'),
        ],
      ),
    );
    final tile = find.byKey(const Key('app_shortcut_s1'));
    await tester.ensureVisible(tile);
    await tester.tap(tile);
    await tester.pumpAndSettle();
    expect(launcher.opened, isEmpty);
    expect(find.text('Đường dẫn lối tắt không hợp lệ.'), findsOneWidget);
  });

  testWidgets('không can_manage: không có Thêm và Quản lý', (tester) async {
    await pumpTab(
      tester,
      repository: FakeWorkHubRepository(
        shortcuts: const [
          AppShortcut(id: 's1', title: 'Máy chủ', url: 'https://a.example'),
        ],
      ),
    );
    await tester.ensureVisible(find.byKey(const Key('app_shortcut_s1')));
    expect(find.text('Máy chủ'), findsOneWidget);
    expect(find.text('Thêm'), findsNothing);
    expect(find.text('Quản lý'), findsNothing);
  });

  testWidgets('chưa có lối tắt: báo "Chưa có lối tắt"', (tester) async {
    await pumpTab(tester);
    await tester.ensureVisible(find.byKey(const Key('app_shared_files')));
    expect(find.text('Chưa có lối tắt'), findsOneWidget);
  });

  testWidgets('máy chủ cũ (không work_hub): ẩn Lịch họp và lối tắt, tự đếm', (
    tester,
  ) async {
    final repository = FakeWorkHubRepository(
      canManage: true,
      shortcuts: const [
        AppShortcut(id: 's1', title: 'Máy chủ', url: 'https://a.example'),
      ],
    );
    await pumpTab(tester, repository: repository, workHub: false);
    await tester.ensureVisible(find.byKey(const Key('app_shared_files')));

    expect(find.text('Lịch họp'), findsNothing);
    expect(find.text('Máy chủ'), findsNothing);
    expect(find.text('Thêm'), findsNothing);
    expect(find.text('Quản lý'), findsNothing);
    expect(find.text('Tệp chia sẻ'), findsOneWidget);
    expect(repository.calls, isEmpty);
    // Tự đếm từ danh sách việc: 1 chưa nhận, 2 đã nhận.
    expect(
      find.descendant(
        of: find.byKey(const Key('count_open')),
        matching: find.text('1'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('count_in_progress')),
        matching: find.text('2'),
      ),
      findsOneWidget,
    );
  });
}
