import '../../../../core/error/failure.dart';
import '../../../../core/result/result.dart';
import '../../domain/entities/my_note.dart';
import '../../domain/repositories/my_notes_repository.dart';

/// Gom mọi use case My Note để nối provider một lần.
final class MyNotesUseCases {
  MyNotesUseCases(MyNotesRepository repository)
    : listNotes = ListMyNotesUseCase(repository),
      getNote = GetMyNoteUseCase(repository),
      createNote = CreateMyNoteUseCase(repository),
      updateNote = UpdateMyNoteUseCase(repository),
      deleteNote = DeleteMyNoteUseCase(repository),
      saveMessage = SaveMessageToMyNoteUseCase(repository),
      removeAttachment = RemoveMyNoteAttachmentUseCase(repository),
      listFolders = ListMyNoteFoldersUseCase(repository),
      createFolder = CreateMyNoteFolderUseCase(repository),
      renameFolder = RenameMyNoteFolderUseCase(repository),
      deleteFolder = DeleteMyNoteFolderUseCase(repository),
      listTags = ListMyNoteTagsUseCase(repository);

  final ListMyNotesUseCase listNotes;
  final GetMyNoteUseCase getNote;
  final CreateMyNoteUseCase createNote;
  final UpdateMyNoteUseCase updateNote;
  final DeleteMyNoteUseCase deleteNote;
  final SaveMessageToMyNoteUseCase saveMessage;
  final RemoveMyNoteAttachmentUseCase removeAttachment;
  final ListMyNoteFoldersUseCase listFolders;
  final CreateMyNoteFolderUseCase createFolder;
  final RenameMyNoteFolderUseCase renameFolder;
  final DeleteMyNoteFolderUseCase deleteFolder;
  final ListMyNoteTagsUseCase listTags;
}

final class ListMyNotesUseCase {
  const ListMyNotesUseCase(this._repository);

  final MyNotesRepository _repository;

  Future<Result<MyNotesCached<MyNotePage>>> execute({
    required String workspaceId,
    MyNoteFilter filter = const MyNoteFilter(),
    String? cursor,
  }) async {
    final ws = workspaceId.trim();
    if (ws.isEmpty) return _workspaceRequired();
    final query = filter.query.trim();
    if (query.runes.length > MyNoteLimits.queryMaxLength) {
      return _invalid(
        'Từ khoá tìm kiếm tối đa ${MyNoteLimits.queryMaxLength} ký tự.',
        'MY_NOTE_QUERY_TOO_LONG',
      );
    }
    return _repository.listNotes(
      workspaceId: ws,
      filter: filter.copyWith(query: query),
      cursor: cursor?.trim(),
    );
  }
}

final class GetMyNoteUseCase {
  const GetMyNoteUseCase(this._repository);

  final MyNotesRepository _repository;

  Future<Result<MyNotesCached<MyNote>>> execute({
    required String workspaceId,
    required String noteId,
  }) async {
    final ws = workspaceId.trim();
    final id = noteId.trim();
    if (ws.isEmpty) return _workspaceRequired();
    if (id.isEmpty) return _noteRequired();
    return _repository.getNote(workspaceId: ws, noteId: id);
  }
}

final class CreateMyNoteUseCase {
  const CreateMyNoteUseCase(this._repository);

  final MyNotesRepository _repository;

  Future<Result<MyNote>> execute({
    required String workspaceId,
    required String title,
    required String body,
    List<String> tags = const [],
    bool pinned = false,
    String? folderId,
  }) async {
    final ws = workspaceId.trim();
    if (ws.isEmpty) return _workspaceRequired();
    final cleanTitle = title.trim();
    final cleanTags = normalizeMyNoteTags(tags);
    final invalid =
        validateMyNoteContent(title: cleanTitle, body: body) ??
        validateMyNoteTags(cleanTags);
    if (invalid != null) return FailureResult(invalid);
    if (cleanTitle.isEmpty && body.trim().isEmpty) {
      return _invalid('Ghi chú cần có tiêu đề hoặc nội dung.', 'MY_NOTE_EMPTY');
    }
    final folder = folderId?.trim();
    return _repository.createNote(
      workspaceId: ws,
      title: cleanTitle,
      body: body,
      tags: cleanTags,
      pinned: pinned,
      folderId: folder == null || folder.isEmpty ? null : folder,
    );
  }
}

final class UpdateMyNoteUseCase {
  const UpdateMyNoteUseCase(this._repository);

  final MyNotesRepository _repository;

  Future<Result<MyNote>> execute({
    required String workspaceId,
    required String noteId,
    required int version,
    required MyNotePatch patch,
  }) async {
    final ws = workspaceId.trim();
    final id = noteId.trim();
    if (ws.isEmpty) return _workspaceRequired();
    if (id.isEmpty) return _noteRequired();
    if (version < 1) {
      return _invalid(
        'Thiếu phiên bản ghi chú, hãy tải lại ghi chú rồi sửa.',
        'MY_NOTE_VERSION_REQUIRED',
      );
    }
    if (patch.isEmpty) {
      return _invalid('Chưa có thay đổi nào để lưu.', 'MY_NOTE_NO_CHANGES');
    }
    final title = patch.title?.trim();
    final tags = patch.tags == null ? null : normalizeMyNoteTags(patch.tags!);
    final invalid =
        validateMyNoteContent(title: title ?? '', body: patch.body ?? '') ??
        (tags == null ? null : validateMyNoteTags(tags));
    if (invalid != null) return FailureResult(invalid);
    if (title != null &&
        patch.body != null &&
        title.isEmpty &&
        patch.body!.trim().isEmpty) {
      return _invalid('Ghi chú cần có tiêu đề hoặc nội dung.', 'MY_NOTE_EMPTY');
    }
    final folder = patch.folderId?.trim();
    return _repository.updateNote(
      workspaceId: ws,
      noteId: id,
      version: version,
      patch: MyNotePatch(
        title: title,
        body: patch.body,
        tags: tags,
        pinned: patch.pinned,
        folderId: folder == null || folder.isEmpty ? null : folder,
        moveToRoot: patch.moveToRoot,
      ),
    );
  }
}

final class DeleteMyNoteUseCase {
  const DeleteMyNoteUseCase(this._repository);

  final MyNotesRepository _repository;

  Future<Result<void>> execute({
    required String workspaceId,
    required String noteId,
  }) async {
    final ws = workspaceId.trim();
    final id = noteId.trim();
    if (ws.isEmpty) return _workspaceRequired();
    if (id.isEmpty) return _noteRequired();
    return _repository.deleteNote(workspaceId: ws, noteId: id);
  }
}

final class SaveMessageToMyNoteUseCase {
  const SaveMessageToMyNoteUseCase(this._repository);

  final MyNotesRepository _repository;

  Future<Result<SavedMessageNote>> execute({
    required String workspaceId,
    required String channelId,
    required String messageId,
    String? folderId,
  }) async {
    final ws = workspaceId.trim();
    final channel = channelId.trim();
    final message = messageId.trim();
    if (ws.isEmpty) return _workspaceRequired();
    // Tin chưa gửi xong (id tạm trên máy) chưa có trên máy chủ để lưu.
    if (channel.isEmpty || message.isEmpty || message.startsWith('local-')) {
      return _invalid(
        'Tin nhắn chưa gửi xong nên chưa lưu vào My Note được.',
        'MY_NOTE_MESSAGE_REQUIRED',
      );
    }
    final folder = folderId?.trim();
    return _repository.saveMessage(
      workspaceId: ws,
      channelId: channel,
      messageId: message,
      folderId: folder == null || folder.isEmpty ? null : folder,
    );
  }
}

final class RemoveMyNoteAttachmentUseCase {
  const RemoveMyNoteAttachmentUseCase(this._repository);

  final MyNotesRepository _repository;

  Future<Result<void>> execute({
    required String workspaceId,
    required String noteId,
    required String fileId,
  }) async {
    final ws = workspaceId.trim();
    final id = noteId.trim();
    final file = fileId.trim();
    if (ws.isEmpty) return _workspaceRequired();
    if (id.isEmpty) return _noteRequired();
    if (file.isEmpty) {
      return _invalid('Chưa chọn tệp đính kèm.', 'MY_NOTE_FILE_REQUIRED');
    }
    return _repository.removeAttachment(
      workspaceId: ws,
      noteId: id,
      fileId: file,
    );
  }
}

final class ListMyNoteFoldersUseCase {
  const ListMyNoteFoldersUseCase(this._repository);

  final MyNotesRepository _repository;

  Future<Result<MyNotesCached<List<MyNoteFolder>>>> execute(
    String workspaceId,
  ) async {
    final ws = workspaceId.trim();
    if (ws.isEmpty) return _workspaceRequired();
    return _repository.listFolders(workspaceId: ws);
  }
}

final class CreateMyNoteFolderUseCase {
  const CreateMyNoteFolderUseCase(this._repository);

  final MyNotesRepository _repository;

  /// [existingFolders] để chặn sớm cây quá sâu (máy chủ vẫn kiểm lại).
  Future<Result<MyNoteFolder>> execute({
    required String workspaceId,
    required String name,
    String? parentId,
    List<MyNoteFolder> existingFolders = const [],
  }) async {
    final ws = workspaceId.trim();
    if (ws.isEmpty) return _workspaceRequired();
    final cleanName = name.trim();
    final invalid = validateMyNoteFolderName(cleanName);
    if (invalid != null) return FailureResult(invalid);
    final parent = parentId?.trim();
    if (parent != null && parent.isNotEmpty) {
      final parentDepth = myNoteFolderDepth(existingFolders, parent);
      if (parentDepth >= MyNoteLimits.folderMaxDepth) {
        return _invalid(
          'Thư mục chỉ lồng tối đa ${MyNoteLimits.folderMaxDepth} tầng.',
          'NOTE_FOLDER_TOO_DEEP',
        );
      }
    }
    return _repository.createFolder(
      workspaceId: ws,
      name: cleanName,
      parentId: parent == null || parent.isEmpty ? null : parent,
    );
  }
}

final class RenameMyNoteFolderUseCase {
  const RenameMyNoteFolderUseCase(this._repository);

  final MyNotesRepository _repository;

  Future<Result<MyNoteFolder>> execute({
    required String workspaceId,
    required String folderId,
    required String name,
  }) async {
    final ws = workspaceId.trim();
    final id = folderId.trim();
    if (ws.isEmpty) return _workspaceRequired();
    if (id.isEmpty) return _folderRequired();
    final cleanName = name.trim();
    final invalid = validateMyNoteFolderName(cleanName);
    if (invalid != null) return FailureResult(invalid);
    return _repository.updateFolder(
      workspaceId: ws,
      folderId: id,
      name: cleanName,
    );
  }
}

final class DeleteMyNoteFolderUseCase {
  const DeleteMyNoteFolderUseCase(this._repository);

  final MyNotesRepository _repository;

  Future<Result<void>> execute({
    required String workspaceId,
    required String folderId,
  }) async {
    final ws = workspaceId.trim();
    final id = folderId.trim();
    if (ws.isEmpty) return _workspaceRequired();
    if (id.isEmpty) return _folderRequired();
    return _repository.deleteFolder(workspaceId: ws, folderId: id);
  }
}

final class ListMyNoteTagsUseCase {
  const ListMyNoteTagsUseCase(this._repository);

  final MyNotesRepository _repository;

  Future<Result<MyNotesCached<List<MyNoteTag>>>> execute(
    String workspaceId,
  ) async {
    final ws = workspaceId.trim();
    if (ws.isEmpty) return _workspaceRequired();
    return _repository.listTags(workspaceId: ws);
  }
}

Failure? validateMyNoteContent({required String title, required String body}) {
  if (title.runes.length > MyNoteLimits.titleMaxLength) {
    return const Failure(
      kind: FailureKind.validation,
      message: 'Tiêu đề tối đa ${MyNoteLimits.titleMaxLength} ký tự.',
      code: 'MY_NOTE_TITLE_TOO_LONG',
    );
  }
  if (body.runes.length > MyNoteLimits.bodyMaxLength) {
    return const Failure(
      kind: FailureKind.validation,
      message: 'Nội dung tối đa 50.000 ký tự.',
      code: 'MY_NOTE_BODY_TOO_LONG',
    );
  }
  return null;
}

Failure? validateMyNoteTags(List<String> tags) {
  if (tags.length > MyNoteLimits.tagsMax) {
    return const Failure(
      kind: FailureKind.validation,
      message: 'Mỗi ghi chú có tối đa ${MyNoteLimits.tagsMax} tag.',
      code: 'MY_NOTE_TOO_MANY_TAGS',
    );
  }
  for (final tag in tags) {
    if (tag.runes.length > MyNoteLimits.tagMaxLength) {
      return const Failure(
        kind: FailureKind.validation,
        message: 'Mỗi tag tối đa ${MyNoteLimits.tagMaxLength} ký tự.',
        code: 'MY_NOTE_TAG_TOO_LONG',
      );
    }
  }
  return null;
}

Failure? validateMyNoteFolderName(String name) {
  if (name.isEmpty) {
    return const Failure(
      kind: FailureKind.validation,
      message: 'Hãy nhập tên thư mục.',
      code: 'NOTE_FOLDER_NAME_REQUIRED',
    );
  }
  if (name.runes.length > MyNoteLimits.folderNameMaxLength) {
    return const Failure(
      kind: FailureKind.validation,
      message: 'Tên thư mục tối đa ${MyNoteLimits.folderNameMaxLength} ký tự.',
      code: 'NOTE_FOLDER_NAME_TOO_LONG',
    );
  }
  return null;
}

FailureResult<T> _invalid<T>(String message, String code) {
  return FailureResult<T>(
    Failure(kind: FailureKind.validation, message: message, code: code),
  );
}

FailureResult<T> _workspaceRequired<T>() =>
    _invalid('Chưa chọn workspace.', 'MY_NOTE_WORKSPACE_REQUIRED');

FailureResult<T> _noteRequired<T>() =>
    _invalid('Chưa chọn ghi chú.', 'MY_NOTE_REQUIRED');

FailureResult<T> _folderRequired<T>() =>
    _invalid('Chưa chọn thư mục.', 'NOTE_FOLDER_REQUIRED');
