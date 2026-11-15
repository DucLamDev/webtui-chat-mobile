import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/features/conversations/domain/entities/channel_avatar_policy.dart';
import 'package:webtui_chat/features/conversations/domain/entities/conversation_summary.dart';

ConversationSummary channel({
  ConversationKind kind = ConversationKind.channel,
  ChannelVisibility visibility = ChannelVisibility.private,
  MembershipStatus membership = MembershipStatus.active,
  bool canManage = false,
  bool privateSessionMode = false,
  bool noticeBot = false,
}) {
  return ConversationSummary(
    id: 'ch',
    workspaceId: 'ws',
    channelId: 'ch',
    kind: kind,
    title: 'Nhóm',
    preview: '',
    updatedAt: DateTime.utc(2026, 11, 15),
    channelVisibility: visibility,
    membershipStatus: membership,
    canManage: canManage,
    privateSessionMode: privateSessionMode,
    noticeBot: noticeBot,
  );
}

void main() {
  group('canChangeChannelAvatar', () {
    test('mọi thành viên nhóm (kênh private) đổi được', () {
      expect(canChangeChannelAvatar(channel()), isTrue);
      expect(
        canChangeChannelAvatar(channel(membership: MembershipStatus.muted)),
        isTrue,
      );
    });

    test('không phải thành viên nhóm thì không', () {
      expect(
        canChangeChannelAvatar(channel(membership: MembershipStatus.invited)),
        isFalse,
      );
      expect(
        canChangeChannelAvatar(channel(membership: MembershipStatus.none)),
        isFalse,
      );
    });

    test('kênh công khai: chỉ người quản lý', () {
      expect(
        canChangeChannelAvatar(channel(visibility: ChannelVisibility.public)),
        isFalse,
      );
      expect(
        canChangeChannelAvatar(
          channel(visibility: ChannelVisibility.public, canManage: true),
        ),
        isTrue,
      );
    });

    test('chat 1-1, phiên bot riêng, chat bot thông báo: không', () {
      expect(
        canChangeChannelAvatar(
          channel(
            kind: ConversationKind.direct,
            visibility: ChannelVisibility.direct,
          ),
        ),
        isFalse,
      );
      expect(
        canChangeChannelAvatar(channel(privateSessionMode: true)),
        isFalse,
      );
      expect(
        canChangeChannelAvatar(channel(noticeBot: true, canManage: true)),
        isFalse,
      );
      expect(canChangeChannelAvatar(null), isFalse);
    });
  });
}
