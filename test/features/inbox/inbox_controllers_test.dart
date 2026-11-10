import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/core/error/failure.dart';
import 'package:webtui_chat/core/result/result.dart';
import 'package:webtui_chat/features/inbox/domain/entities/inbox.dart';
import 'package:webtui_chat/features/inbox/presentation/controllers/inbox_conversation_controller.dart';
import 'package:webtui_chat/features/inbox/presentation/controllers/inbox_list_controller.dart';

import 'support/inbox_fakes.dart';

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  group('InboxListController', () {
    late FakeInboxRepository repo;
    late FakeInboxRealtime realtime;
    late InboxListController controller;

    setUp(() async {
      repo = FakeInboxRepository()
        ..pages = [
          InboxConversationPage(
            items: [
              sampleConversation(
                id: 'a',
                lastAt: DateTime.utc(2026, 11, 10, 3),
              ),
            ],
            nextCursor: 'p2',
          ),
        ];
      realtime = FakeInboxRealtime();
      controller = InboxListController.forTesting(
        repository: repo,
        realtime: realtime,
        currentUserId: 'me',
      )..start();
      await _settle();
    });

    tearDown(() => controller.dispose());

    test('tải trang đầu với bộ lọc mặc định (Đang mở, tất cả người xử lý)', () {
      expect(repo.listCalls.first.status, InboxStatusFilter.open);
      expect(repo.listCalls.first.assignee, InboxAssigneeFilter.all);
      expect(controller.state.items.map((c) => c.id), ['a']);
      expect(controller.state.hasMore, isTrue);
    });

    test('đổi lọc tải lại từ đầu với tham số mới', () async {
      repo.pages = [const InboxConversationPage(items: [])];
      await controller.setFilters(
        status: InboxStatusFilter.closed,
        assignee: InboxAssigneeFilter.unassigned,
      );
      expect(repo.listCalls.last.status, InboxStatusFilter.closed);
      expect(repo.listCalls.last.assignee, InboxAssigneeFilter.unassigned);
      expect(repo.listCalls.last.cursor, isNull);
      expect(controller.state.items, isEmpty);
    });

    test('phân trang theo cursor, bỏ mục trùng', () async {
      repo.pages = [
        InboxConversationPage(
          items: [
            sampleConversation(id: 'a'),
            sampleConversation(id: 'b'),
          ],
        ),
      ];
      await controller.loadMore();
      expect(repo.listCalls.last.cursor, 'p2');
      expect(controller.state.items.map((c) => c.id), ['a', 'b']);
      expect(controller.state.hasMore, isFalse);
    });

    test(
      'realtime: không trùng, đưa lên đầu, bỏ khi không còn khớp lọc',
      () async {
        realtime.emit(
          InboxConversationUpdatedEvent(
            sampleConversation(id: 'b', lastAt: DateTime.utc(2026, 11, 10, 9)),
          ),
        );
        realtime.emit(
          InboxConversationUpdatedEvent(
            sampleConversation(id: 'b', lastAt: DateTime.utc(2026, 11, 10, 9)),
          ),
        );
        await _settle();
        expect(controller.state.items.map((c) => c.id), ['b', 'a']);
        realtime.emit(
          InboxConversationUpdatedEvent(
            sampleConversation(id: 'b', status: InboxStatus.closed),
          ),
        );
        await _settle();
        expect(controller.state.items.map((c) => c.id), ['a']);
      },
    );

    test('lọc "Của tôi" giữ hội thoại vừa được gán cho mình', () async {
      repo.pages = [const InboxConversationPage(items: [])];
      await controller.setFilters(assignee: InboxAssigneeFilter.mine);
      realtime.emit(
        InboxConversationUpdatedEvent(
          sampleConversation(id: 'x', assigneeId: 'me'),
        ),
      );
      realtime.emit(
        InboxConversationUpdatedEvent(
          sampleConversation(id: 'y', assigneeId: 'other'),
        ),
      );
      await _settle();
      expect(controller.state.items.map((c) => c.id), ['x']);
    });

    test('nối lại realtime thì tải lại im lặng', () async {
      final before = repo.listCalls.length;
      realtime.emit(const InboxRealtimeReconnected());
      await _settle();
      expect(repo.listCalls.length, before + 1);
    });

    test('403 thì báo không quyền, không crash', () async {
      repo.listFailure = failure(FailureKind.forbidden, code: 'FORBIDDEN');
      await controller.load();
      expect(controller.state.forbidden, isTrue);
      expect(controller.state.errorMessage, isNull);
      expect(controller.state.items, isEmpty);
    });

    test('lỗi mạng giữ thông báo lỗi', () async {
      repo.listFailure = failure(FailureKind.network, message: 'Mất mạng');
      await controller.load();
      expect(controller.state.forbidden, isFalse);
      expect(controller.state.errorMessage, 'Mất mạng');
    });
  });

  group('InboxConversationController', () {
    late FakeInboxRepository repo;
    late FakeInboxRealtime realtime;
    late InboxConversationController controller;
    var seq = 0;

    Future<void> create({InboxConversation? conversation}) async {
      repo = FakeInboxRepository()
        ..conversation = conversation ?? sampleConversation(unread: 2)
        ..messagePage = InboxMessagePage(
          items: [sampleMessage()],
          nextCursor: 'older',
        );
      realtime = FakeInboxRealtime();
      seq = 0;
      controller = InboxConversationController.forTesting(
        repository: repo,
        realtime: realtime,
        currentUserId: 'me',
        newClientMessageId: () => 'cid-${++seq}',
      )..start();
      await _settle();
    }

    tearDown(() => controller.dispose());

    test('mở màn thì tải tin, gọi read và đưa số chưa đọc về 0', () async {
      await create();
      expect(controller.state.messages.map((m) => m.id), ['m1']);
      expect(repo.readCalls, 1);
      expect(controller.state.conversation!.unreadCount, 0);
    });

    test('gửi lỗi mạng rồi gửi lại dùng cùng client_message_id', () async {
      await create();
      repo.replyResults = [
        FailureResult(failure(FailureKind.network, message: 'Mất mạng')),
      ];
      await controller.sendReply('  Dạ vâng  ');
      var sent = controller.state.messages.last;
      expect(sent.delivery, InboxDelivery.failed);
      expect(sent.isLocal, isTrue);
      expect(sent.body, 'Dạ vâng');

      await controller.retry('cid-1');
      expect(repo.sentReplies.map((r) => r.clientId), ['cid-1', 'cid-1']);
      expect(repo.sentReplies.every((r) => r.body == 'Dạ vâng'), isTrue);
      expect(controller.state.messages, hasLength(2));
      sent = controller.state.messages.last;
      expect(sent.isLocal, isFalse);
      expect(sent.delivery, InboxDelivery.queued);
    });

    test('realtime tin đã gửi đến trước phản hồi vẫn không trùng', () async {
      await create();
      realtime.emit(
        InboxMessageCreatedEvent(
          sampleMessage(
            id: 'srv-1',
            direction: InboxDirection.outbound,
            body: 'Dạ',
            delivery: InboxDelivery.sending,
            clientId: 'cid-1',
            at: DateTime.now().toUtc(),
          ),
        ),
      );
      await controller.sendReply('Dạ');
      realtime.emit(
        InboxMessageCreatedEvent(
          sampleMessage(
            id: 'srv-1',
            direction: InboxDirection.outbound,
            body: 'Dạ',
            delivery: InboxDelivery.sent,
            clientId: 'cid-1',
            at: DateTime.now().toUtc(),
          ),
        ),
      );
      await _settle();
      final mine = controller.state.messages.where((m) => m.body == 'Dạ');
      expect(mine, hasLength(1));
      expect(mine.single.delivery, InboxDelivery.sent);
    });

    test('hết cửa sổ trả lời (409) hiện lỗi tiếng Việt', () async {
      await create();
      repo.replyResults = [
        FailureResult(
          failure(FailureKind.conflict, code: 'INBOX_REPLY_WINDOW_CLOSED'),
        ),
      ];
      await controller.sendReply('Xin lỗi');
      expect(
        controller.state.messages.last.error,
        'Đã quá thời hạn trả lời của kênh này.',
      );
    });

    test('can_reply=false thì không gửi trả lời', () async {
      await create(
        conversation: sampleConversation(
          canReply: false,
          blocked: 'Quá 24 giờ',
        ),
      );
      await controller.sendReply('Thử');
      expect(repo.sentReplies, isEmpty);
    });

    test(
      'ghi chú nội bộ: thành công trả true, lỗi giữ chữ (trả false)',
      () async {
        await create();
        expect(await controller.addNote('Gọi lại sau'), isTrue);
        expect(repo.notes, ['Gọi lại sau']);
        expect(controller.state.messages.last.isNote, isTrue);
        repo.noteResult = FailureResult(failure(FailureKind.forbidden));
        expect(await controller.addNote('Nữa'), isFalse);
        expect(controller.state.actionError, isNotNull);
      },
    );

    test('nhận / bỏ nhận / đổi trạng thái / tag gửi đúng PATCH', () async {
      await create();
      await controller.claim();
      expect(repo.changes.last.assigneeId, 'me');
      expect(controller.state.assignedToMe, isTrue);
      await controller.release();
      expect(repo.changes.last.assigneeId, '');
      await controller.setStatus(InboxStatus.pending);
      expect(repo.changes.last.status, InboxStatus.pending);
      expect(controller.state.conversation!.status, InboxStatus.pending);
      await controller.setTags(['t1', 't2']);
      expect(repo.changes.last.tagIds, ['t1', 't2']);
    });

    test('realtime hội thoại khác bị bỏ; tin khách mới thì đọc lại', () async {
      await create();
      final reads = repo.readCalls;
      realtime.emit(
        InboxConversationUpdatedEvent(
          sampleConversation(id: 'khac', status: InboxStatus.closed),
        ),
      );
      realtime.emit(
        InboxMessageCreatedEvent(
          sampleMessage(
            id: 'm9',
            body: 'Còn hàng không?',
            at: DateTime.utc(2026, 11, 10, 5),
          ),
        ),
      );
      await _settle();
      expect(controller.state.conversation!.status, InboxStatus.open);
      expect(controller.state.messages.map((m) => m.id), ['m1', 'm9']);
      expect(repo.readCalls, reads + 1);
    });

    test(
      'lỗi vĩnh viễn thì tin lỗi không cho gửi lại, lỗi mạng thì cho',
      () async {
        await create();
        repo.replyResults = [
          FailureResult(
            failure(FailureKind.conflict, code: 'INBOX_SOURCE_DISABLED'),
          ),
          FailureResult(failure(FailureKind.network, message: 'Mất mạng')),
        ];
        await controller.sendReply('A');
        await controller.sendReply('B');
        final failed = controller.state.messages
            .where((m) => m.delivery == InboxDelivery.failed)
            .toList();
        expect(failed.map((m) => m.body), ['A', 'B']);
        expect(failed[0].retryable, isFalse);
        expect(failed[1].retryable, isTrue);
      },
    );

    test('tải tin cũ xong sau khi tải lại thì bỏ trang đó', () async {
      await create();
      repo
        ..olderGate = Completer<void>()
        ..olderPage = InboxMessagePage(
          items: [sampleMessage(id: 'cu', at: DateTime.utc(2026, 11, 1))],
        );
      final older = controller.loadOlder();
      await _settle();
      await controller.load();
      repo.olderGate!.complete();
      await older;
      expect(controller.state.messages.map((m) => m.id), ['m1']);
      expect(controller.state.isLoadingMore, isFalse);
    });

    test('thao tác khi đang cập nhật thì báo ngắn, không gửi thêm', () async {
      await create();
      repo.updateGate = Completer<void>();
      final first = controller.setStatus(InboxStatus.pending);
      await _settle();
      await controller.setStatus(InboxStatus.closed);
      expect(
        controller.state.actionError,
        'Đang cập nhật, thử lại sau giây lát.',
      );
      expect(repo.changes, hasLength(1));
      repo.updateGate!.complete();
      await first;
      expect(controller.state.isUpdating, isFalse);
    });

    test('403 / 404 khi tải hội thoại', () async {
      await create();
      repo.conversationFailure = failure(FailureKind.forbidden);
      await controller.load();
      expect(controller.state.forbidden, isTrue);
      repo.conversationFailure = failure(FailureKind.notFound);
      await controller.load();
      expect(controller.state.notFound, isTrue);
    });
  });
}
