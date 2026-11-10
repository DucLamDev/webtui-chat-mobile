import '../../../../core/result/result.dart';
import '../entities/my_note.dart';

abstract interface class MyNotesRepository {
  /// Đọc từ máy chủ; mất mạng thì trả bản lưu trên máy (bộ lọc mặc định,
  /// trang đầu) với `fromCache = true`.
  Future<Result<MyNotesCached<MyNotePage>>> listNotes({
    required String workspaceId,
    MyNoteFilter filter = const MyNoteFilter(),
    String? cursor,
    int limit = MyNoteLimits.pageSize,
  });

  Future<Result<MyNotesCached<MyNote>>> getNote({
    required String workspaceId,
    required String noteId,
  });

  Future<Result<MyNote>> createNote({
    required String workspaceId,
    required String title,
    required String body,
    List<String> tags = const [],
    bool pinned = false,
    String? folderId,
  });

  Future<Result<MyNote>> updateNote({
    required String workspaceId,
    required String noteId,
    required int version,
    required MyNotePatch patch,
  });

  Future<Result<void>> deleteNote({
    required String workspaceId,
    required String noteId,
  });

  Future<Result<SavedMessageNote>> saveMessage({
    required String workspaceId,
    required String channelId,
    required String messageId,
    String? folderId,
  });

  Future<Result<MyNoteAttachment>> addAttachment({
    required String workspaceId,
    required String noteId,
    required String fileId,
  });

  Future<Result<void>> removeAttachment({
    required String workspaceId,
    required String noteId,
    required String fileId,
  });

  Future<Result<MyNotesCached<List<MyNoteFolder>>>> listFolders({
    required String workspaceId,
  });

  Future<Result<MyNoteFolder>> createFolder({
    required String workspaceId,
    required String name,
    String? parentId,
  });

  Future<Result<MyNoteFolder>> updateFolder({
    required String workspaceId,
    required String folderId,
    String? name,
    String? parentId,
    bool moveToRoot = false,
  });

  Future<Result<void>> deleteFolder({
    required String workspaceId,
    required String folderId,
  });

  Future<Result<MyNotesCached<List<MyNoteTag>>>> listTags({
    required String workspaceId,
  });
}
