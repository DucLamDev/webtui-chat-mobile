import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/features/customer_tickets/domain/entities/customer_ticket.dart';
import 'package:webtui_chat/features/customer_tickets/domain/entities/customer_ticket_realtime_event.dart';
import 'package:webtui_chat/features/customer_tickets/presentation/controllers/customer_ticket_detail_controller.dart';
import 'package:webtui_chat/features/customer_tickets/presentation/controllers/customer_ticket_list_controller.dart';

import '../support/customer_ticket_fakes.dart';

Future<void> _settle() async {
  for (var index = 0; index < 5; index++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  group('danh sách ticket', () {
    test('mặc định lọc Chưa trả lời, đổi bộ lọc tải lại từ trang 1', () async {
      final repository = FakeCustomerTicketRepository(
        pages: [
          samplePage([sampleSummary()]),
        ],
      );
      final controller = CustomerTicketListController.forTesting(
        repository: repository,
      )..start();
      addTearDown(controller.dispose);
      await _settle();

      expect(
        repository.listCalls.single.filter,
        CustomerTicketFilter.unanswered,
      );
      expect(repository.listCalls.single.page, 1);
      expect(repository.listCalls.single.perPage, 30);
      expect(controller.state.items.single.ticketId, '1001');
      expect(controller.state.counts.unanswered, 3);

      repository.pages = [
        samplePage([
          sampleSummary(
            ticketId: '2001',
            status: CustomerTicketStatus.answered,
          ),
        ]),
      ];
      await controller.setFilter(CustomerTicketFilter.answered);
      expect(repository.listCalls.last.filter, CustomerTicketFilter.answered);
      expect(controller.state.items.single.ticketId, '2001');

      await controller.setSearch('  Khách  ');
      expect(repository.listCalls.last.search, 'Khách');
      expect(repository.listCalls.last.page, 1);
    });

    test('cuộn tải thêm trang 2 rồi dừng khi đủ tổng số', () async {
      final firstPage = [
        for (var index = 0; index < 30; index++)
          sampleSummary(ticketId: '${1000 + index}'),
      ];
      final secondPage = [
        for (var index = 30; index < 45; index++)
          sampleSummary(ticketId: '${1000 + index}'),
      ];
      final repository = FakeCustomerTicketRepository(
        pages: [
          samplePage(firstPage, total: 45),
          samplePage(secondPage, total: 45, page: 2),
        ],
      );
      final controller = CustomerTicketListController.forTesting(
        repository: repository,
      )..start();
      addTearDown(controller.dispose);
      await _settle();

      expect(controller.state.items, hasLength(30));
      expect(controller.state.hasMore, isTrue);

      await controller.loadMore();
      expect(repository.listCalls.last.page, 2);
      expect(controller.state.items, hasLength(45));
      expect(controller.state.hasMore, isFalse);

      await controller.loadMore();
      expect(repository.listCalls, hasLength(2));
    });

    test('sự kiện realtime cập nhật số đếm và tải lại danh sách', () async {
      final realtime = FakeCustomerTicketRealtimeRepository();
      addTearDown(realtime.close);
      final repository = FakeCustomerTicketRepository(
        pages: [
          samplePage([sampleSummary()]),
        ],
      );
      final controller = CustomerTicketListController.forTesting(
        repository: repository,
        realtime: realtime,
      )..start();
      addTearDown(controller.dispose);
      await _settle();
      expect(realtime.watchedWorkspaces, ['workspace-1']);
      final before = repository.listCalls.length;

      realtime.emit(
        const CustomerTicketRealtimeEvent(
          reason: CustomerTicketRealtimeReason.messages,
          ticketIds: ['1001'],
          counts: CustomerTicketCounts(unanswered: 8, answered: 1, total: 9),
        ),
      );
      await _settle();
      expect(repository.listCalls.length, before + 1);

      // Nháp AI lỗi không làm tải lại danh sách.
      realtime.emit(
        const CustomerTicketRealtimeEvent(
          reason: CustomerTicketRealtimeReason.aiDraftFailed,
          ticketIds: ['1001'],
        ),
      );
      await _settle();
      expect(repository.listCalls.length, before + 1);
    });

    test('máy chủ trả 403 thì chuyển sang trạng thái không có quyền', () async {
      final repository = FakeCustomerTicketRepository()
        ..listFailure = forbiddenFailure;
      final controller = CustomerTicketListController.forTesting(
        repository: repository,
      )..start();
      addTearDown(controller.dispose);
      await _settle();
      expect(controller.state.forbidden, isTrue);
      expect(controller.state.items, isEmpty);
    });
  });

  group('chi tiết ticket', () {
    test('TICKET_CLAIMED hỏi lại rồi gửi với force', () async {
      final repository = FakeCustomerTicketRepository(
        detail: sampleDetail(
          assignee: const CustomerTicketAssignee(
            userId: 'user-lan',
            name: 'Lan',
          ),
        ),
      )..replyFailures.add(claimedFailure('Lan'));
      final controller = CustomerTicketDetailController.forTesting(
        repository: repository,
        currentUserId: 'user-me',
      )..start();
      addTearDown(controller.dispose);
      await _settle();
      expect(controller.state.heldByOther, isTrue);

      final first = await controller.reply('Bên em đã xử lý');
      expect(first.status, CustomerTicketActionStatus.claimedByOther);
      expect(first.holderName, 'Lan');
      expect(repository.replyCalls.single.force, isFalse);

      final second = await controller.reply('Bên em đã xử lý', force: true);
      expect(second.status, CustomerTicketActionStatus.done);
      expect(repository.replyCalls.last.force, isTrue);
      expect(repository.replyCalls.last.message, 'Bên em đã xử lý');
    });

    test('nhận xử lý: người khác giữ thì hỏi lại, đồng ý thì force', () async {
      final repository = FakeCustomerTicketRepository()
        ..claimFailures.add(claimedFailure('Hùng'));
      final controller = CustomerTicketDetailController.forTesting(
        repository: repository,
        currentUserId: 'user-me',
      )..start();
      addTearDown(controller.dispose);
      await _settle();

      final first = await controller.claim();
      expect(first.status, CustomerTicketActionStatus.claimedByOther);
      expect(first.holderName, 'Hùng');

      final second = await controller.claim(force: true);
      expect(second.status, CustomerTicketActionStatus.done);
      expect(repository.claimCalls.last.force, isTrue);
      expect(controller.state.assignedToMe, isTrue);

      await controller.release();
      expect(repository.claimCalls.last.release, isTrue);
    });

    test('thiếu quyền (403) thì không hiện chi tiết', () async {
      final repository = FakeCustomerTicketRepository()
        ..detailFailure = forbiddenFailure;
      final controller = CustomerTicketDetailController.forTesting(
        repository: repository,
      )..start();
      addTearDown(controller.dispose);
      await _settle();
      expect(controller.state.forbidden, isTrue);
      expect(controller.state.detail, isNull);
    });

    test('nhờ AI soạn: chờ tới khi nháp mới đến qua realtime', () async {
      final realtime = FakeCustomerTicketRealtimeRepository();
      addTearDown(realtime.close);
      final repository = FakeCustomerTicketRepository();
      final controller = CustomerTicketDetailController.forTesting(
        repository: repository,
        realtime: realtime,
        currentUserId: 'user-me',
      )..start();
      addTearDown(controller.dispose);
      await _settle();

      await controller.requestAiDraft(instruction: 'xin lỗi khách');
      expect(repository.aiDraftInstructions.single, 'xin lỗi khách');
      expect(controller.state.isDraftPending, isTrue);

      repository.detail = sampleDetail(
        aiDraft: CustomerTicketAiDraft(
          text: 'Chào anh, bên em đã kiểm tra.',
          createdAt: sampleNow,
        ),
      );
      realtime.emit(
        const CustomerTicketRealtimeEvent(
          reason: CustomerTicketRealtimeReason.aiDraft,
          ticketIds: ['1001'],
        ),
      );
      await _settle();
      expect(controller.state.isDraftPending, isFalse);
      expect(controller.state.detail?.aiDraft?.text, contains('đã kiểm tra'));
    });

    test('ai_draft_failed chỉ báo lỗi khi chính mình yêu cầu', () async {
      final realtime = FakeCustomerTicketRealtimeRepository();
      addTearDown(realtime.close);
      final controller = CustomerTicketDetailController.forTesting(
        repository: FakeCustomerTicketRepository(),
        realtime: realtime,
        currentUserId: 'user-me',
      )..start();
      addTearDown(controller.dispose);
      await _settle();

      realtime.emit(
        const CustomerTicketRealtimeEvent(
          reason: CustomerTicketRealtimeReason.aiDraftFailed,
          ticketIds: ['1001'],
          actorUserId: 'user-khac',
          error: 'AI bận',
        ),
      );
      await _settle();
      expect(controller.state.aiErrorMessage, isNull);

      await controller.requestAiDraft();
      realtime.emit(
        const CustomerTicketRealtimeEvent(
          reason: CustomerTicketRealtimeReason.aiDraftFailed,
          ticketIds: ['1001'],
          actorUserId: 'user-me',
          error: 'AI bận',
        ),
      );
      await _settle();
      expect(controller.state.isDraftPending, isFalse);
      expect(controller.state.aiErrorMessage, 'AI bận');
    });

    test('sự kiện của ticket khác không làm tải lại', () async {
      final realtime = FakeCustomerTicketRealtimeRepository();
      addTearDown(realtime.close);
      final repository = FakeCustomerTicketRepository();
      final controller = CustomerTicketDetailController.forTesting(
        repository: repository,
        realtime: realtime,
      )..start();
      addTearDown(controller.dispose);
      await _settle();
      final before = repository.detailCalls;

      realtime.emit(
        const CustomerTicketRealtimeEvent(
          reason: CustomerTicketRealtimeReason.messages,
          ticketIds: ['9999'],
        ),
      );
      await _settle();
      expect(repository.detailCalls, before);

      realtime.emit(
        const CustomerTicketRealtimeEvent(
          reason: CustomerTicketRealtimeReason.messages,
          ticketIds: ['1001'],
        ),
      );
      await _settle();
      expect(repository.detailCalls, before + 1);
    });
  });
}
