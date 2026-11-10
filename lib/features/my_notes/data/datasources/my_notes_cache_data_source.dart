import 'dart:convert';

import '../../../../core/database/app_database.dart';
import '../../../../core/network/api_response.dart';
import '../../../../core/security/instance_scope.dart';
import '../../domain/entities/my_note.dart';
import '../mappers/my_note_json.dart';

/// Bản lưu My Note trên máy (Drift key-value), tách theo máy chủ + workspace.
/// Chỉ lưu dữ liệu đã tải để mở khi mất mạng; không có hàng chờ ghi.
final class MyNotesCacheDataSource {
  const MyNotesCacheDataSource(this._database, this._instanceScope);

  final AppDatabase _database;
  final InstanceScope _instanceScope;

  static const _listKey = 'notes_default_page';
  static const _foldersKey = 'folders';
  static const _tagsKey = 'tags';

  /// Số ghi chú tối đa giữ trong danh sách lưu trên máy.
  static const maxCachedSummaries = 200;

  Future<MyNotesCached<MyNotePage>?> readDefaultPage({
    required String workspaceId,
  }) async {
    final decoded = await _read(workspaceId, _listKey);
    if (decoded == null) return null;
    final notes = jsonMapList(decoded['notes'])
        .map(
          (item) =>
              myNoteSummaryFromJson(item, fallbackWorkspaceId: workspaceId),
        )
        .where((note) => note.id.isNotEmpty)
        .toList(growable: false);
    return MyNotesCached(
      MyNotePage(notes: notes),
      fromCache: true,
      cachedAt: nullableDateTimeField(decoded, const ['saved_at']),
    );
  }

  Future<void> saveDefaultPage({
    required String workspaceId,
    required List<MyNoteSummary> notes,
  }) {
    final sorted = sortMyNoteSummaries(notes);
    return _write(workspaceId, _listKey, {
      'saved_at': DateTime.now().toUtc().toIso8601String(),
      'notes': [
        for (final note in sorted.take(maxCachedSummaries))
          myNoteSummaryToJson(note),
      ],
    });
  }

  /// Cập nhật một ghi chú trong danh sách đã lưu (sau khi tạo / sửa).
  Future<void> upsertSummary({
    required String workspaceId,
    required MyNoteSummary note,
  }) async {
    final cached = await readDefaultPage(workspaceId: workspaceId);
    final notes = [
      note,
      ...?cached?.value.notes.where((item) => item.id != note.id),
    ];
    await saveDefaultPage(workspaceId: workspaceId, notes: notes);
  }

  Future<void> removeSummary({
    required String workspaceId,
    required String noteId,
  }) async {
    final cached = await readDefaultPage(workspaceId: workspaceId);
    if (cached == null) return;
    await saveDefaultPage(
      workspaceId: workspaceId,
      notes: cached.value.notes
          .where((item) => item.id != noteId)
          .toList(growable: false),
    );
  }

  Future<MyNotesCached<MyNote>?> readNote({
    required String workspaceId,
    required String noteId,
  }) async {
    final decoded = await _read(workspaceId, _noteKey(noteId));
    if (decoded == null) return null;
    final note = myNoteFromJson(
      jsonMap(decoded['note']),
      fallbackWorkspaceId: workspaceId,
    );
    if (note.id.isEmpty) return null;
    return MyNotesCached(
      note,
      fromCache: true,
      cachedAt: nullableDateTimeField(decoded, const ['saved_at']),
    );
  }

  Future<void> saveNote({required String workspaceId, required MyNote note}) {
    return _write(workspaceId, _noteKey(note.id), {
      'saved_at': DateTime.now().toUtc().toIso8601String(),
      'note': myNoteToJson(note),
    });
  }

  Future<void> removeNote({
    required String workspaceId,
    required String noteId,
  }) {
    return _database.deleteKeyValue(
      scope: _scope(workspaceId),
      key: _noteKey(noteId),
    );
  }

  Future<MyNotesCached<List<MyNoteFolder>>?> readFolders({
    required String workspaceId,
  }) async {
    final decoded = await _read(workspaceId, _foldersKey);
    if (decoded == null) return null;
    return MyNotesCached(
      jsonMapList(decoded['folders'])
          .map(
            (item) =>
                myNoteFolderFromJson(item, fallbackWorkspaceId: workspaceId),
          )
          .where((folder) => folder.id.isNotEmpty)
          .toList(growable: false),
      fromCache: true,
      cachedAt: nullableDateTimeField(decoded, const ['saved_at']),
    );
  }

  Future<void> saveFolders({
    required String workspaceId,
    required List<MyNoteFolder> folders,
  }) {
    return _write(workspaceId, _foldersKey, {
      'saved_at': DateTime.now().toUtc().toIso8601String(),
      'folders': [for (final folder in folders) myNoteFolderToJson(folder)],
    });
  }

  Future<MyNotesCached<List<MyNoteTag>>?> readTags({
    required String workspaceId,
  }) async {
    final decoded = await _read(workspaceId, _tagsKey);
    if (decoded == null) return null;
    return MyNotesCached(
      jsonMapList(decoded['tags'])
          .map(myNoteTagFromJson)
          .where((tag) => tag.tag.isNotEmpty)
          .toList(growable: false),
      fromCache: true,
      cachedAt: nullableDateTimeField(decoded, const ['saved_at']),
    );
  }

  Future<void> saveTags({
    required String workspaceId,
    required List<MyNoteTag> tags,
  }) {
    return _write(workspaceId, _tagsKey, {
      'saved_at': DateTime.now().toUtc().toIso8601String(),
      'tags': [for (final tag in tags) myNoteTagToJson(tag)],
    });
  }

  Future<JsonMap?> _read(String workspaceId, String key) async {
    final value = await _database.readKeyValue(
      scope: _scope(workspaceId),
      key: key,
    );
    if (value == null) return null;
    try {
      return jsonMapOrNull(jsonDecode(value));
    } on FormatException {
      return null;
    }
  }

  Future<void> _write(String workspaceId, String key, JsonMap value) {
    return _database.putKeyValue(
      scope: _scope(workspaceId),
      key: key,
      value: jsonEncode(value),
    );
  }

  String _scope(String workspaceId) =>
      _instanceScope.localScope('my_notes:${workspaceId.trim()}');

  String _noteKey(String noteId) => 'note:${noteId.trim()}';
}
