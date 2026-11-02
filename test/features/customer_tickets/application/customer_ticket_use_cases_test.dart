import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/core/error/failure.dart';
import 'package:webtui_chat/core/network/self_hosted_server_discovery.dart';
import 'package:webtui_chat/core/result/result.dart';
import 'package:webtui_chat/features/customer_tickets/application/customer_ticket_access_policy.dart';
import 'package:webtui_chat/features/customer_tickets/application/use_cases/customer_ticket_use_cases.dart';
import 'package:webtui_chat/features/customer_tickets/domain/entities/customer_ticket.dart';
import 'package:webtui_chat/features/workspace/domain/entities/workspace_permission.dart';

import '../support/customer_ticket_fakes.dart';

void main() {
  group('quyền vào ticket khách', () {
    test('máy chủ nội bộ + bots + order.view thì xem được', () {
      final access = CustomerTicketAccess.resolve(
        discovery: _discovery(),
        permissions: _permissions(['order.view']),
      );
      expect(access.serverSupported, isTrue);
      expect(access.canView, isTrue);
      expect(access.canReply, isFalse);

      final reply = CustomerTicketAccess.resolve(
        discovery: _discovery(),
        permissions: _permissions(['order.view', 'order.ticket_reply']),
      );
      expect(reply.canReply, isTrue);
    });

    test('thiếu điều kiện nào cũng không vào được', () {
      final allPermissions = _permissions(['order.view', 'order.ticket_reply']);
      // Máy chủ khách tự host (không phải host nội bộ).
      expect(
        CustomerTicketAccess.resolve(
          discovery: _discovery(domain: 'chat.company.example'),
          permissions: allPermissions,
        ).canView,
        isFalse,
      );
      // Đúng host nhưng zone không phải nội bộ.
      expect(
        CustomerTicketAccess.resolve(
          discovery: _discovery(zoneKind: 'dedicated'),
          permissions: allPermissions,
        ).serverSupported,
        isFalse,
      );
      // Không bật bots.
      expect(
        CustomerTicketAccess.resolve(
          discovery: _discovery(bots: false),
          permissions: allPermissions,
        ).canView,
        isFalse,
      );
      expect(
        CustomerTicketAccess.resolve(
          discovery: null,
          permissions: allPermissions,
        ).canView,
        isFalse,
      );
      // Có quyền trả lời nhưng thiếu quyền xem.
      final noView = CustomerTicketAccess.resolve(
        discovery: _discovery(),
        permissions: _permissions(['order.ticket_reply']),
      );
      expect(noView.canView, isFalse);
      expect(noView.canReply, isFalse);
      // Quyền chưa tải: đang chờ.
      final pending = CustomerTicketAccess.resolve(
        discovery: _discovery(),
        permissions: null,
      );
      expect(pending.isPending, isTrue);
      expect(pending.canView, isFalse);
    });
  });

  test('danh sách: chuẩn hoá tìm kiếm, trang, số dòng mỗi trang', () async {
    final repository = FakeCustomerTicketRepository();
    final useCase = ListCustomerTicketsUseCase(repository);

    await useCase.execute(
      workspaceId: ' ws-1 ',
      filter: CustomerTicketFilter.answered,
      search: '  ${'a' * 130}  ',
      page: 0,
      perPage: 500,
    );

    final call = repository.listCalls.single;
    expect(call.workspaceId, 'ws-1');
    expect(call.filter, CustomerTicketFilter.answered);
    expect(call.search.length, customerTicketMaxSearchLength);
    expect(call.page, 1);
    expect(call.perPage, customerTicketMaxPageSize);

    final missing = await useCase.execute(
      workspaceId: ' ',
      filter: CustomerTicketFilter.all,
    );
    expect(missing.failureOrNull?.kind, FailureKind.validation);
    expect(repository.listCalls, hasLength(1));
  });

  test(
    'đếm ticket chưa trả lời dùng counts.unanswered với per_page=1',
    () async {
      final repository = FakeCustomerTicketRepository(
        pages: [
          samplePage(
            [sampleSummary()],
            total: 9,
            counts: const CustomerTicketCounts(
              unanswered: 9,
              answered: 2,
              total: 11,
            ),
          ),
        ],
      );
      final result = await CountUnansweredCustomerTicketsUseCase(
        repository,
      ).execute('ws-1');
      expect(result.valueOrNull, 9);
      expect(repository.listCalls.single.perPage, 1);
      expect(
        repository.listCalls.single.filter,
        CustomerTicketFilter.unanswered,
      );
    },
  );

  test('mã ticket lạ (vd. ../) bị chặn trước khi gọi máy chủ', () async {
    final repository = FakeCustomerTicketRepository();
    final result = await LoadCustomerTicketUseCase(
      repository,
    ).execute(workspaceId: 'ws-1', ticketId: '../1001');
    expect(result.failureOrNull?.code, 'CUSTOMER_TICKET_ID_INVALID');
    expect(repository.detailCalls, 0);
  });

  group('kiểm tra câu trả lời', () {
    CustomerTicketImageUpload image({
      String mime = 'image/jpeg',
      int size = 10,
    }) {
      return CustomerTicketImageUpload(
        name: 'anh.jpg',
        mimeType: mime,
        bytes: Uint8List(size),
      );
    }

    test('cần nội dung hoặc ảnh; tối đa 4.000 ký tự', () {
      expect(
        validateCustomerTicketReply(message: '  \r\n ')?.code,
        'CUSTOMER_TICKET_REPLY_EMPTY',
      );
      expect(validateCustomerTicketReply(message: 'a' * 4000), isNull);
      expect(
        validateCustomerTicketReply(message: 'a' * 4001)?.code,
        'CUSTOMER_TICKET_REPLY_TOO_LONG',
      );
      // Chỉ gửi ảnh (không có chữ) vẫn hợp lệ như máy chủ.
      expect(
        validateCustomerTicketReply(message: '', images: [image()]),
        isNull,
      );
    });

    test('tối đa 3 ảnh PNG / JPEG / GIF / WEBP, mỗi ảnh ≤ 5 MB', () {
      expect(
        validateCustomerTicketReply(
          message: 'x',
          images: [image(), image(), image(), image()],
        )?.code,
        'CUSTOMER_TICKET_TOO_MANY_IMAGES',
      );
      expect(
        validateCustomerTicketReply(
          message: 'x',
          images: [image(mime: 'image/heic')],
        )?.code,
        'CUSTOMER_TICKET_IMAGE_INVALID',
      );
      expect(
        validateCustomerTicketReply(
          message: 'x',
          images: [image(size: customerTicketMaxImageBytes + 1)],
        )?.code,
        'CUSTOMER_TICKET_IMAGE_INVALID',
      );
      expect(
        validateCustomerTicketReply(
          message: 'x',
          images: [
            image(mime: 'image/png'),
            image(mime: 'image/webp'),
          ],
        ),
        isNull,
      );
    });

    test('trả lời gửi nội dung đã chuẩn hoá và cờ force', () async {
      final repository = FakeCustomerTicketRepository();
      final result = await ReplyCustomerTicketUseCase(repository).execute(
        workspaceId: 'ws-1',
        ticketId: '1001',
        message: '  Chào anh\r\nBên em đã xử lý  ',
        force: true,
      );
      expect(result.isSuccess, isTrue);
      final call = repository.replyCalls.single;
      expect(call.message, 'Chào anh\nBên em đã xử lý');
      expect(call.force, isTrue);
    });
  });

  test('đọc tên người đang giữ ticket từ lỗi TICKET_CLAIMED', () {
    final failure = claimedFailure('Nguyễn Lan');
    expect(isCustomerTicketClaimedFailure(failure), isTrue);
    expect(customerTicketHolderName(failure), 'Nguyễn Lan');
    expect(
      customerTicketHolderName(
        const Failure(
          kind: FailureKind.conflict,
          message: 'Dữ liệu đã thay đổi.',
          code: 'TICKET_CLAIMED',
        ),
        fallback: 'Hùng',
      ),
      'Hùng',
    );
    expect(
      isCustomerTicketClaimedFailure(
        const Failure(kind: FailureKind.conflict, message: 'x'),
      ),
      isFalse,
    );
  });

  test('gợi ý cho AI tối đa 1.000 ký tự', () async {
    final repository = FakeCustomerTicketRepository();
    final useCase = RequestCustomerTicketAiDraftUseCase(repository);
    final tooLong = await useCase.execute(
      workspaceId: 'ws-1',
      ticketId: '1001',
      instruction: 'a' * 1001,
    );
    expect(tooLong.failureOrNull?.code, 'CUSTOMER_TICKET_INSTRUCTION_TOO_LONG');
    expect(repository.aiDraftInstructions, isEmpty);
    await useCase.execute(
      workspaceId: 'ws-1',
      ticketId: '1001',
      instruction: '  hẹn 30 phút ',
    );
    expect(repository.aiDraftInstructions.single, 'hẹn 30 phút');
  });

  test('chọn ảnh: chỉ chọn thêm tới đủ 3, bỏ ảnh sai định dạng', () async {
    final picker = FakeCustomerTicketImagePicker([
      CustomerTicketImageUpload(
        name: 'a.jpg',
        mimeType: 'image/jpeg',
        bytes: Uint8List(8),
      ),
      CustomerTicketImageUpload(
        name: 'b.heic',
        mimeType: 'image/heic',
        bytes: Uint8List(8),
      ),
    ]);
    final useCase = PickCustomerTicketImagesUseCase(picker);

    final result = await useCase.execute(
      source: CustomerTicketImageSource.gallery,
      alreadySelected: 1,
    );
    expect(picker.limits.single, 2);
    final pick = result.valueOrNull!;
    expect(pick.images.map((image) => image.name), ['a.jpg']);
    expect(pick.rejectedReason, contains('b.heic'));

    final full = await useCase.execute(
      source: CustomerTicketImageSource.gallery,
      alreadySelected: 3,
    );
    expect(full, isA<FailureResult<CustomerTicketImagePick>>());
    expect(picker.limits, hasLength(1));
  });
}

SelfHostedServerDiscovery _discovery({
  String domain = 'chat.vpsttt.com',
  String zoneKind = 'vpsttt_internal',
  bool bots = true,
}) {
  return SelfHostedServerDiscovery(
    instanceId: '11111111-1111-4111-8111-111111111111',
    discoveryVersion: '1',
    domain: domain,
    name: 'Máy chủ thử',
    apiBaseUri: Uri.parse('https://$domain'),
    wsBaseUri: Uri.parse('wss://$domain/ws'),
    registrationMode: 'closed',
    appVersion: '1.0.0',
    apiContractVersion: 1,
    serverVersion: '1.0.0',
    minimumSupportedMobileVersion: '1.0.0',
    capabilities: SelfHostedCapabilities(bots: bots),
    zoneKind: zoneKind,
  );
}

PermissionSet _permissions(List<String> codes) {
  return PermissionSet([
    for (final code in codes)
      WorkspacePermission(
        id: code,
        code: code,
        module: code.split('.').first,
        action: code.split('.').last,
        name: code,
      ),
  ]);
}
