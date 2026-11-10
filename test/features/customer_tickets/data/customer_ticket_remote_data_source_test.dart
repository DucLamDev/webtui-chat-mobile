import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/core/network/api_transport.dart';
import 'package:webtui_chat/features/conversations/domain/entities/conversation_realtime_event.dart';
import 'package:webtui_chat/features/customer_tickets/data/datasources/customer_ticket_remote_data_source.dart';
import 'package:webtui_chat/features/customer_tickets/data/repositories/public_customer_ticket_image_repository.dart';
import 'package:webtui_chat/features/customer_tickets/data/repositories/web_socket_customer_ticket_realtime_repository.dart';
import 'package:webtui_chat/features/customer_tickets/domain/entities/customer_ticket.dart';
import 'package:webtui_chat/features/customer_tickets/domain/entities/customer_ticket_realtime_event.dart';

void main() {
  group('parseCustomerTicketTime', () {
    test('giờ order không kèm múi giờ được hiểu là +07:00', () {
      expect(
        parseCustomerTicketTime('2026-11-02 09:30:15'),
        DateTime.utc(2026, 11, 2, 2, 30, 15),
      );
      // Sau nửa đêm giờ Việt Nam vẫn là hôm trước theo UTC.
      expect(
        parseCustomerTicketTime('2026-11-02 05:00'),
        DateTime.utc(2026, 11, 1, 22),
      );
      expect(
        parseCustomerTicketTime('2026-12-01'),
        DateTime.utc(2026, 11, 30, 17),
      );
      expect(parseCustomerTicketTime('2026-11-02 09:30:15')!.isUtc, isTrue);
    });

    test('chấp nhận ISO 8601 có múi giờ và bỏ giá trị rỗng / sai', () {
      expect(
        parseCustomerTicketTime('2026-11-02T02:30:00Z'),
        DateTime.utc(2026, 11, 2, 2, 30),
      );
      expect(
        parseCustomerTicketTime('2026-11-02T09:30:00+07:00'),
        DateTime.utc(2026, 11, 2, 2, 30),
      );
      expect(parseCustomerTicketTime(''), isNull);
      expect(parseCustomerTicketTime(null), isNull);
      expect(parseCustomerTicketTime('0000-00-00 00:00:00'), isNull);
      expect(parseCustomerTicketTime('không phải giờ'), isNull);
    });
  });

  test('danh sách: đúng đường dẫn, tham số và đọc phòng thủ', () async {
    final api = _RecordingApiTransport(
      responseData: {
        'success': true,
        'data': {
          'items': [
            {
              'ticket_id': 1001,
              'status': 'unanswered',
              'user_id': 501,
              'customer_name': 'Khách Thử',
              'email': 'khach@example.test',
              'service': 'VPS',
              'created_at': '2026-11-02 08:00:00',
              'last_message_at': '2026-11-02 09:15:00',
              'waiting_since': '2026-11-02 09:00:00',
              'last_sender': 'staff',
              'last_admin': 'Lan',
              'preview': 'Đã kiểm tra',
              'unread': 2,
              'assignee': {
                'user_id': 'user-lan',
                'name': 'Lan',
                'assigned_at': '2026-11-02T02:10:00Z',
              },
              'has_ai_draft': true,
            },
            // Thiếu gần hết trường: vẫn đọc được, không ném lỗi.
            {'ticket_id': '1002'},
            // Không có mã ticket: bỏ qua.
            {'preview': 'rác'},
          ],
          'total': 31,
          'page': 1,
          'per_page': 30,
          'counts': {'unanswered': 7, 'answered': 24, 'total': 31},
        },
      },
    );
    final remote = CustomerTicketRemoteDataSource(api);

    final page = await remote.listTickets(
      workspaceId: 'ws 1',
      filter: CustomerTicketFilter.unanswered,
      search: '  lan  ',
      perPage: 30,
    );

    expect(api.method, 'GET');
    expect(api.path, '/api/v1/workspaces/ws%201/order-tickets');
    expect(api.queryParameters, {
      'filter': 'unanswered',
      'search': 'lan',
      'page': 1,
      'per_page': 30,
    });
    expect(page.items, hasLength(2));
    expect(page.total, 31);
    expect(page.counts.unanswered, 7);
    expect(page.counts.answered, 24);
    final first = page.items.first;
    expect(first.ticketId, '1001');
    expect(first.customerId, '501');
    expect(first.customerLabel, 'Khách Thử');
    expect(first.lastSender, CustomerTicketSender.staff);
    expect(first.lastStaffName, 'Lan');
    expect(first.newMessageCount, 2);
    expect(first.assignee?.userId, 'user-lan');
    expect(first.assignee?.name, 'Lan');
    expect(first.hasAiDraft, isTrue);
    expect(first.lastMessageAt, DateTime.utc(2026, 11, 2, 2, 15));
    expect(first.waitingFrom, DateTime.utc(2026, 11, 2, 2));
    final sparse = page.items.last;
    expect(sparse.ticketId, '1002');
    expect(sparse.status, CustomerTicketStatus.unknown);
    expect(sparse.customerLabel, 'Khách');
    expect(sparse.assignee, isNull);
    expect(sparse.waitingFrom, isNull);
  });

  test('danh sách không gửi search rỗng', () async {
    final api = _RecordingApiTransport(responseData: {'success': true});
    await CustomerTicketRemoteDataSource(api).listTickets(
      workspaceId: 'ws-1',
      filter: CustomerTicketFilter.all,
      search: '   ',
      page: 2,
    );
    expect(api.queryParameters, {'filter': 'all', 'page': 2, 'per_page': 30});
  });

  test('chi tiết: đọc ticket, khách, tin, người xử lý, nháp AI', () async {
    final api = _RecordingApiTransport(
      responseData: {
        'success': true,
        'data': {
          'ticket': {
            'ticket_id': 1001,
            'status': 'answered',
            'service': 'VPS',
            'created_at': '2026-11-02 08:00:00',
            'message_count': 12,
            'truncated': true,
            'admin_url': 'https://order.example.test/admin/ticket/1001',
          },
          'customer': {
            'user_id': 501,
            'name': 'Khách Thử',
            'email': 'khach@example.test',
            'balance': 1250000.5,
            'services_total': 4,
            'services': [
              {
                'id': 's-1',
                'type': 'vps',
                'name': 'VPS thử',
                'status': 'active',
                'expires_at': '2026-12-01 00:00:00',
                'days_remaining': 29,
                'autoextend': true,
              },
            ],
          },
          'messages': [
            {
              'message_id': 1,
              'sender': 'customer',
              'sender_name': 'Khách Thử',
              'text': 'Không vào được',
              'images': ['https://order.example.test/upload/a.png', ''],
              'read': true,
              'time': '2026-11-02 09:00:00',
            },
            {
              'message_id': 2,
              'sender': 'staff',
              'sender_name': 'AI',
              'text': 'Đã ghi nhận',
              'images': null,
              'time': '2026-11-02 09:01:00',
            },
          ],
          'assignee': {'user_id': 'user-me', 'name': 'Tôi'},
          'ai_draft': {
            'text': 'Chào anh, bên em đã kiểm tra.',
            'message_id': 1,
            'created_at': '2026-11-02T02:05:00Z',
            'meta': {
              'confidence': 0.82,
              'category': 'ky_thuat',
              'model': 'model-thu',
              'needs_human': true,
              'reason': 'Cần xác nhận',
              'suggested_command': '/vps restart',
            },
          },
        },
      },
    );

    final detail = await CustomerTicketRemoteDataSource(
      api,
    ).getTicket(workspaceId: 'ws-1', ticketId: '1001');

    expect(api.path, '/api/v1/workspaces/ws-1/order-tickets/1001');
    expect(detail.ticket.status, CustomerTicketStatus.answered);
    expect(detail.ticket.truncated, isTrue);
    expect(detail.ticket.messageCount, 12);
    expect(detail.customer?.customerId, '501');
    expect(detail.customer?.balance, 1250000.5);
    expect(detail.customer?.servicesTotal, 4);
    final service = detail.customer!.services.single;
    expect(service.autoRenew, isTrue);
    expect(service.daysRemaining, 29);
    expect(service.expiresAt, DateTime.utc(2026, 11, 30, 17));
    expect(detail.messages, hasLength(2));
    expect(detail.messages.first.images, [
      'https://order.example.test/upload/a.png',
    ]);
    expect(detail.messages.first.time, DateTime.utc(2026, 11, 2, 2));
    expect(detail.messages.last.isAssistant, isTrue);
    expect(detail.messages.last.displaySenderName, 'Trợ lý ảo');
    expect(detail.assignee?.userId, 'user-me');
    final draft = detail.aiDraft!;
    expect(draft.text, 'Chào anh, bên em đã kiểm tra.');
    expect(draft.confidencePercent, 82);
    expect(draft.category, 'ky_thuat');
    expect(draft.needsHuman, isTrue);
    expect(draft.suggestedCommand, '/vps restart');
    expect(draft.createdAt, DateTime.utc(2026, 11, 2, 2, 5));
  });

  test('chi tiết thiếu khách / nháp vẫn đọc được', () async {
    final api = _RecordingApiTransport(
      responseData: {
        'success': true,
        'data': {
          'ticket': {'ticket_id': 7, 'status': 'unanswered'},
          'customer': null,
          'messages': [],
          'ai_draft': {'text': '   '},
        },
      },
    );
    final detail = await CustomerTicketRemoteDataSource(
      api,
    ).getTicket(workspaceId: 'ws-1', ticketId: '7');
    expect(detail.customer, isNull);
    expect(detail.aiDraft, isNull);
    expect(detail.messages, isEmpty);
    expect(detail.customerLabel, 'Khách');
  });

  test('trả lời: body có message, ảnh data URL base64 và force', () async {
    final api = _RecordingApiTransport(
      responseData: {
        'success': true,
        'data': {
          'ticket_id': 1001,
          'message_id': 9001,
          'replied_by': 'nhanvien@example.test',
          'duplicate': false,
          'status': 'answered',
        },
      },
    );
    final bytes = Uint8List.fromList([1, 2, 3, 4]);

    final result = await CustomerTicketRemoteDataSource(api).reply(
      workspaceId: 'ws-1',
      ticketId: '1001',
      message: 'Đã xử lý xong',
      images: [
        CustomerTicketImageUpload(
          name: 'anh.jpg',
          mimeType: 'image/jpeg',
          bytes: bytes,
        ),
      ],
      force: true,
    );

    expect(api.method, 'POST');
    expect(api.path, '/api/v1/workspaces/ws-1/order-tickets/1001/reply');
    expect(api.data, {
      'message': 'Đã xử lý xong',
      'images': [
        {
          'name': 'anh.jpg',
          'data': 'data:image/jpeg;base64,${base64Encode(bytes)}',
        },
      ],
      'force': true,
    });
    expect(result.messageId, '9001');
    expect(result.duplicate, isFalse);
  });

  test('trạng thái, nhận xử lý, nhờ AI soạn: đúng đường dẫn và body', () async {
    final api = _RecordingApiTransport(
      responseData: {
        'success': true,
        'data': {
          'ticket_id': 1001,
          'status': 'answered',
          'assignee': {'user_id': 'user-me', 'name': 'Tôi'},
        },
      },
    );
    final remote = CustomerTicketRemoteDataSource(api);

    final status = await remote.setStatus(
      workspaceId: 'ws-1',
      ticketId: '1001',
      status: CustomerTicketStatus.answered,
    );
    expect(api.path, '/api/v1/workspaces/ws-1/order-tickets/1001/status');
    expect(api.data, {'status': 'answered'});
    expect(status, CustomerTicketStatus.answered);

    final assignee = await remote.claim(
      workspaceId: 'ws-1',
      ticketId: '1001',
      force: true,
    );
    expect(api.path, '/api/v1/workspaces/ws-1/order-tickets/1001/claim');
    expect(api.data, {'release': false, 'force': true});
    expect(assignee?.userId, 'user-me');

    api.responseData = {
      'success': true,
      'data': {'ticket_id': 1001, 'assignee': null},
    };
    final released = await remote.claim(
      workspaceId: 'ws-1',
      ticketId: '1001',
      release: true,
    );
    expect(api.data, {'release': true, 'force': false});
    expect(released, isNull);

    await remote.requestAiDraft(
      workspaceId: 'ws-1',
      ticketId: '1001',
      instruction: '  xin lỗi khách ',
    );
    expect(api.path, '/api/v1/workspaces/ws-1/order-tickets/1001/ai-draft');
    expect(api.data, {'instruction': 'xin lỗi khách'});

    await remote.requestAiDraft(workspaceId: 'ws-1', ticketId: '1001');
    expect(api.data, <String, Object?>{});
  });

  test('sự kiện realtime OrderTicketUpdated đổi sang sự kiện ticket', () {
    final event = customerTicketRealtimeEventFrom(
      const ConversationRealtimeEvent(
        type: ConversationRealtimeEventType.orderTicketUpdated,
        workspaceId: 'ws-1',
        channelId: '',
        payload: {
          'reason': 'ai_draft_failed',
          'ticket_ids': [1001, 1002],
          'actor_user_id': 'user-me',
          'error': 'AI bận',
          'counts': {'unanswered': 4, 'answered': 9, 'total': 13},
        },
      ),
    )!;
    expect(event.reason, CustomerTicketRealtimeReason.aiDraftFailed);
    expect(event.ticketIds, ['1001', '1002']);
    expect(event.concerns('1002'), isTrue);
    expect(event.concerns('1003'), isFalse);
    expect(event.isFromUser('user-me'), isTrue);
    expect(event.isFromUser('user-khac'), isFalse);
    expect(event.counts?.unanswered, 4);
    expect(event.error, 'AI bận');

    final reconnected = customerTicketRealtimeEventFrom(
      const ConversationRealtimeEvent(
        type: ConversationRealtimeEventType.reconnected,
        workspaceId: 'ws-1',
        channelId: '',
      ),
    )!;
    expect(reconnected.reason, CustomerTicketRealtimeReason.reconnected);
    expect(reconnected.concerns('1001'), isTrue);

    expect(
      customerTicketRealtimeEventFrom(
        const ConversationRealtimeEvent(
          type: ConversationRealtimeEventType.messageCreated,
          workspaceId: 'ws-1',
          channelId: 'c-1',
        ),
      ),
      isNull,
    );
  });

  test(
    'ảnh khách: chỉ nhận URL tuyệt đối HTTPS, không kèm thông tin đăng nhập',
    () {
      expect(
        customerTicketImageUri('https://order.example.test/a.png#x').toString(),
        'https://order.example.test/a.png',
      );
      expect(customerTicketImageUri('http://order.example.test/a.png'), isNull);
      expect(customerTicketImageUri('/upload/a.png'), isNull);
      expect(
        customerTicketImageUri('https://u:p@order.example.test/a'),
        isNull,
      );
      expect(customerTicketImageUri('javascript:alert(1)'), isNull);
    },
  );
}

final class _RecordingApiTransport implements ApiTransport {
  _RecordingApiTransport({this.responseData});

  Object? responseData;
  String? method;
  String? path;
  Object? data;
  Map<String, dynamic>? queryParameters;

  Response<T> _response<T>(String path) {
    return Response<T>(
      data: responseData as T?,
      requestOptions: RequestOptions(path: path),
      statusCode: 200,
    );
  }

  @override
  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    method = 'GET';
    this.path = path;
    this.queryParameters = queryParameters;
    return _response(path);
  }

  @override
  Future<Response<T>> post<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    method = 'POST';
    this.path = path;
    this.data = data;
    return _response(path);
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
