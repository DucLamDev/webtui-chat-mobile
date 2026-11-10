import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/core/error/failure.dart';
import 'package:webtui_chat/core/result/result.dart';
import 'package:webtui_chat/features/conversations/domain/entities/chat_message.dart';
import 'package:webtui_chat/features/my_notes/domain/entities/my_note.dart';
import 'package:webtui_chat/features/my_notes/presentation/controllers/my_note_editor_controller.dart';
import 'package:webtui_chat/features/my_notes/presentation/controllers/my_notes_list_controller.dart';
import 'package:webtui_chat/features/my_notes/presentation/widgets/save_message_to_my_note.dart';

import '../fake_my_notes_repository.dart';

void main() {
  group('MyNotesListController', () {
    test('tải danh sách: ghim lên đầu, đánh dấu bản ngoại tuyến', () async {
      final repository = FakeMyNotesRepository()
        ..listResults.add(
          Success(
            MyNotesCached(
              MyNotePage(
                notes: [
                  testNote(
                    id: 'new',
                    updatedAt: DateTime.utc(2026, 11, 9),
                  ).toSummary(),
                  testNote(
                    id: 'pinned',
                    pinned: true,
                    updatedAt: DateTime.utc(2026, 1, 1),
                  ).toSummary(),
                ],
              ),
              fromCache: true,
            ),
          ),
        );
      final controller = MyNotesListController.forTesting(
        repository: repository,
      );

      await controller.load();

      expect(controller.state.items.map((note) => note.id), ['pinned', 'new']);
      expect(controller.state.isOffline, isTrue);
      expect(controller.state.hasMore, isFalse);
      controller.dispose();
    });

    test('máy chủ tắt cờ thì hiện trạng thái tắt', () async {
      final repository = FakeMyNotesRepository()
        ..listResults.add(
          const FailureResult(
            Failure(
              kind: FailureKind.forbidden,
              message: 'Tính năng này chưa được bật trên máy chủ.',
              code: 'FEATURE_DISABLED',
            ),
          ),
        );
      final controller = MyNotesListController.forTesting(
        repository: repository,
      );

      await controller.load();

      expect(controller.state.featureDisabled, isTrue);
      expect(controller.state.errorMessage, contains('chưa được bật'));
      controller.dispose();
    });

    test('tải thêm theo next_cursor và lọc theo tag', () async {
      final repository = FakeMyNotesRepository()
        ..listResults.addAll([
          Success(
            MyNotesCached(
              MyNotePage(
                notes: [testNote(id: 'a').toSummary()],
                nextCursor: 'cursor-2',
                hasMore: true,
              ),
            ),
          ),
          Success(
            MyNotesCached(MyNotePage(notes: [testNote(id: 'b').toSummary()])),
          ),
        ]);
      final controller = MyNotesListController.forTesting(
        repository: repository,
      );

      await controller.load();
      await controller.loadMore();

      expect(controller.state.items.map((note) => note.id), ['a', 'b']);
      expect(controller.state.hasMore, isFalse);
      expect(repository.listCursors, [null, 'cursor-2']);

      await controller.setTag('việc');
      expect(repository.listFilters.last.tag, 'việc');
      await controller.setFolder(myNoteRootFolderFilter);
      expect(repository.listFilters.last.folderId, myNoteRootFolderFilter);
      expect(repository.listFilters.last.tag, 'việc');
      controller.dispose();
    });

    test('ghim gửi version; xung đột thì tải lại và báo lỗi', () async {
      final repository = FakeMyNotesRepository()
        ..updateResult = const FailureResult(
          Failure(
            kind: FailureKind.conflict,
            message: 'Ghi chú đã được sửa ở nơi khác.',
            code: 'NOTE_VERSION_CONFLICT',
          ),
        );
      final controller = MyNotesListController.forTesting(
        repository: repository,
      );
      final note = testNote(version: 4).toSummary();

      final error = await controller.togglePin(note);

      expect(repository.lastUpdate?['version'], 4);
      expect(repository.lastUpdate?['pinned'], isTrue);
      expect(error, contains('sửa ở nơi khác'));
      await Future<void>.delayed(Duration.zero);
      expect(repository.calls, contains('listNotes'));
      controller.dispose();
    });

    test('xoá thư mục đang lọc thì bỏ lọc thư mục', () async {
      final repository = FakeMyNotesRepository();
      final controller = MyNotesListController.forTesting(
        repository: repository,
      );
      await controller.setFolder('folder-1');

      final error = await controller.deleteFolder('folder-1');

      expect(error, isNull);
      expect(controller.state.filter.folderId, isNull);
      expect(repository.calls, contains('deleteFolder:folder-1'));
      controller.dispose();
    });

    test('còn thư mục con thì báo rõ', () async {
      final repository = FakeMyNotesRepository()
        ..deleteFolderResult = const FailureResult(
          Failure(
            kind: FailureKind.conflict,
            message: 'Thư mục còn thư mục con.',
            code: 'NOTE_FOLDER_HAS_CHILDREN',
          ),
        );
      final controller = MyNotesListController.forTesting(
        repository: repository,
      );

      final error = await controller.deleteFolder('folder-1');

      expect(error, contains('thư mục con'));
      controller.dispose();
    });

    test('ghi chú vừa sửa ở màn khác được cập nhật vào danh sách', () async {
      final repository = FakeMyNotesRepository()
        ..listResults.add(
          Success(
            MyNotesCached(
              MyNotePage(
                notes: [
                  testNote(id: 'a', title: 'Cũ').toSummary(),
                  testNote(id: 'b').toSummary(),
                ],
              ),
            ),
          ),
        );
      final controller = MyNotesListController.forTesting(
        repository: repository,
      );
      await controller.load();

      controller.upsertNote(
        testNote(id: 'b', title: 'Mới', pinned: true, version: 2),
      );
      controller.removeNote('a');

      expect(controller.state.items.single.title, 'Mới');
      expect(controller.state.items.single.version, 2);
      controller.dispose();
    });
  });

  group('MyNoteEditorController', () {
    test('ghi chú mới gọi tạo với tag đã tách', () async {
      final repository = FakeMyNotesRepository()
        ..createResult = Success(testNote(id: 'created'));
      final controller = MyNoteEditorController.forTesting(
        repository: repository,
      );

      final saved = await controller.save(
        const MyNoteDraft(
          title: 'Mới',
          body: 'Nội dung',
          tagsInput: 'việc, #Nhà',
          folderId: 'folder-1',
        ),
      );

      expect(saved?.id, 'created');
      expect(controller.state.isNew, isFalse);
      expect(repository.lastCreate?['tags'], ['việc', 'nhà']);
      expect(repository.lastCreate?['folderId'], 'folder-1');
      controller.dispose();
    });

    test('sửa chỉ gửi trường đã đổi kèm version', () async {
      final repository = FakeMyNotesRepository()
        ..getResult = Success(
          MyNotesCached(
            testNote(version: 3, folderId: 'folder-1', tags: const ['việc']),
          ),
        )
        ..updateResult = Success(testNote(version: 4));
      final controller = MyNoteEditorController.forTesting(
        repository: repository,
        noteId: 'note-1',
      );
      await controller.load();

      await controller.save(
        const MyNoteDraft(
          title: 'Ghi chú',
          body: 'Nội dung đã sửa',
          tagsInput: 'việc',
        ),
      );

      expect(repository.lastUpdate, {
        'version': 3,
        'title': null,
        'body': 'Nội dung đã sửa',
        'tags': null,
        'pinned': null,
        'folderId': null,
        'moveToRoot': true,
      });
      expect(controller.state.note?.version, 4);
      controller.dispose();
    });

    test(
      'xung đột version: báo rõ, tải bản mới nhất thì hết xung đột',
      () async {
        final repository = FakeMyNotesRepository()
          ..getResults.addAll([
            Success(MyNotesCached(testNote(version: 1))),
            Success(MyNotesCached(testNote(version: 2, body: 'Bản máy khác'))),
          ])
          ..updateResult = const FailureResult(
            Failure(
              kind: FailureKind.conflict,
              message: 'Ghi chú đã được sửa ở nơi khác.',
              code: 'NOTE_VERSION_CONFLICT',
            ),
          );
        final controller = MyNoteEditorController.forTesting(
          repository: repository,
          noteId: 'note-1',
        );
        await controller.load();

        final saved = await controller.save(
          const MyNoteDraft(title: 'Ghi chú', body: 'Bản của tôi'),
        );

        expect(saved, isNull);
        expect(controller.state.conflict, isTrue);
        expect(controller.state.saveErrorMessage, myNoteConflictMessage);

        await controller.reloadLatest();

        expect(controller.state.conflict, isFalse);
        expect(controller.state.note?.version, 2);
        expect(controller.state.note?.body, 'Bản máy khác');
        controller.dispose();
      },
    );

    test('ghi chú không còn thì báo không tìm thấy', () async {
      final repository = FakeMyNotesRepository()
        ..getResult = const FailureResult(
          Failure(
            kind: FailureKind.notFound,
            message: 'Không tìm thấy ghi chú.',
            code: 'NOTE_NOT_FOUND',
          ),
        );
      final controller = MyNoteEditorController.forTesting(
        repository: repository,
        noteId: 'note-1',
      );

      await controller.load();

      expect(controller.state.notFound, isTrue);
      expect(controller.state.errorMessage, isNotNull);
      controller.dispose();
    });
  });

  group('Lưu vào My Note từ tin nhắn', () {
    ChatMessage message({
      String id = 'message-1',
      Map<String, Object?> metadata = const {},
      DateTime? deletedAt,
      String kind = 'text',
    }) {
      return ChatMessage(
        id: id,
        workspaceId: 'workspace-1',
        channelId: 'channel-1',
        kind: kind,
        body: 'Xin chào',
        createdAt: DateTime.utc(2026, 11, 1),
        deletedAt: deletedAt,
        metadata: metadata,
      );
    }

    test('chỉ hiện khi cờ bật và tin hợp lệ', () {
      expect(
        canSaveMessageToMyNote(myNotesEnabled: true, message: message()),
        isTrue,
      );
      expect(
        canSaveMessageToMyNote(myNotesEnabled: false, message: message()),
        isFalse,
      );
      expect(
        canSaveMessageToMyNote(
          myNotesEnabled: true,
          message: message(metadata: const {'secret': true}),
        ),
        isFalse,
      );
      expect(
        canSaveMessageToMyNote(
          myNotesEnabled: true,
          message: message(metadata: const {'is_secret': 'true'}),
        ),
        isFalse,
      );
      expect(
        canSaveMessageToMyNote(
          myNotesEnabled: true,
          message: message(deletedAt: DateTime.utc(2026, 11, 2)),
        ),
        isFalse,
      );
      expect(
        canSaveMessageToMyNote(
          myNotesEnabled: true,
          message: message(kind: 'system'),
        ),
        isFalse,
      );
      expect(
        canSaveMessageToMyNote(
          myNotesEnabled: true,
          message: message(
            id: 'local-1',
            metadata: const {'client_message_id': 'c-1'},
          ),
        ),
        isFalse,
      );
    });
  });
}
