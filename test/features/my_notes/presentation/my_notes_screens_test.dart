import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/app/providers/foundation_providers.dart';
import 'package:webtui_chat/core/error/failure.dart';
import 'package:webtui_chat/core/result/result.dart';
import 'package:webtui_chat/features/my_notes/application/use_cases/my_notes_use_cases.dart';
import 'package:webtui_chat/features/my_notes/domain/entities/my_note.dart';
import 'package:webtui_chat/features/my_notes/presentation/controllers/my_note_editor_controller.dart';
import 'package:webtui_chat/features/my_notes/presentation/controllers/my_notes_access_provider.dart';
import 'package:webtui_chat/features/my_notes/presentation/screens/my_note_editor_screen.dart';
import 'package:webtui_chat/features/my_notes/presentation/screens/my_notes_screen.dart';
import 'package:webtui_chat/features/my_notes/presentation/widgets/my_note_rich_text_controller.dart';

import '../fake_my_notes_repository.dart';

void main() {
  Widget app(
    Widget child, {
    required FakeMyNotesRepository repository,
    bool enabled = true,
  }) {
    return ProviderScope(
      overrides: [
        myNotesEnabledProvider.overrideWithValue(enabled),
        myNotesUseCasesProvider.overrideWithValue(MyNotesUseCases(repository)),
      ],
      child: MaterialApp(home: child),
    );
  }

  testWidgets('cờ tắt: hiện thông báo, không gọi máy chủ', (tester) async {
    final repository = FakeMyNotesRepository();

    await tester.pumpWidget(
      app(
        const MyNotesScreen(workspaceId: 'workspace-1'),
        repository: repository,
        enabled: false,
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('my_notes_disabled')), findsOneWidget);
    expect(find.byKey(const Key('my_notes_new')), findsNothing);
    expect(repository.calls, isEmpty);
  });

  testWidgets('thẻ ghi chú: xem trước chữ thuần, ghim, thời gian tương đối', (
    tester,
  ) async {
    final repository = FakeMyNotesRepository()
      ..listResults.add(
        Success(
          MyNotesCached(
            MyNotePage(
              notes: [
                testNote(
                  title: 'Họp tuần',
                  body: '# Mục tiêu\n**Chốt** kế hoạch',
                  pinned: true,
                ).toSummary(),
              ],
            ),
          ),
        ),
      );

    await tester.pumpWidget(
      app(
        const MyNotesScreen(workspaceId: 'workspace-1'),
        repository: repository,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Họp tuần'), findsOneWidget);
    expect(find.textContaining('**'), findsNothing);
    expect(find.byIcon(Icons.push_pin_rounded), findsOneWidget);
  });

  testWidgets(
    'tìm kiếm gửi từ khoá; nút Lọc mở bảng lọc ghim / thư mục / tag',
    (tester) async {
      final repository = FakeMyNotesRepository()
        ..folders = [testFolder('folder-1', name: 'Công việc')]
        ..tags = const [MyNoteTag(tag: 'việc', count: 2)];

      await tester.pumpWidget(
        app(
          const MyNotesScreen(workspaceId: 'workspace-1'),
          repository: repository,
        ),
      );
      await tester.pumpAndSettle();

      // Chỉ còn một ô tìm kiếm, không còn dải chip lọc trên danh sách.
      expect(find.byType(TextField), findsOneWidget);
      expect(find.byKey(const Key('my_notes_pinned_filter')), findsNothing);

      await tester.enterText(find.byType(TextField), 'kế hoạch');
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(repository.listFilters.last.query, 'kế hoạch');

      await tester.tap(find.byKey(const Key('my_notes_filter_button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('my_notes_filter_sheet')), findsOneWidget);
      expect(find.text('Công việc'), findsOneWidget);
      expect(find.text('#việc (2)'), findsOneWidget);
      expect(find.byKey(const Key('my_notes_folder_create')), findsOneWidget);

      await tester.tap(find.byKey(const Key('my_notes_pinned_filter')));
      await tester.pumpAndSettle();
      expect(repository.listFilters.last.pinnedOnly, isTrue);

      await tester.tap(find.text('#việc (2)'));
      await tester.pumpAndSettle();
      expect(repository.listFilters.last.tag, 'việc');

      await tester.tap(find.text('Công việc'));
      await tester.pumpAndSettle();
      expect(repository.listFilters.last.folderId, 'folder-1');
    },
  );

  testWidgets(
    'bảng Lọc duy nhất: tạo, đổi tên, xoá thư mục bằng hộp khung chung',
    (tester) async {
      final repository = FakeMyNotesRepository()
        ..folders = [testFolder('folder-1', name: 'Công việc')];
      await tester.pumpWidget(
        app(
          const MyNotesScreen(workspaceId: 'workspace-1'),
          repository: repository,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('my_notes_filter_button')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('my_notes_folder_create')));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.byKey(const Key('webtui_dialog_input')), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('webtui_dialog_input')),
        'Dự án mới',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('webtui_dialog_confirm')));
      await tester.pumpAndSettle();
      expect(repository.calls, contains('createFolder'));
      expect(repository.lastFolder, {'name': 'Dự án mới', 'parentId': null});
      expect(
        find.byType(BottomSheet),
        findsOneWidget,
        reason: 'không chồng bảng',
      );

      await tester.tap(find.byKey(const Key('my_notes_folder_more_folder-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Đổi tên'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('webtui_dialog_input')),
        'Việc chung',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('webtui_dialog_confirm')));
      await tester.pumpAndSettle();
      expect(repository.calls, contains('updateFolder:folder-1'));
      expect(repository.lastFolder?['name'], 'Việc chung');

      await tester.ensureVisible(find.text('Xoá'));
      await tester.tap(find.text('Xoá'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      await tester.tap(find.byKey(const Key('webtui_dialog_confirm')));
      await tester.pumpAndSettle();
      expect(repository.calls, contains('deleteFolder:folder-1'));
    },
  );

  testWidgets('danh sách rỗng hiện hướng dẫn', (tester) async {
    final repository = FakeMyNotesRepository();

    await tester.pumpWidget(
      app(
        const MyNotesScreen(workspaceId: 'workspace-1'),
        repository: repository,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('my_notes_empty')), findsOneWidget);
    expect(find.text('Chưa có ghi chú'), findsOneWidget);
  });

  testWidgets('bản ngoại tuyến: hiện dải báo và ghi chú đã lưu', (
    tester,
  ) async {
    final repository = FakeMyNotesRepository()
      ..listResults.add(
        Success(
          MyNotesCached(
            MyNotePage(
              notes: [
                testNote(
                  title: 'Kế hoạch',
                  pinned: true,
                  tags: const ['việc'],
                ).toSummary(),
              ],
            ),
            fromCache: true,
            cachedAt: DateTime.utc(2026, 11, 1, 8),
          ),
        ),
      )
      ..tags = const [MyNoteTag(tag: 'việc', count: 1)];

    await tester.pumpWidget(
      app(
        const MyNotesScreen(workspaceId: 'workspace-1'),
        repository: repository,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('my_notes_offline_banner')), findsOneWidget);
    expect(find.text('Kế hoạch'), findsOneWidget);
    expect(find.text('#việc'), findsOneWidget);
  });

  MyNoteRichTextController editor(WidgetTester tester) =>
      tester
              .widget<TextField>(find.byKey(const Key('my_note_editor_field')))
              .controller!
          as MyNoteRichTextController;

  testWidgets('ghi chú mới: một ô soạn kiểu iPhone, không còn nút Lưu', (
    tester,
  ) async {
    final repository = FakeMyNotesRepository()
      ..folders = [testFolder('folder-1', name: 'Công việc')];

    await tester.pumpWidget(
      app(
        const MyNoteEditorScreen(
          noteId: 'new',
          workspaceId: 'workspace-1',
          initialFolderId: 'folder-1',
        ),
        repository: repository,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('my_note_editor_field')), findsOneWidget);
    expect(find.byKey(const Key('my_note_title_field')), findsNothing);
    expect(find.byKey(const Key('my_note_save')), findsNothing);
    expect(find.byKey(const Key('my_note_edit')), findsNothing);
    expect(find.byKey(const Key('my_note_date')), findsOneWidget);
    // Ghi chú mới mở bàn phím ngay; thanh công cụ nằm trên bàn phím.
    expect(find.byKey(const Key('my_note_done')), findsOneWidget);
    expect(find.byKey(const Key('my_note_format_button')), findsOneWidget);
    expect(find.byKey(const Key('my_note_checklist_button')), findsOneWidget);
    expect(find.byKey(const Key('my_note_attach_button')), findsOneWidget);

    await tester.tap(find.byKey(const Key('my_note_more')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('my_note_menu')), findsOneWidget);
    // Thư mục mở từ danh sách đã được chọn sẵn.
    expect(find.text('Công việc'), findsOneWidget);
    // Ghi chú chưa lưu thì chưa có mục Xoá.
    expect(find.byKey(const Key('my_note_menu_delete')), findsNothing);
  });

  testWidgets('gõ chữ thì tự lưu sau một nhịp: dòng đầu là tiêu đề', (
    tester,
  ) async {
    final repository = FakeMyNotesRepository()
      ..createResult = Success(testNote(id: 'created', title: 'Mua sữa'));

    await tester.pumpWidget(
      app(
        const MyNoteEditorScreen(noteId: 'new', workspaceId: 'workspace-1'),
        repository: repository,
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('my_note_editor_field')),
      'Mua sữa\nhai hộp #nhà',
    );
    await tester.pump(const Duration(milliseconds: 200));
    expect(repository.calls, isNot(contains('createNote')));

    await tester.pump(myNoteAutosaveDelay);
    await tester.pump();

    expect(repository.calls.where((c) => c == 'createNote'), hasLength(1));
    expect(repository.lastCreate?['title'], 'Mua sữa');
    expect(repository.lastCreate?['body'], 'hai hộp #nhà');
    expect(repository.lastCreate?['tags'], ['nhà']);
  });

  testWidgets('mở ghi chú: tiêu đề + nội dung nằm chung một ô, sửa được ngay', (
    tester,
  ) async {
    final repository = FakeMyNotesRepository()
      ..getResult = Success(
        MyNotesCached(
          testNote(
            title: 'Họp tuần',
            body: 'Chốt kế hoạch',
            tags: const ['account ide'],
          ),
        ),
      )
      ..updateResult = Success(testNote(version: 2));

    await tester.pumpWidget(
      app(
        const MyNoteEditorScreen(noteId: 'note-1', workspaceId: 'workspace-1'),
        repository: repository,
      ),
    );
    await tester.pumpAndSettle();

    expect(editor(tester).text, 'Họp tuần\nChốt kế hoạch');
    final field = tester.widget<TextField>(
      find.byKey(const Key('my_note_editor_field')),
    );
    expect(field.readOnly, isFalse);

    await tester.enterText(
      find.byKey(const Key('my_note_editor_field')),
      'Họp tuần\nChốt kế hoạch quý 4',
    );
    await tester.pump(myNoteAutosaveDelay);
    await tester.pump();

    expect(repository.lastUpdate?['body'], 'Chốt kế hoạch quý 4');
    expect(repository.lastUpdate?['title'], isNull);
    // Tag đặt từ trước (không có trong chữ) vẫn giữ: không gửi đổi tag.
    expect(repository.lastUpdate?['tags'], isNull);
  });

  testWidgets(
    'markdown hiện trực tiếp: bấm ô tick đổi trạng thái và lưu ngay',
    (tester) async {
      final repository = FakeMyNotesRepository()
        ..getResult = Success(
          MyNotesCached(
            testNote(
              title: 'Họp tuần',
              body: '## Việc chính\n- [ ] chưa\n- [x] xong\n**đậm**',
            ),
          ),
        )
        ..updateResult = Success(testNote(version: 2));

      await tester.pumpWidget(
        app(
          const MyNoteEditorScreen(
            noteId: 'note-1',
            workspaceId: 'workspace-1',
          ),
          repository: repository,
        ),
      );
      await tester.pumpAndSettle();

      final boxes = find.byKey(const ValueKey('my-note-checkbox'));
      expect(boxes, findsNWidgets(2));

      await tester.tap(boxes.first);
      // Lưu ngay (hẹn giờ 0), không chờ nhịp gõ.
      await tester.pump(Duration.zero);
      await tester.pump();

      expect(editor(tester).text, contains('- [x] chưa'));
      expect(repository.lastUpdate?['body'], contains('- [x] chưa'));
    },
  );

  testWidgets('bảng Aa: kiểu dòng, đậm, danh sách chèn đúng markdown', (
    tester,
  ) async {
    final repository = FakeMyNotesRepository();

    await tester.pumpWidget(
      app(
        const MyNoteEditorScreen(noteId: 'new', workspaceId: 'workspace-1'),
        repository: repository,
      ),
    );
    await tester.pumpAndSettle();

    String text() => editor(tester).text;

    await tester.tap(find.byKey(const Key('my_note_format_button')));
    await tester.pump();
    expect(find.byKey(const Key('my_note_format_panel')), findsOneWidget);

    await tester.tap(find.byKey(const Key('my_note_style_bullet')));
    await tester.pump();
    expect(text(), '- ');

    await tester.tap(find.byKey(const Key('my_note_style_bullet')));
    await tester.pump();
    expect(text(), '');

    await tester.tap(find.byKey(const Key('my_note_style_checklist')));
    await tester.pump();
    expect(text(), '- [ ] ');

    await tester.tap(find.byKey(const Key('my_note_inline_bold')));
    await tester.pump();
    expect(text(), contains('****'));

    await tester.tap(find.byKey(const Key('my_note_style_heading')));
    await tester.pump();
    expect(text(), startsWith('## '));

    await tester.tap(find.byKey(const Key('my_note_format_close')));
    await tester.pump();
    expect(find.byKey(const Key('my_note_format_panel')), findsNothing);
    expect(find.byKey(const Key('my_note_toolbar')), findsOneWidget);
  });

  testWidgets('quay lại khi còn chữ chưa lưu: lưu ngay rồi mới đóng', (
    tester,
  ) async {
    final repository = FakeMyNotesRepository()
      ..createResult = Success(testNote(id: 'created'));
    await tester.pumpWidget(
      app(
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const MyNoteEditorScreen(
                    noteId: 'new',
                    workspaceId: 'workspace-1',
                  ),
                ),
              ),
              child: const Text('Mở'),
            ),
          ),
        ),
        repository: repository,
      ),
    );
    await tester.tap(find.text('Mở'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('my_note_editor_field')),
      'Việc gấp',
    );
    await tester.pump();
    // Bấm quay lại trước khi hết nhịp chờ tự lưu.
    await tester.tap(find.byKey(const Key('my_note_back')));
    await tester.pumpAndSettle();

    expect(repository.calls.where((c) => c == 'createNote'), hasLength(1));
    expect(repository.lastCreate?['title'], 'Việc gấp');
    expect(find.byKey(const Key('my_note_editor_field')), findsNothing);
    expect(find.text('Mở'), findsOneWidget);
  });

  testWidgets(
    'xung đột: dừng tự lưu, Giữ bản của tôi ghi đè bằng bản mới nhất',
    (tester) async {
      final repository = FakeMyNotesRepository()
        ..getResults.addAll([
          Success(MyNotesCached(testNote(version: 1))),
          Success(MyNotesCached(testNote(version: 7, body: 'Bản máy khác'))),
        ])
        ..updateResult = const FailureResult(
          Failure(
            kind: FailureKind.conflict,
            message: 'Ghi chú đã được sửa ở nơi khác.',
            code: 'NOTE_VERSION_CONFLICT',
          ),
        );

      await tester.pumpWidget(
        app(
          const MyNoteEditorScreen(
            noteId: 'note-1',
            workspaceId: 'workspace-1',
          ),
          repository: repository,
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('my_note_editor_field')),
        'Ghi chú\nBản của tôi',
      );
      await tester.pump(myNoteAutosaveDelay);
      await tester.pump();

      expect(find.byKey(const Key('my_note_conflict')), findsOneWidget);
      expect(find.byKey(const Key('my_note_reload_latest')), findsOneWidget);
      // Đang xung đột thì ô soạn khoá lại để không mất thêm chữ.
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('my_note_editor_field')))
            .readOnly,
        isTrue,
      );

      repository.updateResult = Success(
        testNote(version: 8, body: 'Bản của tôi'),
      );
      await tester.tap(find.byKey(const Key('my_note_keep_mine')));
      await tester.pumpAndSettle();

      expect(repository.lastUpdate?['version'], 7);
      expect(repository.lastUpdate?['body'], 'Bản của tôi');
      expect(find.byKey(const Key('my_note_conflict')), findsNothing);
    },
  );

  testWidgets('menu ⋯: ghim ghi chú thì lưu ngay', (tester) async {
    final repository = FakeMyNotesRepository()
      ..getResult = Success(MyNotesCached(testNote(version: 3)))
      ..updateResult = Success(testNote(version: 4, pinned: true));

    await tester.pumpWidget(
      app(
        const MyNoteEditorScreen(noteId: 'note-1', workspaceId: 'workspace-1'),
        repository: repository,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('my_note_more')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('my_note_menu_pin')));
    await tester.pumpAndSettle();

    expect(repository.lastUpdate?['pinned'], isTrue);
    expect(repository.lastUpdate?['version'], 3);
  });

  testWidgets('bản ngoại tuyến: chỉ xem, không có thanh công cụ', (
    tester,
  ) async {
    final repository = FakeMyNotesRepository()
      ..getResult = Success(
        MyNotesCached(
          testNote(title: 'Kế hoạch', body: '- [ ] việc'),
          fromCache: true,
        ),
      );

    await tester.pumpWidget(
      app(
        const MyNoteEditorScreen(noteId: 'note-1', workspaceId: 'workspace-1'),
        repository: repository,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('my_notes_offline_banner')), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('my_note_editor_field')))
          .readOnly,
      isTrue,
    );
    expect(find.byKey(const Key('my_note_toolbar')), findsNothing);
    // Bấm ô tick khi chỉ xem thì không đổi gì.
    await tester.tap(find.byKey(const ValueKey('my-note-checkbox')));
    await tester.pump();
    expect(editor(tester).text, contains('- [ ] việc'));
  });
}
