import 'dart:typed_data';

/// Giới hạn của máy chủ cho hộp thư ticket khách (giữ khớp để báo lỗi sớm).
const customerTicketDefaultPageSize = 30;
const customerTicketMaxPageSize = 50;
const customerTicketMaxSearchLength = 120;
const customerTicketMaxReplyLength = 4000;
const customerTicketMaxImages = 3;
const customerTicketMaxImageBytes = 5 * 1024 * 1024;
const customerTicketMaxInstructionLength = 1000;
const customerTicketAllowedImageTypes = {
  'image/png',
  'image/jpeg',
  'image/gif',
  'image/webp',
};

/// Bộ lọc danh sách: Chưa trả lời / Đã trả lời / Tất cả.
enum CustomerTicketFilter { unanswered, answered, all }

extension CustomerTicketFilterApi on CustomerTicketFilter {
  String get apiValue => switch (this) {
    CustomerTicketFilter.unanswered => 'unanswered',
    CustomerTicketFilter.answered => 'answered',
    CustomerTicketFilter.all => 'all',
  };
}

enum CustomerTicketStatus { unanswered, answered, closed, unknown }

extension CustomerTicketStatusApi on CustomerTicketStatus {
  String get apiValue => switch (this) {
    CustomerTicketStatus.unanswered => 'unanswered',
    CustomerTicketStatus.answered => 'answered',
    CustomerTicketStatus.closed => 'closed',
    CustomerTicketStatus.unknown => '',
  };
}

CustomerTicketStatus customerTicketStatusFromApi(String value) {
  return switch (value.trim().toLowerCase()) {
    'unanswered' => CustomerTicketStatus.unanswered,
    'answered' => CustomerTicketStatus.answered,
    'closed' => CustomerTicketStatus.closed,
    _ => CustomerTicketStatus.unknown,
  };
}

enum CustomerTicketSender { customer, staff }

CustomerTicketSender customerTicketSenderFromApi(String value) {
  return switch (value.trim().toLowerCase()) {
    'staff' || 'admin' || 'agent' => CustomerTicketSender.staff,
    _ => CustomerTicketSender.customer,
  };
}

/// Nhân viên đang nhận xử lý ticket.
final class CustomerTicketAssignee {
  const CustomerTicketAssignee({
    required this.userId,
    required this.name,
    this.assignedAt,
  });

  final String userId;
  final String name;
  final DateTime? assignedAt;

  bool isUser(String? currentUserId) {
    final me = currentUserId?.trim();
    return me != null && me.isNotEmpty && userId.trim() == me;
  }
}

final class CustomerTicketCounts {
  const CustomerTicketCounts({
    this.unanswered = 0,
    this.answered = 0,
    this.total = 0,
  });

  static const empty = CustomerTicketCounts();

  final int unanswered;
  final int answered;
  final int total;
}

/// Một dòng trong danh sách ticket.
final class CustomerTicketSummary {
  const CustomerTicketSummary({
    required this.ticketId,
    required this.status,
    this.customerId,
    this.customerName = '',
    this.customerEmail = '',
    this.service = '',
    this.createdAt,
    this.lastMessageAt,
    this.waitingSince,
    this.lastSender,
    this.lastStaffName = '',
    this.preview = '',
    this.newMessageCount = 0,
    this.assignee,
    this.hasAiDraft = false,
  });

  final String ticketId;
  final CustomerTicketStatus status;
  final String? customerId;
  final String customerName;
  final String customerEmail;
  final String service;
  final DateTime? createdAt;
  final DateTime? lastMessageAt;
  final DateTime? waitingSince;
  final CustomerTicketSender? lastSender;
  final String lastStaffName;
  final String preview;
  final int newMessageCount;
  final CustomerTicketAssignee? assignee;
  final bool hasAiDraft;

  bool get isUnanswered => status == CustomerTicketStatus.unanswered;

  String get customerLabel {
    final name = customerName.trim();
    if (name.isNotEmpty) return name;
    final email = customerEmail.trim();
    return email.isNotEmpty ? email : 'Khách';
  }

  /// Mốc tính "Chờ X phút": chỉ khi ticket còn chờ trả lời.
  DateTime? get waitingFrom =>
      isUnanswered ? (waitingSince ?? lastMessageAt) : null;
}

final class CustomerTicketPage {
  const CustomerTicketPage({
    required this.items,
    required this.total,
    required this.page,
    required this.perPage,
    required this.counts,
  });

  final List<CustomerTicketSummary> items;
  final int total;
  final int page;
  final int perPage;
  final CustomerTicketCounts counts;
}

final class CustomerTicketMessage {
  const CustomerTicketMessage({
    required this.messageId,
    required this.sender,
    this.senderName = '',
    this.text = '',
    this.images = const [],
    this.read = false,
    this.time,
  });

  final String messageId;
  final CustomerTicketSender sender;
  final String senderName;
  final String text;
  final List<String> images;
  final bool read;
  final DateTime? time;

  bool get fromStaff => sender == CustomerTicketSender.staff;

  /// Tin do trợ lý ảo tự trả lời (máy chủ ghi tên người gửi là "AI").
  bool get isAssistant => fromStaff && senderName.trim() == 'AI';

  String get displaySenderName {
    final name = senderName.trim();
    if (!fromStaff) return name.isEmpty ? 'Khách' : name;
    if (name == 'AI') return 'Trợ lý ảo';
    return name.isEmpty ? 'Nhân viên' : name;
  }
}

final class CustomerTicketService {
  const CustomerTicketService({
    required this.id,
    this.name = '',
    this.type = '',
    this.status = '',
    this.meta = '',
    this.expiresAt,
    this.daysRemaining,
    this.autoRenew = false,
  });

  final String id;
  final String name;
  final String type;
  final String status;
  final String meta;
  final DateTime? expiresAt;
  final int? daysRemaining;
  final bool autoRenew;
}

final class CustomerTicketCustomer {
  const CustomerTicketCustomer({
    this.customerId,
    this.name = '',
    this.email = '',
    this.balance,
    this.services = const [],
    this.servicesTotal = 0,
  });

  final String? customerId;
  final String name;
  final String email;
  final double? balance;
  final List<CustomerTicketService> services;
  final int servicesTotal;
}

/// Bản nháp trả lời do AI soạn (chỉ để nhân viên xem / chép, chưa gửi khách).
final class CustomerTicketAiDraft {
  const CustomerTicketAiDraft({
    required this.text,
    this.confidence,
    this.category = '',
    this.model = '',
    this.needsHuman = false,
    this.reason = '',
    this.suggestedCommand = '',
    this.status = '',
    this.usedFallback = false,
    this.createdAt,
  });

  final String text;

  /// 0..1 (máy chủ cũ có thể trả 0..100).
  final double? confidence;
  final String category;
  final String model;
  final bool needsHuman;
  final String reason;
  final String suggestedCommand;
  final String status;
  final bool usedFallback;
  final DateTime? createdAt;

  int? get confidencePercent {
    final value = confidence;
    if (value == null || value.isNaN || value < 0) return null;
    final percent = value <= 1 ? value * 100 : value;
    return percent.clamp(0, 100).round();
  }
}

final class CustomerTicketInfo {
  const CustomerTicketInfo({
    required this.ticketId,
    required this.status,
    this.service = '',
    this.createdAt,
    this.messageCount = 0,
    this.truncated = false,
    this.adminUrl = '',
  });

  final String ticketId;
  final CustomerTicketStatus status;
  final String service;
  final DateTime? createdAt;
  final int messageCount;
  final bool truncated;
  final String adminUrl;
}

final class CustomerTicketDetail {
  const CustomerTicketDetail({
    required this.ticket,
    this.customer,
    this.messages = const [],
    this.assignee,
    this.aiDraft,
  });

  final CustomerTicketInfo ticket;
  final CustomerTicketCustomer? customer;
  final List<CustomerTicketMessage> messages;
  final CustomerTicketAssignee? assignee;
  final CustomerTicketAiDraft? aiDraft;

  String get customerLabel {
    final name = customer?.name.trim() ?? '';
    if (name.isNotEmpty) return name;
    final email = customer?.email.trim() ?? '';
    if (email.isNotEmpty) return email;
    for (final message in messages) {
      if (!message.fromStaff && message.senderName.trim().isNotEmpty) {
        return message.senderName.trim();
      }
    }
    return 'Khách';
  }
}

final class CustomerTicketReplyResult {
  const CustomerTicketReplyResult({
    required this.ticketId,
    this.messageId = '',
    this.repliedBy = '',
    this.duplicate = false,
    this.status = '',
  });

  final String ticketId;
  final String messageId;
  final String repliedBy;
  final bool duplicate;
  final String status;
}

/// Ảnh đã chọn (đã nén trên máy) chờ gửi kèm câu trả lời.
final class CustomerTicketImageUpload {
  const CustomerTicketImageUpload({
    required this.name,
    required this.mimeType,
    required this.bytes,
  });

  final String name;
  final String mimeType;
  final Uint8List bytes;

  int get byteSize => bytes.lengthInBytes;
}

enum CustomerTicketImageSource { gallery, camera }

/// Kết quả chọn ảnh: ảnh hợp lệ và lý do bỏ ảnh không hợp lệ (nếu có).
final class CustomerTicketImagePick {
  const CustomerTicketImagePick({this.images = const [], this.rejectedReason});

  final List<CustomerTicketImageUpload> images;
  final String? rejectedReason;
}
