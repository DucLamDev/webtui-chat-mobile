import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/features/conversations/domain/entities/conversation_summary.dart';
import 'package:webtui_chat/features/conversations/presentation/controllers/conversation_home_controller.dart';

void main() {
  final directs = [
    _item('dm-old', 'Hà', hour: 8),
    _item('dm-new', 'Lâm', hour: 11, unread: 2),
  ];
  final channels = [
    _item('general', 'Thông báo chung', hour: 10, group: true),
    _item('pinned', 'Dự án A', hour: 7, group: true, favorite: true),
    _item('public', 'Kênh mở', hour: 12, group: true, member: false),
    _item(
      'orders',
      'Bot đơn hàng',
      hour: 13,
      group: true,
      automation: true,
      slug: 'orders',
    ),
  ];
  final state = ConversationHomeState(
    workspaceId: 'workspace-1',
    conversations: directs,
    channels: channels,
  );

  List<String> ids(List<ConversationSummary> items) {
    return items.map((item) => item.id).toList();
  }

  test('merges directs and joined groups, pinned first then newest', () {
    expect(ids(state.inbox), ['pinned', 'dm-new', 'general', 'dm-old']);
    expect(ids(state.joinableChannels), ['public']);
  });

  test('filters the merged inbox', () {
    ConversationHomeState filtered(ConversationListFilter filter) {
      return state.copyWith(messageFilter: filter);
    }

    expect(ids(filtered(ConversationListFilter.unread).inbox), ['dm-new']);
    expect(ids(filtered(ConversationListFilter.direct).inbox), [
      'dm-new',
      'dm-old',
    ]);
    expect(ids(filtered(ConversationListFilter.group).inbox), [
      'pinned',
      'general',
    ]);
    expect(ids(filtered(ConversationListFilter.favorite).inbox), ['pinned']);
    expect(filtered(ConversationListFilter.direct).joinableChannels, isEmpty);
  });

  test('work channels only appear with automation, after Unread', () {
    expect(state.inboxFilters.contains(ConversationListFilter.bot), isFalse);
    expect(state.quickChannels, isEmpty);
    expect(ids(state.inbox).contains('orders'), isFalse);

    final internal = ConversationHomeState(
      workspaceId: 'workspace-1',
      conversations: directs,
      channels: channels,
      automationEnabled: true,
      messageFilter: ConversationListFilter.bot,
    );
    expect(internal.inboxFilterLabels, [
      'Tất cả',
      'Nhóm',
      'Cá nhân 1',
      'Nghiệp vụ',
      'Chưa đọc 1',
    ]);
    expect(ids(internal.inbox), ['orders']);
    // Ở Tất cả kênh nghiệp vụ không chen vào danh sách; tìm kiếm thì vẫn ra.
    final all = internal.copyWith(messageFilter: ConversationListFilter.all);
    expect(ids(all.inbox).contains('orders'), isFalse);
    expect(ids(all.copyWith(searchQuery: 'đơn').inbox), ['orders']);
  });

  test('quick work channels: fixed business order, not unread / recency', () {
    final internal = ConversationHomeState(
      workspaceId: 'workspace-1',
      automationEnabled: true,
      channels: [
        _item('custom', 'Bot riêng', hour: 14, group: true, automation: true),
        _item(
          'proxy',
          'Giám sát Proxy',
          hour: 8,
          group: true,
          automation: true,
          unread: 3,
          member: false,
          slug: 'monitor-proxy',
        ),
        _item('renew', 'Gia hạn', hour: 9, group: true, automation: true),
        _item(
          'order',
          'Đơn VPS', // quản trị đổi tên: vẫn đứng đầu nhờ slug
          hour: 12,
          group: true,
          automation: true,
          slug: 'orders',
        ),
        _item('team', 'Nhóm team', hour: 13, group: true),
      ],
    );

    // Chỉ còn 3 kênh nghiệp vụ; kênh hệ thống khác và kênh bot tự tạo bị ẩn.
    expect(ids(internal.quickChannels), ['order', 'renew']);
    expect(ids(internal.joinableChannels), isEmpty);
    expect(internal.inboxFilterLabels[3], 'Nghiệp vụ');
  });

  test('tab labels show unread counts', () {
    expect(state.inboxFilterLabels, [
      'Tất cả',
      'Nhóm',
      'Cá nhân 1',
      'Chưa đọc 1',
    ]);
  });

  test('search covers people and groups', () {
    final searched = state.copyWith(searchQuery: 'dự án');
    expect(ids(searched.inbox), ['pinned']);
  });

  group('ẩn kênh hệ thống khỏi app', () {
    final all = ConversationHomeState(
      workspaceId: 'workspace-1',
      automationEnabled: true,
      conversations: [
        _item('dm', 'Lan', hour: 9, unread: 1),
        _item('dm-hidden-bot', 'Bot', hour: 9, unread: 1, automation: true),
      ],
      channels: [
        _item(
          'orders',
          'Đơn hàng',
          hour: 1,
          group: true,
          automation: true,
          slug: 'orders',
          unread: 2,
        ),
        _item(
          'billing',
          'Doanh thu',
          hour: 2,
          group: true,
          automation: true,
          slug: 'billing',
          unread: 5,
        ),
        _item('alert', 'Cảnh báo', hour: 3, group: true, unread: 4),
        _item(
          'custom',
          'Bot riêng',
          hour: 4,
          group: true,
          automation: true,
          unread: 6,
        ),
        _item(
          'hidden-public',
          'Sự cố',
          hour: 5,
          group: true,
          member: false,
          slug: 'incidents',
        ),
        _item('general', 'Chung', hour: 6, group: true, unread: 3),
      ],
    );

    test('hộp thư: chỉ nhóm thường, Cá nhân không có kênh', () {
      expect(
        ids(all.copyWith(messageFilter: ConversationListFilter.group).inbox),
        ['general'],
      );
      expect(
        ids(all.copyWith(messageFilter: ConversationListFilter.direct).inbox),
        ['dm'],
      );
      expect(
        ids(all.copyWith(messageFilter: ConversationListFilter.unread).inbox),
        ['dm', 'general', 'orders'],
      );
      expect(ids(all.copyWith(searchQuery: 'cảnh').inbox), isEmpty);
      expect(ids(all.copyWith(searchQuery: 'đơn').inbox), ['orders']);
    });

    test('tab Nghiệp vụ, gợi ý, danh sách kênh và số đỏ', () {
      expect(ids(all.quickChannels), ['orders']);
      expect(ids(all.joinableChannels), isEmpty);
      expect(ids(all.filteredChannels), ['general']);
      // Lan 1 + Chung 3 + Đơn hàng 2; kênh ẩn không cộng.
      expect(all.unreadBadgeCount(), 6);
    });
  });

  group('số đỏ tab Tin nhắn (unreadBadgeCount)', () {
    final badgeState = ConversationHomeState(
      workspaceId: 'workspace-1',
      automationEnabled: true,
      conversations: [
        _item('dm-a', 'An', hour: 9, unread: 2, peer: 'user-an'),
        _item('dm-b', 'Bình', hour: 10, unread: 5, peer: 'user-binh'),
        _item('dm-muted', 'Chi', hour: 11, unread: 7, muted: true),
      ],
      channels: [
        _item('team', 'Nhóm team', hour: 8, unread: 3, group: true),
        _item(
          'orders',
          'Bot đơn hàng',
          hour: 12,
          unread: 4,
          group: true,
          automation: true,
          slug: 'orders',
        ),
        _item(
          'outside',
          'Kênh chưa vào',
          hour: 7,
          unread: 9,
          group: true,
          member: false,
        ),
        _item(
          'team-muted',
          'Nhóm tắt tiếng',
          hour: 6,
          unread: 6,
          group: true,
          mutedMember: true,
        ),
      ],
    );

    test('đếm cả hộp thư (cả kênh nghiệp vụ), bỏ chat tắt tiếng', () {
      // An 2 + Bình 5 + Nhóm team 3 + Bot đơn hàng 4; không tính chat tắt
      // tiếng (cờ muted hoặc thành viên muted) và kênh chưa tham gia.
      expect(badgeState.unreadBadgeCount(), 14);
    });

    test('không đổi khi đổi chip lọc hay gõ tìm', () {
      for (final filter in ConversationListFilter.values) {
        expect(
          badgeState.copyWith(messageFilter: filter).unreadBadgeCount(),
          14,
          reason: '$filter',
        );
      }
      expect(badgeState.copyWith(searchQuery: 'An').unreadBadgeCount(), 14);
      expect(
        badgeState
            .copyWith(
              messageFilter: ConversationListFilter.group,
              searchQuery: 'không khớp gì',
            )
            .unreadBadgeCount(),
        14,
      );
    });

    test('bỏ chat 1-1 với người đã chặn', () {
      expect(badgeState.unreadBadgeCount(blockedUserIds: {'user-binh'}), 9);
      expect(badgeState.unreadBadgeCount(blockedUserIds: {'người-khác'}), 14);
    });

    test(
      'tắt nghiệp vụ thì không cộng kênh bot; kênh trùng chỉ cộng 1 lần',
      () {
        final withoutAutomation = ConversationHomeState(
          workspaceId: 'workspace-1',
          conversations: badgeState.conversations,
          channels: badgeState.channels,
        );
        expect(withoutAutomation.unreadBadgeCount(), 10);
        final duplicated = badgeState.copyWith(
          conversations: [
            ...badgeState.conversations,
            _item('team', 'Nhóm team', hour: 8, unread: 3, group: true),
          ],
        );
        expect(duplicated.unreadBadgeCount(), 14);
      },
    );
  });

  test(
    'chat bot thông báo (máy chủ trả dạng kênh) không thuộc Nhóm hay Cá nhân',
    () {
      final withBot = ConversationHomeState(
        workspaceId: 'workspace-1',
        conversations: directs,
        channels: [
          ...channels,
          _item('bot', 'Bot', hour: 14, group: true, unread: 1, notice: true),
        ],
      );
      ConversationHomeState filtered(ConversationListFilter filter) =>
          withBot.copyWith(messageFilter: filter);

      expect(ids(withBot.inbox), contains('bot'));
      expect(
        ids(filtered(ConversationListFilter.group).inbox),
        isNot(contains('bot')),
      );
      expect(
        ids(filtered(ConversationListFilter.direct).inbox),
        isNot(contains('bot')),
      );
      expect(
        ids(filtered(ConversationListFilter.unread).inbox),
        contains('bot'),
      );
      // Nhãn chip: bot chỉ tính ở "Chưa đọc", không làm tăng số của Nhóm.
      final labels = withBot.inboxFilterLabels;
      expect(labels, contains('Nhóm'));
      expect(labels, contains('Chưa đọc 2'));
    },
  );
}

ConversationSummary _item(
  String id,
  String title, {
  required int hour,
  int unread = 0,
  bool group = false,
  bool favorite = false,
  bool member = true,
  bool automation = false,
  String? slug,
  String? peer,
  bool muted = false,
  bool mutedMember = false,
  bool notice = false,
}) {
  return ConversationSummary(
    id: id,
    workspaceId: 'workspace-1',
    channelId: id,
    kind: group ? ConversationKind.channel : ConversationKind.direct,
    title: title,
    preview: 'Tin nhắn',
    updatedAt: DateTime.utc(2026, 10, 27, hour),
    unreadCount: unread,
    favorite: favorite,
    channelVisibility: group
        ? ChannelVisibility.public
        : ChannelVisibility.direct,
    membershipStatus: !member
        ? MembershipStatus.none
        : mutedMember
        ? MembershipStatus.muted
        : MembershipStatus.active,
    isAutomation: automation,
    slug: slug,
    peerUserId: peer,
    muted: muted,
    noticeBot: notice,
  );
}
