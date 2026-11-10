/// Hộp thư khách đa kênh (Lõi 6): các đối tượng đọc từ máy chủ. Trường thiếu
/// hoặc `null` dùng giá trị an toàn (vd. `can_reply` thiếu = không được trả lời).
enum InboxStatus {
  open('open', 'Đang mở'),
  pending('pending', 'Chờ khách'),
  closed('closed', 'Đã đóng'),
  unknown('', 'Không rõ');

  const InboxStatus(this.apiValue, this.label);

  final String apiValue;
  final String label;

  static InboxStatus fromApi(String? value) {
    final text = value?.trim().toLowerCase() ?? '';
    for (final status in values) {
      if (status != unknown && status.apiValue == text) return status;
    }
    return unknown;
  }
}

/// Lọc theo trạng thái ở danh sách (`null` = tất cả).
enum InboxStatusFilter {
  all(null, 'Tất cả'),
  open(InboxStatus.open, 'Đang mở'),
  pending(InboxStatus.pending, 'Chờ khách'),
  closed(InboxStatus.closed, 'Đã đóng');

  const InboxStatusFilter(this.status, this.label);

  final InboxStatus? status;
  final String label;

  String? get apiValue => status?.apiValue;
}

/// Lọc theo người xử lý.
enum InboxAssigneeFilter {
  all(null, 'Tất cả'),
  mine('me', 'Của tôi'),
  unassigned('none', 'Chưa gán');

  const InboxAssigneeFilter(this.apiValue, this.label);

  final String? apiValue;
  final String label;
}

enum InboxDirection { inbound, outbound }

enum InboxMessageKind { message, note }

enum InboxDelivery {
  received,
  queued,
  sending,
  sent,
  failed,
  unknown;

  static InboxDelivery fromApi(String? value) {
    return switch (value?.trim().toLowerCase()) {
      'received' => InboxDelivery.received,
      'queued' => InboxDelivery.queued,
      'sending' => InboxDelivery.sending,
      'sent' => InboxDelivery.sent,
      'failed' => InboxDelivery.failed,
      _ => InboxDelivery.unknown,
    };
  }

  /// Nhãn trạng thái gửi (chỉ dùng cho tin do nhân viên gửi).
  String? get label => switch (this) {
    InboxDelivery.queued => 'Đang chờ gửi',
    InboxDelivery.sending => 'Đang gửi',
    InboxDelivery.sent => 'Đã gửi',
    InboxDelivery.failed => 'Gửi lỗi',
    _ => null,
  };
}

final class InboxSourceSummary {
  const InboxSourceSummary({
    this.id = '',
    this.kind = '',
    this.name = '',
    this.code = '',
  });

  final String id;

  /// `email`, `facebook`, `zalo`, `webhook` (giá trị lạ vẫn hiển thị theo mã).
  final String kind;
  final String name;

  /// Mã ngắn (`em`, `fb`, `zl`, `wh`) cho chip nguồn.
  final String code;

  String get chipLabel {
    if (code.trim().isNotEmpty) return code.trim().toUpperCase();
    return switch (kind) {
      'email' => 'EM',
      'facebook' => 'FB',
      'zalo' => 'ZL',
      'webhook' => 'WH',
      _ => '?',
    };
  }

  String get kindLabel => switch (kind) {
    'email' => 'Email',
    'facebook' => 'Facebook',
    'zalo' => 'Zalo',
    'webhook' => 'Webhook',
    _ => name.isEmpty ? 'Nguồn khác' : name,
  };
}

final class InboxTag {
  const InboxTag({required this.id, required this.name, this.color = ''});

  final String id;
  final String name;
  final String color;
}

final class InboxContact {
  const InboxContact({
    this.id = '',
    this.displayName = '',
    this.email = '',
    this.phone = '',
    this.avatarUrl = '',
  });

  final String id;
  final String displayName;
  final String email;
  final String phone;
  final String avatarUrl;
}

final class InboxConversation {
  const InboxConversation({
    required this.id,
    this.workspaceId = '',
    this.source = const InboxSourceSummary(),
    this.contact = const InboxContact(),
    this.subject = '',
    this.status = InboxStatus.open,
    this.assigneeId,
    this.assigneeName = '',
    this.tags = const [],
    this.label = '',
    this.lastMessagePreview = '',
    this.lastMessageAt,
    this.lastInboundAt,
    this.unreadCount = 0,
    this.canReply = false,
    this.replyBlockedReason = '',
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String workspaceId;
  final InboxSourceSummary source;
  final InboxContact contact;
  final String subject;
  final InboxStatus status;
  final String? assigneeId;
  final String assigneeName;
  final List<InboxTag> tags;
  final String label;
  final String lastMessagePreview;
  final DateTime? lastMessageAt;
  final DateTime? lastInboundAt;
  final int unreadCount;
  final bool canReply;
  final String replyBlockedReason;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isAssigned => assigneeId?.isNotEmpty == true;

  bool isAssignedTo(String? userId) =>
      isAssigned && userId != null && userId.isNotEmpty && assigneeId == userId;

  /// Tên hiển thị: `label` của máy chủ, thiếu thì tên khách / tiêu đề.
  String get title {
    if (label.trim().isNotEmpty) return label.trim();
    if (contact.displayName.trim().isNotEmpty) {
      return contact.displayName.trim();
    }
    if (subject.trim().isNotEmpty) return subject.trim();
    return 'Khách';
  }
}

final class InboxMessage {
  const InboxMessage({
    required this.id,
    required this.conversationId,
    this.direction = InboxDirection.inbound,
    this.kind = InboxMessageKind.message,
    this.body = '',
    this.senderUserId,
    this.senderName = '',
    this.delivery = InboxDelivery.unknown,
    this.error = '',
    this.retryable = true,
    this.clientMessageId = '',
    required this.createdAt,
  });

  final String id;
  final String conversationId;
  final InboxDirection direction;
  final InboxMessageKind kind;
  final String body;
  final String? senderUserId;
  final String senderName;
  final InboxDelivery delivery;
  final String error;

  /// `false` khi lỗi gửi là vĩnh viễn (hết cửa sổ trả lời, nguồn tắt...): không mời "Gửi lại".
  final bool retryable;
  final String clientMessageId;
  final DateTime createdAt;

  /// Mã tạm của tin chỉ có trên máy (chưa được máy chủ xác nhận).
  static const localIdPrefix = 'local:';

  bool get isLocal => id.startsWith(localIdPrefix);

  bool get isNote => kind == InboxMessageKind.note;
  bool get isFromCustomer => direction == InboxDirection.inbound && !isNote;

  InboxMessage copyWith({
    InboxDelivery? delivery,
    String? error,
    String? id,
    bool? retryable,
  }) {
    return InboxMessage(
      id: id ?? this.id,
      conversationId: conversationId,
      direction: direction,
      kind: kind,
      body: body,
      senderUserId: senderUserId,
      senderName: senderName,
      delivery: delivery ?? this.delivery,
      error: error ?? this.error,
      retryable: retryable ?? this.retryable,
      clientMessageId: clientMessageId,
      createdAt: createdAt,
    );
  }
}

final class InboxConversationPage {
  const InboxConversationPage({required this.items, this.nextCursor});

  final List<InboxConversation> items;
  final String? nextCursor;
}

/// Trang tin nhắn: [items] xếp cũ → mới, [nextCursor] lấy trang cũ hơn.
final class InboxMessagePage {
  const InboxMessagePage({required this.items, this.nextCursor});

  final List<InboxMessage> items;
  final String? nextCursor;
}

/// Thay đổi gửi bằng PATCH; trường `null` là không đổi. [assigneeId] rỗng là
/// bỏ nhận; [tagIds] thay toàn bộ tag.
final class InboxConversationChange {
  const InboxConversationChange({this.status, this.assigneeId, this.tagIds});

  final InboxStatus? status;
  final String? assigneeId;
  final List<String>? tagIds;

  Map<String, Object?> toJson() => {
    if (status != null) 'status': status!.apiValue,
    'assignee_id': ?assigneeId,
    'tag_ids': ?tagIds,
  };
}

/// Sự kiện realtime của hộp thư khách.
sealed class InboxRealtimeEvent {
  const InboxRealtimeEvent();
}

final class InboxConversationUpdatedEvent extends InboxRealtimeEvent {
  const InboxConversationUpdatedEvent(this.conversation);

  final InboxConversation conversation;
}

final class InboxMessageCreatedEvent extends InboxRealtimeEvent {
  const InboxMessageCreatedEvent(this.message);

  final InboxMessage message;
}

/// Kết nối realtime vừa nối lại: tải lại dữ liệu.
final class InboxRealtimeReconnected extends InboxRealtimeEvent {
  const InboxRealtimeReconnected();
}
