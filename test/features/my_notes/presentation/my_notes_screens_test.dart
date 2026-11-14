import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/app/providers/foundation_providers.dart';
import 'package:webtui_chat/core/result/result.dart';
import 'package:webtui_chat/features/my_notes/application/use_cases/my_notes_use_cases.dart';
import 'package:webtui_chat/features/my_notes/domain/entities/my_note.dart';
import 'package:webtui_chat/features/my_notes/presentation/controllers/my_notes_access_provider.dart';
import 'package:webtui_chat/features/my_notes/presentation/screens/my_note_editor_screen.dart';
import 'package:webtui_chat/features/my_notes/presentation/screens/my_notes_screen.dart';

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
      expect(find.byKey(const Key('my_notes_manage_folders')), findsOneWidget);

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

  testWidgets('màn soạn ghi chú mới hiện ô nhập và nút lưu', (tester) async {
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

    expect(find.byKey(const Key('my_note_title_field')), findsOneWidget);
    expect(find.byKey(const Key('my_note_body_field')), findsOneWidget);
    expect(find.byKey(const Key('my_note_save')), findsOneWidget);
    expect(find.text('Công việc'), findsOneWidget);
  });

  testWidgets('màn xem ghi chú: hiện nội dung, mở được chế độ sửa', (
    tester,
  ) async {
    final repository = FakeMyNotesRepository()
      ..getResult = Success(
        MyNotesCached(testNote(title: 'Họp tuần', body: 'Chốt kế hoạch')),
      );

    await tester.pumpWidget(
      app(
        const MyNoteEditorScreen(noteId: 'note-1', workspaceId: 'workspace-1'),
        repository: repository,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Họp tuần'), findsOneWidget);
    expect(find.text('Chốt kế hoạch'), findsOneWidget);

    await tester.tap(find.byKey(const Key('my_note_edit')));
    await tester.pumpAndSettle();

    final titleField = tester.widget<TextField>(
      find.byKey(const Key('my_note_title_field')),
    );
    expect(titleField.controller?.text, 'Họp tuần');
  });

  testWidgets('chế độ xem hiển thị markdown: tiêu đề, danh sách, ô tick', (
    tester,
  ) async {
    final repository = FakeMyNotesRepository()
      ..getResult = Success(
        MyNotesCached(
          testNote(
            title: 'Họp tuần',
            body:
                '## Việc chính\n- một\n- hai\n1. đầu\n- [ ] chưa\n- [x] xong\n\n**đậm**',
          ),
        ),
      );

    await tester.pumpWidget(
      app(
        const MyNoteEditorScreen(noteId: 'note-1', workspaceId: 'workspace-1'),
        repository: repository,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('my_note_markdown_view')), findsOneWidget);
    expect(find.textContaining('## '), findsNothing);
    expect(find.textContaining('Việc chính'), findsOneWidget);
    expect(find.textContaining('một'), findsOneWidget);
    expect(find.byKey(const Key('md_checkbox_open')), findsOneWidget);
    expect(find.byKey(const Key('md_checkbox_checked')), findsOneWidget);
    expect(find.textContaining('**'), findsNothing);
  });

  testWidgets('soạn: thanh định dạng chèn cú pháp markdown vào nội dung', (
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

    String body() => tester
        .widget<TextField>(find.byKey(const Key('my_note_body_field')))
        .controller!
        .text;

    await tester.tap(find.byKey(const Key('my_note_format_bullet')));
    await tester.pump();
    expect(body(), '- ');

    await tester.tap(find.byKey(const Key('my_note_format_bullet')));
    await tester.pump();
    expect(body(), '');

    await tester.tap(find.byKey(const Key('my_note_format_checklist')));
    await tester.pump();
    expect(body(), '- [ ] ');

    await tester.tap(find.byKey(const Key('my_note_format_bold')));
    await tester.pump();
    expect(body(), contains('****'));

    await tester.tap(find.byKey(const Key('my_note_format_heading')));
    await tester.pump();
    expect(body(), startsWith('## '));
    expect(find.byKey(const Key('my_note_meta_row')), findsOneWidget);
  });
}
