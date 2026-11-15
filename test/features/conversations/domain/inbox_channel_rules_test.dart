import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/features/conversations/domain/entities/conversation_summary.dart';
import 'package:webtui_chat/features/conversations/domain/entities/inbox_channel_rules.dart';

void main() {
  group('isDefaultInternalChannel', () {
    test('nhận 6 slug kênh nội bộ, không phân biệt hoa thường', () {
      for (final slug in [
        'general',
        'announcements',
        'random',
        'chung',
        'thong-bao',
        'tro-chuyen',
        ' General ',
      ]) {
        expect(isDefaultInternalChannel(slug), isTrue, reason: slug);
      }
    });

    test('kênh khác / không có slug không phải kênh nội bộ', () {
      for (final slug in [null, '', 'orders', 'du-an-a', 'generalx']) {
        expect(isDefaultInternalChannel(slug), isFalse, reason: '$slug');
      }
    });
  });

  group('shouldShowChannelInInbox (có last_message_at)', () {
    test('kênh nội bộ chưa có tin vẫn hiện', () {
      expect(shouldShowChannelInInbox(_channel('g', slug: 'general')), isTrue);
      expect(
        shouldShowChannelInInbox(_channel('t', slug: 'tro-chuyen')),
        isTrue,
      );
    });

    test('kênh thường chưa có tin không hiện, có tin thì hiện', () {
      expect(shouldShowChannelInInbox(_channel('a')), isFalse);
      expect(shouldShowChannelInInbox(_channel('a', lastHour: 9)), isTrue);
    });

    test('kênh chưa tham gia không hiện, kể cả kênh nội bộ có tin', () {
      expect(
        shouldShowChannelInInbox(
          _channel('g', slug: 'general', lastHour: 9, member: false),
        ),
        isFalse,
      );
    });

    test('kênh bot nghiệp vụ, chat bot thông báo, phiên riêng giữ như cũ', () {
      expect(
        shouldShowChannelInInbox(
          _channel('o', slug: 'orders', automation: true),
        ),
        isTrue,
      );
      expect(shouldShowChannelInInbox(_channel('n', notice: true)), isTrue);
      expect(
        shouldShowChannelInInbox(
          _channel('s', member: false, privateSession: true),
        ),
        isTrue,
      );
    });
  });

  group('shouldShowChannelInInbox (máy chủ cũ, không có last_message_at)', () {
    test('kênh thường coi như chưa có tin: ẩn', () {
      expect(shouldShowChannelInInbox(_channel('a')), isFalse);
    });

    test('trừ kênh còn tin chưa đọc hoặc đang mở', () {
      expect(shouldShowChannelInInbox(_channel('a', unread: 2)), isTrue);
      expect(
        shouldShowChannelInInbox(_channel('a'), openChannelId: 'a'),
        isTrue,
      );
      expect(
        shouldShowChannelInInbox(_channel('a'), openChannelId: 'khac'),
        isFalse,
      );
    });

    test('kênh nội bộ vẫn luôn hiện', () {
      expect(
        shouldShowChannelInInbox(_channel('g', slug: 'thong-bao')),
        isTrue,
      );
    });
  });

  test('mergeInboxConversations: gộp 1-1 và kênh, xếp theo tin mới nhất', () {
    final items = mergeInboxConversations(
      directs: [_direct('dm-cu', hour: 8), _direct('dm-moi', hour: 11)],
      channels: [
        _channel('general', slug: 'general', updatedHour: 7),
        _channel('du-an', lastHour: 12),
        _channel('im-lang'),
        _channel('cu', lastHour: 9),
        // Trùng kênh của chat 1-1: chỉ giữ một dòng.
        _channel('dm-moi', lastHour: 13),
      ],
    );

    expect(items.map((item) => item.id), [
      'du-an',
      'dm-moi',
      'cu',
      'dm-cu',
      'general',
    ]);
    expect(items[1].kind, ConversationKind.direct);
  });

  test(
    'mergeInboxConversations: ghim lên đầu, bằng giờ thì chưa đọc trước',
    () {
      final items = mergeInboxConversations(
        directs: [_direct('dm', hour: 10)],
        channels: [
          _channel('ghim', lastHour: 1, favorite: true),
          _channel('chua-doc', lastHour: 10, unread: 1),
        ],
      );

      expect(items.map((item) => item.id), ['ghim', 'chua-doc', 'dm']);
    },
  );
}

ConversationSummary _direct(String id, {required int hour}) {
  return ConversationSummary(
    id: id,
    workspaceId: 'ws',
    channelId: id,
    kind: ConversationKind.direct,
    title: id,
    preview: 'xin chào',
    updatedAt: DateTime.utc(2026, 11, 15, hour),
    channelVisibility: ChannelVisibility.direct,
    membershipStatus: MembershipStatus.active,
  );
}

/// Kênh mẫu: [lastHour] là giờ tin cuối (máy chủ trả `last_message_at`);
/// `null` là kênh chưa có tin / máy chủ cũ không trả trường này.
ConversationSummary _channel(
  String id, {
  String? slug,
  int? lastHour,
  int updatedHour = 0,
  bool member = true,
  bool automation = false,
  bool notice = false,
  bool privateSession = false,
  bool favorite = false,
  int unread = 0,
}) {
  final lastMessageAt = lastHour == null
      ? null
      : DateTime.utc(2026, 11, 15, lastHour);
  return ConversationSummary(
    id: id,
    workspaceId: 'ws',
    channelId: id,
    kind: ConversationKind.channel,
    title: id,
    preview: '',
    updatedAt: lastMessageAt ?? DateTime.utc(2026, 11, 15, updatedHour),
    membershipStatus: member ? MembershipStatus.active : MembershipStatus.none,
    isAutomation: automation,
    noticeBot: notice,
    privateSessionMode: privateSession,
    favorite: favorite,
    unreadCount: unread,
    slug: slug,
    lastMessageAt: lastMessageAt,
  );
}
