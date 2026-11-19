import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/core/error/failure.dart';
import 'package:webtui_chat/core/network/api_transport.dart';
import 'package:webtui_chat/features/conversations/data/datasources/conversation_remote_data_source.dart';
import 'package:webtui_chat/features/conversations/data/repositories/conversation_repository_impl.dart';

void main() {
  test(
    'đọc trang luồng thay đổi: tin, bia mộ, tệp, cleared_at, meta',
    () async {
      final transport = _RecordingTransport({
        'success': true,
        'data': {
          'messages': [
            {
              'id': 'm1',
              'workspace_id': 'w1',
              'channel_id': 'c1',
              'sender_id': 'u1',
              'kind': 'text',
              'body': 'đã sửa',
              'created_at': '2026-11-18T08:00:00.123456Z',
              'edited_at': '2026-11-19T01:00:00Z',
              'updated_at': '2026-11-19T01:00:00Z',
              'reactions': [
                {'emoji': '👍', 'count': 2, 'reacted_by_me': true},
              ],
              'attachments': [
                {
                  'id': 'a1',
                  'workspace_id': 'w1',
                  'message_id': 'm1',
                  'file_id': 'f1',
                  'created_at': '2026-11-18T08:00:00Z',
                  'file': {
                    'id': 'f1',
                    'name': 'bao-cao.pdf',
                    'mime_type': 'application/pdf',
                    'byte_size': 10,
                    'created_at': '2026-11-18T08:00:00Z',
                  },
                },
              ],
            },
            {
              'id': 'm2',
              'workspace_id': 'w1',
              'channel_id': 'c1',
              'kind': 'text',
              'body': '',
              'created_at': '2026-11-18T09:00:00Z',
              'deleted_at': '2026-11-19T02:00:00Z',
              'updated_at': '2026-11-19T02:00:00Z',
              'attachments': [],
            },
          ],
          'cleared_at': '2026-11-01T00:00:00Z',
        },
        'meta': {'has_more': true, 'next_cursor': 'cur-2'},
      });
      final remote = ConversationRemoteDataSource(transport);

      final page = await remote.listMessageChanges(
        workspaceId: 'w1',
        channelId: 'c1',
        since: 'cur-1',
        limit: 500,
      );

      expect(
        transport.lastPath,
        '/api/v1/workspaces/w1/channels/c1/messages/changes',
      );
      expect(transport.lastQuery, {'since': 'cur-1', 'limit': 200});
      expect(page.nextCursor, 'cur-2');
      expect(page.hasMore, isTrue);
      expect(page.clearedAt, DateTime.utc(2026, 11, 1));
      expect(page.messages, hasLength(2));
      final edited = page.messages.first;
      expect(edited.body, 'đã sửa');
      expect(edited.isDeleted, isFalse);
      expect(edited.createdAt, DateTime.utc(2026, 11, 18, 8, 0, 0, 123, 456));
      expect(edited.attachmentsIncluded, isTrue);
      expect(edited.attachments.single.file.name, 'bao-cao.pdf');
      expect(edited.reactions.single.count, 2);
      final tombstone = page.messages.last;
      expect(tombstone.isDeleted, isTrue);
      expect(tombstone.body, isEmpty);
    },
  );

  test(
    'since rỗng: không gửi since, trả mốc bắt đầu; cleared_at null',
    () async {
      final transport = _RecordingTransport({
        'success': true,
        'data': {'messages': <Object>[], 'cleared_at': null},
        'meta': {'has_more': false, 'next_cursor': 'start'},
      });
      final remote = ConversationRemoteDataSource(transport);

      final page = await remote.listMessageChanges(
        workspaceId: 'w1',
        channelId: 'c1',
        since: '',
      );

      expect(transport.lastQuery, {'limit': 200});
      expect(page.messages, isEmpty);
      expect(page.nextCursor, 'start');
      expect(page.hasMore, isFalse);
      expect(page.clearedAt, isNull);
    },
  );

  test('thiếu next_cursor là lỗi dữ liệu', () async {
    final repository = ConversationRepositoryImpl(
      ConversationRemoteDataSource(
        _RecordingTransport({
          'success': true,
          'data': {'messages': <Object>[]},
          'meta': {'has_more': false},
        }),
      ),
    );

    final result = await repository.listMessageChanges(
      workspaceId: 'w1',
      channelId: 'c1',
    );

    expect(result.failureOrNull?.kind, FailureKind.decoding);
  });

  test('máy chủ cũ trả 404 → FailureKind.notFound', () async {
    final repository = ConversationRepositoryImpl(
      ConversationRemoteDataSource(_NotFoundTransport()),
    );

    final result = await repository.listMessageChanges(
      workspaceId: 'w1',
      channelId: 'c1',
    );

    expect(result.failureOrNull?.kind, FailureKind.notFound);
  });
}

final class _RecordingTransport implements ApiTransport {
  _RecordingTransport(this.payload);

  final Object payload;
  String? lastPath;
  Map<String, dynamic>? lastQuery;

  @override
  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    lastPath = path;
    lastQuery = queryParameters;
    return Response<T>(
      data: payload as T,
      requestOptions: RequestOptions(path: path),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _NotFoundTransport implements ApiTransport {
  @override
  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    final request = RequestOptions(path: path);
    throw DioException(
      requestOptions: request,
      type: DioExceptionType.badResponse,
      response: Response<Object>(
        requestOptions: request,
        statusCode: 404,
        data: {
          'success': false,
          'error': {'code': 'NOT_FOUND', 'message': 'not found'},
        },
      ),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
