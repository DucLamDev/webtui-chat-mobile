import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/core/database/app_database.dart';
import 'package:webtui_chat/core/error/failure.dart';
import 'package:webtui_chat/core/network/api_transport.dart';
import 'package:webtui_chat/core/security/instance_scope.dart';
import 'package:webtui_chat/features/my_notes/data/datasources/my_notes_cache_data_source.dart';
import 'package:webtui_chat/features/my_notes/data/datasources/my_notes_remote_data_source.dart';
import 'package:webtui_chat/features/my_notes/data/repositories/my_notes_repository_impl.dart';
import 'package:webtui_chat/features/my_notes/domain/entities/my_note.dart';

void main() {
  late AppDatabase database;
  late _ScriptedApiTransport api;
  final scopeA = InstanceScope(
    instanceId: '11111111-1111-4111-8111-111111111111',
    serverOrigin: Uri.parse('https://a.example.com'),
  );
  final scopeB = InstanceScope(
    instanceId: '22222222-2222-4222-8222-222222222222',
    serverOrigin: Uri.parse('https://b.example.com'),
  );

  MyNotesRepositoryImpl repositoryFor(InstanceScope scope) {
    return MyNotesRepositoryImpl(
      remote: MyNotesRemoteDataSource(api),
      cache: MyNotesCacheDataSource(database, scope),
    );
  }

  setUp(() {
    database = AppDatabase(createInMemoryDriftConnection());
    api = _ScriptedApiTransport();
  });

  tearDown(() => database.close());

  test('falls back to the cached default list when offline', () async {
    final repository = repositoryFor(scopeA);
    api.next = _ok({
      'data': {
        'notes': [
          _noteJson('note-old', updatedAt: '2026-11-01T00:00:00Z'),
          _noteJson(
            'note-pinned',
            pinned: true,
            updatedAt: '2026-10-01T00:00:00Z',
          ),
        ],
      },
      'meta': {'has_more': false},
    });

    final online = await repository.listNotes(workspaceId: 'ws-1');
    expect(online.valueOrNull?.fromCache, isFalse);

    api.next = _offline();
    final offline = await repository.listNotes(workspaceId: 'ws-1');

    final cached = offline.valueOrNull!;
    expect(cached.fromCache, isTrue);
    expect(cached.cachedAt, isNotNull);
    expect(cached.value.notes.map((note) => note.id), [
      'note-pinned',
      'note-old',
    ]);
    expect(cached.value.hasMore, isFalse);
  });

  test('filtered lists are not served from the cache', () async {
    final repository = repositoryFor(scopeA);
    api.next = _ok({
      'data': {
        'notes': [_noteJson('note-1')],
      },
    });
    await repository.listNotes(workspaceId: 'ws-1');

    api.next = _offline();
    final result = await repository.listNotes(
      workspaceId: 'ws-1',
      filter: const MyNoteFilter(tag: 'việc'),
    );

    expect(result.failureOrNull?.kind, FailureKind.network);
  });

  test('cache is scoped by instance and workspace', () async {
    api.next = _ok({
      'data': {
        'notes': [_noteJson('note-1')],
      },
    });
    await repositoryFor(scopeA).listNotes(workspaceId: 'ws-1');

    api.next = _offline();
    final otherWorkspace = await repositoryFor(
      scopeA,
    ).listNotes(workspaceId: 'ws-2');
    expect(otherWorkspace.isFailure, isTrue);

    api.next = _offline();
    final otherInstance = await repositoryFor(
      scopeB,
    ).listNotes(workspaceId: 'ws-1');
    expect(otherInstance.isFailure, isTrue);
  });

  test('opened notes stay readable offline and are forgotten on 404', () async {
    final repository = repositoryFor(scopeA);
    api.next = _ok({
      'data': {'note': _noteJson('note-1', body: 'Nội dung đầy đủ')},
    });
    await repository.getNote(workspaceId: 'ws-1', noteId: 'note-1');

    api.next = _offline();
    final offline = await repository.getNote(
      workspaceId: 'ws-1',
      noteId: 'note-1',
    );
    expect(offline.valueOrNull?.fromCache, isTrue);
    expect(offline.valueOrNull?.value.body, 'Nội dung đầy đủ');

    api.next = _status(404, 'NOTE_NOT_FOUND', 'Không tìm thấy ghi chú.');
    final missing = await repository.getNote(
      workspaceId: 'ws-1',
      noteId: 'note-1',
    );
    expect(missing.failureOrNull?.kind, FailureKind.notFound);

    api.next = _offline();
    final afterDelete = await repository.getNote(
      workspaceId: 'ws-1',
      noteId: 'note-1',
    );
    expect(afterDelete.isFailure, isTrue);
  });

  test('writes fail clearly while offline and are not queued', () async {
    final repository = repositoryFor(scopeA);
    api.next = _offline();

    final result = await repository.createNote(
      workspaceId: 'ws-1',
      title: 'Ghi chú',
      body: 'Nội dung',
    );

    final failure = result.failureOrNull!;
    expect(failure.code, 'MY_NOTES_OFFLINE');
    expect(failure.message, myNotesOfflineWriteMessage);
    expect(api.calls, 1);

    api.next = _offline();
    final cached = await repository.listNotes(workspaceId: 'ws-1');
    expect(cached.isFailure, isTrue, reason: 'không có bản tạm chờ gửi');
  });

  test('successful writes update the offline copy', () async {
    final repository = repositoryFor(scopeA);
    api.next = _ok({
      'data': {
        'notes': [_noteJson('note-1')],
      },
    });
    await repository.listNotes(workspaceId: 'ws-1');

    api.next = _ok({
      'data': {
        'note': _noteJson(
          'note-2',
          title: 'Mới',
          updatedAt: '2026-11-09T00:00:00Z',
        ),
      },
    });
    await repository.createNote(
      workspaceId: 'ws-1',
      title: 'Mới',
      body: 'Nội dung',
    );

    api.next = _ok(null);
    await repository.deleteNote(workspaceId: 'ws-1', noteId: 'note-1');

    api.next = _offline();
    final cached = await repository.listNotes(workspaceId: 'ws-1');
    expect(cached.valueOrNull?.value.notes.map((note) => note.id), ['note-2']);
    api.next = _offline();
    final created = await repository.getNote(
      workspaceId: 'ws-1',
      noteId: 'note-2',
    );
    expect(created.valueOrNull?.value.title, 'Mới');
  });

  test('folders and tags are cached for offline filters', () async {
    final repository = repositoryFor(scopeA);
    api.next = _ok({
      'data': {
        'folders': [
          {'id': 'folder-1', 'name': 'Công việc', 'note_count': 2},
        ],
      },
    });
    await repository.listFolders(workspaceId: 'ws-1');
    api.next = _ok({
      'data': {
        'tags': [
          {'tag': 'việc', 'count': 2},
        ],
      },
    });
    await repository.listTags(workspaceId: 'ws-1');

    api.next = _offline();
    final folders = await repository.listFolders(workspaceId: 'ws-1');
    api.next = _offline();
    final tags = await repository.listTags(workspaceId: 'ws-1');

    expect(folders.valueOrNull?.fromCache, isTrue);
    expect(folders.valueOrNull?.value.single.name, 'Công việc');
    expect(tags.valueOrNull?.value.single.tag, 'việc');
  });
}

Map<String, Object?> _noteJson(
  String id, {
  String title = 'Ghi chú',
  String body = 'Nội dung',
  bool pinned = false,
  String updatedAt = '2026-11-01T00:00:00Z',
}) {
  return {
    'id': id,
    'workspace_id': 'ws-1',
    'folder_id': null,
    'title': title,
    'body': body,
    'tags': ['việc'],
    'pinned': pinned,
    'version': 1,
    'created_at': '2026-10-01T00:00:00Z',
    'updated_at': updatedAt,
  };
}

typedef _Reply = Response<Object?> Function(RequestOptions options);

_Reply _ok(Map<String, Object?>? body) {
  return (options) => Response<Object?>(
    data: body == null ? null : {'success': true, ...body},
    requestOptions: options,
    statusCode: body == null ? 204 : 200,
  );
}

_Reply _offline() {
  return (options) => throw DioException(
    requestOptions: options,
    type: DioExceptionType.connectionError,
  );
}

_Reply _status(int status, String code, String message) {
  return (options) => throw DioException(
    requestOptions: options,
    type: DioExceptionType.badResponse,
    response: Response<Object?>(
      requestOptions: options,
      statusCode: status,
      data: {
        'success': false,
        'error': {'code': code, 'message': message},
      },
    ),
  );
}

final class _ScriptedApiTransport implements ApiTransport {
  _Reply? next;
  int calls = 0;

  Future<Response<T>> _reply<T>(String path) async {
    calls++;
    final reply = next;
    next = null;
    if (reply == null) {
      throw StateError('Chưa đặt phản hồi cho $path');
    }
    final response = reply(RequestOptions(path: path));
    return Response<T>(
      data: response.data as T?,
      requestOptions: response.requestOptions,
      statusCode: response.statusCode,
    );
  }

  @override
  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) => _reply(path);

  @override
  Future<Response<T>> post<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) => _reply(path);

  @override
  Future<Response<T>> patch<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) => _reply(path);

  @override
  Future<Response<T>> delete<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) => _reply(path);

  @override
  Future<Response<T>> put<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) => _reply(path);
}
