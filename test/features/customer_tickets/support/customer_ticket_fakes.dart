import 'dart:async';
import 'dart:typed_data';

import 'package:webtui_chat/core/error/failure.dart';
import 'package:webtui_chat/core/result/result.dart';
import 'package:webtui_chat/features/customer_tickets/domain/entities/customer_ticket.dart';
import 'package:webtui_chat/features/customer_tickets/domain/entities/customer_ticket_realtime_event.dart';
import 'package:webtui_chat/features/customer_tickets/domain/repositories/customer_ticket_repository.dart';
import 'package:webtui_chat/features/profile/domain/entities/user_profile.dart';
import 'package:webtui_chat/features/profile/domain/repositories/profile_repository.dart';

/// Dữ liệu giả (không phải khách thật) dùng chung cho test ticket khách.
final class ListCall {
  const ListCall({
    required this.workspaceId,
    required this.filter,
    required this.search,
    required this.page,
    required this.perPage,
  });

  final String workspaceId;
  final CustomerTicketFilter filter;
  final String search;
  final int page;
  final int perPage;
}

final class ReplyCall {
  const ReplyCall({
    required this.ticketId,
    required this.message,
    required this.images,
    required this.force,
  });

  final String ticketId;
  final String message;
  final List<CustomerTicketImageUpload> images;
  final bool force;
}

final class ClaimCall {
  const ClaimCall({required this.release, required this.force});

  final bool release;
  final bool force;
}

final class FakeCustomerTicketRepository implements CustomerTicketRepository {
  FakeCustomerTicketRepository({
    this.pages = const [],
    this.listFailure,
    CustomerTicketDetail? detail,
    this.detailFailure,
  }) : detail = detail ?? sampleDetail();

  /// Trang theo thứ tự số trang (trang 1 = phần tử 0).
  List<CustomerTicketPage> pages;
  Failure? listFailure;
  CustomerTicketDetail detail;
  Failure? detailFailure;

  final listCalls = <ListCall>[];
  final replyCalls = <ReplyCall>[];
  final claimCalls = <ClaimCall>[];
  final statusCalls = <CustomerTicketStatus>[];
  final aiDraftInstructions = <String>[];
  int detailCalls = 0;

  /// Kết quả trả lần lượt cho `reply` (hết thì thành công).
  final replyFailures = <Failure>[];
  final claimFailures = <Failure>[];
  Failure? aiDraftFailure;
  CustomerTicketAssignee? claimAssignee = const CustomerTicketAssignee(
    userId: 'user-me',
    name: 'Tôi',
  );

  @override
  Future<Result<CustomerTicketPage>> listTickets({
    required String workspaceId,
    required CustomerTicketFilter filter,
    String search = '',
    int page = 1,
    int perPage = customerTicketDefaultPageSize,
  }) async {
    listCalls.add(
      ListCall(
        workspaceId: workspaceId,
        filter: filter,
        search: search,
        page: page,
        perPage: perPage,
      ),
    );
    final failure = listFailure;
    if (failure != null) return FailureResult(failure);
    if (page - 1 < pages.length) return Success(pages[page - 1]);
    return Success(
      CustomerTicketPage(
        items: const [],
        total: 0,
        page: page,
        perPage: perPage,
        counts: CustomerTicketCounts.empty,
      ),
    );
  }

  @override
  Future<Result<CustomerTicketDetail>> getTicket({
    required String workspaceId,
    required String ticketId,
  }) async {
    detailCalls += 1;
    final failure = detailFailure;
    if (failure != null) return FailureResult(failure);
    return Success(detail);
  }

  @override
  Future<Result<CustomerTicketReplyResult>> reply({
    required String workspaceId,
    required String ticketId,
    required String message,
    List<CustomerTicketImageUpload> images = const [],
    bool force = false,
  }) async {
    replyCalls.add(
      ReplyCall(
        ticketId: ticketId,
        message: message,
        images: images,
        force: force,
      ),
    );
    if (replyFailures.isNotEmpty) {
      return FailureResult(replyFailures.removeAt(0));
    }
    return Success(
      CustomerTicketReplyResult(ticketId: ticketId, messageId: '9001'),
    );
  }

  @override
  Future<Result<CustomerTicketStatus>> setStatus({
    required String workspaceId,
    required String ticketId,
    required CustomerTicketStatus status,
  }) async {
    statusCalls.add(status);
    return Success(status);
  }

  @override
  Future<Result<CustomerTicketAssignee?>> claim({
    required String workspaceId,
    required String ticketId,
    bool release = false,
    bool force = false,
  }) async {
    claimCalls.add(ClaimCall(release: release, force: force));
    if (claimFailures.isNotEmpty) {
      return FailureResult(claimFailures.removeAt(0));
    }
    return Success(release ? null : claimAssignee);
  }

  @override
  Future<Result<void>> requestAiDraft({
    required String workspaceId,
    required String ticketId,
    String instruction = '',
  }) async {
    aiDraftInstructions.add(instruction);
    final failure = aiDraftFailure;
    if (failure != null) return FailureResult(failure);
    return const Success(null);
  }
}

final class FakeCustomerTicketRealtimeRepository
    implements CustomerTicketRealtimeRepository {
  final _controller = StreamController<CustomerTicketRealtimeEvent>.broadcast();
  final watchedWorkspaces = <String>[];

  @override
  Stream<CustomerTicketRealtimeEvent> watch({required String workspaceId}) {
    watchedWorkspaces.add(workspaceId);
    return _controller.stream;
  }

  void emit(CustomerTicketRealtimeEvent event) => _controller.add(event);

  Future<void> close() => _controller.close();
}

final class FakeCustomerTicketImagePicker
    implements CustomerTicketImagePickerRepository {
  FakeCustomerTicketImagePicker([this.images = const []]);

  List<CustomerTicketImageUpload> images;
  final limits = <int>[];

  @override
  Future<Result<List<CustomerTicketImageUpload>>> pick({
    required CustomerTicketImageSource source,
    required int limit,
  }) async {
    limits.add(limit);
    return Success(images);
  }
}

/// Không tải ảnh thật trong test (trả `null` → hiện ô thay thế).
final class FakeCustomerTicketImageRepository
    implements CustomerTicketImageRepository {
  final requested = <String>[];

  @override
  Future<Uint8List?> loadImage(String url) async {
    requested.add(url);
    return null;
  }
}

final class FakeProfileRepository implements ProfileRepository {
  const FakeProfileRepository(this.userId);

  final String userId;

  @override
  Future<Result<UserProfile>> me() async {
    return Success(
      UserProfile(
        id: userId,
        email: 'nhanvien@example.test',
        username: 'nhanvien',
        displayName: 'Nhân viên thử',
        status: 'active',
        locale: 'vi',
        timezone: 'Asia/Ho_Chi_Minh',
      ),
    );
  }

  @override
  Future<Result<UserProfile>> updateMe(UpdateProfileCommand command) => me();
}

/// 02/11/2026 10:00 giờ Việt Nam.
final sampleNow = DateTime.utc(2026, 11, 2, 3);

CustomerTicketSummary sampleSummary({
  String ticketId = '1001',
  CustomerTicketStatus status = CustomerTicketStatus.unanswered,
  String customerName = 'Khách Thử Nghiệm',
  String service = 'VPS',
  Duration waiting = const Duration(minutes: 45),
  CustomerTicketSender lastSender = CustomerTicketSender.customer,
  String lastStaffName = '',
  String preview = 'Máy chủ không vào được',
  int newMessageCount = 0,
  CustomerTicketAssignee? assignee,
  bool hasAiDraft = false,
}) {
  final lastAt = sampleNow.subtract(waiting);
  return CustomerTicketSummary(
    ticketId: ticketId,
    status: status,
    customerName: customerName,
    customerEmail: 'khach$ticketId@example.test',
    service: service,
    createdAt: lastAt,
    lastMessageAt: lastAt,
    waitingSince: lastAt,
    lastSender: lastSender,
    lastStaffName: lastStaffName,
    preview: preview,
    newMessageCount: newMessageCount,
    assignee: assignee,
    hasAiDraft: hasAiDraft,
  );
}

CustomerTicketPage samplePage(
  List<CustomerTicketSummary> items, {
  int? total,
  int page = 1,
  CustomerTicketCounts counts = const CustomerTicketCounts(
    unanswered: 3,
    answered: 10,
    total: 13,
  ),
}) {
  return CustomerTicketPage(
    items: items,
    total: total ?? items.length,
    page: page,
    perPage: customerTicketDefaultPageSize,
    counts: counts,
  );
}

CustomerTicketDetail sampleDetail({
  String ticketId = '1001',
  CustomerTicketStatus status = CustomerTicketStatus.unanswered,
  CustomerTicketAssignee? assignee,
  CustomerTicketAiDraft? aiDraft,
  List<CustomerTicketMessage>? messages,
}) {
  return CustomerTicketDetail(
    ticket: CustomerTicketInfo(
      ticketId: ticketId,
      status: status,
      service: 'VPS',
      createdAt: sampleNow.subtract(const Duration(hours: 1)),
      messageCount: 3,
    ),
    customer: CustomerTicketCustomer(
      customerId: '501',
      name: 'Khách Thử Nghiệm',
      email: 'khach@example.test',
      balance: 1250000,
      services: [
        CustomerTicketService(
          id: 's-1',
          name: 'VPS thử',
          type: 'vps',
          status: 'active',
          expiresAt: DateTime.utc(2026, 12, 1),
          daysRemaining: 29,
          autoRenew: true,
        ),
      ],
      servicesTotal: 1,
    ),
    messages:
        messages ??
        [
          CustomerTicketMessage(
            messageId: '1',
            sender: CustomerTicketSender.customer,
            senderName: 'Khách Thử Nghiệm',
            text: 'Máy chủ không vào được',
            images: const ['https://order.example.test/upload/a.png'],
            time: sampleNow.subtract(const Duration(minutes: 50)),
          ),
          CustomerTicketMessage(
            messageId: '2',
            sender: CustomerTicketSender.staff,
            senderName: 'AI',
            text: 'Trợ lý đã ghi nhận yêu cầu.',
            time: sampleNow.subtract(const Duration(minutes: 49)),
          ),
          CustomerTicketMessage(
            messageId: '3',
            sender: CustomerTicketSender.customer,
            senderName: 'Khách Thử Nghiệm',
            text: 'Nhờ kiểm tra giúp',
            time: sampleNow.subtract(const Duration(minutes: 45)),
          ),
        ],
    assignee: assignee,
    aiDraft: aiDraft,
  );
}

Failure claimedFailure(String holder) {
  return Failure(
    kind: FailureKind.conflict,
    message: 'Ticket đang do $holder xử lý.',
    code: 'TICKET_CLAIMED',
  );
}

const forbiddenFailure = Failure(
  kind: FailureKind.forbidden,
  message: 'Bạn chưa có quyền xem ticket khách.',
  code: 'FORBIDDEN',
);
