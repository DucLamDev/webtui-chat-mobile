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
import 'package:webtui_chat/features/my_notes/presentation/widgets/my_notes_entry_card.dart';

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

  testWidgets('thẻ lối vào ẩn khi cờ tắt', (tester) async {
    await tester.pumpWidget(
      app(
        const Scaffold(body: MyNotesEntryCard(workspaceId: 'workspace-1')),
        repository: FakeMyNotesRepository(),
        enabled: false,
      ),
    );
    expect(find.byKey(const Key('my_notes_entry_card')), findsNothing);

    await tester.pumpWidget(
      app(
        const Scaffold(body: MyNotesEntryCard(workspaceId: 'workspace-1')),
        repository: FakeMyNotesRepository(),
      ),
    );
    expect(find.byKey(const Key('my_notes_entry_card')), findsOneWidget);
  });

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
}
