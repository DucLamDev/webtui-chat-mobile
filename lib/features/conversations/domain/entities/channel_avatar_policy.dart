import 'conversation_summary.dart';

/// Ai được đổi ảnh đại diện của kênh (chỉ để hiện / ẩn nút; máy chủ kiểm lại):
/// - Nhóm (kênh `private`): mọi thành viên đang tham gia.
/// - Kênh công khai: chỉ người quản lý (`can_manage`).
/// - Không có cho chat 1-1, phiên bot riêng, chat bot thông báo.
bool canChangeChannelAvatar(ConversationSummary? channel) {
  if (channel == null) return false;
  if (channel.kind != ConversationKind.channel ||
      channel.channelVisibility == ChannelVisibility.direct ||
      channel.privateSessionMode ||
      channel.noticeBot) {
    return false;
  }
  return switch (channel.channelVisibility) {
    ChannelVisibility.private => channel.isMember,
    ChannelVisibility.public => channel.canManage,
    ChannelVisibility.direct => false,
  };
}
