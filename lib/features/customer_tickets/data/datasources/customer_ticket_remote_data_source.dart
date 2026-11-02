import 'dart:convert';

import '../../../../core/network/api_response.dart';
import '../../../../core/network/api_transport.dart';
import '../../domain/entities/customer_ticket.dart';

/// Hộp thư ticket khách của máy chủ nội bộ: `/workspaces/{ws}/order-tickets`.
final class CustomerTicketRemoteDataSource {
  const CustomerTicketRemoteDataSource(this._api);

  final ApiTransport _api;

  Future<CustomerTicketPage> listTickets({
    required String workspaceId,
    required CustomerTicketFilter filter,
    String search = '',
    int page = 1,
    int perPage = customerTicketDefaultPageSize,
  }) async {
    final query = search.trim();
    final response = await _api.get<Object>(
      _base(workspaceId),
      queryParameters: {
        'filter': filter.apiValue,
        if (query.isNotEmpty) 'search': query,
        'page': page,
        'per_page': perPage,
      },
    );
    final data = envelopeData(response.data);
    if (data is List) {
      final items = jsonMapList(data).map(_summaryFromMap).toList();
      return CustomerTicketPage(
        items: items,
        total: items.length,
        page: page,
        perPage: perPage,
        counts: CustomerTicketCounts.empty,
      );
    }
    final map = jsonMap(data);
    final items = jsonMapList(
      field(map, const ['items', 'tickets']),
    ).map(_summaryFromMap).where((item) => item.ticketId.isNotEmpty).toList();
    return CustomerTicketPage(
      items: items,
      total: intField(map, const ['total'], fallback: items.length),
      page: intField(map, const ['page'], fallback: page),
      perPage: intField(map, const ['per_page', 'perPage'], fallback: perPage),
      counts: _countsFromMap(jsonMap(field(map, const ['counts']))),
    );
  }

  Future<CustomerTicketDetail> getTicket({
    required String workspaceId,
    required String ticketId,
  }) async {
    final response = await _api.get<Object>(_ticketPath(workspaceId, ticketId));
    final data = jsonMap(envelopeData(response.data));
    final ticketMap = jsonMap(field(data, const ['ticket']));
    final customerMap = jsonMapOrNull(field(data, const ['customer']));
    return CustomerTicketDetail(
      ticket: CustomerTicketInfo(
        ticketId: stringField(ticketMap, const [
          'ticket_id',
          'ticketId',
          'id',
        ], fallback: ticketId.trim()),
        status: customerTicketStatusFromApi(
          stringField(ticketMap, const ['status']),
        ),
        service: stringField(ticketMap, const ['service']),
        createdAt: parseCustomerTicketTime(
          field(ticketMap, const ['created_at', 'createdAt']),
        ),
        messageCount: intField(ticketMap, const [
          'message_count',
          'messageCount',
        ]),
        truncated: boolField(ticketMap, const ['truncated']),
        adminUrl: stringField(ticketMap, const ['admin_url', 'adminUrl']),
      ),
      customer: customerMap == null || customerMap.isEmpty
          ? null
          : _customerFromMap(customerMap),
      messages: jsonMapList(
        field(data, const ['messages']),
      ).map(_messageFromMap).toList(growable: false),
      assignee: _assigneeFromMap(field(data, const ['assignee'])),
      aiDraft: _aiDraftFromMap(field(data, const ['ai_draft', 'aiDraft'])),
    );
  }

  Future<CustomerTicketReplyResult> reply({
    required String workspaceId,
    required String ticketId,
    required String message,
    List<CustomerTicketImageUpload> images = const [],
    bool force = false,
  }) async {
    final response = await _api.post<Object>(
      '${_ticketPath(workspaceId, ticketId)}/reply',
      data: {
        'message': message,
        'images': [
          for (final image in images)
            {'name': image.name, 'data': customerTicketImageDataUrl(image)},
        ],
        'force': force,
      },
    );
    final data = jsonMap(envelopeData(response.data));
    return CustomerTicketReplyResult(
      ticketId: stringField(data, const [
        'ticket_id',
        'ticketId',
      ], fallback: ticketId.trim()),
      messageId: stringField(data, const ['message_id', 'messageId']),
      repliedBy: stringField(data, const ['replied_by', 'repliedBy']),
      duplicate: boolField(data, const ['duplicate']),
      status: stringField(data, const ['status']),
    );
  }

  Future<CustomerTicketStatus> setStatus({
    required String workspaceId,
    required String ticketId,
    required CustomerTicketStatus status,
  }) async {
    final response = await _api.post<Object>(
      '${_ticketPath(workspaceId, ticketId)}/status',
      data: {'status': status.apiValue},
    );
    final data = jsonMap(envelopeData(response.data));
    final returned = customerTicketStatusFromApi(
      stringField(data, const ['status']),
    );
    return returned == CustomerTicketStatus.unknown ? status : returned;
  }

  Future<CustomerTicketAssignee?> claim({
    required String workspaceId,
    required String ticketId,
    bool release = false,
    bool force = false,
  }) async {
    final response = await _api.post<Object>(
      '${_ticketPath(workspaceId, ticketId)}/claim',
      data: {'release': release, 'force': force},
    );
    final data = jsonMap(envelopeData(response.data));
    return _assigneeFromMap(field(data, const ['assignee']));
  }

  Future<void> requestAiDraft({
    required String workspaceId,
    required String ticketId,
    String instruction = '',
  }) async {
    final cleanInstruction = instruction.trim();
    await _api.post<Object>(
      '${_ticketPath(workspaceId, ticketId)}/ai-draft',
      data: {if (cleanInstruction.isNotEmpty) 'instruction': cleanInstruction},
    );
  }
}

/// Ảnh gửi lên dạng data URL base64 (`data:image/jpeg;base64,...`).
String customerTicketImageDataUrl(CustomerTicketImageUpload image) {
  return 'data:${image.mimeType};base64,${base64Encode(image.bytes)}';
}

final _vietnamLocalTime = RegExp(
  r'^(\d{4})-(\d{2})-(\d{2})(?:[ T](\d{2}):(\d{2})(?::(\d{2})(?:\.(\d{1,6}))?)?)?$',
);

/// Giờ của hệ thống order là giờ Việt Nam `YYYY-MM-DD HH:mm:ss` không kèm múi
/// giờ: hiểu là +07:00, không phụ thuộc múi giờ của máy. Chuỗi ISO 8601 có múi
/// giờ (vd. `...Z`, `+07:00`) đọc như bình thường. Trả về giờ UTC.
DateTime? parseCustomerTicketTime(Object? value) {
  if (value is DateTime) return value.toUtc();
  final text = value?.toString().trim() ?? '';
  if (text.isEmpty) return null;
  final match = _vietnamLocalTime.firstMatch(text);
  if (match != null) {
    int part(int index) => int.parse(match.group(index) ?? '0');
    // Ngày rỗng kiểu MySQL (`0000-00-00 ...`) hoặc sai thì coi như không có.
    if (part(1) < 1970 ||
        part(2) < 1 ||
        part(2) > 12 ||
        part(3) < 1 ||
        part(3) > 31 ||
        part(4) > 23 ||
        part(5) > 59 ||
        part(6) > 59) {
      return null;
    }
    final fraction = (match.group(7) ?? '').padRight(6, '0');
    final local = DateTime.utc(
      part(1),
      part(2),
      part(3),
      part(4),
      part(5),
      part(6),
      0,
      int.parse(fraction),
    );
    return local.subtract(const Duration(hours: 7));
  }
  return DateTime.tryParse(text)?.toUtc();
}

CustomerTicketSummary _summaryFromMap(JsonMap map) {
  final lastSender = nullableStringField(map, const [
    'last_sender',
    'lastSender',
  ]);
  return CustomerTicketSummary(
    ticketId: stringField(map, const ['ticket_id', 'ticketId', 'id']).trim(),
    status: customerTicketStatusFromApi(stringField(map, const ['status'])),
    customerId: nullableStringField(map, const [
      'user_id',
      'customer_id',
      'userId',
    ]),
    customerName: stringField(map, const [
      'customer_name',
      'customerName',
      'name',
    ]).trim(),
    customerEmail: stringField(map, const [
      'email',
      'customer_email',
      'customerEmail',
    ]).trim(),
    service: stringField(map, const ['service']).trim(),
    createdAt: parseCustomerTicketTime(
      field(map, const ['created_at', 'createdAt']),
    ),
    lastMessageAt: parseCustomerTicketTime(
      field(map, const ['last_message_at', 'lastMessageAt']),
    ),
    waitingSince: parseCustomerTicketTime(
      field(map, const ['waiting_since', 'waitingSince']),
    ),
    lastSender: lastSender == null
        ? null
        : customerTicketSenderFromApi(lastSender),
    lastStaffName: stringField(map, const [
      'last_admin',
      'last_staff_name',
      'lastAdmin',
    ]).trim(),
    preview: stringField(map, const ['preview']).trim(),
    newMessageCount: intField(map, const [
      'unread',
      'new_messages',
      'unread_count',
    ]),
    assignee: _assigneeFromMap(field(map, const ['assignee'])),
    hasAiDraft:
        boolField(map, const ['has_ai_draft', 'hasAiDraft']) ||
        _aiDraftFromMap(field(map, const ['ai_draft', 'aiDraft'])) != null,
  );
}

CustomerTicketCounts _countsFromMap(JsonMap map) {
  if (map.isEmpty) return CustomerTicketCounts.empty;
  final unanswered = intField(map, const ['unanswered']);
  final answered = intField(map, const ['answered']);
  return CustomerTicketCounts(
    unanswered: unanswered,
    answered: answered,
    total: intField(map, const ['total'], fallback: unanswered + answered),
  );
}

/// Dùng chung cho payload realtime (`counts`).
CustomerTicketCounts? customerTicketCountsFromJson(Object? value) {
  final map = jsonMapOrNull(value);
  if (map == null || map.isEmpty) return null;
  return _countsFromMap(map);
}

CustomerTicketAssignee? _assigneeFromMap(Object? value) {
  final map = jsonMapOrNull(value);
  if (map == null || map.isEmpty) return null;
  final userId = stringField(map, const ['user_id', 'userId', 'id']).trim();
  if (userId.isEmpty) return null;
  return CustomerTicketAssignee(
    userId: userId,
    name: stringField(map, const [
      'name',
      'display_name',
      'displayName',
    ]).trim(),
    assignedAt: parseCustomerTicketTime(
      field(map, const ['assigned_at', 'assignedAt']),
    ),
  );
}

CustomerTicketMessage _messageFromMap(JsonMap map) {
  final images = field(map, const ['images']);
  return CustomerTicketMessage(
    messageId: stringField(map, const ['message_id', 'messageId', 'id']),
    sender: customerTicketSenderFromApi(stringField(map, const ['sender'])),
    senderName: stringField(map, const ['sender_name', 'senderName']).trim(),
    text: stringField(map, const ['text', 'message', 'body']),
    images: images is List
        ? images
              .map((value) => value?.toString().trim() ?? '')
              .where((value) => value.isNotEmpty)
              .toList(growable: false)
        : const [],
    read: boolField(map, const ['read']),
    time: parseCustomerTicketTime(
      field(map, const ['time', 'created_at', 'createdAt']),
    ),
  );
}

CustomerTicketCustomer _customerFromMap(JsonMap map) {
  final balance = field(map, const ['balance']);
  final services = jsonMapList(
    field(map, const ['services']),
  ).map(_serviceFromMap).toList(growable: false);
  return CustomerTicketCustomer(
    customerId: nullableStringField(map, const [
      'user_id',
      'customer_id',
      'userId',
      'id',
    ]),
    name: stringField(map, const ['name', 'customer_name']).trim(),
    email: stringField(map, const ['email']).trim(),
    balance: balance is num
        ? balance.toDouble()
        : double.tryParse(balance?.toString() ?? ''),
    services: services,
    servicesTotal: intField(map, const [
      'services_total',
      'servicesTotal',
    ], fallback: services.length),
  );
}

CustomerTicketService _serviceFromMap(JsonMap map) {
  final days = field(map, const ['days_remaining', 'daysRemaining']);
  return CustomerTicketService(
    id: stringField(map, const ['id']),
    name: stringField(map, const ['name']).trim(),
    type: stringField(map, const ['type']).trim(),
    status: stringField(map, const ['status']).trim(),
    meta: stringField(map, const ['meta']).trim(),
    expiresAt: parseCustomerTicketTime(
      field(map, const ['expires_at', 'expiresAt']),
    ),
    daysRemaining: days is num ? days.toInt() : int.tryParse('${days ?? ''}'),
    autoRenew: boolField(map, const ['autoextend', 'auto_renew', 'autoRenew']),
  );
}

CustomerTicketAiDraft? _aiDraftFromMap(Object? value) {
  final map = jsonMapOrNull(value);
  if (map == null || map.isEmpty) return null;
  final text = stringField(map, const ['text', 'draft', 'reply']).trim();
  if (text.isEmpty) return null;
  final meta = jsonMap(field(map, const ['meta']));
  Object? pick(List<String> keys) => field(meta, keys) ?? field(map, keys);
  final confidence = pick(const ['confidence']);
  String textOf(List<String> keys) => pick(keys)?.toString().trim() ?? '';
  bool flag(List<String> keys) {
    final raw = pick(keys);
    return raw == true || raw?.toString().toLowerCase() == 'true';
  }

  return CustomerTicketAiDraft(
    text: text,
    confidence: confidence is num
        ? confidence.toDouble()
        : double.tryParse(confidence?.toString() ?? ''),
    category: textOf(const ['category']),
    model: textOf(const ['model']),
    needsHuman: flag(const ['needs_human', 'needsHuman']),
    reason: textOf(const ['reason']),
    suggestedCommand: textOf(const ['suggested_command', 'suggestedCommand']),
    status: textOf(const ['status']),
    usedFallback: flag(const ['used_fallback', 'usedFallback']),
    createdAt: parseCustomerTicketTime(
      field(map, const ['created_at', 'createdAt']),
    ),
  );
}

String _base(String workspaceId) =>
    '/api/v1/workspaces/${_e(workspaceId)}/order-tickets';

String _ticketPath(String workspaceId, String ticketId) =>
    '${_base(workspaceId)}/${_e(ticketId)}';

String _e(String value) => Uri.encodeComponent(value.trim());
