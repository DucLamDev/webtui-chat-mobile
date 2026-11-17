import 'chat_message.dart';
import 'conversation_summary.dart';

/// Người đang gọi tới, hiện ở màn cuộc gọi đến (tên, ảnh, giới tính cho hình
/// người mặc định khi chưa có ảnh).
final class IncomingCaller {
  const IncomingCaller({
    required this.name,
    this.avatarUrl,
    this.gender,
    this.userId,
  });

  final String name;
  final String? avatarUrl;
  final String? gender;
  final String? userId;

  /// Thêm ảnh / giới tính từ [other] khi bản này còn thiếu (giữ tên của bản này).
  IncomingCaller mergedWith(IncomingCaller? other) {
    if (other == null) return this;
    return IncomingCaller(
      name: name,
      avatarUrl: _filled(avatarUrl) ?? _filled(other.avatarUrl),
      gender: _filled(gender) ?? _filled(other.gender),
      userId: _filled(userId) ?? _filled(other.userId),
    );
  }
}

/// Tìm người gọi trong dữ liệu đã có: danh bạ / thành viên workspace theo mã
/// người gọi, rồi cuộc trò chuyện 1-1 của cuộc gọi (tên, ảnh người kia), rồi
/// thành viên của cuộc trò chuyện tải từ máy chủ ([members]). Null khi không
/// tìm được tên.
///
/// Sự kiện `CallInvited` (WebSocket) và bản hỏi định kỳ chỉ có mã người gọi,
/// không kèm tên: trước đây app chỉ tra danh bạ đã tải sẵn nên màn cuộc gọi đến
/// hay chỉ ghi "Cuộc gọi đến".
IncomingCaller? findIncomingCaller({
  required String initiatorUserId,
  required String channelId,
  Iterable<ContactSummary> people = const [],
  Iterable<ConversationSummary> conversations = const [],
  Iterable<ChannelMember> members = const [],
}) {
  final userId = initiatorUserId.trim();
  final channel = channelId.trim();
  if (userId.isNotEmpty) {
    for (final person in people) {
      if (person.userId.trim() != userId) continue;
      final name = _filled(person.displayName);
      if (name != null) {
        return IncomingCaller(
          name: name,
          avatarUrl: _filled(person.avatarUrl),
          gender: _filled(person.gender),
          userId: userId,
        );
      }
    }
  }
  if (channel.isNotEmpty) {
    for (final conversation in conversations) {
      if (conversation.channelId.trim() != channel ||
          conversation.kind != ConversationKind.direct) {
        continue;
      }
      final peer = conversation.peerUserId?.trim() ?? '';
      if (userId.isNotEmpty && peer.isNotEmpty && peer != userId) continue;
      final name = _filled(conversation.title);
      if (name != null) {
        return IncomingCaller(
          name: name,
          avatarUrl: _filled(conversation.avatarUrl),
          gender: _filled(conversation.gender),
          userId: userId.isEmpty ? null : userId,
        );
      }
    }
  }
  if (userId.isNotEmpty) {
    for (final member in members) {
      if (member.userId.trim() != userId) continue;
      final name = _filled(member.displayName) ?? _filled(member.username);
      if (name != null) {
        return IncomingCaller(
          name: name,
          avatarUrl: _filled(member.avatarUrl),
          gender: _filled(member.gender),
          userId: userId,
        );
      }
    }
  }
  return null;
}

String? _filled(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}
