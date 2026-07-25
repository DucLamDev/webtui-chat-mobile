import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/core/network/api_transport.dart';
import 'package:webtui_chat/features/conversations/data/datasources/message_attachment_remote_data_source.dart';

void main() {
  test('downloads attachment bytes through authenticated transport', () async {
    final api = _FakeApiTransport([1, 2, 3, 4]);
    final remote = MessageAttachmentRemoteDataSource(api);

    final bytes = await remote.downloadFileBytes(
      downloadPath: '/api/v1/workspaces/workspace-1/files/file-1/download',
      mimeType: 'image/jpeg',
    );

    expect(bytes, [1, 2, 3, 4]);
    expect(api.path, '/api/v1/workspaces/workspace-1/files/file-1/download');
    expect(api.options?.responseType, ResponseType.bytes);
    expect(api.options?.headers?['Accept'], 'image/jpeg');
  });

  test('lists all image attachments for a conversation', () async {
    final api = _FakeApiTransport({
      'success': true,
      'data': {
        'attachments': [
          {
            'workspace_id': 'workspace-1',
            'message_id': 'message-1',
            'file_id': 'file-1',
            'created_at': '2026-07-22T08:00:00Z',
            'file': {
              'id': 'file-1',
              'original_name': 'anh.png',
              'mime_type': 'image/png',
              'byte_size': 1024,
              'created_at': '2026-07-22T08:00:00Z',
            },
          },
        ],
      },
    });
    final remote = MessageAttachmentRemoteDataSource(api);

    final attachments = await remote.listChannelMedia(
      workspaceId: 'workspace-1',
      channelId: 'channel-1',
    );

    expect(attachments, hasLength(1));
    expect(attachments.single.isImage, isTrue);
    expect(api.path, '/api/v1/workspaces/workspace-1/channels/channel-1/media');
    expect(api.queryParameters?['limit'], 500);
  });
}

final class _FakeApiTransport implements ApiTransport {
  _FakeApiTransport(this.payload);

  final Object payload;
  String? path;
  Options? options;
  Map<String, dynamic>? queryParameters;

  @override
  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    this.path = path;
    this.options = options;
    this.queryParameters = queryParameters;
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
