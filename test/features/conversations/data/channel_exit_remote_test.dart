import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/core/database/app_database.dart';
import 'package:webtui_chat/core/network/api_transport.dart';
import 'package:webtui_chat/core/result/result.dart';
import 'package:webtui_chat/core/security/instance_scope.dart';
import 'package:webtui_chat/features/conversations/data/datasources/conversation_cache_data_source.dart';
import 'package:webtui_chat/features/conversations/data/datasources/conversation_remote_data_source.dart';
import 'package:webtui_chat/features/conversations/data/dto/conversation_dto.dart';
import 'package:webtui_chat/features/conversations/data/repositories/channel_exit_repository_impl.dart';
import 'package:webtui_chat/features/conversations/domain/entities/chat_message.dart';
import 'package:webtui_chat/features/conversations/domain/entities/conversation_summary.dart';

void main() {
  test('kênh: đọc can_leave / can_delete (có / thiếu / null)', () async {
    final transport = _RecordingTransport(
      getPayload: {
        'data': {
          'channels': [
            {
              'id': 'co-co',
              'workspace_id': 'ws',
              'name': 'Nhóm A',
              'type': 'private',
              'updated_at': '2026-11-16T08:00:00Z',
              'can_leave': true,
              'can_delete': true,
            },
            {
              'id': 'thieu',
              'workspace_id': 'ws',
              'name': 'Nhóm B',
              'type': 'private',
              'updated_at': '2026-11-16T08:00:00Z',
            },
            {
              'id': 'null',
              'workspace_id': 'ws',
              'name': 'Nhóm C',
              'type': 'private',
              'updated_at': '2026-11-16T08:00:00Z',
              'can_leave': null,
              'can_delete': null,
            },
            {
              'id': 'chi-roi',
              'workspace_id': 'ws',
              'name': 'Nhóm D',
              'type': 'private',
              'updated_at': '2026-11-16T08:00:00Z',
              'can_leave': true,
              'can_delete': false,
            },
          ],
        },
      },
    );
    final remote = ConversationRemoteDataSource(transport);

    final channels = await remote.listChannels(workspaceId: 'ws');
    final byId = {for (final channel in channels) channel.id: channel};

    expect(byId['co-co']!.canLeave, isTrue);
    expect(byId['co-co']!.canDelete, isTrue);
    expect(byId['thieu']!.canLeave, isFalse);
    expect(byId['thieu']!.canDelete, isFalse);
    expect(byId['null']!.canLeave, isFalse);
    expect(byId['null']!.canDelete, isFalse);
    expect(byId['chi-roi']!.canLeave, isTrue);
    expect(byId['chi-roi']!.canDelete, isFalse);
  });

  test('ChannelDto: đọc can_leave / can_delete, thiếu thì false', () {
    final withFlags = ChannelDto.fromJson({
      'id': 'c1',
      'workspace_id': 'ws',
      'name': 'Nhóm',
      'type': 'private',
      'can_leave': true,
      'can_delete': true,
    }).toDomain();
    final without = ChannelDto.fromJson({
      'id': 'c2',
      'workspace_id': 'ws',
      'name': 'Nhóm',
      'type': 'private',
    }).toDomain();

    expect(withFlags.canLeave, isTrue);
    expect(withFlags.canDelete, isTrue);
    expect(without.canLeave, isFalse);
    expect(without.canDelete, isFalse);
  });

  test('rời nhóm: POST .../channels/{id}/leave, đọc archived', () async {
    final transport = _RecordingTransport(
      postPayload: {
        'success': true,
        'data': {'channel_id': 'ch 1', 'status': 'left', 'archived': true},
      },
    );
    final remote = ConversationRemoteDataSource(transport);

    final result = await remote.leaveChannel(
      workspaceId: 'ws',
      channelId: 'ch 1',
    );

    expect(transport.postPath, '/api/v1/workspaces/ws/channels/ch%201/leave');
    expect(transport.deletePath, isNull);
    expect(result.channelId, 'ch 1');
    expect(result.archived, isTrue);
  });

  test('rời nhóm: máy chủ không trả archived thì coi là false', () async {
    final transport = _RecordingTransport(
      postPayload: {
        'success': true,
        'data': {'status': 'left'},
      },
    );
    final result = await ConversationRemoteDataSource(
      transport,
    ).leaveChannel(workspaceId: 'ws', channelId: 'ch-1');

    expect(result.channelId, 'ch-1');
    expect(result.archived, isFalse);
  });

  test('xoá nhóm: DELETE .../channels/{id}', () async {
    final transport = _RecordingTransport();
    await ConversationRemoteDataSource(
      transport,
    ).deleteChannel(workspaceId: 'ws', channelId: 'ch-1');

    expect(transport.deletePath, '/api/v1/workspaces/ws/channels/ch-1');
    expect(transport.postPath, isNull);
  });

  test('cache: lưu / đọc lại cờ canLeave / canDelete', () async {
    final database = AppDatabase(createInMemoryDriftConnection());
    addTearDown(database.close);
    final cache = ConversationCacheDataSource(database, _instance);

    await cache.saveChannels(
      workspaceId: 'ws',
      items: [_group('a', canLeave: true, canDelete: true), _group('b')],
    );
    final restored = await cache.readChannels(workspaceId: 'ws');

    expect(restored!.first.canLeave, isTrue);
    expect(restored.first.canDelete, isTrue);
    expect(restored.last.canLeave, isFalse);
    expect(restored.last.canDelete, isFalse);
  });

  test(
    'repository: rời / xoá thành công thì bỏ nhóm khỏi bộ nhớ đệm',
    () async {
      final database = AppDatabase(createInMemoryDriftConnection());
      addTearDown(database.close);
      final cache = ConversationCacheDataSource(database, _instance);
      await cache.saveChannels(
        workspaceId: 'ws',
        items: [_group('a'), _group('b'), _group('c')],
      );
      await cache.saveLatestMessagePage(
        workspaceId: 'ws',
        channelId: 'a',
        page: MessagePage(
          messages: [
            ChatMessage(
              id: 'm1',
              workspaceId: 'ws',
              channelId: 'a',
              kind: 'text',
              body: 'Chào',
              createdAt: DateTime.utc(2026, 11, 16),
            ),
          ],
        ),
      );
      final transport = _RecordingTransport(
        postPayload: {
          'data': {'channel_id': 'a', 'status': 'left', 'archived': false},
        },
      );
      final repository = ChannelExitRepositoryImpl(
        remote: ConversationRemoteDataSource(transport),
        cache: cache,
      );

      final left = await repository.leave(workspaceId: 'ws', channelId: 'a');
      expect(left, isA<Success<Object?>>());
      final deleted = await repository.delete(
        workspaceId: 'ws',
        channelId: 'b',
      );
      expect(deleted, isA<Success<Object?>>());

      final channels = await cache.readChannels(workspaceId: 'ws');
      expect(channels!.map((item) => item.channelId), ['c']);
      expect(
        await cache.readLatestMessagePage(workspaceId: 'ws', channelId: 'a'),
        isNull,
      );
    },
  );

  test('repository: máy chủ báo lỗi thì giữ nguyên bộ nhớ đệm', () async {
    final database = AppDatabase(createInMemoryDriftConnection());
    addTearDown(database.close);
    final cache = ConversationCacheDataSource(database, _instance);
    await cache.saveChannels(workspaceId: 'ws', items: [_group('a')]);
    final repository = ChannelExitRepositoryImpl(
      remote: ConversationRemoteDataSource(_RecordingTransport(failWith: 403)),
      cache: cache,
    );

    final result = await repository.delete(workspaceId: 'ws', channelId: 'a');

    expect(result, isA<FailureResult<void>>());
    final channels = await cache.readChannels(workspaceId: 'ws');
    expect(channels!.map((item) => item.channelId), ['a']);
  });
}

final _instance = InstanceScope(
  instanceId: '11111111-1111-4111-8111-111111111111',
  serverOrigin: Uri.parse('https://one.example'),
);

ConversationSummary _group(
  String id, {
  bool canLeave = false,
  bool canDelete = false,
}) {
  return ConversationSummary(
    id: id,
    workspaceId: 'ws',
    channelId: id,
    kind: ConversationKind.channel,
    title: 'Nhóm $id',
    preview: '',
    updatedAt: DateTime.utc(2026, 11, 16),
    channelVisibility: ChannelVisibility.private,
    membershipStatus: MembershipStatus.active,
    canLeave: canLeave,
    canDelete: canDelete,
  );
}

final class _RecordingTransport implements ApiTransport {
  _RecordingTransport({this.getPayload, this.postPayload, this.failWith});

  final Object? getPayload;
  final Object? postPayload;
  final int? failWith;
  String? postPath;
  String? deletePath;

  Response<T> _respond<T>(String path, Object? payload) {
    final status = failWith;
    if (status != null) {
      final options = RequestOptions(path: path);
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.badResponse,
        response: Response<Object?>(
          requestOptions: options,
          statusCode: status,
          data: {
            'success': false,
            'error': {
              'code': 'FORBIDDEN',
              'message': 'Bạn không có quyền xoá nhóm này.',
            },
          },
        ),
      );
    }
    return Response<T>(
      data: payload as T,
      requestOptions: RequestOptions(path: path),
    );
  }

  @override
  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async => _respond<T>(path, getPayload);

  @override
  Future<Response<T>> post<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    postPath = path;
    return _respond<T>(path, postPayload);
  }

  @override
  Future<Response<T>> delete<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    deletePath = path;
    return _respond<T>(path, const {'success': true});
  }

  @override
  Future<Response<T>> patch<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) => throw UnimplementedError();

  @override
  Future<Response<T>> put<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) => throw UnimplementedError();
}
