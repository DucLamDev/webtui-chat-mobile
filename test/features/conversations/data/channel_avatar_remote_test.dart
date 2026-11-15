import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/core/network/api_transport.dart';
import 'package:webtui_chat/features/conversations/data/datasources/conversation_remote_data_source.dart';

void main() {
  test('kênh: đọc avatar_url (có / thiếu / null)', () async {
    final transport = _RecordingTransport(
      getPayload: {
        'data': {
          'channels': [
            {
              'id': 'co-anh',
              'workspace_id': 'ws',
              'name': 'Nhóm A',
              'type': 'private',
              'updated_at': '2026-11-15T08:00:00Z',
              'avatar_url':
                  '/api/v1/channels/avatars/z1/co-anh/avatar-0123456789abcdef.jpg',
            },
            {
              'id': 'thieu',
              'workspace_id': 'ws',
              'name': 'Nhóm B',
              'type': 'private',
              'updated_at': '2026-11-15T08:00:00Z',
            },
            {
              'id': 'null',
              'workspace_id': 'ws',
              'name': 'Nhóm C',
              'type': 'private',
              'updated_at': '2026-11-15T08:00:00Z',
              'avatar_url': null,
            },
          ],
        },
      },
    );
    final remote = ConversationRemoteDataSource(transport);

    final channels = await remote.listChannels(workspaceId: 'ws');
    final byId = {for (final channel in channels) channel.id: channel};

    expect(
      byId['co-anh']!.avatarUrl,
      '/api/v1/channels/avatars/z1/co-anh/avatar-0123456789abcdef.jpg',
    );
    expect(byId['thieu']!.avatarUrl, isNull);
    expect(byId['null']!.avatarUrl, isNull);
  });

  test('đổi ảnh nhóm: POST multipart trường avatar, đọc kênh trả về', () async {
    final dir = await Directory.systemTemp.createTemp('channel-avatar-test');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/anh.png');
    await file.writeAsBytes(const [137, 80, 78, 71]);

    final transport = _RecordingTransport(
      postPayload: {
        'success': true,
        'data': {
          'channel': {
            'id': 'ch-1',
            'workspace_id': 'ws',
            'name': 'Nhóm A',
            'type': 'private',
            'membership_status': 'active',
            'updated_at': '2026-11-15T08:00:00Z',
            'avatar_url':
                '/api/v1/channels/avatars/z1/ch-1/avatar-0123456789abcdef.jpg',
          },
        },
      },
    );
    final remote = ConversationRemoteDataSource(transport);

    final channel = await remote.uploadChannelAvatar(
      workspaceId: 'ws',
      channelId: 'ch-1',
      filePath: file.path,
      fileName: 'anh.png',
      mimeType: 'image/png',
    );

    expect(transport.postPath, '/api/v1/workspaces/ws/channels/ch-1/avatar');
    final form = transport.postData as FormData;
    expect(form.files.map((entry) => entry.key), ['avatar']);
    expect(form.files.single.value.filename, 'anh.png');
    expect(form.files.single.value.contentType?.mimeType, 'image/png');
    expect(
      transport.postOptions?.contentType,
      Headers.multipartFormDataContentType,
    );
    expect(channel.channelId, 'ch-1');
    expect(
      channel.avatarUrl,
      '/api/v1/channels/avatars/z1/ch-1/avatar-0123456789abcdef.jpg',
    );
  });
}

final class _RecordingTransport implements ApiTransport {
  _RecordingTransport({this.getPayload, this.postPayload});

  final Object? getPayload;
  final Object? postPayload;
  String? postPath;
  Object? postData;
  Options? postOptions;

  @override
  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    return Response<T>(
      data: getPayload as T,
      requestOptions: RequestOptions(path: path),
    );
  }

  @override
  Future<Response<T>> post<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    postPath = path;
    postData = data;
    postOptions = options;
    return Response<T>(
      data: postPayload as T,
      requestOptions: RequestOptions(path: path),
    );
  }

  @override
  Future<Response<T>> delete<T>(
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
  Future<Response<T>> put<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) => throw UnimplementedError();
}
