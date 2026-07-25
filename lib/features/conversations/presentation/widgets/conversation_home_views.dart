import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../design_system/components/webtui_components.dart';
import '../../../../design_system/tokens/webtui_colors.dart';
import '../../../../design_system/tokens/webtui_spacing.dart';
import '../../domain/entities/conversation_summary.dart';
import '../controllers/conversation_home_controller.dart';
import '../screens/chat_room_screen.dart';

class MessagesHomeView extends ConsumerWidget {
  const MessagesHomeView({required this.workspaceId, super.key});

  final String workspaceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = conversationHomeControllerProvider(workspaceId);
    final state = ref.watch(provider);
    final controller = ref.read(provider.notifier);

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 720;
        final selected =
            state.selectedConversation ??
            (state.filteredConversations.isEmpty
                ? null
                : state.filteredConversations.first);
        final list = _MessagesList(
          state: state,
          selectedId: wide ? selected?.id : null,
          onRetry: controller.load,
          onSearch: controller.setSearchQuery,
          onFilterChanged: (index) {
            controller.setMessageFilter(ConversationListFilter.values[index]);
          },
          onTap: (conversation) {
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

    return ListView(
      padding: const EdgeInsets.only(bottom: WebTuiSpacing.lg),
      children: [
        _TopSearch(
          hintText: 'Tìm bạn bè...',
          onChanged: controller.setSearchQuery,
        ),
        if (state.errorMessage != null)
          WebTuiErrorState(
            title: 'Không tải được dữ liệu',
            message: state.errorMessage!,
            onRetry: controller.load,
          )
        else
          _ContactSections(
            contacts: state.filteredContacts,
            presenceByUserId: state.presenceByUserId,
            onTap: (contact) async {
              final conversation = await controller.openDirect(contact);
              if (conversation != null && context.mounted) {
                _openChat(context, conversation);
              }
            },
          ),
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
    required this.onRetry,
    required this.onSearch,
    required this.onFilterChanged,
    required this.onTap,
    this.selectedId,
  });

  final ConversationHomeState state;
  final VoidCallback onRetry;
  final ValueChanged<String> onSearch;
  final ValueChanged<int> onFilterChanged;
  final ValueChanged<ConversationSummary> onTap;
  final String? selectedId;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async => onRetry(),
      child: ListView(
        padding: const EdgeInsets.only(bottom: WebTuiSpacing.lg),
        children: [
          _TopSearch(hintText: 'Tìm hội thoại...', onChanged: onSearch),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: WebTuiSpacing.lg),
            child: WebTuiSegmentedTabs(
              tabs: const ['Tất cả', 'Chưa đọc', 'Yêu thích'],
              selectedIndex: state.messageFilter.index,
              onChanged: onFilterChanged,
            ),
          ),
          if (state.isLoading)
            const WebTuiLoadingState(message: 'Đang tải hội thoại...')
          else if (state.errorMessage != null)
            WebTuiErrorState(
              title: 'Không tải được hội thoại',
              message: state.errorMessage!,
              onRetry: onRetry,
            )
          else if (state.filteredConversations.isEmpty)
            const WebTuiEmptyState(
              title: 'Chưa có hội thoại',
              message: 'Hội thoại và kênh bạn tham gia sẽ xuất hiện tại đây.',
              icon: Icons.chat_bubble_outline_rounded,
            )
          else ...[
            const SizedBox(height: WebTuiSpacing.xs),
            const WebTuiSectionLabel('Hội thoại gần đây'),
            WebTuiListSurface(
              children: [
                for (final conversation in state.filteredConversations)
                  _ConversationTile(
                    conversation: conversation,
                    presence: state.presenceForConversation(conversation),
                    selected: selectedId == conversation.id,
                    onTap: () => onTap(conversation),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ConversationTile extends StatelessWidget {
  const _ConversationTile({
    required this.conversation,
    required this.onTap,
    this.presence,
    this.selected = false,
  });

  final ConversationSummary conversation;
  final VoidCallback onTap;
  final ConversationPresence? presence;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return WebTuiConversationListItem(
      title: conversation.title,
      preview: conversation.preview,
      timeLabel: _timeLabel(conversation.updatedAt),
      avatarLabel: conversation.avatarLabel ?? conversation.title,
      avatarUrl: conversation.avatarUrl,
      unreadCount: conversation.unreadCount,
      muted: conversation.muted,
      status: conversation.kind == ConversationKind.direct
          ? _presenceStatus(presence)
          : null,
      selected: selected,
      onTap: onTap,
    );
  }
}

class _ContactSections extends StatelessWidget {
  const _ContactSections({
    required this.contacts,
    required this.presenceByUserId,
    required this.onTap,
  });

  final List<ContactSummary> contacts;
  final Map<String, ConversationPresence> presenceByUserId;
  final ValueChanged<ContactSummary> onTap;

  @override
  Widget build(BuildContext context) {
    if (contacts.isEmpty) {
      return const WebTuiEmptyState(
        title: 'Chưa có bạn bè',
        message: 'Bạn bè đã kết nối sẽ xuất hiện tại đây.',
        icon: Icons.contacts_outlined,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (contacts.isNotEmpty) ...[
          const WebTuiSectionLabel('Bạn bè'),
          WebTuiListSurface(
            children: [
              for (final contact in contacts)
                _ContactTile(
                  contact: contact,
                  presence: presenceByUserId[contact.userId],
                  onTap: () => onTap(contact),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _ContactTile extends StatelessWidget {
  const _ContactTile({
    required this.contact,
    required this.onTap,
    this.presence,
  });

  final ContactSummary contact;
  final VoidCallback onTap;
  final ConversationPresence? presence;

  @override
  Widget build(BuildContext context) {
    return WebTuiConversationListItem(
      title: contact.displayName,
      preview: contact.title ?? contact.email,
      timeLabel: _presenceLabel(presence),
      avatarLabel: contact.displayName,
      avatarUrl: contact.avatarUrl,
      status: _presenceStatus(presence),
      onTap: onTap,
    );
  }
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
