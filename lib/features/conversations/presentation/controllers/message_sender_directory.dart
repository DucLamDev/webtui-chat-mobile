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

/// Khoảng cách tối đa giữa hai tin liền nhau cùng người gửi để còn tính là
/// một cụm (quá mức này thì tin sau được coi là mở đầu cụm mới).
const messageRunGap = Duration(minutes: 5);

/// Tin [message] có mở đầu một cụm tin liên tiếp cùng người gửi không: tin đầu
/// danh sách, khác người gửi, sang ngày khác (mốc ngày) hoặc cách tin trước
/// quá [messageRunGap].
bool startsSenderRun(ChatMessage? previous, ChatMessage message) {
  if (previous == null) return true;
  if (previous.senderId != message.senderId) return true;
  final a = previous.createdAt.toLocal();
  final b = message.createdAt.toLocal();
  if (a.year != b.year || a.month != b.month || a.day != b.day) return true;
  return b.difference(a).abs() > messageRunGap;
}

/// Tên người gửi in phía trên tin; null khi không nên hiện: tin của mình, tin
/// không mở đầu cụm, hoặc chưa biết tên (không bao giờ hiện mã người gửi).
String? senderNameToShow({
  required ChatMessage message,
  required ChatMessage? previous,
  required MessageSenderDirectory directory,
}) {
  if (message.isMine || !startsSenderRun(previous, message)) return null;
  final name = directory[message.senderId]?.name.trim();
  if (name == null ||
      name.isEmpty ||
      name == MessageSenderDirectory.unknownSenderName) {
    return null;
  }
  return name;
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
