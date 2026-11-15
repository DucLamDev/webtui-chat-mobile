import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/core/network/api_transport.dart';
import 'package:webtui_chat/features/conversations/data/datasources/conversation_remote_data_source.dart';

void main() {
  test('direct conversations use last message time as updatedAt', () async {
    final remote = ConversationRemoteDataSource(
      _FakeApiTransport({
        'data': {
          'direct_conversations': [
            {
              'id': 'direct-1',
              'workspace_id': 'workspace-1',
              'channel_id': 'channel-1',
              'updated_at': '2026-07-10T08:00:00Z',
              'participants': [
                {'user_id': 'user-2', 'display_name': 'Lam Duc'},
              ],
              'last_message': {
                'id': 'message-1',
                'body': 'xin chao',
                'created_at': '2026-07-21T09:30:00Z',
              },
            },
          ],
        },
      }),
    );

    final conversations = await remote.listDirectConversations(
      workspaceId: 'workspace-1',
    );

    expect(conversations, hasLength(1));
    expect(conversations.single.updatedAt, DateTime.utc(2026, 7, 21, 9, 30));
  });

  test(
    'kênh: đọc last_message_at, thiếu / null thì coi như chưa có tin',
    () async {
      final remote = ConversationRemoteDataSource(
        _FakeApiTransport({
          'data': {
            'channels': [
              {
                'id': 'co-tin',
                'workspace_id': 'workspace-1',
                'name': 'Dự án A',
                'updated_at': '2026-07-10T08:00:00Z',
                'last_message_at': '2026-07-21T09:30:00Z',
                'membership_status': 'active',
              },
              {
                'id': 'tin-null',
                'workspace_id': 'workspace-1',
                'name': 'Dự án B',
                'updated_at': '2026-07-10T08:00:00Z',
                'last_message_at': null,
                'membership_status': 'active',
              },
              {
                // Máy chủ cũ: không có trường last_message_at.
                'id': 'may-chu-cu',
                'workspace_id': 'workspace-1',
                'name': 'Dự án C',
                'updated_at': '2026-07-10T08:00:00Z',
                'membership_status': 'active',
              },
            ],
          },
        }),
      );

      final channels = await remote.listChannels(workspaceId: 'workspace-1');
      final byId = {for (final channel in channels) channel.id: channel};

      expect(byId['co-tin']!.lastMessageAt, DateTime.utc(2026, 7, 21, 9, 30));
      expect(byId['co-tin']!.hasMessages, isTrue);
      // Có tin thì xếp / hiện giờ theo tin cuối.
      expect(byId['co-tin']!.updatedAt, DateTime.utc(2026, 7, 21, 9, 30));
      for (final id in ['tin-null', 'may-chu-cu']) {
        expect(byId[id]!.lastMessageAt, isNull, reason: id);
        expect(byId[id]!.hasMessages, isFalse, reason: id);
        expect(byId[id]!.updatedAt, DateTime.utc(2026, 7, 10, 8), reason: id);
      }
    },
  );
}

final class _FakeApiTransport implements ApiTransport {
  const _FakeApiTransport(this.payload);

  final Object payload;

  @override
  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    return Response<T>(
      data: payload as T,
      requestOptions: RequestOptions(path: path),
    );
  }

  @override
  Future<Response<T>> delete<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<Response<T>> patch<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<Response<T>> post<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<Response<T>> put<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) {
    throw UnimplementedError();
  }
}
