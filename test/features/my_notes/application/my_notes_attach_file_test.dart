import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/core/error/failure.dart';
import 'package:webtui_chat/core/result/result.dart';
import 'package:webtui_chat/features/my_notes/application/use_cases/my_notes_use_cases.dart';
import 'package:webtui_chat/features/my_notes/domain/entities/my_note.dart';

import '../fake_my_notes_repository.dart';

void main() {
  late FakeMyNotesRepository repository;
  late MyNotesUseCases useCases;
  const photo = MyNoteLocalFile(
    path: '/tmp/anh.jpg',
    name: 'anh.jpg',
    mimeType: 'image/jpeg',
    byteSize: 2048,
  );
  final attachment = MyNoteAttachment(
    fileId: 'file-1',
    originalName: 'anh.jpg',
    mimeType: 'image/jpeg',
    byteSize: 2048,
    createdAt: DateTime.utc(2026, 11, 16),
  );

  setUp(() {
    repository = FakeMyNotesRepository();
    useCases = MyNotesUseCases(repository);
  });

  test('tải lên rồi gắn vào ghi chú, tiến độ chạy tới 1', () async {
    repository
      ..uploadResult = const Success('file-1')
      ..addAttachmentResult = Success(attachment);
    final progress = <double>[];

    final result = await useCases.attachLocalFile.execute(
      workspaceId: ' workspace-1 ',
      noteId: ' note-1 ',
      file: photo,
      onProgress: progress.add,
    );

    expect(result.valueOrNull?.fileId, 'file-1');
    expect(repository.calls, ['uploadFile:anh.jpg', 'addAttachment']);
    expect(repository.lastAddAttachment, {
      'workspaceId': 'workspace-1',
      'noteId': 'note-1',
      'fileId': 'file-1',
    });
    expect(progress, [closeTo(0.475, 1e-9), closeTo(0.95, 1e-9), 1]);
  });

  test('chặn tệp rỗng và tệp quá 100 MB trước khi gọi máy chủ', () async {
    final empty = await useCases.attachLocalFile.execute(
      workspaceId: 'workspace-1',
      noteId: 'note-1',
      file: const MyNoteLocalFile(
        path: '/tmp/a.txt',
        name: 'a.txt',
        mimeType: 'text/plain',
        byteSize: 0,
      ),
    );
    final huge = await useCases.attachLocalFile.execute(
      workspaceId: 'workspace-1',
      noteId: 'note-1',
      file: const MyNoteLocalFile(
        path: '/tmp/b.mp4',
        name: 'b.mp4',
        mimeType: 'video/mp4',
        byteSize: MyNoteLimits.attachmentMaxBytes + 1,
      ),
    );
    final noNote = await useCases.attachLocalFile.execute(
      workspaceId: 'workspace-1',
      noteId: ' ',
      file: photo,
    );

    expect(empty.failureOrNull?.code, 'MY_NOTE_FILE_EMPTY');
    expect(huge.failureOrNull?.code, 'MY_NOTE_FILE_TOO_LARGE');
    expect(huge.failureOrNull?.message, contains('100 MB'));
    expect(noNote.failureOrNull?.code, 'MY_NOTE_REQUIRED');
    expect(repository.calls, isEmpty);
  });

  test('403 khi tải lên ra câu thiếu quyền, không gắn', () async {
    repository.uploadResult = const FailureResult(
      Failure(kind: FailureKind.forbidden, message: 'Forbidden'),
    );

    final result = await useCases.attachLocalFile.execute(
      workspaceId: 'workspace-1',
      noteId: 'note-1',
      file: photo,
    );

    expect(result.failureOrNull?.message, contains('không có quyền tải tệp'));
    expect(repository.calls, ['uploadFile:anh.jpg']);
  });

  test('lỗi máy chủ khi tải lên ra câu thử lại có tên tệp', () async {
    repository.uploadResult = const FailureResult(
      Failure(kind: FailureKind.server, message: 'internal'),
    );

    final result = await useCases.attachLocalFile.execute(
      workspaceId: 'workspace-1',
      noteId: 'note-1',
      file: photo,
    );

    expect(result.failureOrNull?.message, contains('"anh.jpg"'));
  });

  test('giữ câu lỗi dễ hiểu của kho (ngoại tuyến, tệp quá lớn)', () async {
    repository.uploadResult = const FailureResult(
      Failure(
        kind: FailureKind.validation,
        message: 'Tệp quá lớn nên máy chủ không nhận.',
        code: 'MY_NOTE_FILE_TOO_LARGE',
      ),
    );

    final result = await useCases.attachLocalFile.execute(
      workspaceId: 'workspace-1',
      noteId: 'note-1',
      file: photo,
    );

    expect(
      result.failureOrNull?.message,
      'Tệp quá lớn nên máy chủ không nhận.',
    );
  });

  test('ghi chú đã đủ 20 tệp thì báo giới hạn', () async {
    repository
      ..uploadResult = const Success('file-1')
      ..addAttachmentResult = const FailureResult(
        Failure(
          kind: FailureKind.validation,
          message: 'limit',
          code: 'NOTE_ATTACHMENT_LIMIT',
        ),
      );

    final result = await useCases.attachLocalFile.execute(
      workspaceId: 'workspace-1',
      noteId: 'note-1',
      file: photo,
    );

    expect(result.failureOrNull?.message, contains('tối đa 20 tệp'));
  });
}
