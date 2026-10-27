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

  test('bot channels only appear with automation and the Bot filter', () {
    expect(state.inboxFilters.contains(ConversationListFilter.bot), isFalse);
    expect(ids(state.inbox).contains('orders'), isFalse);

    final internal = ConversationHomeState(
      workspaceId: 'workspace-1',
      conversations: directs,
      channels: channels,
      automationEnabled: true,
      messageFilter: ConversationListFilter.bot,
    );
    expect(internal.inboxFilterLabels.last, 'Bot');
    expect(ids(internal.inbox), ['orders']);
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
  );
}
