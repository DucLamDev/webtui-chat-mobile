import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers/foundation_providers.dart';
import '../../../../core/result/result.dart';
import '../../domain/entities/chat_message.dart';
import 'chat_room_controller.dart';

/// Tên và ảnh hiển thị của người gửi tin.
final class MessageSenderProfile {
  const MessageSenderProfile({required this.name, this.avatarUrl});

  final String name;
  final String? avatarUrl;
}

/// Tra người gửi theo `sender_id`: máy chủ chỉ gửi mã người gửi kèm tin nhắn,
/// tên / ảnh lấy từ danh sách thành viên phòng (kể cả người đã rời phòng).
final class MessageSenderDirectory {
  const MessageSenderDirectory._(this._byUserId);

  const MessageSenderDirectory.empty() : _byUserId = const {};

  factory MessageSenderDirectory.fromMembers(Iterable<ChannelMember> members) {
    final byUserId = <String, MessageSenderProfile>{};
    for (final member in members) {
      final userId = member.userId.trim();
      if (userId.isEmpty) continue;
      final avatarUrl = member.avatarUrl?.trim();
      byUserId[userId] = MessageSenderProfile(
        name: _displayName(member),
        avatarUrl: avatarUrl == null || avatarUrl.isEmpty ? null : avatarUrl,
      );
    }
    return MessageSenderDirectory._(byUserId);
  }

  static const unknownSenderName = 'Người dùng';

  final Map<String, MessageSenderProfile> _byUserId;

  int get length => _byUserId.length;

  MessageSenderProfile? operator [](String? userId) {
    final key = userId?.trim();
    if (key == null || key.isEmpty) return null;
    return _byUserId[key];
  }

  String nameOf(String? userId) => this[userId]?.name ?? unknownSenderName;
}

String _displayName(ChannelMember member) {
  for (final candidate in [member.displayName, member.username]) {
    final value = candidate.trim();
    if (value.isNotEmpty) return value;
  }
  final email = member.email.trim();
  if (email.isNotEmpty) return email.split('@').first;
  return MessageSenderDirectory.unknownSenderName;
}

/// Danh bạ người gửi của một phòng; lỗi mạng thì trả danh bạ rỗng (tin vẫn hiện,
/// chỉ thiếu tên) để không chặn màn chat.
final messageSenderDirectoryProvider = FutureProvider.autoDispose
    .family<MessageSenderDirectory, ChatRoomScope>((ref, scope) async {
      final result = await ref
          .watch(listChannelMembersUseCaseProvider)
          .execute(workspaceId: scope.workspaceId, channelId: scope.channelId);
      return switch (result) {
        Success(value: final members) => MessageSenderDirectory.fromMembers(
          members,
        ),
        FailureResult() => const MessageSenderDirectory.empty(),
      };
    });
