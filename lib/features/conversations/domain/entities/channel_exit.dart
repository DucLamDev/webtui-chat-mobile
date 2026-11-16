import 'conversation_summary.dart';

/// Kết quả rời nhóm. [archived] = `true` khi mình là thành viên cuối cùng nên
/// máy chủ tự lưu trữ nhóm.
final class ChannelLeaveResult {
  const ChannelLeaveResult({required this.channelId, required this.archived});

  final String channelId;
  final bool archived;
}

/// Kênh có phải loại được rời / xoá từ app không: không áp dụng cho chat 1-1,
/// phiên bot riêng, chat bot thông báo, kênh automation.
bool _isExitableChannel(ConversationSummary channel) {
  return channel.kind == ConversationKind.channel &&
      channel.channelVisibility != ChannelVisibility.direct &&
      !channel.privateSessionMode &&
      !channel.noticeBot &&
      !channel.isAutomation;
}

/// Hiện nút "Rời nhóm" (chỉ để hiện / ẩn; máy chủ kiểm lại khi gọi): máy chủ
/// cho rời (`can_leave`) và kênh là nhóm (kênh `private` thường).
bool canLeaveGroup(ConversationSummary? channel) {
  if (channel == null || !channel.canLeave) return false;
  return _isExitableChannel(channel) &&
      channel.channelVisibility == ChannelVisibility.private;
}

/// Hiện nút "Xoá nhóm" (lưu trữ cho mọi thành viên): máy chủ cho xoá
/// (`can_delete`: người tạo nhóm hoặc quản trị). Quản trị có thể xoá cả kênh
/// công khai nên không giới hạn ở kênh `private`.
bool canDeleteGroup(ConversationSummary? channel) {
  if (channel == null || !channel.canDelete) return false;
  return _isExitableChannel(channel);
}
