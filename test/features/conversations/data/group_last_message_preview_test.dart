import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/core/network/api_transport.dart';
import 'package:webtui_chat/features/conversations/application/channel_last_message_preview.dart';
import 'package:webtui_chat/features/conversations/data/datasources/conversation_remote_data_source.dart';

void main() {
  group('groupLastMessagePreview', () {
    test('người khác gửi: "Tên: nội dung"', () {
      expect(
        groupLastMessagePreview(
          kind: 'text',
          body: 'Chiều họp nhé',
          senderId: 'u-2',
          senderName: 'Minh',
          currentUserId: 'u-1',
        ),
        'Minh: Chiều họp nhé',
      );
    });

    test('thiếu sender_name: chỉ nội dung', () {
      expect(
        groupLastMessagePreview(
          kind: 'text',
          body: 'Chiều họp nhé',
          senderId: 'u-2',
          currentUserId: 'u-1',
        ),
        'Chiều họp nhé',
      );
    });

    test('tin của mình: "Bạn: nội dung", dù có tên', () {
      expect(
        groupLastMessagePreview(
          kind: 'text',
          body: 'ok',
          senderId: 'u-1',
          senderName: 'Tôi',
          currentUserId: 'u-1',
        ),
        'Bạn: ok',
      );
    });

    test('chưa biết mình là ai: không nhận nhầm là tin của mình', () {
      expect(
        groupLastMessagePreview(
          kind: 'text',
          body: 'ok',
          senderName: 'Minh',
          currentUserId: null,
        ),
        'Minh: ok',
      );
    });

    test('tin chỉ có tệp', () {
      expect(
        groupLastMessagePreview(
          kind: 'file',
          body: '',
          senderId: 'u-1',
          currentUserId: 'u-1',
        ),
        'Bạn: đã gửi một tệp',
      );
      expect(
        groupLastMessagePreview(
          kind: 'file',
          body: '  ',
          senderId: 'u-2',
          senderName: 'Minh',
          currentUserId: 'u-1',
        ),
        'Minh: đã gửi một tệp',
      );
      expect(groupLastMessagePreview(kind: 'file', body: ''), 'Đã gửi một tệp');
    });

    test('tin bí mật không lộ nội dung và tên', () {
      expect(
        groupLastMessagePreview(
          kind: 'text',
          body: 'mật khẩu là 123',
          senderName: 'Minh',
          secret: true,
        ),
        'Tin nhắn bí mật',
      );
    });

    test('nhiều dòng gộp thành một dòng', () {
      expect(
        groupLastMessagePreview(
          kind: 'text',
          body: 'dòng một\n\n  dòng hai\r\ndòng ba ',
          senderName: 'Minh',
        ),
        'Minh: dòng một dòng hai dòng ba',
      );
    });

    test('tin hệ thống / sự kiện không ghép tên', () {
      expect(
        groupLastMessagePreview(
          kind: 'system',
          body: 'An đã tham gia nhóm',
          senderName: 'An',
        ),
        'An đã tham gia nhóm',
      );
    });

    test('rỗng và không phải tệp: null để rơi về mô tả', () {
      expect(groupLastMessagePreview(kind: 'text', body: ' '), isNull);
    });

    test('tin thời gian thực: isMine và tệp đính kèm không có chữ', () {
      expect(
        groupLastMessagePreview(kind: 'text', body: 'ok', isMine: true),
        'Bạn: ok',
      );
      expect(
        groupLastMessagePreview(
          kind: 'text',
          body: '',
          senderName: 'Minh',
          hasAttachments: true,
        ),
        'Minh: đã gửi một tệp',
      );
    });
  });

  group('listChannels', () {
    Map<String, Object?> channel({
      Map<String, Object?>? lastMessage,
      bool noticeBot = false,
      String type = 'private',
    }) => {
      'id': 'g-1',
      'workspace_id': 'ws',
      'name': 'Nhóm thử',
      'description': 'Mô tả nhóm',
      'type': type,
      'notice_bot': noticeBot,
      'updated_at': '2026-11-17T02:45:00Z',
      'last_message_at': ?(lastMessage == null ? null : '2026-11-17T03:35:00Z'),
      'last_message': ?lastMessage,
    };

    Future<String> previewOf(
      Map<String, Object?> item, {
      String? me = 'u-1',
    }) async {
      final remote = ConversationRemoteDataSource(
        _GetTransport({
          'success': true,
          'data': {
            'channels': [item],
          },
        }),
        resolveCurrentUserId: () async => me,
      );
      return (await remote.listChannels(workspaceId: 'ws')).single.preview;
    }

    test('nhóm có tin cuối: ghép tên người gửi', () async {
      expect(
        await previewOf(
          channel(
            lastMessage: {
              'kind': 'text',
              'body': 'xin chào',
              'sender_id': 'u-2',
              'sender_name': 'Minh',
            },
          ),
        ),
        'Minh: xin chào',
      );
    });

    test('tin của mình: "Bạn:"', () async {
      expect(
        await previewOf(
          channel(
            lastMessage: {
              'kind': 'text',
              'body': 'xin chào',
              'sender_id': 'u-1',
              'sender_name': 'Tôi',
            },
          ),
        ),
        'Bạn: xin chào',
      );
    });

    test('máy chủ cũ không có last_message: giữ mô tả nhóm', () async {
      expect(await previewOf(channel()), 'Mô tả nhóm');
    });

    test('tin cuối rỗng không phải tệp: giữ mô tả nhóm', () async {
      expect(
        await previewOf(channel(lastMessage: {'kind': 'text', 'body': ''})),
        'Mô tả nhóm',
      );
    });

    test('bot thông báo và chat 1-1 giữ nguyên nội dung tin', () async {
      final last = {
        'kind': 'bot',
        'body': 'Có cuộc gọi nhỡ',
        'sender_name': 'Bot',
      };
      expect(
        await previewOf(channel(lastMessage: last, noticeBot: true)),
        'Có cuộc gọi nhỡ',
      );
      expect(
        await previewOf(channel(lastMessage: last, type: 'direct')),
        'Có cuộc gọi nhỡ',
      );
    });

    test('không đọc được mã người dùng: vẫn có dòng xem trước', () async {
      final remote = ConversationRemoteDataSource(
        _GetTransport({
          'success': true,
          'data': {
            'channels': [
              channel(
                lastMessage: {
                  'kind': 'text',
                  'body': 'hi',
                  'sender_name': 'Minh',
                },
              ),
            ],
          },
        }),
        resolveCurrentUserId: () async => throw StateError('kho token lỗi'),
      );
      expect(
        (await remote.listChannels(workspaceId: 'ws')).single.preview,
        'Minh: hi',
      );
    });
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
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
