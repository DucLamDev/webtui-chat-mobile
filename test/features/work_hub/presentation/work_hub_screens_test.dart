import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/core/error/failure.dart';
import 'package:webtui_chat/design_system/icons/webtui_icons.dart';
import 'package:webtui_chat/features/conversations/domain/entities/collaboration_room.dart';
import 'package:webtui_chat/features/work_hub/domain/entities/work_hub.dart';
import 'package:webtui_chat/features/work_hub/presentation/screens/meetings_screen.dart';
import 'package:webtui_chat/features/work_hub/presentation/screens/my_tasks_screen.dart';
import 'package:webtui_chat/features/work_hub/presentation/screens/shared_files_screen.dart';
import 'package:webtui_chat/features/work_hub/presentation/screens/shortcuts_manage_screen.dart';

import '../work_hub_fakes.dart';
import 'work_hub_harness.dart';

void main() {
  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(390, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  group('form thêm / sửa lối tắt', () {
    Future<FakeWorkHubRepository> openAddForm(
      WidgetTester tester, {
      Failure? saveFailure,
    }) async {
      phone(tester);
      final repository = FakeWorkHubRepository(
        canManage: true,
        saveFailure: saveFailure,
      );
      await tester.pumpWidget(
        workHubApp(repository: repository, tasks: FakeTaskRepository([])),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('app_add')));
      await tester.tap(find.byKey(const Key('app_add')));
      await tester.pumpAndSettle();
      return repository;
    }

    testWidgets('có lưới 20 biểu tượng và hàng 7 màu', (tester) async {
      await openAddForm(tester);
      expect(find.text('Thêm lối tắt'), findsOneWidget);
      expect(find.byKey(const Key('shortcut_icon_server')), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget.key is ValueKey<String> &&
              (widget.key! as ValueKey<String>).value.startsWith(
                'shortcut_icon_',
              ),
        ),
        findsNWidgets(20),
      );
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget.key is ValueKey<String> &&
              (widget.key! as ValueKey<String>).value.startsWith(
                'shortcut_color_',
              ),
        ),
        findsNWidgets(7),
      );
    });

    testWidgets('tên trống và đường dẫn http: báo lỗi, không gọi máy chủ', (
      tester,
    ) async {
      final repository = await openAddForm(tester);
      await tester.enterText(
        find.byKey(const Key('shortcut_url')),
        'http://panel.example.com',
      );
      await tester.tap(find.byKey(const Key('shortcut_save')));
      await tester.pumpAndSettle();

      expect(find.text('Hãy nhập tên lối tắt.'), findsOneWidget);
      expect(find.text('Đường dẫn phải bắt đầu bằng https://'), findsOneWidget);
      expect(repository.calls.where((c) => c.startsWith('create')), isEmpty);
    });

    testWidgets('tên quá 40 ký tự bị chặn', (tester) async {
      final repository = await openAddForm(tester);
      final field = tester.widget<TextField>(
        find.byKey(const Key('shortcut_title')),
      );
      expect(field.maxLength, 40);
      expect(repository.calls.where((c) => c.startsWith('create')), isEmpty);
    });

    testWidgets('nhập đúng: gửi tên, https, biểu tượng và màu đã chọn', (
      tester,
    ) async {
      final repository = await openAddForm(tester);
      await tester.enterText(
        find.byKey(const Key('shortcut_title')),
        '  Máy chủ  ',
      );
      await tester.enterText(
        find.byKey(const Key('shortcut_url')),
        'https://panel.example.com',
      );
      await tester.tap(find.byKey(const Key('shortcut_icon_server')));
      await tester.tap(find.byKey(const Key('shortcut_color_violet')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('shortcut_save')));
      await tester.pumpAndSettle();

      final draft = repository.savedDrafts.single;
      expect(draft.title, 'Máy chủ');
      expect(draft.url, 'https://panel.example.com');
      expect(draft.icon, 'server');
      expect(draft.color, 'violet');
      // Đóng form và ô mới hiện ở lưới.
      expect(find.byKey(const Key('shortcut_form')), findsNothing);
      expect(find.text('Máy chủ'), findsOneWidget);
    });

    testWidgets('máy chủ báo đủ 24 lối tắt: hiện câu dễ hiểu, giữ form', (
      tester,
    ) async {
      await openAddForm(
        tester,
        saveFailure: const Failure(
          kind: FailureKind.conflict,
          message: 'limit',
          code: 'SHORTCUT_LIMIT_REACHED',
        ),
      );
      await tester.enterText(find.byKey(const Key('shortcut_title')), 'A');
      await tester.enterText(
        find.byKey(const Key('shortcut_url')),
        'https://a.example',
      );
      await tester.tap(find.byKey(const Key('shortcut_save')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('shortcut_form')), findsOneWidget);
      expect(find.textContaining('Đã đủ 24 lối tắt'), findsOneWidget);
    });

    testWidgets('không có quyền (403): báo chỉ quản trị viên được thay đổi', (
      tester,
    ) async {
      await openAddForm(
        tester,
        saveFailure: const Failure(
          kind: FailureKind.forbidden,
          message: 'Forbidden',
          code: 'FORBIDDEN',
        ),
      );
      await tester.enterText(find.byKey(const Key('shortcut_title')), 'A');
      await tester.enterText(
        find.byKey(const Key('shortcut_url')),
        'https://a.example',
      );
      await tester.tap(find.byKey(const Key('shortcut_save')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('shortcut_server_error')), findsOneWidget);
      expect(find.textContaining('quản trị viên'), findsOneWidget);
    });
  });

  group('màn Quản lý lối tắt', () {
    final items = [
      const AppShortcut(id: 's1', title: 'Một', url: 'https://1.example'),
      const AppShortcut(id: 's2', title: 'Hai', url: 'https://2.example'),
    ];

    Future<FakeWorkHubRepository> openManage(
      WidgetTester tester, {
      bool canManage = true,
    }) async {
      phone(tester);
      final repository = FakeWorkHubRepository(
        canManage: canManage,
        shortcuts: [...items],
      );
      await tester.pumpWidget(
        workHubApp(repository: repository, tasks: FakeTaskRepository([])),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('apps_manage')));
      await tester.tap(find.byKey(const Key('apps_manage')));
      await tester.pumpAndSettle();
      return repository;
    }

    testWidgets('xoá có hộp xác nhận, Huỷ thì giữ nguyên', (tester) async {
      final repository = await openManage(tester);
      await tester.tap(find.byKey(const Key('shortcut_delete_s1')));
      await tester.pumpAndSettle();
      expect(find.text('Xoá lối tắt?'), findsOneWidget);
      await tester.tap(find.text('Huỷ'));
      await tester.pumpAndSettle();
      expect(repository.calls.where((c) => c.startsWith('delete')), isEmpty);

      await tester.tap(find.byKey(const Key('shortcut_delete_s1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('shortcut_delete_confirm')));
      await tester.pumpAndSettle();
      expect(repository.calls, contains('deleteShortcut:s1'));
      expect(find.text('Một'), findsNothing);
      expect(find.text('Hai'), findsOneWidget);
    });

    testWidgets('kéo tay cầm đổi thứ tự rồi gửi đủ mọi id', (tester) async {
      final repository = await openManage(tester);
      await tester.timedDrag(
        find.byIcon(WebTuiIcons.dragHandle).first,
        const Offset(0, 150),
        const Duration(milliseconds: 600),
      );
      await tester.pumpAndSettle();
      expect(repository.lastOrder, ['s2', 's1']);
    });

    testWidgets('không có quyền quản lý: báo rõ, không có danh sách', (
      tester,
    ) async {
      phone(tester);
      final repository = FakeWorkHubRepository(shortcuts: [...items]);
      await tester.pumpWidget(
        workHubApp(
          repository: repository,
          tasks: FakeTaskRepository([]),
          home: const _ManageOnly(),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Chỉ quản trị viên mới được quản lý lối tắt.'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('shortcut_reorder_list')), findsNothing);
    });
  });

  group('màn Lịch họp', () {
    final now = DateTime(2026, 11, 14, 8);

    testWidgets('nhóm theo ngày: Hôm nay, Ngày mai, dd/MM; nhãn Đang diễn ra', (
      tester,
    ) async {
      phone(tester);
      final repository = FakeWorkHubRepository(
        meetings: [
          UpcomingMeeting(
            id: 'm1',
            channelId: 'c1',
            channelName: 'Nhóm Kỹ thuật',
            title: 'Họp tuần',
            startsAt: DateTime(2026, 11, 14, 9),
            endsAt: DateTime(2026, 11, 14, 10, 30),
            status: 'active',
          ),
          UpcomingMeeting(
            id: 'm2',
            channelId: 'c2',
            channelName: 'Kinh doanh',
            title: 'Chốt bảng giá',
            startsAt: DateTime(2026, 11, 15, 14),
            endsAt: DateTime(2026, 11, 15, 15),
          ),
          UpcomingMeeting(
            id: 'm3',
            channelId: 'c1',
            channelName: 'Nhóm Kỹ thuật',
            title: 'Tổng kết',
            startsAt: DateTime(2026, 11, 20, 16),
            endsAt: null,
          ),
        ],
      );
      await tester.pumpWidget(
        workHubApp(
          repository: repository,
          tasks: FakeTaskRepository([]),
          home: MeetingsScreen(workspaceId: 'ws', now: now),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Hôm nay'), findsOneWidget);
      expect(find.text('Ngày mai'), findsOneWidget);
      expect(find.text('20/11'), findsOneWidget);
      expect(find.text('09:00 – 10:30'), findsOneWidget);
      expect(find.text('16:00'), findsOneWidget);
      expect(find.text('Đang diễn ra'), findsOneWidget);
      expect(find.text('Họp tuần'), findsOneWidget);
      expect(find.text('Kinh doanh'), findsOneWidget);
    });

    testWidgets('không có cuộc họp: báo rỗng', (tester) async {
      phone(tester);
      await tester.pumpWidget(
        workHubApp(
          repository: FakeWorkHubRepository(),
          tasks: FakeTaskRepository([]),
          home: const MeetingsScreen(workspaceId: 'ws'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Chưa có cuộc họp sắp tới'), findsOneWidget);
    });

    test('groupMeetingsByDay sắp xếp theo giờ trong ngày', () {
      final groups = groupMeetingsByDay([
        UpcomingMeeting(
          id: 'b',
          channelId: 'c',
          channelName: '',
          title: 'Sau',
          startsAt: DateTime(2026, 11, 14, 15),
          endsAt: null,
        ),
        UpcomingMeeting(
          id: 'a',
          channelId: 'c',
          channelName: '',
          title: 'Trước',
          startsAt: DateTime(2026, 11, 14, 9),
          endsAt: null,
        ),
      ], DateTime(2026, 11, 14, 8));
      expect(groups.single.$1, 'Hôm nay');
      expect(groups.single.$2.map((m) => m.id), ['a', 'b']);
    });
  });

  group('màn Tệp chia sẻ', () {
    final files = [
      SharedFile(
        id: 'f1',
        name: 'anh-san-pham.png',
        mimeType: 'image/png',
        byteSize: 2 * 1024 * 1024,
        createdAt: DateTime(2026, 11, 10),
      ),
      SharedFile(
        id: 'f2',
        name: 'quay-man-hinh.mp4',
        mimeType: 'video/mp4',
        byteSize: 5000,
        createdAt: DateTime(2026, 11, 11),
      ),
      SharedFile(
        id: 'f3',
        name: 'bao-cao.pdf',
        mimeType: 'application/pdf',
        byteSize: 800,
        createdAt: DateTime(2026, 11, 12),
      ),
      SharedFile(
        id: 'f4',
        name: 'ghi-am.m4a',
        mimeType: 'audio/mp4',
        byteSize: 3000,
        createdAt: DateTime(2026, 11, 13),
      ),
    ];

    Future<void> openFiles(WidgetTester tester, List<SharedFile> data) async {
      phone(tester);
      await tester.pumpWidget(
        workHubApp(
          repository: FakeWorkHubRepository(files: data),
          tasks: FakeTaskRepository([]),
          home: const SharedFilesScreen(workspaceId: 'ws'),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('lọc theo loại: Ảnh / Video / Tài liệu / Ghi âm', (
      tester,
    ) async {
      await openFiles(tester, files);
      expect(find.byKey(const Key('files_list')), findsOneWidget);
      for (final id in ['f1', 'f2', 'f3', 'f4']) {
        expect(find.byKey(Key('file_$id')), findsOneWidget);
      }
      expect(find.text('2,0 MB · 10/11/2026'), findsOneWidget);

      Future<void> choose(String key, Set<String> expected) async {
        await tester.ensureVisible(find.byKey(Key(key)));
        await tester.tap(find.byKey(Key(key)));
        await tester.pumpAndSettle();
        for (final id in ['f1', 'f2', 'f3', 'f4']) {
          expect(
            find.byKey(Key('file_$id')),
            expected.contains(id) ? findsOneWidget : findsNothing,
            reason: '$key / $id',
          );
        }
      }

      await choose('files_filter_image', {'f1'});
      await choose('files_filter_video', {'f2'});
      await choose('files_filter_document', {'f3'});
      await choose('files_filter_audio', {'f4'});
      await choose('files_filter_all', {'f1', 'f2', 'f3', 'f4'});
    });

    testWidgets('chưa có tệp / lọc không còn tệp nào', (tester) async {
      await openFiles(tester, const []);
      expect(find.text('Chưa có tệp nào'), findsOneWidget);

      await openFiles(tester, [files.first]);
      await tester.ensureVisible(find.byKey(const Key('files_filter_audio')));
      await tester.tap(find.byKey(const Key('files_filter_audio')));
      await tester.pumpAndSettle();
      expect(find.text('Không có tệp nào ở mục này'), findsOneWidget);
    });

    test('nhãn kích thước tệp', () {
      expect(sharedFileSizeLabel(500), '500 B');
      expect(sharedFileSizeLabel(1536), '1,5 KB');
      expect(sharedFileSizeLabel(20 * 1024), '20 KB');
      expect(sharedFileSizeLabel(3 * 1024 * 1024), '3,0 MB');
    });
  });

  group('màn Việc của tôi', () {
    testWidgets('lọc Chưa nhận / Đã nhận / Hoàn thành và tìm theo tên', (
      tester,
    ) async {
      phone(tester);
      final tasks = FakeTaskRepository([
        fakeTask('a', 'Viết tài liệu API', CollaborationTaskStatus.open),
        fakeTask(
          'b',
          'Kiểm tra cụm lưu trữ',
          CollaborationTaskStatus.inProgress,
        ),
        fakeTask('c', 'Gửi báo cáo tuần', CollaborationTaskStatus.done),
      ]);
      await tester.pumpWidget(
        workHubApp(
          repository: FakeWorkHubRepository(),
          tasks: tasks,
          home: const _MyTasksOnly(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Viết tài liệu API'), findsOneWidget);
      expect(find.text('Kiểm tra cụm lưu trữ'), findsNothing);

      await tester.tap(find.byKey(const Key('my_tasks_filter_in_progress')));
      await tester.pumpAndSettle();
      expect(find.text('Kiểm tra cụm lưu trữ'), findsOneWidget);
      expect(find.text('Viết tài liệu API'), findsNothing);

      await tester.ensureVisible(find.byKey(const Key('my_tasks_filter_done')));
      await tester.tap(find.byKey(const Key('my_tasks_filter_done')));
      await tester.pumpAndSettle();
      expect(find.text('Gửi báo cáo tuần'), findsOneWidget);
      expect(tasks.listStatuses.last, 'all');

      await tester.tap(find.byKey(const Key('my_tasks_search_toggle')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('my_tasks_search')), 'cụm');
      await tester.pumpAndSettle();
      expect(find.text('Kiểm tra cụm lưu trữ'), findsOneWidget);
      expect(find.text('Gửi báo cáo tuần'), findsNothing);
    });
  });
}

class _ManageOnly extends StatelessWidget {
  const _ManageOnly();

  @override
  Widget build(BuildContext context) =>
      const ShortcutsManageScreen(workspaceId: 'ws');
}

class _MyTasksOnly extends StatelessWidget {
  const _MyTasksOnly();

  @override
  Widget build(BuildContext context) => const MyTasksScreen(workspaceId: 'ws');
}
