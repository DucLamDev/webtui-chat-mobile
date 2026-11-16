import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../design_system/components/webtui_components.dart';
import '../../../../design_system/icons/webtui_icons.dart';
import '../../../../design_system/tokens/webtui_colors.dart';
import '../../../../design_system/tokens/webtui_radii.dart';
import '../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../design_system/tokens/webtui_typography.dart';
import '../../../../l10n/app_strings.dart';
import '../../../approvals/presentation/widgets/approval_inbox_entry.dart';
import '../../../business/presentation/widgets/business_inbox_entry.dart';
import '../../../customer_tickets/application/customer_ticket_channel_route.dart';
import '../../../customer_tickets/presentation/controllers/customer_ticket_access_provider.dart';
import '../../../customer_tickets/presentation/widgets/customer_ticket_inbox_entry.dart';
import '../../../inbox/presentation/widgets/inbox_entry.dart';
import '../../../moderation/presentation/controllers/moderation_controller.dart';
import '../../../moderation/presentation/widgets/moderation_actions.dart';
import '../../../profile/presentation/controllers/profile_controller.dart';
import '../../domain/entities/conversation_summary.dart';
import '../controllers/conversation_home_controller.dart';
import '../controllers/notice_bot_identity.dart';
import '../models/conversation_privacy_projection.dart';
import '../screens/chat_room_screen.dart';
import 'business_channel_grid.dart';

class MessagesHomeView extends ConsumerWidget {
  const MessagesHomeView({
    required this.workspaceId,
    this.searchActions = const [],
    this.onCompose,
    super.key,
  });

  final String workspaceId;

  /// Nút đặt bên phải ô tìm kiếm (chuông thông báo): tab Tin nhắn không còn
  /// thanh tiêu đề.
  final List<Widget> searchActions;

  /// Bấm nút soạn tin (ô vuông bên trái ô tìm); `null` thì không hiện nút.
  final VoidCallback? onCompose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = conversationHomeControllerProvider(workspaceId);
    final state = ref.watch(provider);
    final controller = ref.read(provider.notifier);
    final moderationProvider = moderationControllerProvider(workspaceId);
    final moderationState = ref.watch(moderationProvider);

    if (moderationState.isLoadingBlockedUsers) {
      return WebTuiLoadingState(
        message: tr(
          'Đang áp dụng cài đặt an toàn...',
          'Applying safety settings...',
        ),
      );
    }
    if (moderationState.errorMessage != null) {
      return WebTuiErrorState(
        title: tr(
          'Chưa thể áp dụng cài đặt an toàn',
          'Couldn\'t apply safety settings',
        ),
        message: moderationState.errorMessage!,
        onRetry: () => ref.read(moderationProvider.notifier).loadBlockedUsers(),
      );
    }
    final blockedUserIds = moderationState.blockedUserIds;
    // Hộp thư gộp: tin nhắn riêng + nhóm / kênh trong một danh sách.
    final conversations = privacySafeConversationResults(
      state.inbox,
      blockedUserIds,
      searchQuery: state.searchQuery,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 720;
        controller.reportSplitView(wide);
        final selected = _safeSelectedConversation(
          state.selectedConversation,
          conversations,
          blockedUserIds,
        );
        final list = _MessagesList(
          state: state,
          conversations: conversations,
          blockedUserIds: blockedUserIds,
          selectedId: wide ? selected?.id : null,
          searchActions: searchActions,
          onCompose: onCompose,
          onRetry: () {
            // Kéo làm mới cũng lấy lại số ticket khách chưa trả lời.
            ref.invalidate(customerTicketUnansweredCountProvider(workspaceId));
            controller.load();
          },
          onSearch: controller.setSearchQuery,
          onFilterChanged: (index) {
            controller.setMessageFilter(state.inboxFilters[index]);
          },
          onTap: (conversation) async {
            final isGroup = conversation.kind == ConversationKind.channel;
            // Phiên hỗ trợ riêng / kênh chưa tham gia: đi luồng kênh như cũ.
            if (isGroup &&
                (conversation.privateSessionMode || !conversation.isMember)) {
              await _handleChannelTap(context, controller, conversation);
              return;
            }
            final blockedPeerUserId = blockedDirectPeerUserId(
              conversation,
              blockedUserIds,
            );
            if (blockedPeerUserId != null) {
              await showUserSafetyActions(
                context,
                ref,
                workspaceId: workspaceId,
                userId: blockedPeerUserId,
                userLabel: conversation.title,
              );
              return;
            }
            if (wide) {
              if (_openCustomerTicketInbox(
                context,
                conversation,
                onReturn: controller.syncSilently,
              )) {
                return;
              }
              controller.selectConversation(conversation);
            } else {
              controller.markConversationOpened(conversation);
              _openChat(
                context,
                conversation,
                onReturn: controller.syncSilently,
              );
            }
          },
        );

        if (!wide) {
          return list;
        }

        return Row(
          children: [
            SizedBox(width: 360, child: list),
            const VerticalDivider(width: 1),
            Expanded(
              child: selected == null
                  ? Center(
                      child: WebTuiEmptyState(
                        title: tr(
                          'Chưa chọn hội thoại',
                          'No conversation selected',
                        ),
                        message: tr(
                          'Chọn một hội thoại ở bên trái để xem chi tiết.',
                          'Select a conversation on the left to see details.',
                        ),
                        icon: Icons.chat_bubble_outline_rounded,
                      ),
                    )
                  : ChatRoomScreen(
                      workspaceId: workspaceId,
                      channelId: selected.channelId,
                      title: selected.title,
                      conversation: selected,
                      embedded: true,
                    ),
            ),
          ],
        );
      },
    );
  }
}

/// Danh bạ: hai tab "Đồng nghiệp" (thành viên workspace, bấm để nhắn riêng)
/// và "Kênh" (kênh đã tham gia, bấm để vào chat; kênh công khai có thể tham
/// gia ở dưới).
class ContactsHomeView extends ConsumerStatefulWidget {
  const ContactsHomeView({
    required this.workspaceId,
    this.initialTab = ContactsHomeView.colleaguesTab,
    super.key,
  });

  static const colleaguesTab = 0;
  static const channelsTab = 1;

  final String workspaceId;
  final int initialTab;

  @override
  ConsumerState<ContactsHomeView> createState() => _ContactsHomeViewState();
}

class _ContactsHomeViewState extends ConsumerState<ContactsHomeView> {
  late int _tab = widget.initialTab;

  @override
  Widget build(BuildContext context) {
    final workspaceId = widget.workspaceId;
    final provider = conversationHomeControllerProvider(workspaceId);
    final state = ref.watch(provider);
    final controller = ref.read(provider.notifier);
    final channelsTab = _tab == ContactsHomeView.channelsTab;

    return CustomScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      slivers: [
        SliverToBoxAdapter(
          child: _TopSearch(
            hintText: channelsTab
                ? tr('Tìm nhóm theo tên...', 'Search groups by name...')
                : tr('Tìm đồng nghiệp...', 'Search colleagues...'),
            onChanged: controller.setSearchQuery,
          ),
        ),
        SliverToBoxAdapter(
          child: _InboxFilterChips(
            chipsKey: const ValueKey('contacts-tabs'),
            labels: [tr('Đồng nghiệp', 'Colleagues'), tr('Nhóm', 'Groups')],
            selectedIndex: _tab,
            onChanged: (index) => setState(() => _tab = index),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: WebTuiSpacing.xs)),
        if (channelsTab)
          ..._channelSlivers(context, state, controller)
        else
          ..._colleagueSlivers(context, state, controller),
        // Đệm đáy: mục cuối cuộn lên được trên thanh tab nổi.
        SliverToBoxAdapter(
          child: SizedBox(
            height:
                WebTuiSpacing.lg +
                WebTuiFloatingTabBar.contentBottomPadding(context),
          ),
        ),
      ],
    );
  }

  List<Widget> _colleagueSlivers(
    BuildContext context,
    ConversationHomeState state,
    ConversationHomeController controller,
  ) {
    final workspaceId = widget.workspaceId;
    final moderationState = ref.watch(
      moderationControllerProvider(workspaceId),
    );
    final currentUserId = ref.watch(
      profileControllerProvider.select((state) => state.profile?.id),
    );
    // Danh bạ là thành viên workspace (gồm cả chính mình): ẩn chính mình.
    final contacts = state.filteredContacts
        .where((contact) => contact.userId != currentUserId)
        .toList(growable: false);
    if (state.errorMessage != null) {
      return [
        SliverToBoxAdapter(
          child: WebTuiErrorState(
            title: tr('Không tải được dữ liệu', 'Couldn\'t load data'),
            message: state.errorMessage!,
            onRetry: controller.load,
          ),
        ),
      ];
    }
    if (contacts.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: WebTuiEmptyState(
            title: tr('Chưa có đồng nghiệp', 'No colleagues yet'),
            message: tr(
              'Thành viên workspace hiện ở đây, bấm để nhắn ngay.',
              'Workspace members show up here. Tap to message them.',
            ),
            icon: Icons.contacts_outlined,
          ),
        ),
      ];
    }
    return [
      SliverToBoxAdapter(
        child: WebTuiSectionLabel(tr('Đồng nghiệp', 'Colleagues')),
      ),
      WebTuiSliverListSurface(
        itemCount: contacts.length,
        itemBuilder: (context, index) {
          final contact = contacts[index];
          return _ContactTile(
            contact: contact,
            presence: state.presenceByUserId[contact.userId],
            blocked: moderationState.blockedUserIds.contains(contact.userId),
            onTap: () async {
              if (!contact.canOpenDirectConversation) {
                return;
              }
              if (moderationState.isBlocked(contact.userId)) {
                await showUserSafetyActions(
                  context,
                  ref,
                  workspaceId: workspaceId,
                  userId: contact.userId,
                  userLabel: contact.displayName,
                );
                return;
              }
              final conversation = await controller.openDirect(contact);
              if (conversation != null && context.mounted) {
                _openChat(
                  context,
                  conversation,
                  onReturn: controller.syncSilently,
                );
              }
            },
            onSafety: () => showUserSafetyActions(
              context,
              ref,
              workspaceId: workspaceId,
              userId: contact.userId,
              userLabel: contact.displayName,
            ),
          );
        },
      ),
    ];
  }

  List<Widget> _channelSlivers(
    BuildContext context,
    ConversationHomeState state,
    ConversationHomeController controller,
  ) {
    final joined = state.joinedChannels;
    final joinable = state.joinableChannels;
    if (state.isLoading && state.channels.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: WebTuiLoadingState(
            message: tr('Đang tải nhóm...', 'Loading groups...'),
          ),
        ),
      ];
    }
    if (state.errorMessage != null) {
      return [
        SliverToBoxAdapter(
          child: WebTuiErrorState(
            title: tr('Không tải được danh sách nhóm', 'Couldn\'t load groups'),
            message: state.errorMessage!,
            onRetry: controller.load,
          ),
        ),
      ];
    }
    if (joined.isEmpty && joinable.isEmpty) {
      final searching = state.searchQuery.trim().isNotEmpty;
      return [
        SliverToBoxAdapter(
          child: WebTuiEmptyState(
            title: searching
                ? tr('Không tìm thấy nhóm', 'No groups found')
                : tr('Chưa có nhóm nào', 'No groups yet'),
            message: searching
                ? tr('Thử tìm bằng tên khác.', 'Try a different name.')
                : tr(
                    'Nhóm bạn tham gia trong workspace sẽ hiện ở đây.',
                    'Groups you join in the workspace will show up here.',
                  ),
            icon: Icons.tag_outlined,
          ),
        ),
      ];
    }
    return [
      if (joined.isNotEmpty) ...[
        SliverToBoxAdapter(
          child: WebTuiSectionLabel(tr('Nhóm đã tham gia', 'Joined groups')),
        ),
        WebTuiSliverListSurface(
          itemCount: joined.length,
          itemBuilder: (context, index) {
            final channel = joined[index];
            return WebTuiConversationListItem(
              key: ValueKey('contacts-channel-${channel.channelId}'),
              title: channel.title,
              preview: channel.preview,
              timeLabel: '',
              avatarLabel: channel.avatarLabel ?? channel.title,
              avatarUrl: channel.avatarUrl,
              avatarIcon: conversationChannelIcon(channel),
              unreadCount: channel.unreadCount,
              muted: channel.muted,
              onTap: () => _openDirectoryChannel(context, controller, channel),
            );
          },
        ),
      ],
      if (joinable.isNotEmpty)
        SliverToBoxAdapter(
          child: _ChannelList(
            channels: joinable,
            emptyTitle: '',
            sectionLabel: tr('Nhóm có thể tham gia', 'Groups you can join'),
            onTap: (channel) => _handleChannelTap(context, controller, channel),
          ),
        ),
    ];
  }
}

/// Bấm một kênh ở Danh bạ > Kênh: kênh đã tham gia vào thẳng màn chat; phiên
/// hỗ trợ riêng / kênh chưa tham gia đi luồng kênh như ở Tin nhắn.
Future<void> _openDirectoryChannel(
  BuildContext context,
  ConversationHomeController controller,
  ConversationSummary channel,
) async {
  if (channel.privateSessionMode || !channel.isMember) {
    await _handleChannelTap(context, controller, channel);
    return;
  }
  controller.markConversationOpened(channel);
  _openChat(context, channel, onReturn: controller.syncSilently);
}

class _MessagesList extends StatelessWidget {
  const _MessagesList({
    required this.state,
    required this.conversations,
    required this.blockedUserIds,
    required this.onRetry,
    required this.onSearch,
    required this.onFilterChanged,
    required this.onTap,
    this.selectedId,
    this.searchActions = const [],
    this.onCompose,
  });

  final ConversationHomeState state;
  final List<ConversationSummary> conversations;
  final Set<String> blockedUserIds;
  final VoidCallback onRetry;
  final ValueChanged<String> onSearch;
  final ValueChanged<int> onFilterChanged;
  final ValueChanged<ConversationSummary> onTap;
  final String? selectedId;
  final List<Widget> searchActions;
  final VoidCallback? onCompose;

  @override
  Widget build(BuildContext context) {
    final filterIndex = state.inboxFilters.indexOf(state.messageFilter);
    final workTab = state.inboxFilters.indexOf(ConversationListFilter.bot);
    final showWorkEntries = state.messageFilter == ConversationListFilter.bot;
    // Máy chủ bật phê duyệt nhưng tắt automation thì không có tab Nghiệp vụ:
    // dòng Phê duyệt (tự ẩn khi không có quyền) hiện ở Tất cả.
    final showApprovalOnAll =
        workTab < 0 &&
        state.messageFilter == ConversationListFilter.all &&
        state.searchQuery.trim().isEmpty;
    return RefreshIndicator(
      onRefresh: () async => onRetry(),
      child: CustomScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: _MessagesTopBar(
              onChanged: onSearch,
              onCompose: onCompose,
              actions: searchActions,
            ),
          ),
          SliverToBoxAdapter(
            child: _InboxFilterChips(
              labels: state.inboxFilterLabels,
              selectedIndex: filterIndex < 0 ? 0 : filterIndex,
              onChanged: onFilterChanged,
            ),
          ),
          if (showWorkEntries)
            SliverToBoxAdapter(
              child: Column(
                children: [
                  BusinessInboxEntry(workspaceId: state.workspaceId),
                  ApprovalInboxEntry(workspaceId: state.workspaceId),
                  InboxEntry(workspaceId: state.workspaceId),
                  CustomerTicketInboxEntry(workspaceId: state.workspaceId),
                ],
              ),
            )
          else if (showApprovalOnAll)
            SliverToBoxAdapter(
              child: Column(
                children: [
                  ApprovalInboxEntry(workspaceId: state.workspaceId),
                  InboxEntry(workspaceId: state.workspaceId),
                ],
              ),
            ),
          if (state.isLoading)
            SliverToBoxAdapter(
              child: WebTuiLoadingState(
                message: tr(
                  'Đang tải hội thoại...',
                  'Loading conversations...',
                ),
              ),
            )
          else if (state.errorMessage != null)
            SliverToBoxAdapter(
              child: WebTuiErrorState(
                title: tr(
                  'Không tải được hội thoại',
                  'Couldn\'t load conversations',
                ),
                message: state.errorMessage!,
                onRetry: onRetry,
              ),
            )
          else if (conversations.isEmpty)
            SliverToBoxAdapter(
              child: WebTuiEmptyState(
                title: tr('Chưa có hội thoại', 'No conversations yet'),
                message: tr(
                  'Hội thoại và nhóm bạn tham gia sẽ xuất hiện tại đây.',
                  'Conversations and groups you join will appear here.',
                ),
                icon: Icons.chat_bubble_outline_rounded,
              ),
            )
          else ...[
            const SliverToBoxAdapter(child: SizedBox(height: WebTuiSpacing.xs)),
            WebTuiSliverListSurface(
              itemCount: conversations.length,
              itemBuilder: (context, index) {
                final conversation = conversations[index];
                return _ConversationTile(
                  conversation: conversation,
                  blockedUserIds: blockedUserIds,
                  presence: state.presenceForConversation(conversation),
                  selected: selectedId == conversation.id,
                  onTap: () => onTap(conversation),
                );
              },
            ),
          ],
          // Đệm đáy: hội thoại cuối cuộn lên được trên thanh tab nổi.
          SliverToBoxAdapter(
            child: SizedBox(
              height:
                  WebTuiSpacing.lg +
                  WebTuiFloatingTabBar.contentBottomPadding(context),
            ),
          ),
        ],
      ),
    );
  }
}

/// Bộ lọc hộp thư dạng viên thuốc (Tất cả, Chưa đọc, Nghiệp vụ, Nhóm; cũng là
/// tab Đồng nghiệp / Kênh ở Danh bạ): chọn =
/// nền xanh chữ trắng, chưa chọn = viền xám nền trắng.
class _InboxFilterChips extends StatelessWidget {
  const _InboxFilterChips({
    required this.labels,
    this.chipsKey = const ValueKey('inbox-filter-chips'),
    required this.selectedIndex,
    required this.onChanged,
  });

  final List<String> labels;
  final Key chipsKey;
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    // Không thu nhỏ chữ: máy hẹp hay cỡ chữ hệ thống lớn thì cả hàng cuộn ngang
    // (đệm 16 nằm trong vùng cuộn để chip trượt sát mép màn hình). Mọi nút cùng
    // cỡ chữ, vùng bấm luôn cao ≥ 48dp.
    return SingleChildScrollView(
      key: chipsKey,
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: WebTuiSpacing.lg),
      child: Row(
        children: [
          for (var index = 0; index < labels.length; index++) ...[
            if (index > 0) const SizedBox(width: WebTuiSpacing.sm),
            ChoiceChip(
              label: Text(labels[index]),
              selected: index == selectedIndex,
              showCheckmark: false,
              // Mật độ dọc chuẩn + `padded`: vùng bấm cao 48dp (mật độ
              // compact hạ còn 40dp). Đệm dọc giảm 4 để viên chip trông vẫn
              // gọn như mẫu.
              visualDensity: const VisualDensity(horizontal: -2, vertical: 0),
              materialTapTargetSize: MaterialTapTargetSize.padded,
              shape: const StadiumBorder(),
              padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
              labelPadding: const EdgeInsets.symmetric(horizontal: 6),
              labelStyle: TextStyle(
                fontFamily: WebTuiTypography.fontFamily,
                fontSize: 15,
                fontWeight: index == selectedIndex
                    ? FontWeight.w800
                    : FontWeight.w500,
                color: index == selectedIndex
                    ? WebTuiColors.textOnPrimary
                    : WebTuiColors.textSecondary,
              ),
              selectedColor: WebTuiColors.primary,
              backgroundColor: WebTuiColors.surface,
              side: BorderSide(
                color: index == selectedIndex
                    ? WebTuiColors.primary
                    : const Color(0xFFC3D0E0),
                width: 1.2,
              ),
              onSelected: (_) => onChanged(index),
            ),
          ],
        ],
      ),
    );
  }
}

class _ConversationTile extends ConsumerWidget {
  const _ConversationTile({
    required this.conversation,
    required this.blockedUserIds,
    required this.onTap,
    this.presence,
    this.selected = false,
  });

  final ConversationSummary conversation;
  final Set<String> blockedUserIds;
  final VoidCallback onTap;
  final ConversationPresence? presence;
  final bool selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final privacy = ConversationPrivacyProjection.from(
      conversation,
      blockedUserIds,
    );
    final bot = conversation.noticeBot
        ? ref.watch(noticeBotIdentityProvider)
        : null;
    return WebTuiConversationListItem(
      title: bot?.title ?? conversation.title,
      preview: privacy.preview,
      timeLabel: _timeLabel(conversation.updatedAt),
      avatarLabel:
          bot?.avatarLabel ?? conversation.avatarLabel ?? conversation.title,
      avatarUrl: bot != null ? bot.logoUrl : conversation.avatarUrl,
      avatarPublicImage: bot != null,
      // Kênh: ô vuông bo góc + biểu tượng theo loại; người: ảnh tròn. Chat bot
      // thông báo giữ logo tổ chức nhưng cũng là ô vuông.
      avatarIcon: bot != null || conversation.kind != ConversationKind.channel
          ? null
          : conversationChannelIcon(conversation),
      squareAvatar: bot != null,
      pinned: conversation.favorite,
      badgeLabel: bot != null ? 'BOT' : null,
      unreadCount: privacy.isBlocked ? 0 : conversation.unreadCount,
      // Chat 1-1 và bot thông báo: 1–5 rồi "5+"; nhóm / kênh: 1–99 rồi "99+".
      unreadMax: conversation.kind == ConversationKind.channel
          ? webTuiUnreadMaxGroup
          : webTuiUnreadMaxDirect,
      muted: conversation.muted,
      status:
          conversation.kind == ConversationKind.direct &&
              !privacy.isBlocked &&
              !conversation.noticeBot
          ? (presence == ConversationPresence.online
                ? WebTuiPresenceStatus.online
                : null)
          : null,
      selected: selected,
      onTap: onTap,
      onLongPress: privacy.isBlocked ? onTap : null,
      trailing: privacy.isBlocked
          ? Tooltip(
              message: tr('Quản lý người dùng đã chặn', 'Manage blocked users'),
              child: Icon(Icons.block_rounded, color: WebTuiColors.danger),
            )
          : null,
    );
  }
}

ConversationSummary? _safeSelectedConversation(
  ConversationSummary? selected,
  List<ConversationSummary> conversations,
  Set<String> blockedUserIds,
) {
  if (selected != null &&
      blockedDirectPeerUserId(selected, blockedUserIds) == null) {
    return selected;
  }
  for (final conversation in conversations) {
    if (conversation.privateSessionMode) continue;
    if (blockedDirectPeerUserId(conversation, blockedUserIds) == null) {
      return conversation;
    }
  }
  return null;
}

class _ContactTile extends StatelessWidget {
  const _ContactTile({
    required this.contact,
    required this.onTap,
    required this.blocked,
    required this.onSafety,
    this.presence,
  });

  final ContactSummary contact;
  final VoidCallback onTap;
  final bool blocked;
  final VoidCallback onSafety;
  final ConversationPresence? presence;

  @override
  Widget build(BuildContext context) {
    final relationshipLabel = _contactRelationshipLabel(contact);
    final canOpenChat = contact.canOpenDirectConversation && !blocked;
    return WebTuiConversationListItem(
      title: contact.displayName,
      preview: blocked
          ? tr('Đã chặn · Nhấn để quản lý', 'Blocked · Tap to manage')
          : relationshipLabel ?? contact.title ?? contact.email,
      timeLabel: canOpenChat ? _presenceLabel(presence) : '',
      avatarLabel: contact.displayName,
      avatarUrl: contact.avatarUrl,
      status: canOpenChat ? _presenceStatus(presence) : null,
      onTap: canOpenChat ? onTap : null,
      onLongPress: onSafety,
      trailing: IconButton(
        tooltip: tr(
          'Báo cáo hoặc chặn ${contact.displayName}',
          'Report or block ${contact.displayName}',
        ),
        onPressed: onSafety,
        icon: Icon(blocked ? Icons.block_rounded : Icons.shield_outlined),
      ),
    );
  }
}

String? _contactRelationshipLabel(ContactSummary contact) {
  final status = contact.contactStatus?.trim();
  if (status == null || status.isEmpty || status == 'accepted') {
    return null;
  }
  if (status == 'pending') {
    return contact.isOutgoingContactRequest
        ? tr('Đã gửi lời mời', 'Invitation sent')
        : tr('Lời mời đang chờ', 'Invitation pending');
  }
  if (status == 'rejected') {
    return tr('Lời mời đã bị từ chối', 'Invitation declined');
  }
  if (status == 'cancelled') {
    return tr('Lời mời đã hủy', 'Invitation canceled');
  }
  return status;
}

class _ChannelList extends StatelessWidget {
  const _ChannelList({
    required this.channels,
    required this.emptyTitle,
    required this.sectionLabel,
    required this.onTap,
  });

  final List<ConversationSummary> channels;
  final String emptyTitle;
  final String sectionLabel;
  final ValueChanged<ConversationSummary> onTap;

  @override
  Widget build(BuildContext context) {
    if (channels.isEmpty) {
      return WebTuiEmptyState(
        title: emptyTitle,
        message: tr(
          'Nhóm lấy từ workspace sẽ xuất hiện tại đây khi bạn có quyền.',
          'Groups from the workspace will appear here when you have access.',
        ),
        icon: Icons.tag_outlined,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        WebTuiSectionLabel(sectionLabel),
        WebTuiListSurface(
          children: [
            for (final channel in channels)
              WebTuiChannelBotListItem(
                title: channel.title,
                subtitle: channel.preview,
                icon: _channelIcon(channel),
                color: _channelColor(channel),
                trailingLabel: _channelTrailing(channel),
                unreadCount: channel.unreadCount,
                onTap: () => onTap(channel),
              ),
          ],
        ),
      ],
    );
  }
}

/// Hàng đầu tab Tin nhắn: nút soạn tin (trái), ô tìm bo tròn, nút phụ (phải).
class _MessagesTopBar extends StatelessWidget {
  const _MessagesTopBar({
    required this.onChanged,
    this.onCompose,
    this.actions = const [],
  });

  final ValueChanged<String> onChanged;
  final VoidCallback? onCompose;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        WebTuiSpacing.lg,
        WebTuiSpacing.md,
        WebTuiSpacing.lg,
        WebTuiSpacing.md,
      ),
      child: Row(
        children: [
          if (onCompose != null) ...[
            Material(
              color: WebTuiColors.primarySoft,
              borderRadius: BorderRadius.circular(WebTuiRadii.md + 2),
              child: InkWell(
                key: const Key('compose_button'),
                borderRadius: BorderRadius.circular(WebTuiRadii.md + 2),
                onTap: onCompose,
                child: SizedBox.square(
                  dimension: 46,
                  child: Tooltip(
                    message: tr(
                      'Tin nhắn mới hoặc tạo nhóm',
                      'New message or create group',
                    ),
                    child: Icon(
                      WebTuiIcons.compose,
                      size: 24,
                      color: WebTuiColors.primary,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: WebTuiSpacing.md),
          ],
          Expanded(
            child: WebTuiSearchBar(
              hintText: tr(
                'Tìm tin nhắn, nhóm...',
                'Search messages, groups...',
              ),
              onChanged: onChanged,
            ),
          ),
          ...actions,
        ],
      ),
    );
  }
}

class _TopSearch extends StatelessWidget {
  const _TopSearch({required this.hintText, required this.onChanged});

  final String hintText;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        WebTuiSpacing.lg,
        WebTuiSpacing.md,
        WebTuiSpacing.lg,
        WebTuiSpacing.sm,
      ),
      child: WebTuiSearchBar(hintText: hintText, onChanged: onChanged),
    );
  }
}

/// Kênh "Ticket" (kênh bot gốc hoặc phiên riêng của nó): người xem được ticket
/// khách vào thẳng hộp thư trả lời ticket như mục Ticket trên web, không mở
/// phòng chat bot. Trả `true` khi đã mở hộp thư ticket.
bool _openCustomerTicketInbox(
  BuildContext context,
  ConversationSummary conversation, {
  Future<void> Function()? onReturn,
}) {
  final location = customerTicketLocationForConversation(
    conversation,
    ProviderScope.containerOf(
      context,
      listen: false,
    ).read(customerTicketAccessProvider),
  );
  if (location == null) return false;
  context.push<void>(location).then((_) => onReturn?.call());
  return true;
}

/// [onReturn] chạy khi người dùng rời phòng chat để danh sách có tin mới nhất,
/// số chưa đọc đúng (hộp thư chưa nhận sự kiện realtime của từng phòng).
void _openChat(
  BuildContext context,
  ConversationSummary conversation, {
  Future<void> Function()? onReturn,
}) {
  if (_openCustomerTicketInbox(context, conversation, onReturn: onReturn)) {
    return;
  }
  final queryParameters = {
    'workspaceId': conversation.workspaceId,
    'title': conversation.title,
    'kind': conversation.kind.name,
  };
  final avatarUrl = conversation.avatarUrl?.trim();
  if (avatarUrl != null && avatarUrl.isNotEmpty) {
    queryParameters['avatarUrl'] = avatarUrl;
  }
  final peerUserId = conversation.peerUserId?.trim();
  if (peerUserId != null && peerUserId.isNotEmpty) {
    queryParameters['peerUserId'] = peerUserId;
  }
  final participantIds = conversation.participantIds
      .map((id) => id.trim())
      .where((id) => id.isNotEmpty)
      .join(',');
  if (participantIds.isNotEmpty) {
    queryParameters['participantIds'] = participantIds;
  }
  context
      .push<void>(
        Uri(
          path: '/conversations/${conversation.channelId}',
          queryParameters: queryParameters,
        ).toString(),
        extra: conversation,
      )
      .then((_) => onReturn?.call());
}

void _openChannelDetail(BuildContext context, ConversationSummary channel) {
  context.push(
    Uri(
      path: '/channels/${channel.channelId}',
      queryParameters: {'title': channel.title},
    ).toString(),
  );
}

Future<void> _handleChannelTap(
  BuildContext context,
  ConversationHomeController controller,
  ConversationSummary channel,
) async {
  // Kênh Ticket: không mở phiên bot riêng, vào thẳng hộp thư ticket khách.
  if (_openCustomerTicketInbox(
    context,
    channel,
    onReturn: controller.syncSilently,
  )) {
    return;
  }
  final destination = await controller.openChannel(channel);
  if (destination == null || !context.mounted) {
    return;
  }
  if (channel.privateSessionMode) {
    _openChat(context, destination, onReturn: controller.syncSilently);
  } else {
    _openChannelDetail(context, destination);
  }
}

WebTuiPresenceStatus? _presenceStatus(ConversationPresence? presence) {
  return switch (presence) {
    ConversationPresence.online => WebTuiPresenceStatus.online,
    ConversationPresence.away => WebTuiPresenceStatus.away,
    ConversationPresence.offline => WebTuiPresenceStatus.offline,
    null => null,
  };
}

String _presenceLabel(ConversationPresence? presence) {
  return switch (presence) {
    ConversationPresence.online => 'Online',
    ConversationPresence.away => tr('Vắng mặt', 'Away'),
    ConversationPresence.offline => tr('Ngoại tuyến', 'Offline'),
    null => '',
  };
}

String _timeLabel(DateTime value) {
  final now = DateTime.now();
  final local = value.toLocal();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(local.year, local.month, local.day);
  if (day == today) {
    return '${_two(local.hour)}:${_two(local.minute)}';
  }
  if (day == today.subtract(const Duration(days: 1))) {
    return tr('Hôm qua', 'Yesterday');
  }
  final difference = today.difference(day).inDays;
  if (difference < 7) {
    return tr(
      '$difference ngày',
      difference == 1 ? '1 day ago' : '$difference days ago',
    );
  }
  return '${_two(local.day)}/${_two(local.month)}';
}

String _two(int value) => value.toString().padLeft(2, '0');

String _channelTrailing(ConversationSummary channel) {
  if (channel.isMember) {
    return channel.memberCount > 0
        ? tr('${channel.memberCount} tham gia', '${channel.memberCount} joined')
        : tr('Đã tham gia', 'Joined');
  }
  if (channel.membershipStatus == MembershipStatus.invited) {
    return tr('Chờ duyệt', 'Pending approval');
  }
  return channel.channelVisibility == ChannelVisibility.private
      ? tr('Yêu cầu', 'Request')
      : tr('Mở nhóm', 'Open group');
}

IconData _channelIcon(ConversationSummary channel) {
  if (channel.isAutomation) {
    return Icons.smart_toy_outlined;
  }
  if (channel.privateSessionMode) {
    return Icons.support_agent_rounded;
  }
  return switch (channel.channelVisibility) {
    ChannelVisibility.private => Icons.lock_outline_rounded,
    ChannelVisibility.direct => Icons.chat_bubble_outline_rounded,
    ChannelVisibility.public => Icons.tag_outlined,
  };
}

Color _channelColor(ConversationSummary channel) {
  if (channel.isAutomation) {
    return WebTuiColors.chatHeader;
  }
  if (channel.privateSessionMode) {
    return WebTuiColors.accentAmber;
  }
  return switch (channel.channelVisibility) {
    ChannelVisibility.private => WebTuiColors.danger,
    ChannelVisibility.direct => WebTuiColors.primary,
    ChannelVisibility.public => WebTuiColors.accentGreen,
  };
}
