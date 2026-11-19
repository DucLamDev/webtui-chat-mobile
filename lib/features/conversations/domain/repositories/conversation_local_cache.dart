import '../entities/chat_message.dart';
import '../entities/conversation_summary.dart';

/// Đọc danh sách hội thoại đã lưu trên máy (không gọi máy chủ): mở app / mở
/// tab hiện ngay bản đã lưu rồi mới làm mới ngầm. `null` = chưa từng lưu.
abstract interface class ConversationListCacheReader {
  Future<List<ConversationSummary>?> readCachedDirectConversations({
    required String workspaceId,
  });

  Future<List<ConversationSummary>?> readCachedChannels({
    required String workspaceId,
  });
}

/// Danh sách thành viên mỗi nhóm lưu trên máy (theo máy chủ, workspace, nhóm).
/// Lỗi đọc / ghi bộ đệm không được làm hỏng luồng chính: bên gọi bỏ qua lỗi.
abstract interface class ChannelMemberCache {
  /// `null` = chưa lưu (hoặc bản lưu hỏng).
  Future<List<ChannelMember>?> readMembers({
    required String workspaceId,
    required String channelId,
  });

  Future<void> saveMembers({
    required String workspaceId,
    required String channelId,
    required List<ChannelMember> members,
  });

  /// Thêm / thay một thành viên trong bản đã lưu (vừa mời / vừa duyệt). Chưa
  /// có bản lưu thì bỏ qua (lần tải sau lưu cả danh sách).
  Future<void> upsertMember({
    required String workspaceId,
    required String channelId,
    required ChannelMember member,
  });

  Future<void> removeMembers({
    required String workspaceId,
    required String channelId,
  });
}
