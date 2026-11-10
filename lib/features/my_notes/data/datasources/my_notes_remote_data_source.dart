import '../../../../core/network/api_response.dart';
import '../../../../core/network/api_transport.dart';
import '../../domain/entities/my_note.dart';
import '../mappers/my_note_json.dart';

/// Gọi API My Note dưới `/api/v1/workspaces/{ws}/me/`.
final class MyNotesRemoteDataSource {
  const MyNotesRemoteDataSource(this._api);

  final ApiTransport _api;

  Future<MyNotePage> listNotes({
    required String workspaceId,
    MyNoteFilter filter = const MyNoteFilter(),
    String? cursor,
    int limit = MyNoteLimits.pageSize,
  }) async {
    final query = filter.query.trim();
    final response = await _api.get<Object>(
      '${_meBase(workspaceId)}/notes',
      queryParameters: {
        if (filter.folderId != null && filter.folderId!.trim().isNotEmpty)
          'folder_id': filter.folderId!.trim(),
        if (filter.tag != null && filter.tag!.trim().isNotEmpty)
          'tag': filter.tag!.trim(),
        if (query.isNotEmpty) 'q': query,
        if (filter.pinnedOnly) 'pinned': 'true',
        'limit': limit,
        if (cursor != null && cursor.trim().isNotEmpty) 'cursor': cursor.trim(),
      },
    );
    final notes = envelopeList(response.data, 'notes')
        .map(
          (item) =>
              myNoteSummaryFromJson(item, fallbackWorkspaceId: workspaceId),
        )
        .where((note) => note.id.isNotEmpty)
        .toList(growable: false);
    final meta = jsonMap(jsonMap(response.data)['meta']);
    final nextCursor = nullableStringField(meta, const [
      'next_cursor',
      'nextCursor',
    ]);
    return MyNotePage(
      notes: notes,
      nextCursor: nextCursor,
      hasMore:
          boolField(meta, const ['has_more', 'hasMore']) && nextCursor != null,
    );
  }

  Future<MyNote> getNote({
    required String workspaceId,
    required String noteId,
  }) async {
    final response = await _api.get<Object>(_notePath(workspaceId, noteId));
    return myNoteFromJson(
      envelopeItem(response.data, 'note'),
      fallbackWorkspaceId: workspaceId,
    );
  }

  Future<MyNote> createNote({
    required String workspaceId,
    required String title,
    required String body,
    List<String> tags = const [],
    bool pinned = false,
    String? folderId,
  }) async {
    final response = await _api.post<Object>(
      '${_meBase(workspaceId)}/notes',
      data: {
        'title': title,
        'body': body,
        'tags': tags,
        'pinned': pinned,
        if (folderId != null && folderId.trim().isNotEmpty)
          'folder_id': folderId.trim(),
      },
    );
    return myNoteFromJson(
      envelopeItem(response.data, 'note'),
      fallbackWorkspaceId: workspaceId,
    );
  }

  Future<MyNote> updateNote({
    required String workspaceId,
    required String noteId,
    required int version,
    required MyNotePatch patch,
  }) async {
    final response = await _api.patch<Object>(
      _notePath(workspaceId, noteId),
      data: {
        'version': version,
        if (patch.title != null) 'title': patch.title,
        if (patch.body != null) 'body': patch.body,
        if (patch.tags != null) 'tags': patch.tags,
        if (patch.pinned != null) 'pinned': patch.pinned,
        if (patch.moveToRoot)
          'folder_id': null
        else if (patch.folderId != null)
          'folder_id': patch.folderId!.trim(),
      },
    );
    return myNoteFromJson(
      envelopeItem(response.data, 'note'),
      fallbackWorkspaceId: workspaceId,
    );
  }

  Future<void> deleteNote({
    required String workspaceId,
    required String noteId,
  }) async {
    await _api.delete<Object>(_notePath(workspaceId, noteId));
  }

  Future<SavedMessageNote> saveMessage({
    required String workspaceId,
    required String channelId,
    required String messageId,
    String? folderId,
  }) async {
    final response = await _api.post<Object>(
      '${_meBase(workspaceId)}/notes/from-message',
      data: {
        'channel_id': channelId.trim(),
        'message_id': messageId.trim(),
        if (folderId != null && folderId.trim().isNotEmpty)
          'folder_id': folderId.trim(),
      },
    );
    final data = jsonMap(envelopeData(response.data));
    final noteMap = jsonMapOrNull(data['note']) ?? data;
    return SavedMessageNote(
      note: myNoteFromJson(noteMap, fallbackWorkspaceId: workspaceId),
      created: boolField(data, const [
        'created',
      ], fallback: response.statusCode == 201),
    );
  }

  Future<MyNoteAttachment> addAttachment({
    required String workspaceId,
    required String noteId,
    required String fileId,
  }) async {
    final response = await _api.post<Object>(
      '${_notePath(workspaceId, noteId)}/attachments',
      data: {'file_id': fileId.trim()},
    );
    return myNoteAttachmentFromJson(envelopeItem(response.data, 'attachment'));
  }

  Future<void> removeAttachment({
    required String workspaceId,
    required String noteId,
    required String fileId,
  }) async {
    await _api.delete<Object>(
      '${_notePath(workspaceId, noteId)}/attachments/${_e(fileId)}',
    );
  }

  Future<List<MyNoteFolder>> listFolders({required String workspaceId}) async {
    final response = await _api.get<Object>(
      '${_meBase(workspaceId)}/note-folders',
    );
    return envelopeList(response.data, 'folders')
        .map(
          (item) =>
              myNoteFolderFromJson(item, fallbackWorkspaceId: workspaceId),
        )
        .where((folder) => folder.id.isNotEmpty)
        .toList(growable: false);
  }

  Future<MyNoteFolder> createFolder({
    required String workspaceId,
    required String name,
    String? parentId,
  }) async {
    final response = await _api.post<Object>(
      '${_meBase(workspaceId)}/note-folders',
      data: {
        'name': name,
        if (parentId != null && parentId.trim().isNotEmpty)
          'parent_id': parentId.trim(),
      },
    );
    return myNoteFolderFromJson(
      envelopeItem(response.data, 'folder'),
      fallbackWorkspaceId: workspaceId,
    );
  }

  Future<MyNoteFolder> updateFolder({
    required String workspaceId,
    required String folderId,
    String? name,
    String? parentId,
    bool moveToRoot = false,
  }) async {
    final response = await _api.patch<Object>(
      '${_meBase(workspaceId)}/note-folders/${_e(folderId)}',
      data: {
        'name': ?name,
        if (moveToRoot)
          'parent_id': null
        else if (parentId != null)
          'parent_id': parentId.trim(),
      },
    );
    return myNoteFolderFromJson(
      envelopeItem(response.data, 'folder'),
      fallbackWorkspaceId: workspaceId,
    );
  }

  Future<void> deleteFolder({
    required String workspaceId,
    required String folderId,
  }) async {
    await _api.delete<Object>(
      '${_meBase(workspaceId)}/note-folders/${_e(folderId)}',
    );
  }

  Future<List<MyNoteTag>> listTags({required String workspaceId}) async {
    final response = await _api.get<Object>(
      '${_meBase(workspaceId)}/note-tags',
    );
    return envelopeList(response.data, 'tags')
        .map(myNoteTagFromJson)
        .where((tag) => tag.tag.isNotEmpty)
        .toList(growable: false);
  }
}

String _meBase(String workspaceId) =>
    '/api/v1/workspaces/${_e(workspaceId)}/me';

String _notePath(String workspaceId, String noteId) =>
    '${_meBase(workspaceId)}/notes/${_e(noteId)}';

String _e(String value) => Uri.encodeComponent(value.trim());
