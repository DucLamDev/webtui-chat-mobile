import 'dart:io';

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
  late Directory tempDir;
  late MyNoteLocalFile photo;
  late _UploadApiTransport api;
  late AppDatabase database;
  late MyNotesRepositoryImpl repository;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('my_note_upload_');
    final file = File('${tempDir.path}/anh.jpg');
    await file.writeAsBytes(List<int>.filled(64, 7));
    photo = MyNoteLocalFile(
      path: file.path,
      name: 'anh.jpg',
      mimeType: 'image/jpeg',
      byteSize: 64,
    );
    api = _UploadApiTransport();
    database = AppDatabase(createInMemoryDriftConnection());
    repository = MyNotesRepositoryImpl(
      remote: MyNotesRemoteDataSource(api),
      cache: MyNotesCacheDataSource(
        database,
        InstanceScope(
          instanceId: '11111111-1111-4111-8111-111111111111',
          serverOrigin: Uri.parse('https://a.example.com'),
        ),
      ),
    );
  });

  tearDown(() async {
    await database.close();
    await tempDir.delete(recursive: true);
  });

  test('tải tệp lên bằng multipart đúng đường API và trả file_id', () async {
    api.reply = (options) => Response<Object?>(
      requestOptions: options,
      statusCode: 201,
      data: {
        'success': true,
        'data': {
          'id': 'file-1',
          'original_name': 'anh.jpg',
          'mime_type': 'image/jpeg',
          'byte_size': 64,
          'status': 'ready',
          'created_at': '2026-11-16T00:00:00Z',
        },
      },
    );
    final progress = <double>[];

    final fileId = await MyNotesRemoteDataSource(
      api,
    ).uploadFile(workspaceId: 'ws/1', file: photo, onProgress: progress.add);

    expect(fileId, 'file-1');
    expect(api.path, '/api/v1/workspaces/ws%2F1/files');
    expect(api.options?.contentType, Headers.multipartFormDataContentType);
    final form = api.data! as FormData;
    final part = form.files.single;
    expect(part.key, 'file');
    expect(part.value.filename, 'anh.jpg');
    expect(part.value.contentType.toString(), 'image/jpeg');
    expect(part.value.length, 64);
    expect(progress.last, 1);
  });

  test('gắn tệp vào ghi chú gửi file_id tới đường attachments', () async {
    api.reply = (options) => Response<Object?>(
      requestOptions: options,
      statusCode: 201,
      data: {
        'success': true,
        'data': {
          'file_id': 'file-1',
          'original_name': 'anh.jpg',
          'mime_type': 'image/jpeg',
          'byte_size': 64,
          'created_at': '2026-11-16T00:00:00Z',
        },
      },
    );

    final attachment = await MyNotesRemoteDataSource(
      api,
    ).addAttachment(workspaceId: 'ws-1', noteId: 'note-1', fileId: 'file-1');

    expect(api.path, '/api/v1/workspaces/ws-1/me/notes/note-1/attachments');
    expect(api.data, {'file_id': 'file-1'});
    expect(attachment.isImage, isTrue);
  });

  test('413 từ máy chủ / proxy thành câu "tệp quá lớn" dễ hiểu', () async {
    api.reply = (options) => throw DioException(
      requestOptions: options,
      type: DioExceptionType.badResponse,
      response: Response<Object?>(
        requestOptions: options,
        statusCode: 413,
        data: '<html>413 Request Entity Too Large</html>',
      ),
    );

    final result = await repository.uploadFile(
      workspaceId: 'ws-1',
      file: photo,
    );

    final failure = result.failureOrNull!;
    expect(failure.code, 'MY_NOTE_FILE_TOO_LARGE');
    expect(failure.kind, FailureKind.validation);
    expect(failure.message, contains('100 MB'));
  });

  test('mất mạng khi tải lên báo đang ngoại tuyến', () async {
    api.reply = (options) => throw DioException(
      requestOptions: options,
      type: DioExceptionType.connectionError,
    );

    final result = await repository.uploadFile(
      workspaceId: 'ws-1',
      file: photo,
    );

    expect(result.failureOrNull?.code, 'MY_NOTES_OFFLINE');
    expect(result.failureOrNull?.message, myNotesOfflineWriteMessage);
  });

  test('403 giữ loại forbidden để use case báo thiếu quyền', () async {
    api.reply = (options) => throw DioException(
      requestOptions: options,
      type: DioExceptionType.badResponse,
      response: Response<Object?>(
        requestOptions: options,
        statusCode: 403,
        data: {
          'success': false,
          'error': {'code': 'FORBIDDEN', 'message': 'Không có quyền.'},
        },
      ),
    );

    final result = await repository.uploadFile(
      workspaceId: 'ws-1',
      file: photo,
    );

    expect(result.failureOrNull?.kind, FailureKind.forbidden);
  });

  test('tệp trên máy đã mất thì báo chọn lại, không gọi máy chủ', () async {
    final missing = MyNoteLocalFile(
      path: '${tempDir.path}/khong-co.jpg',
      name: 'khong-co.jpg',
      mimeType: 'image/jpeg',
      byteSize: 64,
    );

    final result = await repository.uploadFile(
      workspaceId: 'ws-1',
      file: missing,
    );

    expect(result.failureOrNull?.code, 'MY_NOTE_FILE_UNREADABLE');
    expect(api.calls, 0);
  });

  test('nhận biết ảnh theo mime hoặc đuôi tên', () {
    MyNoteAttachment item(String mime, String name) => MyNoteAttachment(
      fileId: 'f',
      originalName: name,
      mimeType: mime,
      byteSize: 1,
      createdAt: DateTime.utc(2026),
    );
    expect(item('image/heic', 'a.heic').isImage, isTrue);
    expect(item('image/heic', 'a.heic').hasServerThumbnail, isFalse);
    expect(item('image/webp', 'a.webp').hasServerThumbnail, isTrue);
    expect(item('', 'a.PNG').isImage, isTrue);
    expect(item('application/octet-stream', 'a.gif').isImage, isTrue);
    expect(item('image/svg+xml', 'a.svg').isImage, isFalse);
    expect(item('application/pdf', 'a.pdf').isImage, isFalse);
    expect(myNoteMimeTypeForName('Bao cao.DOCX'), contains('wordprocessing'));
    expect(myNoteMimeTypeForName('khong-duoi'), 'application/octet-stream');
  });
}

typedef _Reply = Response<Object?> Function(RequestOptions options);

final class _UploadApiTransport implements ApiTransport {
  _Reply? reply;
  int calls = 0;
  String? path;
  Object? data;
  Options? options;

  Future<Response<T>> _record<T>(String path, Object? data, Options? options) {
    calls++;
    this.path = path;
    this.data = data;
    this.options = options;
    final handler = reply;
    if (handler == null) throw StateError('Chưa đặt phản hồi cho $path');
    final response = handler(RequestOptions(path: path));
    return Future.value(
      Response<T>(
        data: response.data as T?,
        requestOptions: response.requestOptions,
        statusCode: response.statusCode,
      ),
    );
  }

  @override
  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) => _record(path, null, options);

  @override
  Future<Response<T>> post<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) => _record(path, data, options);

  @override
  Future<Response<T>> put<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) => _record(path, data, options);

  @override
  Future<Response<T>> patch<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) => _record(path, data, options);

  @override
  Future<Response<T>> delete<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) => _record(path, data, options);
}
