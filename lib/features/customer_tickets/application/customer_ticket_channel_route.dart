import '../../conversations/domain/entities/conversation_summary.dart';
import 'customer_ticket_access_policy.dart';

/// `slug` của kênh bot "Ticket" trong danh mục kênh nghiệp vụ.
const customerTicketChannelSlug = 'ticket';

/// Hộp thư ticket khách hàng (giống mục Ticket trên web).
String customerTicketInboxLocation(String? workspaceId) {
  final workspace = workspaceId?.trim() ?? '';
  return Uri(
    path: '/customer-tickets',
    queryParameters: workspace.isEmpty ? null : {'workspaceId': workspace},
  ).toString();
}

/// [conversation] có phải kênh "Ticket" (kênh bot gốc hoặc phiên riêng mở từ
/// kênh đó) không.
///
/// - Có `slug`: chỉ khớp `ticket`.
/// - Không có `slug` (máy chủ cũ, hoặc phiên riêng: máy chủ tạo phòng 1-1 không
///   slug, đặt tên theo kênh gốc): tên "Ticket" và là kênh bot / phiên riêng
///   (phòng 1-1 không có người nhận). Nhóm thường hay người dùng tên "Ticket"
///   không khớp.
bool isCustomerTicketChannel(ConversationSummary conversation) {
  final slug = conversation.slug?.trim().toLowerCase() ?? '';
  if (slug.isNotEmpty) return slug == customerTicketChannelSlug;
  if (conversation.title.trim().toLowerCase() != customerTicketChannelSlug) {
    return false;
  }
  final peer = conversation.peerUserId?.trim() ?? '';
  final botSession =
      conversation.kind == ConversationKind.direct && peer.isEmpty;
  return conversation.isAutomation ||
      conversation.privateSessionMode ||
      botSession;
}

/// Đường mở khi bấm [conversation]: kênh "Ticket" luôn mở thẳng hộp thư ticket
/// khách (không vào phòng chat bot) nếu người dùng xem được ticket. Còn lại
/// trả `null`: mở phòng chat như thường.
String? customerTicketLocationForConversation(
  ConversationSummary conversation,
  CustomerTicketAccess access,
) {
  if (!access.canView || !isCustomerTicketChannel(conversation)) return null;
  return customerTicketInboxLocation(conversation.workspaceId);
}
