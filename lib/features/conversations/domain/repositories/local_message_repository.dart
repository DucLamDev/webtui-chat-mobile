import '../entities/chat_message.dart';
import '../entities/message_sync.dart';

/// Kho tin nhắn lưu trên máy (giai đoạn 2 bộ đệm: lưu đủ tin, chỉ hỏi máy chủ
/// phần thay đổi; mở cuộc trò chuyện / không có mạng vẫn đọc được).
///
/// Mọi thao tác trong vùng của máy chủ đang đăng nhập; đăng xuất xoá cùng dữ
/// liệu khác của máy chủ đó. Tin trả về xếp từ CŨ tới MỚI.
abstract interface class LocalMessageRepository {
  /// [limit] tin mới nhất của cuộc trò chuyện.
  Future<List<ChatMessage>> readLatest({
    required String workspaceId,
    required String channelId,
    int limit = 50,
  });

  /// [limit] tin ngay trước tin ([beforeCreatedAt], [beforeId]) (cùng thứ tự
  /// máy chủ: thời điểm tạo rồi tới mã tin).
  Future<List<ChatMessage>> readBefore({
    required String workspaceId,
    required String channelId,
    required DateTime beforeCreatedAt,
    required String beforeId,
    int limit = 50,
  });

  /// Ghi / ghi đè theo mã tin. Tin đã xoá ([ChatMessage.isDeleted]) và tin tạm
  /// (`local-…`) không được lưu: tin đã xoá thì xoá dòng có sẵn.
  Future<void> upsert({
    required String workspaceId,
    required String channelId,
    required List<ChatMessage> messages,
  });

  Future<void> remove({
    required String workspaceId,
    required String channelId,
    required List<String> messageIds,
  });

  /// Xoá mọi tin tạo trước / bằng [clearedAt] (người dùng xoá lịch sử).
  Future<void> removeCreatedUpTo({
    required String workspaceId,
    required String channelId,
    required DateTime clearedAt,
  });

  Future<ChannelSyncState?> readSyncState({
    required String workspaceId,
    required String channelId,
  });

  Future<void> writeSyncState(ChannelSyncState state);

  /// Tìm trong tin đã lưu của cuộc trò chuyện: chứa đủ mọi từ của [query]
  /// (không phân biệt hoa thường / dấu, xem `normalizeSearchText`), mới nhất
  /// trước, tối đa [limit] tin.
  Future<List<ChatMessage>> search({
    required String workspaceId,
    required String channelId,
    required String query,
    int limit = 50,
  });

  /// Xoá mọi tin + trạng thái đồng bộ của một cuộc trò chuyện (rời nhóm, máy
  /// chủ báo phải tải lại từ đầu).
  Future<void> clearChannel({
    required String workspaceId,
    required String channelId,
  });
}
