import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/core/error/failure.dart';
import 'package:webtui_chat/features/conversations/domain/entities/collaboration_room.dart';
import 'package:webtui_chat/features/conversations/presentation/screens/workspace_tools_screen.dart';
import 'package:webtui_chat/features/work_hub/domain/entities/work_hub.dart';
import 'package:webtui_chat/features/work_hub/presentation/widgets/my_tasks_card.dart';

import '../../meeting_calendar/meeting_calendar_fakes.dart';
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
    FakeMeetingCalendarRepository? calendar,
    DateTime? now,
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
        calendar: calendar,
        now: now,
        home: Scaffold(
          body: WorkspaceToolsScreen(workspaceId: 'ws', now: now),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Việc của tôi: tiêu đề lớn + tìm, 3 cột số, 2 việc gần hạn', (
    tester,
  ) async {
    await pumpTab(tester);

    // Tiêu đề lớn 'Công việc' với nút tìm ở đầu màn (ngoài nhóm Việc của tôi).
    expect(find.text('Công việc'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('my_tasks_card')),
        matching: find.byKey(const Key('work_search')),
      ),
      findsNothing,
    );
    expect(
      tester.getSize(find.byKey(const Key('work_search'))).width,
      inInclusiveRange(44, 48),
    );
    expect(find.text('Việc của tôi'), findsOneWidget);
    expect(find.text('Xem tất cả'), findsOneWidget);
    // Không còn thẻ bo góc / ô nền: số liệu nằm thẳng trên nền trang.
    expect(
      find.descendant(
        of: find.byKey(const Key('my_tasks_card')),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is DecoratedBox &&
              widget.decoration is BoxDecoration &&
              (widget.decoration as BoxDecoration).borderRadius != null,
        ),
      ),
      findsNothing,
    );
    for (final (key, number, label) in [
      ('count_open', '1', 'Chưa nhận'),
      ('count_in_progress', '2', 'Đã nhận'),
      ('count_done', '4', 'Hoàn thành'),
    ]) {
      final tile = find.byKey(Key(key));
      expect(find.descendant(of: tile, matching: find.text(number)), findsOne);
      expect(find.descendant(of: tile, matching: find.text(label)), findsOne);
    }
    // Hạn gần nhất lên trước, chỉ 2 việc; phụ đề "Hạn dd/MM, HH:mm – nhóm".
    final titles = ['Kiểm tra cụm lưu trữ', 'Cập nhật bảng giá'];
    final tops = [for (final t in titles) tester.getTopLeft(find.text(t)).dy];
    expect(tops, orderedEquals([...tops]..sort()));
    expect(find.text('Viết tài liệu API'), findsNothing);
    expect(find.text('Hạn 16/11, 09:00 – Nhóm Kỹ thuật'), findsOneWidget);
    expect(find.text('Hạn 17/11, 09:00 – Nhóm Kinh doanh'), findsOneWidget);
  });

  test('phụ đề việc: hạn không giờ bỏ giờ, không hạn chỉ tên nhóm', () {
    expect(
      workTabTaskSubtitle(
        fakeTask(
          'x',
          'X',
          CollaborationTaskStatus.open,
          dueAt: DateTime(2026, 11, 18),
        ),
      ),
      'Hạn 18/11 – Nhóm Kỹ thuật',
    );
    expect(
      workTabTaskSubtitle(fakeTask('y', 'Y', CollaborationTaskStatus.open)),
      'Nhóm Kỹ thuật',
    );
    expect(
      workTabTaskSubtitle(
        fakeTask('z', 'Z', CollaborationTaskStatus.open, channelName: ' '),
      ),
      'Không có hạn',
    );
  });

  testWidgets('chỉ hiện tối đa 2 việc dù có nhiều hơn', (tester) async {
    await pumpTab(
      tester,
      tasks: FakeTaskRepository([
        ...threeTasks,
        fakeTask('d', 'Việc thứ tư', CollaborationTaskStatus.open),
      ]),
    );
    expect(find.text('Việc thứ tư'), findsNothing);
    expect(find.byKey(const Key('task_row_a')), findsNothing);
    expect(find.byKey(const Key('task_row_b')), findsOneWidget);
    expect(find.byKey(const Key('task_row_c')), findsOneWidget);
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
    // Chỉ 2 việc hiện: bỏ việc c để việc a (chưa nhận) lọt vào danh sách.
    final tasks = FakeTaskRepository([threeTasks[0], threeTasks[1]]);
    await pumpTab(tester, tasks: tasks);
    expect(
      tester.getSize(find.byKey(const Key('task_box_a'))).width,
      greaterThanOrEqualTo(44),
    );

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

  testWidgets('lưới Ứng dụng có ô Ghi chú mở /my-notes; tắt thì ẩn', (
    tester,
  ) async {
    await pumpTab(tester);
    // My Note không còn thẻ riêng: thành ô "Ghi chú" trong lưới Ứng dụng.
    expect(find.text('My Note'), findsNothing);
    expect(find.text('Ghi chú riêng, chỉ mình bạn xem'), findsNothing);
    final tile = find.byKey(const Key('workspace_module_my_notes'));
    expect(
      find.descendant(
        of: find.byKey(const Key('work_apps_section')),
        matching: tile,
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: tile, matching: find.text('Ghi chú')),
      findsOneWidget,
    );
    // Cùng hàng với Tệp chia sẻ, sau Tệp chia sẻ.
    final files = tester.getRect(find.byKey(const Key('app_shared_files')));
    final notes = tester.getRect(tile);
    expect(notes.top, moreOrLessEquals(files.top));
    expect(notes.left, greaterThan(files.left));

    await tester.ensureVisible(tile);
    await tester.tap(tile);
    await tester.pumpAndSettle();
    expect(find.text('màn My Note'), findsOneWidget);

    await pumpTab(tester, myNotes: false);
    expect(find.byKey(const Key('workspace_module_my_notes')), findsNothing);
    expect(find.text('Ghi chú'), findsNothing);
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
      final section = find.byKey(const Key('work_apps_section'));
      for (final text in ['Lịch họp', 'Tệp chia sẻ', 'Máy chủ', 'Thêm']) {
        expect(
          find.descendant(of: section, matching: find.text(text)),
          findsOneWidget,
        );
      }

      // Ô ứng dụng: nền gradient riêng, bo 14, biểu tượng trắng; ô Thêm khác.
      Iterable<Decoration> decorations(String key) => tester
          .widgetList<DecoratedBox>(
            find.descendant(
              of: find.byKey(Key(key)),
              matching: find.byKey(const Key('app_tile_color')),
            ),
          )
          .map((box) => box.decoration);
      final gradients = <LinearGradient>[];
      for (final key in [
        'app_meetings',
        'app_shared_files',
        'app_shortcut_s1',
      ]) {
        final decoration = decorations(key).single as BoxDecoration;
        expect(decoration.borderRadius, BorderRadius.circular(14));
        gradients.add(decoration.gradient! as LinearGradient);
        expect(
          tester.getSize(
            find.descendant(
              of: find.byKey(Key(key)),
              matching: find.byKey(const Key('app_tile_color')),
            ),
          ),
          const Size(52, 52),
        );
      }
      expect(
        {for (final g in gradients) g.colors.first}.length,
        3,
        reason: 'mỗi ứng dụng một màu riêng',
      );
      for (final gradient in gradients) {
        for (final color in gradient.colors) {
          final l = color.computeLuminance();
          expect(1.05 / (l + 0.05), greaterThanOrEqualTo(3));
        }
      }
      final add = find.byKey(const Key('app_add'));
      expect(
        find.descendant(
          of: add,
          matching: find.byKey(const Key('app_tile_dashed')),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: add,
          matching: find.byKey(const Key('app_tile_color')),
        ),
        findsNothing,
      );

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

  testWidgets('chưa có lối tắt: lưới chỉ có ô sẵn có, không câu báo thừa', (
    tester,
  ) async {
    await pumpTab(tester);
    await tester.ensureVisible(find.byKey(const Key('app_shared_files')));
    expect(find.byKey(const Key('app_meetings')), findsOneWidget);
    expect(find.byKey(const Key('workspace_module_my_notes')), findsOneWidget);
    expect(find.text('Chưa có lối tắt'), findsNothing);
  });

  testWidgets('lỗi tải lối tắt: câu báo gọn + Thử lại', (tester) async {
    final repository = FakeWorkHubRepository(
      shortcutsFailure: const Failure(
        kind: FailureKind.network,
        message: 'Không thể kết nối máy chủ.',
      ),
    );
    await pumpTab(tester, repository: repository);
    expect(find.text('Không thể kết nối máy chủ.'), findsOneWidget);
    expect(find.byKey(const Key('app_shared_files')), findsOneWidget);
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
    // Không có Lịch họp thì cũng không có nhóm Họp sắp tới.
    expect(find.byKey(const Key('upcoming_meetings')), findsNothing);
    expect(find.text('Họp sắp tới'), findsNothing);
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

  group('Họp sắp tới', () {
    final now = DateTime(2026, 11, 16, 8);

    testWidgets('tối đa 3 họp chưa qua, chưa huỷ; giờ + Hôm nay / Ngày mai', (
      tester,
    ) async {
      final calendar = FakeMeetingCalendarRepository(
        meetings: [
          fakeMeeting(
            'm3',
            title: 'Tổng kết',
            startsAt: DateTime(2026, 11, 20, 16),
          ),
          fakeMeeting(
            'm1',
            title: 'Họp giao ban tuần',
            channelName: 'Nhóm dự án',
            startsAt: DateTime(2026, 11, 16, 16, 15),
          ),
          fakeMeeting(
            'huy',
            title: 'Họp đã huỷ',
            startsAt: DateTime(2026, 11, 16, 10),
            status: 'cancelled',
          ),
          fakeMeeting(
            'qua',
            title: 'Họp sáng sớm',
            startsAt: DateTime(2026, 11, 16, 6),
            endsAt: DateTime(2026, 11, 16, 7),
          ),
          fakeMeeting(
            'm2',
            channelId: 'c2',
            title: 'Demo sản phẩm',
            channelName: 'Kinh doanh',
            startsAt: DateTime(2026, 11, 17, 14),
          ),
          fakeMeeting(
            'm4',
            title: 'Họp thứ tư',
            startsAt: DateTime(2026, 11, 25, 9),
          ),
        ],
      );
      await pumpTab(tester, calendar: calendar, now: now);
      final section = find.byKey(const Key('upcoming_meetings'));
      await tester.ensureVisible(section);
      expect(
        find.descendant(of: section, matching: find.text('Họp sắp tới')),
        findsOneWidget,
      );

      final ids = ['m1', 'm2', 'm3'];
      for (final id in ids) {
        expect(find.byKey(Key('upcoming_meeting_$id')), findsOneWidget);
      }
      final tops = [
        for (final id in ids)
          tester.getTopLeft(find.byKey(Key('upcoming_meeting_$id'))).dy,
      ];
      expect(tops, orderedEquals([...tops]..sort()));
      for (final id in ['m4', 'huy', 'qua']) {
        expect(find.byKey(Key('upcoming_meeting_$id')), findsNothing);
      }
      Finder inRow(String id, String text) => find.descendant(
        of: find.byKey(Key('upcoming_meeting_$id')),
        matching: find.text(text),
      );
      expect(inRow('m1', '16:15'), findsOneWidget);
      expect(inRow('m1', 'Hôm nay'), findsOneWidget);
      expect(inRow('m1', 'Nhóm dự án'), findsOneWidget);
      expect(inRow('m2', '14:00'), findsOneWidget);
      expect(inRow('m2', 'Ngày mai'), findsOneWidget);
      expect(inRow('m3', '20/11'), findsOneWidget);
      // Cột giờ rộng 66, phần chữ thẳng hàng giữa các dòng.
      expect(
        tester.getTopLeft(inRow('m1', 'Họp giao ban tuần')).dx,
        moreOrLessEquals(tester.getTopLeft(inRow('m2', 'Demo sản phẩm')).dx),
      );

      await tester.tap(find.byKey(const Key('upcoming_meeting_m2')));
      await tester.pumpAndSettle();
      expect(calendar.calls, contains('get:c2/m2'));
    });

    testWidgets('không có họp: báo rỗng; "Lịch họp" mở màn Lịch họp', (
      tester,
    ) async {
      await pumpTab(tester, now: now);
      final empty = find.byKey(const Key('upcoming_meetings_empty'));
      await tester.ensureVisible(empty);
      expect(
        find.descendant(
          of: empty,
          matching: find.text('Chưa có cuộc họp sắp tới'),
        ),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('upcoming_meetings_all')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('meetings_list')), findsOneWidget);
    });

    testWidgets('lỗi tải họp: một dòng báo + Thử lại tải lại được', (
      tester,
    ) async {
      final calendar = FakeMeetingCalendarRepository(
        meetings: [
          fakeMeeting(
            'm1',
            title: 'Họp giao ban tuần',
            startsAt: DateTime(2026, 11, 16, 16),
          ),
        ],
        listFailure: const Failure(
          kind: FailureKind.network,
          message: 'Không thể kết nối máy chủ.',
        ),
      );
      await pumpTab(tester, calendar: calendar, now: now);
      final error = find.byKey(const Key('upcoming_meetings_error'));
      await tester.ensureVisible(error);
      expect(error, findsOneWidget);

      calendar.listFailure = null;
      await tester.tap(
        find.descendant(of: error, matching: find.text('Thử lại')),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('upcoming_meeting_m1')), findsOneWidget);
    });
  });
}
