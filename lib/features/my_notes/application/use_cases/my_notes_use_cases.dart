import 'package:webtui_chat/l10n/app_strings.dart';

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
      attachLocalFile = AttachLocalFileToMyNoteUseCase(repository),
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
  final AttachLocalFileToMyNoteUseCase attachLocalFile;
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
        tr(
          'Từ khoá tìm kiếm tối đa ${MyNoteLimits.queryMaxLength} ký tự.',
          'Search terms can be up to ${MyNoteLimits.queryMaxLength} characters.',
        ),
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
      return _invalid(
        tr(
          'Ghi chú cần có tiêu đề hoặc nội dung.',
          'A note needs a title or content.',
        ),
        'MY_NOTE_EMPTY',
      );
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
        tr(
          'Thiếu phiên bản ghi chú, hãy tải lại ghi chú rồi sửa.',
          'The note version is missing. Reload the note, then edit it.',
        ),
        'MY_NOTE_VERSION_REQUIRED',
      );
    }
    if (patch.isEmpty) {
      return _invalid(
        tr('Chưa có thay đổi nào để lưu.', 'No changes to save.'),
        'MY_NOTE_NO_CHANGES',
      );
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
      return _invalid(
        tr(
          'Ghi chú cần có tiêu đề hoặc nội dung.',
          'A note needs a title or content.',
        ),
        'MY_NOTE_EMPTY',
      );
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
        tr(
          'Tin nhắn chưa gửi xong nên chưa lưu vào My Note được.',
          'The message hasn\'t finished sending, so it can\'t be saved to My Note yet.',
        ),
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

/// Tải ảnh / tệp trên máy lên rồi gắn vào ghi chú. [onProgress] chạy 0 → 1
/// (phần tải lên chiếm tới 0,95; gắn xong mới báo 1).
final class AttachLocalFileToMyNoteUseCase {
  const AttachLocalFileToMyNoteUseCase(this._repository);

  final MyNotesRepository _repository;

  Future<Result<MyNoteAttachment>> execute({
    required String workspaceId,
    required String noteId,
    required MyNoteLocalFile file,
    void Function(double progress)? onProgress,
  }) async {
    final ws = workspaceId.trim();
    final id = noteId.trim();
    if (ws.isEmpty) return _workspaceRequired();
    if (id.isEmpty) return _noteRequired();
    final name = file.name.trim();
    if (file.path.trim().isEmpty || name.isEmpty) {
      return _invalid(
        tr('Chưa chọn tệp đính kèm.', 'No attachment selected.'),
        'MY_NOTE_FILE_REQUIRED',
      );
    }
    if (file.byteSize <= 0) {
      return _invalid(
        tr(
          'Tệp "$name" trống, không đính kèm được.',
          '"$name" is empty and can\'t be attached.',
        ),
        'MY_NOTE_FILE_EMPTY',
      );
    }
    if (file.byteSize > MyNoteLimits.attachmentMaxBytes) {
      return _invalid(
        tr(
          'Tệp "$name" quá lớn. Mỗi tệp đính kèm tối đa 100 MB.',
          '"$name" is too large. Each attachment can be up to 100 MB.',
        ),
        'MY_NOTE_FILE_TOO_LARGE',
      );
    }
    final uploaded = await _repository.uploadFile(
      workspaceId: ws,
      file: file,
      onProgress: onProgress == null
          ? null
          : (value) => onProgress(value.clamp(0.0, 1.0).toDouble() * 0.95),
    );
    final String fileId;
    switch (uploaded) {
      case Success(:final value):
        fileId = value;
      case FailureResult(:final failure):
        return FailureResult(_friendlyUploadFailure(failure, name));
    }
    final attached = await _repository.addAttachment(
      workspaceId: ws,
      noteId: id,
      fileId: fileId,
    );
    if (attached case FailureResult(:final failure)) {
      return FailureResult(_friendlyAttachFailure(failure));
    }
    onProgress?.call(1);
    return attached;
  }
}

Failure _friendlyUploadFailure(Failure failure, String name) {
  return switch (failure.kind) {
    FailureKind.forbidden => failure.copyWith(
      message: tr(
        'Bạn không có quyền tải tệp lên workspace này.',
        'You don\'t have permission to upload files to this workspace.',
      ),
    ),
    FailureKind.unauthorized => failure.copyWith(
      message: tr(
        'Phiên đăng nhập đã hết hạn. Hãy đăng nhập lại rồi đính kèm.',
        'Your session has expired. Sign in again, then attach the file.',
      ),
    ),
    FailureKind.server ||
    FailureKind.unknown ||
    FailureKind.decoding => failure.copyWith(
      message: tr(
        'Chưa tải "$name" lên được. Vui lòng thử lại.',
        'Couldn\'t upload "$name". Please try again.',
      ),
    ),
    _ => failure,
  };
}

Failure _friendlyAttachFailure(Failure failure) {
  if (failure.hasCode('NOTE_ATTACHMENT_LIMIT')) {
    return failure.copyWith(
      message: tr(
        'Mỗi ghi chú gắn tối đa ${MyNoteLimits.attachmentsMax} tệp.',
        'Each note can have up to ${MyNoteLimits.attachmentsMax} attachments.',
      ),
    );
  }
  return switch (failure.kind) {
    FailureKind.forbidden => failure.copyWith(
      message: tr(
        'Bạn không có quyền gắn tệp này vào ghi chú.',
        'You don\'t have permission to attach this file to the note.',
      ),
    ),
    FailureKind.notFound => failure.copyWith(
      message: tr(
        'Ghi chú không còn tồn tại hoặc đã bị xoá.',
        'The note no longer exists or was deleted.',
      ),
    ),
    FailureKind.server ||
    FailureKind.unknown ||
    FailureKind.decoding => failure.copyWith(
      message: tr(
        'Đã tải tệp lên nhưng chưa gắn vào ghi chú được. Vui lòng thử lại.',
        'The file was uploaded but couldn\'t be attached to the note. Please try again.',
      ),
    ),
    _ => failure,
  };
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
      return _invalid(
        tr('Chưa chọn tệp đính kèm.', 'No attachment selected.'),
        'MY_NOTE_FILE_REQUIRED',
      );
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
          tr(
            'Thư mục chỉ lồng tối đa ${MyNoteLimits.folderMaxDepth} tầng.',
            'Folders can be nested up to ${MyNoteLimits.folderMaxDepth} levels.',
          ),
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
    return Failure(
      kind: FailureKind.validation,
      message: tr(
        'Tiêu đề tối đa ${MyNoteLimits.titleMaxLength} ký tự.',
        'Titles can be up to ${MyNoteLimits.titleMaxLength} characters.',
      ),
      code: 'MY_NOTE_TITLE_TOO_LONG',
    );
  }
  if (body.runes.length > MyNoteLimits.bodyMaxLength) {
    return Failure(
      kind: FailureKind.validation,
      message: tr(
        'Nội dung tối đa 50.000 ký tự.',
        'Content can be up to 50,000 characters.',
      ),
      code: 'MY_NOTE_BODY_TOO_LONG',
    );
  }
  return null;
}

Failure? validateMyNoteTags(List<String> tags) {
  if (tags.length > MyNoteLimits.tagsMax) {
    return Failure(
      kind: FailureKind.validation,
      message: tr(
        'Mỗi ghi chú có tối đa ${MyNoteLimits.tagsMax} tag.',
        'Each note can have up to ${MyNoteLimits.tagsMax} tags.',
      ),
      code: 'MY_NOTE_TOO_MANY_TAGS',
    );
  }
  for (final tag in tags) {
    if (tag.runes.length > MyNoteLimits.tagMaxLength) {
      return Failure(
        kind: FailureKind.validation,
        message: tr(
          'Mỗi tag tối đa ${MyNoteLimits.tagMaxLength} ký tự.',
          'Each tag can be up to ${MyNoteLimits.tagMaxLength} characters.',
        ),
        code: 'MY_NOTE_TAG_TOO_LONG',
      );
    }
  }
  return null;
}

Failure? validateMyNoteFolderName(String name) {
  if (name.isEmpty) {
    return Failure(
      kind: FailureKind.validation,
      message: tr('Hãy nhập tên thư mục.', 'Enter a folder name.'),
      code: 'NOTE_FOLDER_NAME_REQUIRED',
    );
  }
  if (name.runes.length > MyNoteLimits.folderNameMaxLength) {
    return Failure(
      kind: FailureKind.validation,
      message: tr(
        'Tên thư mục tối đa ${MyNoteLimits.folderNameMaxLength} ký tự.',
        'Folder names can be up to ${MyNoteLimits.folderNameMaxLength} characters.',
      ),
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

FailureResult<T> _workspaceRequired<T>() => _invalid(
  tr('Chưa chọn workspace.', 'No workspace selected.'),
  'MY_NOTE_WORKSPACE_REQUIRED',
);

FailureResult<T> _noteRequired<T>() =>
    _invalid(tr('Chưa chọn ghi chú.', 'No note selected.'), 'MY_NOTE_REQUIRED');

FailureResult<T> _folderRequired<T>() => _invalid(
  tr('Chưa chọn thư mục.', 'No folder selected.'),
  'NOTE_FOLDER_REQUIRED',
);
