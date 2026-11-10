import '../../../../core/error/failure.dart';
import '../../../../core/result/result.dart';
import '../../../../core/result/result_guard.dart';
import '../../domain/entities/my_note.dart';
import '../../domain/repositories/my_notes_repository.dart';
import '../datasources/my_notes_cache_data_source.dart';
import '../datasources/my_notes_remote_data_source.dart';

const myNotesOfflineWriteMessage =
    'Bạn đang ngoại tuyến. My Note chưa lưu được thay đổi khi mất mạng, '
    'hãy thử lại khi có kết nối.';

/// Đọc: máy chủ trước, lưu bản sao trên máy; mất mạng thì trả bản lưu.
/// Ghi: chỉ qua máy chủ (không có hàng chờ), mất mạng báo lỗi rõ.
final class MyNotesRepositoryImpl implements MyNotesRepository {
  const MyNotesRepositoryImpl({
    required MyNotesRemoteDataSource remote,
    required MyNotesCacheDataSource cache,
  }) : _remote = remote,
       _cache = cache;

  final MyNotesRemoteDataSource _remote;
  final MyNotesCacheDataSource _cache;

  @override
  Future<Result<MyNotesCached<MyNotePage>>> listNotes({
    required String workspaceId,
    MyNoteFilter filter = const MyNoteFilter(),
    String? cursor,
    int limit = MyNoteLimits.pageSize,
  }) async {
    final cacheable = filter.isDefault && (cursor == null || cursor.isEmpty);
    final result = await guardResult(
      () => _remote.listNotes(
        workspaceId: workspaceId,
        filter: filter,
        cursor: cursor,
        limit: limit,
      ),
    );
    switch (result) {
      case Success(value: final page):
        if (cacheable) {
          await _quietly(
            () => _cache.saveDefaultPage(
              workspaceId: workspaceId,
              notes: page.notes,
            ),
          );
        }
        return Success(MyNotesCached(page));
      case FailureResult(failure: final failure):
        if (cacheable && _isOffline(failure)) {
          final cached = await _readQuietly(
            () => _cache.readDefaultPage(workspaceId: workspaceId),
          );
          if (cached != null) return Success(cached);
        }
        return FailureResult(failure);
    }
  }

  @override
  Future<Result<MyNotesCached<MyNote>>> getNote({
    required String workspaceId,
    required String noteId,
  }) async {
    final result = await guardResult(
      () => _remote.getNote(workspaceId: workspaceId, noteId: noteId),
    );
    switch (result) {
      case Success(value: final note):
        await _quietly(
          () => _cache.saveNote(workspaceId: workspaceId, note: note),
        );
        return Success(MyNotesCached(note));
      case FailureResult(failure: final failure):
        if (_isOffline(failure)) {
          final cached = await _readQuietly(
            () => _cache.readNote(workspaceId: workspaceId, noteId: noteId),
          );
          if (cached != null) return Success(cached);
        } else if (failure.kind == FailureKind.notFound ||
            failure.kind == FailureKind.forbidden) {
          // Ghi chú đã bị xoá / không còn quyền: bỏ bản lưu cũ.
          await _quietly(() => _forget(workspaceId, noteId));
        }
        return FailureResult(failure);
    }
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
    final result = await _write(
      () => _remote.createNote(
        workspaceId: workspaceId,
        title: title,
        body: body,
        tags: tags,
        pinned: pinned,
        folderId: folderId,
      ),
    );
    if (result case Success(value: final note)) {
      await _remember(workspaceId, note);
    }
    return result;
  }

  @override
  Future<Result<MyNote>> updateNote({
    required String workspaceId,
    required String noteId,
    required int version,
    required MyNotePatch patch,
  }) async {
    final result = await _write(
      () => _remote.updateNote(
        workspaceId: workspaceId,
        noteId: noteId,
        version: version,
        patch: patch,
      ),
    );
    if (result case Success(value: final note)) {
      await _remember(workspaceId, note);
    }
    return result;
  }

  @override
  Future<Result<void>> deleteNote({
    required String workspaceId,
    required String noteId,
  }) async {
    final result = await _write(
      () => _remote.deleteNote(workspaceId: workspaceId, noteId: noteId),
    );
    if (result.isSuccess) {
      await _quietly(() => _forget(workspaceId, noteId));
    }
    return result;
  }

  @override
  Future<Result<SavedMessageNote>> saveMessage({
    required String workspaceId,
    required String channelId,
    required String messageId,
    String? folderId,
  }) async {
    final result = await _write(
      () => _remote.saveMessage(
        workspaceId: workspaceId,
        channelId: channelId,
        messageId: messageId,
        folderId: folderId,
      ),
    );
    if (result case Success(value: final saved)) {
      await _remember(workspaceId, saved.note);
    }
    return result;
  }

  @override
  Future<Result<MyNoteAttachment>> addAttachment({
    required String workspaceId,
    required String noteId,
    required String fileId,
  }) async {
    final result = await _write(
      () => _remote.addAttachment(
        workspaceId: workspaceId,
        noteId: noteId,
        fileId: fileId,
      ),
    );
    if (result case Success(value: final attachment)) {
      await _quietly(() async {
        final cached = await _cache.readNote(
          workspaceId: workspaceId,
          noteId: noteId,
        );
        if (cached == null) return;
        await _remember(
          workspaceId,
          cached.value.copyWith(
            attachments: [
              ...cached.value.attachments.where(
                (item) => item.fileId != attachment.fileId,
              ),
              attachment,
            ],
          ),
        );
      });
    }
    return result;
  }

  @override
  Future<Result<void>> removeAttachment({
    required String workspaceId,
    required String noteId,
    required String fileId,
  }) async {
    final result = await _write(
      () => _remote.removeAttachment(
        workspaceId: workspaceId,
        noteId: noteId,
        fileId: fileId,
      ),
    );
    if (result.isSuccess) {
      await _quietly(() async {
        final cached = await _cache.readNote(
          workspaceId: workspaceId,
          noteId: noteId,
        );
        if (cached == null) return;
        await _remember(
          workspaceId,
          cached.value.copyWith(
            attachments: cached.value.attachments
                .where((item) => item.fileId != fileId.trim())
                .toList(growable: false),
          ),
        );
      });
    }
    return result;
  }

  @override
  Future<Result<MyNotesCached<List<MyNoteFolder>>>> listFolders({
    required String workspaceId,
  }) async {
    final result = await guardResult(
      () => _remote.listFolders(workspaceId: workspaceId),
    );
    switch (result) {
      case Success(value: final folders):
        await _quietly(
          () => _cache.saveFolders(workspaceId: workspaceId, folders: folders),
        );
        return Success(MyNotesCached(folders));
      case FailureResult(failure: final failure):
        if (_isOffline(failure)) {
          final cached = await _readQuietly(
            () => _cache.readFolders(workspaceId: workspaceId),
          );
          if (cached != null) return Success(cached);
        }
        return FailureResult(failure);
    }
  }

  @override
  Future<Result<MyNoteFolder>> createFolder({
    required String workspaceId,
    required String name,
    String? parentId,
  }) {
    return _write(
      () => _remote.createFolder(
        workspaceId: workspaceId,
        name: name,
        parentId: parentId,
      ),
    );
  }

  @override
  Future<Result<MyNoteFolder>> updateFolder({
    required String workspaceId,
    required String folderId,
    String? name,
    String? parentId,
    bool moveToRoot = false,
  }) {
    return _write(
      () => _remote.updateFolder(
        workspaceId: workspaceId,
        folderId: folderId,
        name: name,
        parentId: parentId,
        moveToRoot: moveToRoot,
      ),
    );
  }

  @override
  Future<Result<void>> deleteFolder({
    required String workspaceId,
    required String folderId,
  }) {
    return _write(
      () => _remote.deleteFolder(workspaceId: workspaceId, folderId: folderId),
    );
  }

  @override
  Future<Result<MyNotesCached<List<MyNoteTag>>>> listTags({
    required String workspaceId,
  }) async {
    final result = await guardResult(
      () => _remote.listTags(workspaceId: workspaceId),
    );
    switch (result) {
      case Success(value: final tags):
        await _quietly(
          () => _cache.saveTags(workspaceId: workspaceId, tags: tags),
        );
        return Success(MyNotesCached(tags));
      case FailureResult(failure: final failure):
        if (_isOffline(failure)) {
          final cached = await _readQuietly(
            () => _cache.readTags(workspaceId: workspaceId),
          );
          if (cached != null) return Success(cached);
        }
        return FailureResult(failure);
    }
  }

  Future<Result<T>> _write<T>(Future<T> Function() body) async {
    final result = await guardResult(body);
    if (result case FailureResult(
      failure: final failure,
    ) when _isOffline(failure)) {
      return FailureResult(
        failure.copyWith(
          message: myNotesOfflineWriteMessage,
          code: 'MY_NOTES_OFFLINE',
        ),
      );
    }
    return result;
  }

  Future<void> _remember(String workspaceId, MyNote note) async {
    await _quietly(() async {
      await _cache.saveNote(workspaceId: workspaceId, note: note);
      await _cache.upsertSummary(
        workspaceId: workspaceId,
        note: note.toSummary(),
      );
    });
  }

  Future<void> _forget(String workspaceId, String noteId) async {
    await _cache.removeNote(workspaceId: workspaceId, noteId: noteId);
    await _cache.removeSummary(workspaceId: workspaceId, noteId: noteId);
  }
}

bool _isOffline(Failure failure) =>
    failure.kind == FailureKind.network || failure.kind == FailureKind.timeout;

/// Lỗi bộ nhớ trên máy không được làm hỏng thao tác đã thành công ở máy chủ.
Future<void> _quietly(Future<void> Function() body) async {
  try {
    await body();
  } on Object {
    // Bỏ qua: bản lưu trên máy chỉ để đọc khi mất mạng.
  }
}

Future<T?> _readQuietly<T>(Future<T?> Function() body) async {
  try {
    return await body();
  } on Object {
    return null;
  }
}
