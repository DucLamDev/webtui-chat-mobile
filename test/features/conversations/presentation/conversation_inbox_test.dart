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
    _item('orders', 'Bot đơn hàng', hour: 13, group: true, automation: true),
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
      'Chưa đọc 1',
      'Nghiệp vụ',
      'Nhóm',
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

    expect(ids(internal.quickChannels), ['order', 'renew', 'proxy', 'custom']);
    expect(internal.inboxFilterLabels[2], 'Nghiệp vụ 1');
  });

  test('tab labels show unread counts', () {
    expect(state.inboxFilterLabels, ['Tất cả', 'Chưa đọc 1', 'Nhóm']);
  });

  test('search covers people and groups', () {
    final searched = state.copyWith(searchQuery: 'dự án');
    expect(ids(searched.inbox), ['pinned']);
  });
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
    membershipStatus: member ? MembershipStatus.active : MembershipStatus.none,
    isAutomation: automation,
    slug: slug,
  );
}
