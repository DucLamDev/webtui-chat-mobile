import 'chat_message.dart';

/// Trạng thái lưu / đồng bộ tin nhắn trên máy của một cuộc trò chuyện.
///
/// Tin lưu trên máy là MỘT đoạn liền mạch tính từ tin mới nhất trở về trước
/// tới [oldestMessageId]; cũ hơn mốc đó (chưa lưu) thì phải hỏi máy chủ.
final class ChannelSyncState {
  const ChannelSyncState({
    required this.workspaceId,
    required this.channelId,
    this.changeCursor,
    this.oldestMessageId,
    this.oldestCreatedAt,
    this.reachedBeginning = false,
    this.syncedAt,
  });

  final String workspaceId;
  final String channelId;

  /// Mốc của luồng thay đổi máy chủ (`next_cursor` của
  /// `GET .../messages/changes`); null = chưa đồng bộ lần nào.
  final String? changeCursor;

  /// Tin cũ nhất của đoạn liền mạch đã lưu; null = chưa lưu tin nào.
  final String? oldestMessageId;
  final DateTime? oldestCreatedAt;

  /// Đã lưu tới tin đầu tiên của cuộc trò chuyện (không còn gì cũ hơn).
  final bool reachedBeginning;

  /// Lần đồng bộ xong gần nhất.
  final DateTime? syncedAt;

  ChannelSyncState copyWith({
    String? changeCursor,
    String? oldestMessageId,
    DateTime? oldestCreatedAt,
    bool? reachedBeginning,
    DateTime? syncedAt,
    bool clearChangeCursor = false,
    bool clearOldest = false,
  }) {
    return ChannelSyncState(
      workspaceId: workspaceId,
      channelId: channelId,
      changeCursor: clearChangeCursor
          ? null
          : changeCursor ?? this.changeCursor,
      oldestMessageId: clearOldest
          ? null
          : oldestMessageId ?? this.oldestMessageId,
      oldestCreatedAt: clearOldest
          ? null
          : oldestCreatedAt ?? this.oldestCreatedAt,
      reachedBeginning: reachedBeginning ?? this.reachedBeginning,
      syncedAt: syncedAt ?? this.syncedAt,
    );
  }
}

/// Một trang của luồng thay đổi tin (`GET .../channels/{id}/messages/changes`).
final class MessageChangesPage {
  const MessageChangesPage({
    required this.messages,
    required this.nextCursor,
    this.hasMore = false,
    this.clearedAt,
  });

  /// Tin mới / đã sửa / đã xoá theo thứ tự thay đổi. Tin đã xoá là "bia mộ"
  /// ([ChatMessage.isDeleted], không còn nội dung): xoá khỏi máy.
  final List<ChatMessage> messages;

  /// Mốc để hỏi lần sau (luôn có, kể cả khi không có thay đổi).
  final String nextCursor;

  /// Còn trang sau: hỏi tiếp ngay với [nextCursor].
  final bool hasMore;

  /// Người dùng đã xoá lịch sử cuộc trò chuyện tới mốc này (máy khác): xoá
  /// mọi tin tạo trước / bằng mốc đó trên máy.
  final DateTime? clearedAt;
}
