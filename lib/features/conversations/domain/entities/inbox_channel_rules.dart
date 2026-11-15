import 'conversation_summary.dart';

/// Mã (`slug`) của ba kênh nội bộ mặc định mỗi workspace: Chung, Thông báo,
/// Trò chuyện (tên tiếng Anh cũ và tên tiếng Việt). Ba kênh này luôn nằm ở
/// Tin nhắn dù chưa có tin nào.
const defaultInternalChannelSlugs = {
  'general',
  'announcements',
  'random',
  'chung',
  'thong-bao',
  'tro-chuyen',
};

/// Kênh nội bộ mặc định (Chung / Thông báo / Trò chuyện), so theo `slug` không
/// phân biệt hoa thường; kênh không có `slug` không phải kênh mặc định.
bool isDefaultInternalChannel(String? slug) {
  final normalized = slug?.trim().toLowerCase() ?? '';
  return normalized.isNotEmpty &&
      defaultInternalChannelSlugs.contains(normalized);
}

/// Kênh (nhóm) có được vào danh sách Tin nhắn không:
/// - phiên hỗ trợ riêng, kênh bot nghiệp vụ, chat bot thông báo: giữ như cũ
///   (luật ẩn / tab Nghiệp vụ xử lý riêng);
/// - kênh chưa tham gia: không (chỉ thấy ở Danh bạ > Kênh);
/// - kênh nội bộ mặc định đã tham gia: luôn có;
/// - kênh khác đã tham gia: khi đã có tin ([ConversationSummary.lastMessageAt]),
///   còn tin chưa đọc, hoặc đang mở ([openChannelId]). Máy chủ cũ chưa trả
///   `last_message_at` thì kênh khác coi như chưa có tin.
bool shouldShowChannelInInbox(
  ConversationSummary channel, {
  String? openChannelId,
}) {
  if (channel.kind != ConversationKind.channel) return true;
  if (channel.privateSessionMode) return true;
  if (!channel.isMember) return false;
  if (channel.isAutomation || channel.noticeBot) return true;
  if (isDefaultInternalChannel(channel.slug)) return true;
  if (channel.hasMessages || channel.isUnread) return true;
  return openChannelId != null && channel.channelId == openChannelId;
}

/// Gộp chat 1-1 và kênh cho Tin nhắn: bỏ trùng theo `channelId` (bản trong
/// [directs] được giữ), lọc kênh theo [shouldShowChannelInInbox], rồi xếp theo
/// [compareInboxConversations].
List<ConversationSummary> mergeInboxConversations({
  required Iterable<ConversationSummary> directs,
  required Iterable<ConversationSummary> channels,
  String? openChannelId,
}) {
  final seen = <String>{};
  final items = <ConversationSummary>[];
  for (final direct in directs) {
    if (seen.add(direct.channelId)) items.add(direct);
  }
  for (final channel in channels) {
    if (!shouldShowChannelInInbox(channel, openChannelId: openChannelId)) {
      continue;
    }
    if (seen.add(channel.channelId)) items.add(channel);
  }
  items.sort(compareInboxConversations);
  return items;
}

/// Ghim trước; sau đó hội thoại có tin mới nhất trước; bằng thời gian thì
/// hội thoại chưa đọc trước, rồi theo tên để thứ tự ổn định.
int compareInboxConversations(
  ConversationSummary left,
  ConversationSummary right,
) {
  if (left.favorite != right.favorite) return left.favorite ? -1 : 1;
  final byTime = right.updatedAt.compareTo(left.updatedAt);
  if (byTime != 0) return byTime;
  if (left.isUnread != right.isUnread) return left.isUnread ? -1 : 1;
  return left.title.toLowerCase().compareTo(right.title.toLowerCase());
}
