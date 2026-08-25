import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../design_system/components/webtui_components.dart';
import '../../../../design_system/tokens/webtui_colors.dart';
import '../../../../design_system/tokens/webtui_spacing.dart';
import '../../../moderation/presentation/controllers/moderation_controller.dart';
import '../../../moderation/presentation/widgets/moderation_actions.dart';
import '../../domain/entities/conversation_summary.dart';
import '../controllers/conversation_home_controller.dart';
import '../models/conversation_privacy_projection.dart';
import '../screens/chat_room_screen.dart';

class MessagesHomeView extends ConsumerWidget {
  const MessagesHomeView({required this.workspaceId, super.key});

  final String workspaceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = conversationHomeControllerProvider(workspaceId);
    final state = ref.watch(provider);
    final controller = ref.read(provider.notifier);
    final moderationProvider = moderationControllerProvider(workspaceId);
    final moderationState = ref.watch(moderationProvider);

    if (moderationState.isLoadingBlockedUsers) {
      return const WebTuiLoadingState(
        message: 'Đang áp dụng cài đặt an toàn...',
      );
    }
    if (moderationState.errorMessage != null) {
      return WebTuiErrorState(
        title: 'Chưa thể áp dụng cài đặt an toàn',
        message: moderationState.errorMessage!,
        onRetry: () => ref.read(moderationProvider.notifier).loadBlockedUsers(),
      );
    }
    final blockedUserIds = moderationState.blockedUserIds;
    final conversations = privacySafeConversationResults(
      state.filteredConversations,
      blockedUserIds,
      searchQuery: state.searchQuery,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 720;
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
          onRetry: controller.load,
          onSearch: controller.setSearchQuery,
          onFilterChanged: (index) {
            controller.setMessageFilter(ConversationListFilter.values[index]);
          },
          onTap: (conversation) async {
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
              controller.selectConversation(conversation);
            } else {
              controller.markConversationOpened(conversation);
              _openChat(context, conversation);
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
                  ? const Center(
                      child: WebTuiEmptyState(
                        title: 'Chưa chọn hội thoại',
                        message:
                            'Chọn một hội thoại ở bên trái để xem chi tiết.',
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

class ContactsHomeView extends ConsumerWidget {
  const ContactsHomeView({required this.workspaceId, super.key});

  final String workspaceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = conversationHomeControllerProvider(workspaceId);
    final state = ref.watch(provider);
    final controller = ref.read(provider.notifier);
    final moderationState = ref.watch(
      moderationControllerProvider(workspaceId),
    );

    final contacts = state.filteredContacts;
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: _TopSearch(
            hintText: 'Tìm bạn bè...',
            onChanged: controller.setSearchQuery,
          ),
        ),
        if (state.errorMessage != null)
          SliverToBoxAdapter(
            child: WebTuiErrorState(
              title: 'Không tải được dữ liệu',
              message: state.errorMessage!,
              onRetry: controller.load,
            ),
          )
        else if (contacts.isEmpty)
          const SliverToBoxAdapter(
            child: WebTuiEmptyState(
              title: 'Chưa có bạn bè',
              message: 'Bạn bè đã kết nối sẽ xuất hiện tại đây.',
              icon: Icons.contacts_outlined,
            ),
          )
        else ...[
          const SliverToBoxAdapter(child: WebTuiSectionLabel('Bạn bè')),
          WebTuiSliverListSurface(
            itemCount: contacts.length,
            itemBuilder: (context, index) {
              final contact = contacts[index];
              return _ContactTile(
                contact: contact,
                presence: state.presenceByUserId[contact.userId],
                blocked: moderationState.blockedUserIds.contains(
                  contact.userId,
                ),
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
                    _openChat(context, conversation);
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
        ],
        const SliverToBoxAdapter(child: SizedBox(height: WebTuiSpacing.lg)),
      ],
    );
  }
}

class ChannelsHomeView extends ConsumerWidget {
  const ChannelsHomeView({required this.workspaceId, super.key});

  final String workspaceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = conversationHomeControllerProvider(workspaceId);
    final state = ref.watch(provider);
    final controller = ref.read(provider.notifier);

    return ListView(
      padding: const EdgeInsets.only(bottom: WebTuiSpacing.lg),
      children: [
        _TopSearch(
          hintText: 'Tìm kênh hoặc bot...',
          onChanged: controller.setSearchQuery,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: WebTuiSpacing.lg),
          child: WebTuiSegmentedTabs(
            tabs: const ['Tất cả', 'Công khai', 'Riêng tư'],
            selectedIndex: state.channelTab,
            onChanged: controller.setChannelTab,
          ),
        ),
        if (state.isLoading)
          const WebTuiLoadingState(message: 'Đang tải danh sách kênh...')
        else if (state.errorMessage != null)
          WebTuiErrorState(
            title: 'Không tải được kênh',
            message: state.errorMessage!,
            onRetry: controller.load,
          )
        else
          _ChannelList(
            channels: state.filteredChannels,
            emptyTitle: 'Chưa có kênh phù hợp',
            sectionLabel: 'Kênh trong workspace',
            onTap: (channel) => _handleChannelTap(context, controller, channel),
          ),
      ],
    );
  }
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
  });

  final ConversationHomeState state;
  final List<ConversationSummary> conversations;
  final Set<String> blockedUserIds;
  final VoidCallback onRetry;
  final ValueChanged<String> onSearch;
  final ValueChanged<int> onFilterChanged;
  final ValueChanged<ConversationSummary> onTap;
  final String? selectedId;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async => onRetry(),
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: _TopSearch(
              hintText: 'Tìm hội thoại...',
              onChanged: onSearch,
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: WebTuiSpacing.lg),
              child: WebTuiSegmentedTabs(
                tabs: const ['Tất cả', 'Chưa đọc', 'Yêu thích'],
                selectedIndex: state.messageFilter.index,
                onChanged: onFilterChanged,
              ),
            ),
          ),
          if (state.isLoading)
            const SliverToBoxAdapter(
              child: WebTuiLoadingState(message: 'Đang tải hội thoại...'),
            )
          else if (state.errorMessage != null)
            SliverToBoxAdapter(
              child: WebTuiErrorState(
                title: 'Không tải được hội thoại',
                message: state.errorMessage!,
                onRetry: onRetry,
              ),
            )
          else if (conversations.isEmpty)
            const SliverToBoxAdapter(
              child: WebTuiEmptyState(
                title: 'Chưa có hội thoại',
                message: 'Hội thoại và kênh bạn tham gia sẽ xuất hiện tại đây.',
                icon: Icons.chat_bubble_outline_rounded,
              ),
            )
          else ...[
            const SliverToBoxAdapter(child: SizedBox(height: WebTuiSpacing.xs)),
            const SliverToBoxAdapter(
              child: WebTuiSectionLabel('Hội thoại gần đây'),
            ),
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
          const SliverToBoxAdapter(child: SizedBox(height: WebTuiSpacing.lg)),
        ],
      ),
    );
  }
}

class _ConversationTile extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final privacy = ConversationPrivacyProjection.from(
      conversation,
      blockedUserIds,
    );
    return WebTuiConversationListItem(
      title: conversation.title,
      preview: privacy.preview,
      timeLabel: _timeLabel(conversation.updatedAt),
      avatarLabel: conversation.avatarLabel ?? conversation.title,
      avatarUrl: conversation.avatarUrl,
      unreadCount: privacy.isBlocked ? 0 : conversation.unreadCount,
      muted: conversation.muted,
      status: conversation.kind == ConversationKind.direct && !privacy.isBlocked
          ? _presenceStatus(presence)
          : null,
      selected: selected,
      onTap: onTap,
      onLongPress: privacy.isBlocked ? onTap : null,
      trailing: privacy.isBlocked
          ? const Tooltip(
              message: 'Quản lý người dùng đã chặn',
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
          ? 'Đã chặn · Nhấn để quản lý'
          : relationshipLabel ?? contact.title ?? contact.email,
      timeLabel: canOpenChat ? _presenceLabel(presence) : '',
      avatarLabel: contact.displayName,
      avatarUrl: contact.avatarUrl,
      status: canOpenChat ? _presenceStatus(presence) : null,
      onTap: canOpenChat ? onTap : null,
      onLongPress: onSafety,
      trailing: IconButton(
        tooltip: 'Báo cáo hoặc chặn ${contact.displayName}',
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
        ? 'Đã gửi lời mời'
        : 'Lời mời đang chờ';
  }
  if (status == 'rejected') {
    return 'Lời mời đã bị từ chối';
  }
  if (status == 'cancelled') {
    return 'Lời mời đã hủy';
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
        message: 'Kênh lấy từ workspace sẽ xuất hiện tại đây khi bạn có quyền.',
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

void _openChat(BuildContext context, ConversationSummary conversation) {
  final queryParameters = {
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
  context.push(
    Uri(
      path: '/conversations/${conversation.channelId}',
      queryParameters: queryParameters,
    ).toString(),
    extra: conversation,
  );
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
  final destination = await controller.openChannel(channel);
  if (destination == null || !context.mounted) {
    return;
  }
  if (channel.privateSessionMode) {
    _openChat(context, destination);
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
    ConversationPresence.away => 'Vắng mặt',
    ConversationPresence.offline => 'Ngoại tuyến',
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
    return 'Hôm qua';
  }
  final difference = today.difference(day).inDays;
  if (difference < 7) {
    return '$difference ngày';
  }
  return '${_two(local.day)}/${_two(local.month)}';
}

String _two(int value) => value.toString().padLeft(2, '0');

String _channelTrailing(ConversationSummary channel) {
  if (channel.isMember) {
    return channel.memberCount > 0
        ? '${channel.memberCount} tham gia'
        : 'Đã tham gia';
  }
  if (channel.membershipStatus == MembershipStatus.invited) {
    return 'Chờ duyệt';
  }
  return channel.channelVisibility == ChannelVisibility.private
      ? 'Yêu cầu'
      : 'Mở kênh';
}

IconData _channelIcon(ConversationSummary channel) {
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
  if (channel.privateSessionMode) {
    return WebTuiColors.accentAmber;
  }
  return switch (channel.channelVisibility) {
    ChannelVisibility.private => WebTuiColors.danger,
    ChannelVisibility.direct => WebTuiColors.primary,
    ChannelVisibility.public => WebTuiColors.accentGreen,
  };
}
