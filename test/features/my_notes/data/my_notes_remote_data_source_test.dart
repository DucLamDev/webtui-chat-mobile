import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/core/network/api_transport.dart';
import 'package:webtui_chat/features/my_notes/data/datasources/my_notes_remote_data_source.dart';
import 'package:webtui_chat/features/my_notes/domain/entities/my_note.dart';

void main() {
  const base = '/api/v1/workspaces/ws%2F1/me';

  test('lists notes with every filter and reads the cursor meta', () async {
    final api = _RecordingApiTransport(
      responseData: {
        'success': true,
        'data': {
          'notes': [
            {
              'id': 'note-1',
              'workspace_id': 'ws/1',
              'folder_id': null,
              'title': 'Họp tuần',
              'excerpt': 'Chốt kế hoạch',
              'tags': ['việc', 'họp'],
              'pinned': true,
              'version': 3,
              'source_channel_id': 'channel-1',
              'source_message_id': 'message-1',
              'attachment_count': 2,
              'created_at': '2026-11-01T00:00:00Z',
              'updated_at': '2026-11-02T00:00:00Z',
            },
          ],
        },
        'meta': {'next_cursor': 'cursor-2', 'has_more': true},
      },
    );
    final remote = MyNotesRemoteDataSource(api);

    final page = await remote.listNotes(
      workspaceId: 'ws/1',
      filter: const MyNoteFilter(
        folderId: 'folder-1',
        tag: 'việc',
        query: '  kế hoạch ',
        pinnedOnly: true,
      ),
      cursor: 'cursor-1',
      limit: 20,
    );

    expect(api.method, 'GET');
    expect(api.path, '$base/notes');
    expect(api.queryParameters, {
      'folder_id': 'folder-1',
      'tag': 'việc',
      'q': 'kế hoạch',
      'pinned': 'true',
      'limit': 20,
      'cursor': 'cursor-1',
    });
    expect(page.nextCursor, 'cursor-2');
    expect(page.hasMore, isTrue);
    final note = page.notes.single;
    expect(note.title, 'Họp tuần');
    expect(note.folderId, isNull);
    expect(note.tags, ['việc', 'họp']);
    expect(note.pinned, isTrue);
    expect(note.version, 3);
    expect(note.isFromMessage, isTrue);
    expect(note.attachmentCount, 2);
  });

  test('default list only sends the limit', () async {
    final api = _RecordingApiTransport(
      responseData: {
        'success': true,
        'data': {'notes': <Object>[]},
        'meta': {'has_more': false},
      },
    );

    final page = await MyNotesRemoteDataSource(
      api,
    ).listNotes(workspaceId: 'ws/1');

    expect(api.queryParameters, {'limit': MyNoteLimits.pageSize});
    expect(page.notes, isEmpty);
    expect(page.hasMore, isFalse);
  });

  test('creates, reads and deletes a note on the owner routes', () async {
    final api = _RecordingApiTransport(
      responseData: {
        'success': true,
        'data': {
          'note': {
            'id': 'note-1',
            'workspace_id': 'ws/1',
            'folder_id': 'folder-1',
            'title': 'Ý tưởng',
            'body': '# Tiêu đề\nNội dung',
            'tags': ['ý tưởng'],
            'pinned': false,
            'version': 1,
            'attachments': [
              {
                'file_id': 'file-1',
                'original_name': 'anh.png',
                'mime_type': 'image/png',
                'byte_size': 2048,
                'created_at': '2026-11-01T00:00:00Z',
              },
            ],
            'created_at': '2026-11-01T00:00:00Z',
            'updated_at': '2026-11-01T00:00:00Z',
          },
        },
      },
    );
    final remote = MyNotesRemoteDataSource(api);

    final created = await remote.createNote(
      workspaceId: 'ws/1',
      title: 'Ý tưởng',
      body: '# Tiêu đề\nNội dung',
      tags: const ['ý tưởng'],
      folderId: ' folder-1 ',
    );
    expect(api.method, 'POST');
    expect(api.path, '$base/notes');
    expect(api.data, {
      'title': 'Ý tưởng',
      'body': '# Tiêu đề\nNội dung',
      'tags': ['ý tưởng'],
      'pinned': false,
      'folder_id': 'folder-1',
    });
    expect(created.body, '# Tiêu đề\nNội dung');
    expect(created.attachments.single.originalName, 'anh.png');
    expect(created.attachmentCount, 1);

    await remote.getNote(workspaceId: 'ws/1', noteId: 'note/1');
    expect(api.method, 'GET');
    expect(api.path, '$base/notes/note%2F1');

    await remote.deleteNote(workspaceId: 'ws/1', noteId: 'note-1');
    expect(api.method, 'DELETE');
    expect(api.path, '$base/notes/note-1');
  });

  test(
    'patch sends version and folder_id null to move a note to the root',
    () async {
      final api = _RecordingApiTransport(
        responseData: {
          'success': true,
          'data': {
            'note': {'id': 'note-1', 'title': 'A', 'body': '', 'version': 5},
          },
        },
      );

      final note = await MyNotesRemoteDataSource(api).updateNote(
        workspaceId: 'ws/1',
        noteId: 'note-1',
        version: 4,
        patch: const MyNotePatch(pinned: true, moveToRoot: true),
      );

      expect(api.method, 'PATCH');
      expect(api.path, '$base/notes/note-1');
      expect(api.data, {'version': 4, 'pinned': true, 'folder_id': null});
      expect(note.version, 5);
      expect(note.workspaceId, 'ws/1');
    },
  );

  test('saves a message and reads the created flag', () async {
    final api = _RecordingApiTransport(
      statusCode: 200,
      responseData: {
        'success': true,
        'data': {
          'note': {
            'id': 'note-9',
            'title': 'Tin nhắn đã lưu',
            'body': 'Xin chào',
            'version': 1,
            'source_channel_id': 'channel-1',
            'source_message_id': 'message-1',
          },
          'created': false,
        },
      },
    );

    final saved = await MyNotesRemoteDataSource(api).saveMessage(
      workspaceId: 'ws/1',
      channelId: ' channel-1 ',
      messageId: 'message-1',
    );

    expect(api.method, 'POST');
    expect(api.path, '$base/notes/from-message');
    expect(api.data, {'channel_id': 'channel-1', 'message_id': 'message-1'});
    expect(saved.created, isFalse);
    expect(saved.note.id, 'note-9');
    expect(saved.note.sourceMessageId, 'message-1');
  });

  test('attachment routes encode ids', () async {
    final api = _RecordingApiTransport(
      responseData: {
        'success': true,
        'data': {
          'attachment': {
            'file_id': 'file/1',
            'original_name': 'bao-cao.pdf',
            'mime_type': 'application/pdf',
            'byte_size': 10,
          },
        },
      },
    );
    final remote = MyNotesRemoteDataSource(api);

    final attachment = await remote.addAttachment(
      workspaceId: 'ws/1',
      noteId: 'note-1',
      fileId: 'file/1',
    );
    expect(api.method, 'POST');
    expect(api.path, '$base/notes/note-1/attachments');
    expect(api.data, {'file_id': 'file/1'});
    expect(attachment.fileId, 'file/1');

    await remote.removeAttachment(
      workspaceId: 'ws/1',
      noteId: 'note-1',
      fileId: 'file/1',
    );
    expect(api.method, 'DELETE');
    expect(api.path, '$base/notes/note-1/attachments/file%2F1');
  });

  test('folder and tag routes', () async {
    final api = _RecordingApiTransport(
      responseData: {
        'success': true,
        'data': {
          'folders': [
            {
              'id': 'folder-1',
              'parent_id': null,
              'name': 'Công việc',
              'position': 1,
              'note_count': 4,
            },
          ],
          'folder': {'id': 'folder-2', 'parent_id': 'folder-1', 'name': 'Con'},
          'tags': [
            {'tag': 'việc', 'count': 3},
          ],
        },
      },
    );
    final remote = MyNotesRemoteDataSource(api);

    final folders = await remote.listFolders(workspaceId: 'ws/1');
    expect(api.path, '$base/note-folders');
    expect(folders.single.noteCount, 4);

    final created = await remote.createFolder(
      workspaceId: 'ws/1',
      name: 'Con',
      parentId: 'folder-1',
    );
    expect(api.method, 'POST');
    expect(api.path, '$base/note-folders');
    expect(api.data, {'name': 'Con', 'parent_id': 'folder-1'});
    expect(created.parentId, 'folder-1');

    await remote.updateFolder(
      workspaceId: 'ws/1',
      folderId: 'folder-2',
      name: 'Đổi tên',
    );
    expect(api.method, 'PATCH');
    expect(api.path, '$base/note-folders/folder-2');
    expect(api.data, {'name': 'Đổi tên'});

    await remote.updateFolder(
      workspaceId: 'ws/1',
      folderId: 'folder-2',
      moveToRoot: true,
    );
    expect(api.data, {'parent_id': null});

    await remote.deleteFolder(workspaceId: 'ws/1', folderId: 'folder-2');
    expect(api.method, 'DELETE');
    expect(api.path, '$base/note-folders/folder-2');

    final tags = await remote.listTags(workspaceId: 'ws/1');
    expect(api.method, 'GET');
    expect(api.path, '$base/note-tags');
    expect(tags.single.tag, 'việc');
    expect(tags.single.count, 3);
  });
}

final class _RecordingApiTransport implements ApiTransport {
  _RecordingApiTransport({this.responseData, this.statusCode = 200});

  final Object? responseData;
  final int statusCode;
  String? method;
  String? path;
  Object? data;
  Map<String, dynamic>? queryParameters;

  Response<T> _record<T>(
    String method,
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
  }) {
    this.method = method;
    this.path = path;
    this.data = data;
    this.queryParameters = queryParameters;
    return Response<T>(
      data: responseData as T?,
      requestOptions: RequestOptions(path: path),
      statusCode: statusCode,
    );
  }

  @override
  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async => _record('GET', path, queryParameters: queryParameters);

  @override
  Future<Response<T>> post<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async => _record('POST', path, data: data);

  @override
  Future<Response<T>> patch<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async => _record('PATCH', path, data: data);

  @override
  Future<Response<T>> delete<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async => _record('DELETE', path, data: data);

  @override
  Future<Response<T>> put<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) => throw UnimplementedError();
}
