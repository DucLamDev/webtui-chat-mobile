import '../../conversations/domain/entities/business_channel_catalog.dart';
import '../../conversations/domain/entities/conversation_summary.dart';
import 'customer_ticket_access_policy.dart';

/// `slug` của kênh bot "Ticket" trong danh mục kênh nghiệp vụ.
const customerTicketChannelSlug = 'ticket';

/// Đường mở khi bấm [conversation] trong hộp thư: kênh bot "Ticket" mở thẳng
/// hộp thư ticket khách (giống mục Ticket trên web) nếu người dùng xem được
/// ticket; kèm mã kênh để màn ticket có nút quay lại kênh chat (dùng lệnh bot).
/// Còn lại trả `null`: mở phòng chat như thường.
String? customerTicketLocationForConversation(
  ConversationSummary conversation,
  CustomerTicketAccess access,
) {
  if (!access.canView || !conversation.isAutomation) return null;
  final definition = businessChannelDefinitionOf(conversation);
  if (definition?.slug != customerTicketChannelSlug) return null;
  final workspaceId = conversation.workspaceId.trim();
  final channelId = conversation.channelId.trim();
  return Uri(
    path: '/customer-tickets',
    queryParameters: {
      if (workspaceId.isNotEmpty) 'workspaceId': workspaceId,
      if (channelId.isNotEmpty) 'channelId': channelId,
      if (channelId.isNotEmpty) 'channelTitle': conversation.title,
    },
  ).toString();
}

/// Đường mở kênh chat bot "Ticket" từ màn ticket (để gõ lệnh `/ticket`,
/// `/user`...). `null` khi không biết kênh.
String? customerTicketChannelChatLocation({
  required String? channelId,
  required String? channelTitle,
  required String? workspaceId,
}) {
  final id = channelId?.trim() ?? '';
  if (id.isEmpty) return null;
  final workspace = workspaceId?.trim() ?? '';
  final title = channelTitle?.trim() ?? '';
  return Uri(
    path: '/conversations/$id',
    queryParameters: {
      if (workspace.isNotEmpty) 'workspaceId': workspace,
      'title': title.isEmpty ? 'Ticket' : title,
      'kind': ConversationKind.channel.name,
    },
  ).toString();
}
