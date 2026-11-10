import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/core/error/failure.dart';
import 'package:webtui_chat/core/result/result.dart';
import 'package:webtui_chat/features/my_notes/application/use_cases/my_notes_use_cases.dart';
import 'package:webtui_chat/features/my_notes/domain/entities/my_note.dart';

import '../fake_my_notes_repository.dart';

void main() {
  late FakeMyNotesRepository repository;
  late MyNotesUseCases useCases;

  setUp(() {
    repository = FakeMyNotesRepository();
    useCases = MyNotesUseCases(repository);
  });

  group('tạo ghi chú', () {
    test('chuẩn hoá tag và bỏ thư mục rỗng trước khi gọi máy chủ', () async {
      repository.createResult = Success(testNote());

      final result = await useCases.createNote.execute(
        workspaceId: ' workspace-1 ',
        title: '  Họp tuần ',
        body: 'Nội dung',
        tags: const ['#Việc', 'việc', '  Ý   tưởng '],
        folderId: '  ',
      );

      expect(result.isSuccess, isTrue);
      expect(repository.lastCreate, {
        'workspaceId': 'workspace-1',
        'title': 'Họp tuần',
        'body': 'Nội dung',
        'tags': ['việc', 'ý tưởng'],
        'pinned': false,
        'folderId': null,
      });
    });

    test('từ chối ghi chú rỗng, quá dài, quá nhiều tag', () async {
      Future<String?> codeOf({
        String title = '',
        String body = '',
        List<String> tags = const [],
        String workspaceId = 'workspace-1',
      }) async {
        final result = await useCases.createNote.execute(
          workspaceId: workspaceId,
          title: title,
          body: body,
          tags: tags,
        );
        return result.failureOrNull?.code;
      }

      expect(await codeOf(title: ' ', body: '  '), 'MY_NOTE_EMPTY');
      expect(
        await codeOf(title: 'a' * (MyNoteLimits.titleMaxLength + 1)),
        'MY_NOTE_TITLE_TOO_LONG',
      );
      expect(
        await codeOf(body: 'a' * (MyNoteLimits.bodyMaxLength + 1)),
        'MY_NOTE_BODY_TOO_LONG',
      );
      expect(
        await codeOf(
          title: 'A',
          tags: [for (var i = 0; i <= MyNoteLimits.tagsMax; i++) 'tag$i'],
        ),
        'MY_NOTE_TOO_MANY_TAGS',
      );
      expect(
        await codeOf(title: 'A', tags: ['a' * (MyNoteLimits.tagMaxLength + 1)]),
        'MY_NOTE_TAG_TOO_LONG',
      );
      expect(
        await codeOf(title: 'A', workspaceId: ' '),
        'MY_NOTE_WORKSPACE_REQUIRED',
      );
      expect(repository.calls, isEmpty);
    });
  });

  group('sửa ghi chú', () {
    test('cần version và ít nhất một thay đổi', () async {
      final noVersion = await useCases.updateNote.execute(
        workspaceId: 'workspace-1',
        noteId: 'note-1',
        version: 0,
        patch: const MyNotePatch(title: 'A'),
      );
      final noChanges = await useCases.updateNote.execute(
        workspaceId: 'workspace-1',
        noteId: 'note-1',
        version: 2,
        patch: const MyNotePatch(),
      );

      expect(noVersion.failureOrNull?.code, 'MY_NOTE_VERSION_REQUIRED');
      expect(noChanges.failureOrNull?.code, 'MY_NOTE_NO_CHANGES');
      expect(repository.calls, isEmpty);
    });

    test('gửi version và chuẩn hoá tag', () async {
      repository.updateResult = Success(testNote(version: 3));

      await useCases.updateNote.execute(
        workspaceId: 'workspace-1',
        noteId: 'note-1',
        version: 2,
        patch: const MyNotePatch(tags: ['#A', 'a'], moveToRoot: true),
      );

      expect(repository.lastUpdate?['version'], 2);
      expect(repository.lastUpdate?['tags'], ['a']);
      expect(repository.lastUpdate?['moveToRoot'], isTrue);
    });
  });

  test('không lưu tin chưa gửi xong vào My Note', () async {
    final result = await useCases.saveMessage.execute(
      workspaceId: 'workspace-1',
      channelId: 'channel-1',
      messageId: 'local-123',
    );

    expect(result.failureOrNull?.code, 'MY_NOTE_MESSAGE_REQUIRED');
    expect(result.failureOrNull?.kind, FailureKind.validation);
    expect(repository.calls, isEmpty);
  });

  test('lưu tin gửi đúng id kênh và tin', () async {
    repository.saveResult = Success(
      SavedMessageNote(note: testNote(), created: true),
    );

    final result = await useCases.saveMessage.execute(
      workspaceId: 'workspace-1',
      channelId: ' channel-1 ',
      messageId: ' message-1 ',
    );

    expect(result.valueOrNull?.created, isTrue);
    expect(repository.lastSave, {
      'channelId': 'channel-1',
      'messageId': 'message-1',
      'folderId': null,
    });
  });

  group('thư mục', () {
    test('kiểm tên và độ sâu tối đa', () async {
      final empty = await useCases.createFolder.execute(
        workspaceId: 'workspace-1',
        name: '  ',
      );
      final tooLong = await useCases.createFolder.execute(
        workspaceId: 'workspace-1',
        name: 'a' * (MyNoteLimits.folderNameMaxLength + 1),
      );
      final folders = [
        testFolder('f1'),
        testFolder('f2', parentId: 'f1'),
        testFolder('f3', parentId: 'f2'),
        testFolder('f4', parentId: 'f3'),
        testFolder('f5', parentId: 'f4'),
      ];
      final tooDeep = await useCases.createFolder.execute(
        workspaceId: 'workspace-1',
        name: 'Tầng 6',
        parentId: 'f5',
        existingFolders: folders,
      );

      expect(empty.failureOrNull?.code, 'NOTE_FOLDER_NAME_REQUIRED');
      expect(tooLong.failureOrNull?.code, 'NOTE_FOLDER_NAME_TOO_LONG');
      expect(tooDeep.failureOrNull?.code, 'NOTE_FOLDER_TOO_DEEP');
      expect(repository.calls, isEmpty);

      repository.folderResult = Success(testFolder('f6', parentId: 'f4'));
      final ok = await useCases.createFolder.execute(
        workspaceId: 'workspace-1',
        name: ' Tầng 5 ',
        parentId: 'f4',
        existingFolders: folders,
      );
      expect(ok.isSuccess, isTrue);
      expect(repository.lastFolder, {'name': 'Tầng 5', 'parentId': 'f4'});
    });

    test('đổi tên cần id thư mục', () async {
      final result = await useCases.renameFolder.execute(
        workspaceId: 'workspace-1',
        folderId: ' ',
        name: 'Mới',
      );

      expect(result.failureOrNull?.code, 'NOTE_FOLDER_REQUIRED');
    });
  });

  test('từ khoá tìm quá dài bị chặn', () async {
    final result = await useCases.listNotes.execute(
      workspaceId: 'workspace-1',
      filter: MyNoteFilter(query: 'a' * (MyNoteLimits.queryMaxLength + 1)),
    );

    expect(result.failureOrNull?.code, 'MY_NOTE_QUERY_TOO_LONG');
  });

  group('hàm domain', () {
    test(
      'dựng cây thư mục theo vị trí, đưa thư mục mồ côi / vòng lặp về gốc',
      () {
        final tree = buildMyNoteFolderTree([
          testFolder('b', name: 'B').copyWithPosition(2),
          testFolder('a', name: 'A').copyWithPosition(1),
          testFolder('a1', parentId: 'a'),
          testFolder('orphan', parentId: 'missing'),
          testFolder('loop1', parentId: 'loop2'),
          testFolder('loop2', parentId: 'loop1'),
        ]);
        final flat = flattenMyNoteFolderTree(tree);

        expect(tree.map((node) => node.folder.id).take(3), [
          'orphan',
          'a',
          'b',
        ]);
        expect(tree[1].children.single.folder.id, 'a1');
        expect(tree[1].children.single.depth, 2);
        expect(flat.map((node) => node.folder.id).toSet(), {
          'a',
          'a1',
          'b',
          'orphan',
          'loop1',
          'loop2',
        });
        expect(flat.length, 6);
      },
    );

    test('tách và chuẩn hoá tag người dùng gõ', () {
      expect(parseMyNoteTagInput('Việc, #nhà riêng;  ; việc'), [
        'việc',
        'nhà riêng',
      ]);
    });

    test('tiêu đề hiển thị lấy dòng đầu khi chưa đặt tiêu đề', () {
      expect(myNoteDisplayTitle('', '\n# Kế hoạch\nchi tiết'), 'Kế hoạch');
      expect(myNoteDisplayTitle(' ', ' '), 'Ghi chú không tiêu đề');
    });
  });
}

extension on MyNoteFolder {
  MyNoteFolder copyWithPosition(int value) {
    return MyNoteFolder(
      id: id,
      workspaceId: workspaceId,
      parentId: parentId,
      name: name,
      position: value,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}
