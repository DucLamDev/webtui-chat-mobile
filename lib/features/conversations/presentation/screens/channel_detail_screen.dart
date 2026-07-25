import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../design_system/components/webtui_components.dart';
import '../../../../design_system/tokens/webtui_colors.dart';
import '../../../../design_system/tokens/webtui_radii.dart';
import '../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../design_system/tokens/webtui_typography.dart';
import '../../../workspace/presentation/controllers/workspace_controller.dart';
import '../../domain/entities/channel_file.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/entities/conversation_summary.dart';
import '../controllers/channel_detail_controller.dart';
import '../widgets/message_media_widgets.dart';

class ChannelDetailScreen extends ConsumerStatefulWidget {
  const ChannelDetailScreen({
    required this.channelId,
    required this.initialTitle,
    super.key,
  });

  final String channelId;
  final String initialTitle;

  @override
  ConsumerState<ChannelDetailScreen> createState() =>
      _ChannelDetailScreenState();
}

class _ChannelDetailScreenState extends ConsumerState<ChannelDetailScreen> {
  final _inviteController = TextEditingController();
  int _tabIndex = 0;

  @override
  void dispose() {
    _inviteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final workspaceId = ref
        .watch(workspaceControllerProvider)
        .activeWorkspace
        ?.id;
    if (workspaceId == null || workspaceId.isEmpty) {
      return const Scaffold(
        body: SafeArea(
          child: WebTuiEmptyState(
            title: 'Chưa chọn workspace',
            message: 'Bạn cần chọn workspace trước khi mở kênh.',
            icon: Icons.business_rounded,
          ),
        ),
      );
    }

    final scope = ChannelDetailScope(
      workspaceId: workspaceId,
      channelId: widget.channelId,
      initialTitle: widget.initialTitle,
    );
    final provider = channelDetailControllerProvider(scope);
    final state = ref.watch(provider);
    final controller = ref.read(provider.notifier);

    return Scaffold(
      backgroundColor: WebTuiColors.background,
      appBar: AppBar(
        toolbarHeight: 54,
        surfaceTintColor: Colors.transparent,
        shape: Border(
          bottom: BorderSide(color: WebTuiColors.border.withValues(alpha: 0.7)),
        ),
        titleSpacing: 0,
        title: Text(state.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'Tải lại',
            onPressed: controller.load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: state.isLoading
            ? const WebTuiLoadingState(message: 'Đang tải chi tiết kênh...')
            : ListView(
                padding: const EdgeInsets.only(bottom: WebTuiSpacing.xl),
                children: [
                  if (state.errorMessage != null)
                    WebTuiErrorState(
                      title: 'Không tải được kênh',
                      message: state.errorMessage!,
                      onRetry: controller.load,
                    ),
                  if (state.noticeMessage != null)
                    _Notice(message: state.noticeMessage!),
                  _ChannelHeader(
                    channel: state.channel,
                    fallbackTitle: state.title,
                    submitting: state.isSubmitting,
                    joinPending:
                        state.channel?.membershipStatus ==
                        MembershipStatus.invited,
                    onOpenChat: state.channel?.isMember == true
                        ? () => _openChat(context, state)
                        : null,
                    onRequestJoin: state.channel?.isMember == true
                        ? null
                        : controller.requestJoin,
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: WebTuiSpacing.lg,
                    ),
                    child: WebTuiSegmentedTabs(
                      tabs: const [
                        'Thành viên',
                        'Ghim',
                        'Media',
                        'Tệp',
                        'Thiết lập',
                      ],
                      selectedIndex: _tabIndex,
                      onChanged: (value) => setState(() => _tabIndex = value),
                    ),
                  ),
                  const SizedBox(height: WebTuiSpacing.sm),
                  switch (_tabIndex) {
                    0 => _MembersTab(
                      state: state,
                      inviteController: _inviteController,
                      onInvite: () async {
                        await controller.inviteMember(_inviteController.text);
                        _inviteController.clear();
                      },
                      onApprove: controller.approveJoinRequest,
                      onReject: controller.rejectJoinRequest,
                    ),
                    1 => _PinnedTab(
                      messages: state.pinnedMessages,
                      errorMessage: state.pinsErrorMessage,
                    ),
                    2 => _MediaTab(
                      attachments: state.mediaAttachments,
                      errorMessage: state.mediaErrorMessage,
                    ),
                    3 => _FilesTab(
                      files: state.files
                          .where((file) => !_isMedia(file))
                          .toList(growable: false),
                      errorMessage: state.filesErrorMessage,
                    ),
                    _ => _SettingsTab(channel: state.channel),
                  },
                ],
              ),
      ),
    );
  }
}

class _ChannelHeader extends StatelessWidget {
  const _ChannelHeader({
    required this.channel,
    required this.fallbackTitle,
    required this.submitting,
    required this.joinPending,
    this.onOpenChat,
    this.onRequestJoin,
  });

  final ConversationSummary? channel;
  final String fallbackTitle;
  final bool submitting;
  final bool joinPending;
  final VoidCallback? onOpenChat;
  final VoidCallback? onRequestJoin;

  @override
  Widget build(BuildContext context) {
    final title = channel?.title ?? fallbackTitle;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        WebTuiSpacing.lg,
        WebTuiSpacing.md,
        WebTuiSpacing.lg,
        WebTuiSpacing.lg,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: WebTuiColors.surface,
          borderRadius: BorderRadius.circular(WebTuiRadii.lg),
          border: Border.all(color: WebTuiColors.border),
        ),
        child: Padding(
          padding: const EdgeInsets.all(WebTuiSpacing.lg),
          child: Row(
            children: [
              WebTuiAvatar(
                label: title,
                imageUrl: channel?.avatarUrl,
                icon: Icons.tag_rounded,
                color: WebTuiColors.primarySoft,
                foregroundColor: WebTuiColors.primary,
                size: 58,
              ),
              const SizedBox(width: WebTuiSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: WebTuiTypography.titleLarge.copyWith(
                        color: WebTuiColors.textPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: WebTuiSpacing.xs),
                    Text(
                      channel?.preview ?? 'Kênh trong workspace WebTui',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: WebTuiTypography.bodySmall.copyWith(
                        color: WebTuiColors.textMuted,
                      ),
                    ),
                    const SizedBox(height: WebTuiSpacing.sm),
                    Wrap(
                      spacing: WebTuiSpacing.xs,
                      runSpacing: WebTuiSpacing.xs,
                      children: [
                        WebTuiStatusPill(
                          label: _visibilityLabel(channel?.channelVisibility),
                          color: WebTuiColors.primary,
                        ),
                        if ((channel?.memberCount ?? 0) > 0)
                          WebTuiStatusPill(
                            label: '${channel!.memberCount} tham gia',
                            color: WebTuiColors.accentGreen,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: WebTuiSpacing.sm),
              if (onOpenChat != null)
                IconButton.filled(
                  tooltip: 'Mở hội thoại',
                  onPressed: onOpenChat,
                  icon: const Icon(Icons.chat_bubble_rounded),
                )
              else
                FilledButton(
                  onPressed: submitting || joinPending ? null : onRequestJoin,
                  child: submitting
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(joinPending ? 'Đang chờ' : 'Tham gia'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MembersTab extends StatelessWidget {
  const _MembersTab({
    required this.state,
    required this.inviteController,
    required this.onInvite,
    required this.onApprove,
    required this.onReject,
  });

  final ChannelDetailState state;
  final TextEditingController inviteController;
  final VoidCallback onInvite;
  final ValueChanged<String> onApprove;
  final ValueChanged<String> onReject;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (state.channel?.canManage == true)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              WebTuiSpacing.lg,
              WebTuiSpacing.sm,
              WebTuiSpacing.lg,
              WebTuiSpacing.sm,
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: inviteController,
                    decoration: const InputDecoration(
                      hintText: 'Nhập user ID để mời',
                      prefixIcon: Icon(Icons.person_add_alt_1_rounded),
                    ),
                  ),
                ),
                const SizedBox(width: WebTuiSpacing.sm),
                IconButton.filled(
                  tooltip: 'Mời',
                  onPressed: state.isSubmitting ? null : onInvite,
                  icon: const Icon(Icons.send_rounded),
                ),
              ],
            ),
          ),
        if (state.joinRequests.isNotEmpty) ...[
          const WebTuiSectionLabel('Yêu cầu tham gia'),
          WebTuiListSurface(
            children: [
              for (final request in state.joinRequests)
                _JoinRequestTile(
                  member: request,
                  onApprove: () => onApprove(request.userId),
                  onReject: () => onReject(request.userId),
                ),
            ],
          ),
        ],
        if (state.membersErrorMessage != null)
          WebTuiErrorState(
            title: 'Không tải được thành viên',
            message: state.membersErrorMessage!,
          )
        else if (state.members.isEmpty)
          const WebTuiEmptyState(
            title: 'Chưa có thành viên',
            message: 'Thành viên kênh sẽ xuất hiện tại đây.',
            icon: Icons.group_outlined,
          )
        else ...[
          const WebTuiSectionLabel('Thành viên'),
          WebTuiListSurface(
            children: [
              for (final member in state.members)
                WebTuiConversationListItem(
                  title: member.displayName,
                  preview: member.email,
                  timeLabel: member.status,
                  avatarLabel: member.displayName,
                  avatarUrl: member.avatarUrl,
                  status: member.status == 'active'
                      ? WebTuiPresenceStatus.online
                      : null,
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _JoinRequestTile extends StatelessWidget {
  const _JoinRequestTile({
    required this.member,
    required this.onApprove,
    required this.onReject,
  });

  final ChannelMember member;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 64,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: WebTuiSpacing.lg),
        child: Row(
          children: [
            WebTuiAvatar(label: member.displayName, imageUrl: member.avatarUrl),
            const SizedBox(width: WebTuiSpacing.md),
            Expanded(
              child: Text(
                member.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: WebTuiTypography.bodyMedium.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Duyệt',
              onPressed: onApprove,
              icon: const Icon(Icons.check_circle_outline_rounded),
            ),
            IconButton(
              tooltip: 'Từ chối',
              onPressed: onReject,
              icon: const Icon(Icons.cancel_outlined),
            ),
          ],
        ),
      ),
    );
  }
}

class _PinnedTab extends StatelessWidget {
  const _PinnedTab({required this.messages, this.errorMessage});

  final List<ChatMessage> messages;
  final String? errorMessage;

  @override
  Widget build(BuildContext context) {
    if (errorMessage != null) {
      return WebTuiErrorState(
        title: 'Không tải được tin ghim',
        message: errorMessage!,
      );
    }
    if (messages.isEmpty) {
      return const WebTuiEmptyState(
        title: 'Chưa có tin ghim',
        message: 'Tin nhắn được ghim trong kênh sẽ xuất hiện tại đây.',
        icon: Icons.push_pin_outlined,
      );
    }
    return WebTuiListSurface(
      children: [
        for (final message in messages)
          WebTuiConversationListItem(
            title: 'Tin ghim',
            preview: message.body,
            timeLabel: _timeLabel(message.createdAt),
            avatarLabel: 'Tin ghim',
          ),
      ],
    );
  }
}

class _FilesTab extends StatelessWidget {
  const _FilesTab({required this.files, this.errorMessage});

  final List<ChannelFile> files;
  final String? errorMessage;

  @override
  Widget build(BuildContext context) {
    if (errorMessage != null) {
      return WebTuiErrorState(
        title: 'Không tải được tệp',
        message: errorMessage!,
      );
    }
    if (files.isEmpty) {
      return const WebTuiEmptyState(
        title: 'Chưa có tệp',
        message: 'Tệp đã chia sẻ trong workspace sẽ xuất hiện tại đây.',
        icon: Icons.insert_drive_file_outlined,
      );
    }
    return WebTuiListSurface(
      children: [
        for (final file in files)
          WebTuiChannelBotListItem(
            title: file.name,
            subtitle: _fileSubtitle(file),
            icon: Icons.insert_drive_file_outlined,
            color: WebTuiColors.primary,
          ),
      ],
    );
  }
}

class _MediaTab extends StatelessWidget {
  const _MediaTab({required this.attachments, this.errorMessage});

  final List<MessageAttachment> attachments;
  final String? errorMessage;

  @override
  Widget build(BuildContext context) {
    if (errorMessage != null) {
      return WebTuiErrorState(
        title: 'Không tải được media',
        message: errorMessage!,
      );
    }
    if (attachments.isEmpty) {
      return const WebTuiEmptyState(
        title: 'Chưa có media',
        message: 'Ảnh đã gửi trong cuộc trò chuyện sẽ xuất hiện tại đây.',
        icon: Icons.photo_library_outlined,
      );
    }
    final apiBaseUri = WebTuiAvatarNetworkScope.maybeOf(context)?.apiBaseUri;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: WebTuiSpacing.lg),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 4,
          mainAxisSpacing: 4,
        ),
        itemCount: attachments.length,
        itemBuilder: (context, index) {
          return LayoutBuilder(
            builder: (context, constraints) {
              return MessageImageAttachmentView(
                attachment: attachments[index],
                apiBaseUri: apiBaseUri,
                height: constraints.maxHeight,
                maxHeight: constraints.maxHeight,
                maxWidth: constraints.maxWidth,
                onPressed: () => openMessageImageGallery(
                  context,
                  attachments: attachments,
                  initialIndex: index,
                  apiBaseUri: apiBaseUri,
                  title: 'Ảnh trong cuộc trò chuyện',
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _SettingsTab extends StatelessWidget {
  const _SettingsTab({required this.channel});

  final ConversationSummary? channel;

  @override
  Widget build(BuildContext context) {
    return WebTuiListSurface(
      children: [
        WebTuiSettingRow(
          title: 'Loại kênh',
          subtitle: _visibilityLabel(channel?.channelVisibility),
          icon: Icons.tag_outlined,
        ),
        WebTuiSettingRow(
          title: 'Thành viên',
          subtitle: '${channel?.memberCount ?? 0} người tham gia',
          icon: Icons.group_outlined,
        ),
        WebTuiSettingRow(
          title: 'Quyền quản lý',
          subtitle: channel?.canManage == true
              ? 'Bạn có thể mời và duyệt thành viên'
              : 'Bạn không có quyền quản lý kênh này',
          icon: Icons.admin_panel_settings_outlined,
        ),
      ],
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: WebTuiSpacing.lg,
        vertical: WebTuiSpacing.sm,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: WebTuiColors.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(WebTuiRadii.md),
        ),
        child: Padding(
          padding: const EdgeInsets.all(WebTuiSpacing.md),
          child: Text(
            message,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: WebTuiTypography.bodySmall.copyWith(
              color: WebTuiColors.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

void _openChat(BuildContext context, ChannelDetailState state) {
  final queryParameters = {'title': state.title};
  final avatarUrl = state.channel?.avatarUrl?.trim();
  if (avatarUrl != null && avatarUrl.isNotEmpty) {
    queryParameters['avatarUrl'] = avatarUrl;
  }
  context.push(
    Uri(
      path: '/conversations/${state.scope.channelId}',
      queryParameters: queryParameters,
    ).toString(),
  );
}

String _timeLabel(DateTime value) {
  final local = value.toLocal();
  return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
}

String _fileSubtitle(ChannelFile file) {
  final kb = (file.byteSize / 1024).ceil();
  return '${file.mimeType.isEmpty ? 'Tệp' : file.mimeType} · ${kb}KB';
}

String _visibilityLabel(ChannelVisibility? visibility) {
  return switch (visibility) {
    ChannelVisibility.private => 'Riêng tư',
    ChannelVisibility.direct => 'Hội thoại riêng',
    ChannelVisibility.public => 'Công khai',
    null => 'Chưa xác định',
  };
}

bool _isMedia(ChannelFile file) {
  return file.mimeType.startsWith('image/') ||
      file.mimeType.startsWith('video/');
}
