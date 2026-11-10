import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/features/conversations/domain/entities/conversation_realtime_event.dart';
import 'package:webtui_chat/features/inbox/application/inbox_merge.dart';
import 'package:webtui_chat/features/inbox/data/datasources/inbox_remote_data_source.dart';
import 'package:webtui_chat/features/inbox/data/repositories/web_socket_inbox_realtime_repository.dart';
import 'package:webtui_chat/features/inbox/domain/entities/inbox.dart';

import 'support/inbox_fakes.dart';

void main() {
  group('đọc JSON', () {
    test('hội thoại đầy đủ', () {
      final c = inboxConversationFromMap(
        conversationJson(unread: 3, assigneeId: 'u1'),
      );
      expect(c.id, 'c1');
      expect(c.label, 'An · fb#vip');
      expect(c.source.chipLabel, 'FB');
      expect(c.tags.single.name, 'vip');
      expect(c.unreadCount, 3);
      expect(c.canReply, isTrue);
      expect(c.isAssignedTo('u1'), isTrue);
      expect(c.lastMessageAt, isNotNull);
    });

    test('thiếu trường / null / sai kiểu không crash', () {
      final c = inboxConversationFromMap({
        'id': 'c9',
        'source': null,
        'contact': 'lạ',
        'tags': 5,
        'status': 'xyz',
        'assignee_id': null,
        'unread_count': 'abc',
        'last_message_at': 'không phải ngày',
      });
      expect(c.id, 'c9');
      expect(c.status, InboxStatus.unknown);
      expect(
        c.canReply,
        isFalse,
        reason: 'thiếu can_reply = không được trả lời',
      );
      expect(c.isAssigned, isFalse);
      expect(c.unreadCount, 0);
      expect(c.tags, isEmpty);
      expect(c.lastMessageAt, isNull);
      expect(c.title, 'Khách');
    });

    test('tin nhắn: ghi chú, trạng thái gửi, thiếu trường', () {
      final note = inboxMessageFromMap(
        messageJson(direction: 'out', kind: 'note', delivery: 'sent'),
      );
      expect(note.isNote, isTrue);
      expect(note.isFromCustomer, isFalse);
      final failed = inboxMessageFromMap(
        messageJson(direction: 'out', delivery: 'failed'),
      );
      expect(failed.delivery.label, 'Gửi lỗi');
      final bare = inboxMessageFromMap({'id': 'm2'});
      expect(bare.body, '');
      expect(bare.direction, InboxDirection.inbound);
      expect(bare.delivery, InboxDelivery.unknown);
    });
  });

  group('InboxRemoteDataSource', () {
    test('danh sách: URL, lọc, cursor; đọc items / next_cursor', () async {
      final api = RecordingTransport({
        'success': true,
        'data': {
          'items': [conversationJson(), 'rác', {}],
          'next_cursor': 'cur2',
        },
      });
      final page = await InboxRemoteDataSource(api).listConversations(
        workspaceId: 'ws 1',
        status: InboxStatusFilter.pending,
        assignee: InboxAssigneeFilter.mine,
        cursor: 'cur1',
      );
      expect(api.method, 'GET');
      expect(api.path, '/api/v1/workspaces/ws%201/inbox/conversations');
      expect(api.query, {
        'status': 'pending',
        'assignee': 'me',
        'limit': 30,
        'cursor': 'cur1',
      });
      expect(page.items.map((e) => e.id), ['c1']);
      expect(page.nextCursor, 'cur2');
    });

    test('lọc tất cả thì không gửi status / assignee', () async {
      final api = RecordingTransport({
        'data': {'items': []},
      });
      await InboxRemoteDataSource(api).listConversations(workspaceId: 'ws');
      expect(api.query, {'limit': 30});
    });

    test('chi tiết, tin nhắn phân trang, đã đọc', () async {
      var api = RecordingTransport({'data': conversationJson()});
      await InboxRemoteDataSource(
        api,
      ).getConversation(workspaceId: 'ws', conversationId: 'c1');
      expect(api.method, 'GET');
      expect(api.path, '/api/v1/workspaces/ws/inbox/conversations/c1');

      api = RecordingTransport({
        'data': {
          'items': [messageJson()],
          'next_cursor': 'old',
        },
      });
      final page = await InboxRemoteDataSource(api).listMessages(
        workspaceId: 'ws',
        conversationId: 'c1',
        cursor: 'x',
        limit: 20,
      );
      expect(api.path, '/api/v1/workspaces/ws/inbox/conversations/c1/messages');
      expect(api.query, {'limit': 20, 'cursor': 'x'});
      expect(page.nextCursor, 'old');

      api = RecordingTransport(null);
      await InboxRemoteDataSource(
        api,
      ).markRead(workspaceId: 'ws', conversationId: 'c1');
      expect(api.method, 'POST');
      expect(api.path, '/api/v1/workspaces/ws/inbox/conversations/c1/read');
    });

    test('trả lời gửi body + client_message_id; ghi chú chỉ body', () async {
      var api = RecordingTransport({'data': messageJson(direction: 'out')});
      await InboxRemoteDataSource(api).sendReply(
        workspaceId: 'ws',
        conversationId: 'c1',
        body: 'Dạ vâng',
        clientMessageId: 'uuid-1',
      );
      expect(api.method, 'POST');
      expect(api.path, '/api/v1/workspaces/ws/inbox/conversations/c1/messages');
      expect(api.body, {'body': 'Dạ vâng', 'client_message_id': 'uuid-1'});

      api = RecordingTransport({'data': messageJson(kind: 'note')});
      final note = await InboxRemoteDataSource(
        api,
      ).addNote(workspaceId: 'ws', conversationId: 'c1', body: 'Gọi lại');
      expect(api.path, '/api/v1/workspaces/ws/inbox/conversations/c1/notes');
      expect(api.body, {'body': 'Gọi lại'});
      expect(note.isNote, isTrue);
    });

    test('PATCH chỉ gửi trường thay đổi; bỏ nhận gửi chuỗi rỗng', () async {
      final api = RecordingTransport({'data': conversationJson()});
      final source = InboxRemoteDataSource(api);
      await source.update(
        workspaceId: 'ws',
        conversationId: 'c1',
        change: const InboxConversationChange(status: InboxStatus.closed),
      );
      expect(api.method, 'PATCH');
      expect(api.path, '/api/v1/workspaces/ws/inbox/conversations/c1');
      expect(api.body, {'status': 'closed'});
      await source.update(
        workspaceId: 'ws',
        conversationId: 'c1',
        change: const InboxConversationChange(assigneeId: ''),
      );
      expect(api.body, {'assignee_id': ''});
      await source.update(
        workspaceId: 'ws',
        conversationId: 'c1',
        change: const InboxConversationChange(assigneeId: 'u1', tagIds: ['t1']),
      );
      expect(api.body, {
        'assignee_id': 'u1',
        'tag_ids': ['t1'],
      });
    });

    test('danh sách tag', () async {
      final api = RecordingTransport({
        'data': {
          'items': [
            {'id': 't1', 'name': 'vip', 'color': '#fff'},
            {'name': 'thiếu id'},
          ],
        },
      });
      final tags = await InboxRemoteDataSource(api).listTags(workspaceId: 'ws');
      expect(api.path, '/api/v1/workspaces/ws/inbox/tags');
      expect(tags.single.name, 'vip');
    });
  });

  group('realtime', () {
    test('đổi sự kiện WebSocket sang sự kiện hộp thư', () {
      final updated = inboxRealtimeEventFrom(
        ConversationRealtimeEvent(
          type: ConversationRealtimeEventType.inboxConversationUpdated,
          workspaceId: 'ws',
          channelId: '',
          payload: {
            'workspace_id': 'ws',
            'conversation': conversationJson(unread: 1),
          },
        ),
      );
      expect(
        (updated! as InboxConversationUpdatedEvent).conversation.unreadCount,
        1,
      );
      final created = inboxRealtimeEventFrom(
        ConversationRealtimeEvent(
          type: ConversationRealtimeEventType.inboxMessageCreated,
          workspaceId: 'ws',
          channelId: '',
          payload: {
            'workspace_id': 'ws',
            'conversation_id': 'c1',
            'message': {
              'id': 'm5',
              'body': 'x',
              'created_at': '2026-11-10T03:00:00Z',
            },
          },
        ),
      );
      expect(
        (created! as InboxMessageCreatedEvent).message.conversationId,
        'c1',
      );
      expect(
        inboxRealtimeEventFrom(
          ConversationRealtimeEvent(
            type: ConversationRealtimeEventType.inboxMessageCreated,
            workspaceId: 'ws',
            channelId: '',
            payload: const {'message': 5},
          ),
        ),
        isNull,
      );
      expect(
        inboxRealtimeEventFrom(
          const ConversationRealtimeEvent(
            type: ConversationRealtimeEventType.reconnected,
            workspaceId: 'ws',
            channelId: '',
          ),
        ),
        isA<InboxRealtimeReconnected>(),
      );
    });

    test('gộp tin không trùng theo id và client_message_id', () {
      final local = sampleMessage(
        id: 'local:u1',
        direction: InboxDirection.outbound,
        delivery: InboxDelivery.sending,
        clientId: 'u1',
        at: DateTime.utc(2026, 11, 10, 4),
      );
      var list = mergeInboxMessages([sampleMessage()], [local]);
      expect(list.map((m) => m.id), ['m1', 'local:u1']);
      final confirmed = sampleMessage(
        id: 'm2',
        direction: InboxDirection.outbound,
        delivery: InboxDelivery.queued,
        clientId: 'u1',
        at: DateTime.utc(2026, 11, 10, 4),
      );
      list = mergeInboxMessages(list, [confirmed, confirmed]);
      expect(list.map((m) => m.id), ['m1', 'm2']);
      // Cùng id đến lại với trạng thái mới thì cập nhật, không thêm.
      list = mergeInboxMessages(list, [
        confirmed.copyWith(delivery: InboxDelivery.sent),
      ]);
      expect(list, hasLength(2));
      expect(list.last.delivery, InboxDelivery.sent);
    });

    test(
      'cập nhật hội thoại: thay tại chỗ, đưa lên đầu, bỏ khi hết khớp lọc',
      () {
        final a = sampleConversation(
          id: 'a',
          lastAt: DateTime.utc(2026, 11, 10, 1),
        );
        final b = sampleConversation(
          id: 'b',
          lastAt: DateTime.utc(2026, 11, 10, 2),
        );
        var items = upsertInboxConversation(
          [b, a],
          a.copyWith2(DateTime.utc(2026, 11, 10, 5)),
          matches: (_) => true,
        );
        expect(items.map((c) => c.id), ['a', 'b']);
        items = upsertInboxConversation(items, b, matches: (_) => true);
        expect(items.map((c) => c.id), ['a', 'b']);
        items = upsertInboxConversation(items, b, matches: (c) => c.id != 'b');
        expect(items.map((c) => c.id), ['a']);
        // Hội thoại mới khớp lọc thì chèn đúng thứ tự.
        items = upsertInboxConversation(
          items,
          sampleConversation(id: 'n', lastAt: DateTime.utc(2026, 11, 11)),
          matches: (_) => true,
        );
        expect(items.first.id, 'n');
      },
    );
  });
}

extension on InboxConversation {
  InboxConversation copyWith2(DateTime at) =>
      sampleConversation(id: id, lastAt: at);
}
