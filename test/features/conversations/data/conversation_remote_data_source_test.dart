import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/core/network/api_transport.dart';
import 'package:webtui_chat/features/conversations/data/datasources/conversation_remote_data_source.dart';
import 'package:webtui_chat/features/conversations/domain/entities/chat_message.dart';
import 'package:webtui_chat/features/conversations/presentation/controllers/chat_room_controller.dart';

void main() {
  _includedAttachmentTests();
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

void _includedAttachmentTests() {
  // Phần tử đúng dạng của GET .../messages/{id}/attachments.
  Map<String, Object?> attachmentJson() => {
    'id': 'att-1',
    'workspace_id': 'workspace-1',
    'message_id': 'msg-co-tep',
    'file_id': 'file-1',
    'sort_order': 0,
    'created_at': '2026-11-19T08:00:00Z',
    'file': {
      'id': 'file-1',
      'workspace_id': 'workspace-1',
      'name': 'anh.jpg',
      'mime_type': 'image/jpeg',
      'byte_size': 2048,
      'download_url': '/api/v1/workspaces/workspace-1/files/file-1/download',
      'thumbnail_url': '/api/v1/workspaces/workspace-1/files/file-1/thumbnail',
      'status': 'ready',
      'width': 640,
      'height': 480,
      'created_at': '2026-11-19T08:00:00Z',
    },
  };

  Map<String, Object?> message(String id, {Object? attachments = _absent}) => {
    'id': id,
    'workspace_id': 'workspace-1',
    'channel_id': 'channel-1',
    'kind': 'file',
    'body': 'Đã gửi 1 ảnh',
    'created_at': '2026-11-19T08:00:00Z',
    'sender_id': 'user-2',
    if (!identical(attachments, _absent)) 'attachments': attachments,
  };

  Future<Map<String, ChatMessage>> load(List<Object?> messages) async {
    final remote = ConversationRemoteDataSource(
      _FakeApiTransport({
        'data': {'messages': messages},
      }),
    );
    final page = await remote.listMessagePage(
      workspaceId: 'workspace-1',
      channelId: 'channel-1',
    );
    return {for (final item in page.messages) item.id: item};
  }

  group('danh sách tin kèm khoá attachments', () {
    test('có khoá: đọc tệp như GET .../attachments, không hỏi riêng', () async {
      final byId = await load([
        message('msg-co-tep', attachments: [attachmentJson()]),
      ]);
      final item = byId['msg-co-tep']!;
      expect(item.attachmentsIncluded, isTrue);
      final attachment = item.attachments.single;
      expect(attachment.id, 'att-1');
      expect(attachment.messageId, 'msg-co-tep');
      expect(attachment.fileId, 'file-1');
      expect(attachment.file.name, 'anh.jpg');
      expect(attachment.file.byteSize, 2048);
      expect(
        attachment.file.thumbnailUrl,
        '/api/v1/workspaces/workspace-1/files/file-1/thumbnail',
      );
      expect(attachment.file.width, 640);
      expect(shouldHydrateMessageAttachments(item), isFalse);
    });

    test('khoá rỗng: đã biết là không có tệp, không hỏi riêng', () async {
      final byId = await load([message('msg-rong', attachments: const [])]);
      final item = byId['msg-rong']!;
      expect(item.attachmentsIncluded, isTrue);
      expect(item.attachments, isEmpty);
      // Tin "Đã gửi 1 ảnh" với máy chủ cũ sẽ bị hỏi riêng; máy chủ mới thì không.
      expect(shouldHydrateMessageAttachments(item), isFalse);
    });

    test('không có khoá (máy chủ cũ): giữ cách hỏi riêng từng tin', () async {
      final byId = await load([
        message('msg-cu'),
        message('msg-null', attachments: null),
      ]);
      for (final id in ['msg-cu', 'msg-null']) {
        final item = byId[id]!;
        expect(item.attachmentsIncluded, isFalse, reason: id);
        expect(item.attachments, isEmpty, reason: id);
        expect(shouldHydrateMessageAttachments(item), isTrue, reason: id);
      }
    });

    test('phần tử thiếu message_id thì lấy mã tin chứa nó', () async {
      final element = attachmentJson()..remove('message_id');
      final byId = await load([
        message('msg-co-tep', attachments: [element]),
      ]);
      expect(byId['msg-co-tep']!.attachments.single.messageId, 'msg-co-tep');
    });
  });
}

const Object _absent = Object();

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
