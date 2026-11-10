import 'package:webtui_chat/core/error/failure.dart';
import 'package:webtui_chat/core/result/result.dart';
import 'package:webtui_chat/features/my_notes/domain/entities/my_note.dart';
import 'package:webtui_chat/features/my_notes/domain/repositories/my_notes_repository.dart';

/// Repository giả viết tay: ghi lại lời gọi, trả kết quả đã đặt trước.
final class FakeMyNotesRepository implements MyNotesRepository {
  final calls = <String>[];

  /// Kết quả theo thứ tự cho `listNotes` (hết thì trả trang rỗng).
  final listResults = <Result<MyNotesCached<MyNotePage>>>[];
  final listFilters = <MyNoteFilter>[];
  final listCursors = <String?>[];

  Result<MyNotesCached<MyNote>>? getResult;
  final getResults = <Result<MyNotesCached<MyNote>>>[];
  Result<MyNote>? createResult;
  Result<MyNote>? updateResult;
  Result<void> deleteResult = const Success(null);
  Result<SavedMessageNote>? saveResult;
  Result<void> deleteFolderResult = const Success(null);
  Result<MyNoteFolder>? folderResult;
  List<MyNoteFolder> folders = const [];
  List<MyNoteTag> tags = const [];

  Map<String, Object?>? lastCreate;
  Map<String, Object?>? lastUpdate;
  Map<String, Object?>? lastSave;
  Map<String, Object?>? lastFolder;

  @override
  Future<Result<MyNotesCached<MyNotePage>>> listNotes({
    required String workspaceId,
    MyNoteFilter filter = const MyNoteFilter(),
    String? cursor,
    int limit = MyNoteLimits.pageSize,
  }) async {
    calls.add('listNotes');
    listFilters.add(filter);
    listCursors.add(cursor);
    if (listResults.isEmpty) {
      return const Success(MyNotesCached(MyNotePage(notes: [])));
    }
    return listResults.removeAt(0);
  }

  @override
  Future<Result<MyNotesCached<MyNote>>> getNote({
    required String workspaceId,
    required String noteId,
  }) async {
    calls.add('getNote:$noteId');
    if (getResults.isNotEmpty) return getResults.removeAt(0);
    return getResult ?? FailureResult(_notConfigured);
  }

  @override
  Future<Result<MyNote>> createNote({
    required String workspaceId,
    required String title,
    required String body,
    List<String> tags = const [],
    bool pinned = false,
    String? folderId,
  }) async {
    calls.add('createNote');
    lastCreate = {
      'workspaceId': workspaceId,
      'title': title,
      'body': body,
      'tags': tags,
      'pinned': pinned,
      'folderId': folderId,
    };
    return createResult ?? FailureResult(_notConfigured);
  }

  @override
  Future<Result<MyNote>> updateNote({
    required String workspaceId,
    required String noteId,
    required int version,
    required MyNotePatch patch,
  }) async {
    calls.add('updateNote:$noteId');
    lastUpdate = {
      'version': version,
      'title': patch.title,
      'body': patch.body,
      'tags': patch.tags,
      'pinned': patch.pinned,
      'folderId': patch.folderId,
      'moveToRoot': patch.moveToRoot,
    };
    return updateResult ?? FailureResult(_notConfigured);
  }

  @override
  Future<Result<void>> deleteNote({
    required String workspaceId,
    required String noteId,
  }) async {
    calls.add('deleteNote:$noteId');
    return deleteResult;
  }

  @override
  Future<Result<SavedMessageNote>> saveMessage({
    required String workspaceId,
    required String channelId,
    required String messageId,
    String? folderId,
  }) async {
    calls.add('saveMessage');
    lastSave = {
      'channelId': channelId,
      'messageId': messageId,
      'folderId': folderId,
    };
    return saveResult ?? FailureResult(_notConfigured);
  }

  @override
  Future<Result<MyNoteAttachment>> addAttachment({
    required String workspaceId,
    required String noteId,
    required String fileId,
  }) async {
    calls.add('addAttachment');
    return FailureResult(_notConfigured);
  }

  @override
  Future<Result<void>> removeAttachment({
    required String workspaceId,
    required String noteId,
    required String fileId,
  }) async {
    calls.add('removeAttachment:$fileId');
    return const Success(null);
  }

  @override
  Future<Result<MyNotesCached<List<MyNoteFolder>>>> listFolders({
    required String workspaceId,
  }) async {
    calls.add('listFolders');
    return Success(MyNotesCached(folders));
  }

  @override
  Future<Result<MyNoteFolder>> createFolder({
    required String workspaceId,
    required String name,
    String? parentId,
  }) async {
    calls.add('createFolder');
    lastFolder = {'name': name, 'parentId': parentId};
    return folderResult ?? FailureResult(_notConfigured);
  }

  @override
  Future<Result<MyNoteFolder>> updateFolder({
    required String workspaceId,
    required String folderId,
    String? name,
    String? parentId,
    bool moveToRoot = false,
  }) async {
    calls.add('updateFolder:$folderId');
    lastFolder = {'name': name, 'parentId': parentId};
    return folderResult ?? FailureResult(_notConfigured);
  }

  @override
  Future<Result<void>> deleteFolder({
    required String workspaceId,
    required String folderId,
  }) async {
    calls.add('deleteFolder:$folderId');
    return deleteFolderResult;
  }

  @override
  Future<Result<MyNotesCached<List<MyNoteTag>>>> listTags({
    required String workspaceId,
  }) async {
    calls.add('listTags');
    return Success(MyNotesCached(tags));
  }
}

const _notConfigured = Failure(
  kind: FailureKind.unknown,
  message: 'Chưa cấu hình kết quả giả.',
  code: 'FAKE_NOT_CONFIGURED',
);

MyNote testNote({
  String id = 'note-1',
  String title = 'Ghi chú',
  String body = 'Nội dung',
  int version = 1,
  bool pinned = false,
  String? folderId,
  List<String> tags = const [],
  DateTime? updatedAt,
}) {
  final time = updatedAt ?? DateTime.utc(2026, 11, 1);
  return MyNote(
    id: id,
    workspaceId: 'workspace-1',
    title: title,
    body: body,
    version: version,
    pinned: pinned,
    folderId: folderId,
    tags: tags,
    createdAt: time,
    updatedAt: time,
  );
}

MyNoteFolder testFolder(String id, {String? parentId, String? name}) {
  return MyNoteFolder(
    id: id,
    workspaceId: 'workspace-1',
    parentId: parentId,
    name: name ?? id,
    createdAt: DateTime.utc(2026, 11, 1),
    updatedAt: DateTime.utc(2026, 11, 1),
  );
}
