import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/core/network/api_transport.dart';
import 'package:webtui_chat/features/conversations/data/datasources/conversation_remote_data_source.dart';

/// Lỗi 17/11: dòng bot thông báo ở danh sách hiện giờ sửa kênh (09:45) và mô tả
/// kênh "Thông báo của bạn" dù tin bot mới nhất (cuộc gọi nhỡ) lúc 10:35.
void main() {
  Map<String, Object?> payload(List<Map<String, Object?>> channels) => {
    'success': true,
    'data': {'channels': channels},
  };

  test('kênh bot: giờ và dòng xem trước lấy từ tin cuối máy chủ trả', () async {
    final remote = ConversationRemoteDataSource(
      _GetTransport(
        payload([
          {
            'id': 'notice-1',
            'workspace_id': 'ws',
            'name': 'Webtui Chat Bot',
            'description': 'Thông báo của bạn',
            'type': 'direct',
            'notice_bot': true,
            'updated_at': '2026-11-17T02:45:00Z',
            'last_message_at': '2026-11-17T03:35:00Z',
            'last_message': {
              'id': 'm-1',
              'channel_id': 'notice-1',
              'kind': 'bot',
              'body': 'Nguyễn Thanh Tiền đã gọi cho bạn',
              'created_at': '2026-11-17T03:35:00Z',
            },
          },
        ]),
      ),
    );

    final channel = (await remote.listChannels(workspaceId: 'ws')).single;

    expect(channel.noticeBot, isTrue);
    expect(channel.preview, 'Nguyễn Thanh Tiền đã gọi cho bạn');
    expect(channel.lastMessageAt, DateTime.utc(2026, 11, 17, 3, 35));
    expect(channel.updatedAt, DateTime.utc(2026, 11, 17, 3, 35));
  });

  test('chỉ có tin cuối (thiếu last_message_at) vẫn lấy giờ của tin', () async {
    final remote = ConversationRemoteDataSource(
      _GetTransport(
        payload([
          {
            'id': 'notice-1',
            'workspace_id': 'ws',
            'name': 'Bot',
            'type': 'direct',
            'notice_bot': true,
            'updated_at': '2026-11-17T02:45:00Z',
            'last_message': {
              'id': 'm-1',
              'body': 'Có việc mới',
              'created_at': '2026-11-17T03:35:00Z',
            },
          },
        ]),
      ),
    );

    final channel = (await remote.listChannels(workspaceId: 'ws')).single;

    expect(channel.preview, 'Có việc mới');
    expect(channel.updatedAt, DateTime.utc(2026, 11, 17, 3, 35));
  });

  test('máy chủ cũ / nhóm thường: giữ mô tả và giờ như trước', () async {
    final remote = ConversationRemoteDataSource(
      _GetTransport(
        payload([
          {
            'id': 'notice-1',
            'workspace_id': 'ws',
            'name': 'Bot',
            'description': 'Thông báo của bạn',
            'type': 'direct',
            'notice_bot': true,
            'updated_at': '2026-11-17T02:45:00Z',
          },
          {
            'id': 'group-1',
            'workspace_id': 'ws',
            'name': 'Nhóm A',
            'description': 'Mô tả nhóm',
            'type': 'private',
            'updated_at': '2026-11-17T01:00:00Z',
            'last_message_at': '2026-11-17T03:00:00Z',
          },
        ]),
      ),
    );

    final byId = {
      for (final item in await remote.listChannels(workspaceId: 'ws'))
        item.id: item,
    };

    expect(byId['notice-1']!.preview, 'Thông báo của bạn');
    expect(byId['notice-1']!.lastMessageAt, isNull);
    expect(byId['notice-1']!.updatedAt, DateTime.utc(2026, 11, 17, 2, 45));
    expect(byId['group-1']!.preview, 'Mô tả nhóm');
    expect(byId['group-1']!.updatedAt, DateTime.utc(2026, 11, 17, 3));
  });
}

final class _GetTransport implements ApiTransport {
  _GetTransport(this._payload);

  final Object _payload;

  @override
  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async => Response<T>(
    data: _payload as T,
    requestOptions: RequestOptions(path: path),
  );

  @override
  Future<Response<T>> post<T>(
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

  @override
  Future<Response<T>> patch<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) => throw UnimplementedError();

  @override
  Future<Response<T>> delete<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) => throw UnimplementedError();
}
