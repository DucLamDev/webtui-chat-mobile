import 'dart:async';

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
import '../../../moderation/presentation/controllers/moderation_controller.dart';
import '../../../moderation/presentation/widgets/moderation_actions.dart';
import '../../../profile/domain/entities/avatar_upload.dart';
import '../../../profile/presentation/controllers/profile_controller.dart';
import '../../../workspace/presentation/controllers/workspace_controller.dart';
import '../../domain/entities/channel_avatar_policy.dart';
import '../../domain/entities/channel_file.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/entities/conversation_summary.dart';
import '../controllers/channel_detail_controller.dart';
import '../controllers/conversation_home_controller.dart';
import '../widgets/channel_avatar_setting.dart';
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
      return Scaffold(
        body: SafeArea(
          child: WebTuiEmptyState(
            title: tr('Chưa chọn workspace', 'No workspace selected'),
            message: tr(
              'Bạn cần chọn workspace trước khi mở kênh.',
              'Select a workspace before opening a channel.',
            ),
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
    final moderationState = ref.watch(
      moderationControllerProvider(workspaceId),
    );
    final currentUserId = ref.watch(
      profileControllerProvider.select((state) => state.profile?.id),
    );
    final canChangeAvatar = canChangeChannelAvatar(state.channel);
    final onChangeAvatar = canChangeAvatar && !state.isUpdatingAvatar
        ? () => _pickChannelAvatar(context, controller, workspaceId)
        : null;

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
            tooltip: tr('Tải lại', 'Reload'),
            onPressed: controller.load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: state.isLoading
            ? WebTuiLoadingState(
                message: tr(
                  'Đang tải chi tiết kênh...',
                  'Loading channel details...',
                ),
              )
            : ListView(
                padding: const EdgeInsets.only(bottom: WebTuiSpacing.xl),
                children: [
                  if (state.errorMessage != null)
                    WebTuiErrorState(
                      title: tr(
                        'Không tải được kênh',
                        'Couldn\'t load channel',
                      ),
                      message: state.errorMessage!,
                      onRetry: controller.load,
                    ),
                  if (state.noticeMessage != null)
                    _Notice(message: state.noticeMessage!),
                  _ChannelHeader(
                    channel: state.channel,
                    updatingAvatar: state.isUpdatingAvatar,
                    onChangeAvatar: onChangeAvatar,
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
                  ChannelAvatarSetting(
                    channel: state.channel,
                    updating: state.isUpdatingAvatar,
                    errorMessage: state.avatarErrorMessage,
                    onChange: onChangeAvatar,
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: WebTuiSpacing.lg,
                    ),
                    child: WebTuiSegmentedTabs(
                      tabs: [
                        tr('Thành viên', 'Members'),
                        tr('Ghim', 'Pinned'),
                        'Media',
                        tr('Tệp', 'Files'),
                        tr('Thiết lập', 'Settings'),
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
                      currentUserId: currentUserId,
                      blockedUserIds: moderationState.blockedUserIds,
                      onSafety: (member) => showUserSafetyActions(
                        context,
                        ref,
                        workspaceId: workspaceId,
                        userId: member.userId,
                        userLabel: member.displayName,
                      ),
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

Future<void> _pickChannelAvatar(
  BuildContext context,
  ChannelDetailController controller,
  String workspaceId,
) async {
  final source = await showWebTuiSheet<AvatarPickerSource>(
    context: context,
    builder: (sheetContext) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          WebTuiSheetHeader(title: tr('Ảnh nhóm', 'Group photo')),
          WebTuiSheetActionTile(
            title: tr('Chụp ảnh mới', 'Take a new photo'),
            icon: WebTuiIcons.image,
            onTap: () =>
                Navigator.of(sheetContext).pop(AvatarPickerSource.camera),
          ),
          WebTuiSheetActionTile(
            title: tr('Chọn từ thư viện', 'Choose from library'),
            icon: WebTuiIcons.imageFile,
            onTap: () =>
                Navigator.of(sheetContext).pop(AvatarPickerSource.gallery),
          ),
          const SizedBox(height: 8),
        ],
      );
    },
  );
  if (source == null || !context.mounted) return;
  final changed = await controller.changeAvatar(source);
  if (!changed || !context.mounted) return;
  // Làm mới danh sách Tin nhắn / Kênh để ảnh mới hiện ngay (máy chủ cũng phát
  // `ChannelUpdated`, đây là đường dự phòng khi mất kết nối realtime).
  final container = ProviderScope.containerOf(context, listen: false);
  final home = conversationHomeControllerProvider(workspaceId);
  if (container.exists(home)) {
    unawaited(container.read(home.notifier).syncSilently());
  }
}

class _ChannelHeader extends StatelessWidget {
  const _ChannelHeader({
    required this.channel,
    required this.updatingAvatar,
    required this.fallbackTitle,
    required this.submitting,
    required this.joinPending,
    this.onChangeAvatar,
    this.onOpenChat,
    this.onRequestJoin,
  });

  final ConversationSummary? channel;
  final bool updatingAvatar;

  /// Có khi người dùng được đổi ảnh nhóm: chạm vào ảnh để đổi.
  final VoidCallback? onChangeAvatar;
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
              _HeaderAvatar(
                title: title,
                imageUrl: channel?.avatarUrl,
                updating: updatingAvatar,
                onTap: onChangeAvatar,
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
                      channel?.preview ??
                          tr(
                            'Kênh trong workspace WebTui',
                            'Channel in the WebTui workspace',
                          ),
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
                  tooltip: tr('Mở hội thoại', 'Open chat'),
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
                      : Text(
                          joinPending
                              ? tr('Đang chờ', 'Pending')
                              : tr('Tham gia', 'Join'),
                        ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeaderAvatar extends StatelessWidget {
  const _HeaderAvatar({
    required this.title,
    required this.imageUrl,
    required this.updating,
    this.onTap,
  });

  final String title;
  final String? imageUrl;
  final bool updating;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final avatar = Stack(
      clipBehavior: Clip.none,
      children: [
        WebTuiAvatar(
          label: title,
          imageUrl: imageUrl,
          icon: Icons.tag_rounded,
          color: WebTuiColors.primarySoft,
          foregroundColor: WebTuiColors.primary,
          size: 58,
        ),
        if (updating)
          const Positioned.fill(
            child: Center(
              child: SizedBox.square(
                dimension: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          )
        else if (onTap != null)
          Positioned(
            right: -2,
            bottom: -2,
            child: Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: WebTuiColors.primary,
                shape: BoxShape.circle,
                border: Border.all(color: WebTuiColors.surface, width: 2),
              ),
              child: const Icon(
                Icons.photo_camera_rounded,
                size: 12,
                color: Colors.white,
              ),
            ),
          ),
      ],
    );
    if (onTap == null) return avatar;
    return Semantics(
      button: true,
      label: tr('Đổi ảnh nhóm', 'Change group photo'),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(WebTuiRadii.md),
        child: avatar,
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
    required this.currentUserId,
    required this.blockedUserIds,
    required this.onSafety,
  });

  final ChannelDetailState state;
  final TextEditingController inviteController;
  final VoidCallback onInvite;
  final ValueChanged<String> onApprove;
  final ValueChanged<String> onReject;
  final String? currentUserId;
  final Set<String> blockedUserIds;
  final ValueChanged<ChannelMember> onSafety;

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
                    decoration: InputDecoration(
                      hintText: tr(
                        'Nhập user ID để mời',
                        'Enter a user ID to invite',
                      ),
                      prefixIcon: const Icon(Icons.person_add_alt_1_rounded),
                    ),
                  ),
                ),
                const SizedBox(width: WebTuiSpacing.sm),
                IconButton.filled(
                  tooltip: tr('Mời', 'Invite'),
                  onPressed: state.isSubmitting ? null : onInvite,
                  icon: const Icon(Icons.send_rounded),
                ),
              ],
            ),
          ),
        if (state.joinRequests.isNotEmpty) ...[
          WebTuiSectionLabel(tr('Yêu cầu tham gia', 'Join requests')),
          WebTuiLazyListSurface(
            itemCount: state.joinRequests.length,
            estimatedItemExtent: 65,
            itemBuilder: (context, index) {
              final request = state.joinRequests[index];
              return _JoinRequestTile(
                member: request,
                onApprove: () => onApprove(request.userId),
                onReject: () => onReject(request.userId),
              );
            },
          ),
        ],
        if (state.membersErrorMessage != null)
          WebTuiErrorState(
            title: tr('Không tải được thành viên', 'Couldn\'t load members'),
            message: state.membersErrorMessage!,
          )
        else if (state.members.isEmpty)
          WebTuiEmptyState(
            title: tr('Chưa có thành viên', 'No members yet'),
            message: tr(
              'Thành viên kênh sẽ xuất hiện tại đây.',
              'Channel members will show up here.',
            ),
            icon: Icons.group_outlined,
          )
        else ...[
          WebTuiSectionLabel(tr('Thành viên', 'Members')),
          WebTuiLazyListSurface(
            itemCount: state.members.length,
            itemBuilder: (context, index) {
              final member = state.members[index];
              return WebTuiConversationListItem(
                title: member.displayName,
                preview: blockedUserIds.contains(member.userId)
                    ? tr(
                        'Đã chặn · Nội dung đang được ẩn',
                        'Blocked · Content hidden',
                      )
                    : member.email,
                timeLabel: member.status,
                avatarLabel: member.displayName,
                avatarUrl: member.avatarUrl,
                status: member.status == 'active'
                    ? WebTuiPresenceStatus.online
                    : null,
                onLongPress: member.userId == currentUserId
                    ? null
                    : () => onSafety(member),
                trailing: member.userId == currentUserId
                    ? Text(tr('Bạn', 'You'))
                    : IconButton(
                        tooltip: tr(
                          'Báo cáo hoặc chặn ${member.displayName}',
                          'Report or block ${member.displayName}',
                        ),
                        onPressed: () => onSafety(member),
                        icon: Icon(
                          blockedUserIds.contains(member.userId)
                              ? Icons.block_rounded
                              : Icons.shield_outlined,
                        ),
                      ),
              );
            },
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
              tooltip: tr('Duyệt', 'Approve'),
              onPressed: onApprove,
              icon: const Icon(Icons.check_circle_outline_rounded),
            ),
            IconButton(
              tooltip: tr('Từ chối', 'Decline'),
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
        title: tr('Không tải được tin ghim', 'Couldn\'t load pinned messages'),
        message: errorMessage!,
      );
    }
    if (messages.isEmpty) {
      return WebTuiEmptyState(
        title: tr('Chưa có tin ghim', 'No pinned messages'),
        message: tr(
          'Tin nhắn được ghim trong kênh sẽ xuất hiện tại đây.',
          'Messages pinned in this channel will show up here.',
        ),
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
        title: tr('Không tải được tệp', 'Couldn\'t load files'),
        message: errorMessage!,
      );
    }
    if (files.isEmpty) {
      return WebTuiEmptyState(
        title: tr('Chưa có tệp', 'No files yet'),
        message: tr(
          'Tệp đã chia sẻ trong workspace sẽ xuất hiện tại đây.',
          'Files shared in the workspace will show up here.',
        ),
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
        title: tr('Không tải được media', 'Couldn\'t load media'),
        message: errorMessage!,
      );
    }
    if (attachments.isEmpty) {
      return WebTuiEmptyState(
        title: tr('Chưa có media', 'No media yet'),
        message: tr(
          'Ảnh đã gửi trong cuộc trò chuyện sẽ xuất hiện tại đây.',
          'Photos sent in this chat will show up here.',
        ),
        icon: Icons.photo_library_outlined,
      );
    }
    final apiBaseUri = WebTuiAvatarNetworkScope.maybeOf(context)?.apiBaseUri;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: WebTuiSpacing.lg),
      child: WebTuiLazyGridSurface(
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
                  title: tr('Ảnh trong cuộc trò chuyện', 'Photos in this chat'),
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
          title: tr('Loại kênh', 'Channel type'),
          subtitle: _visibilityLabel(channel?.channelVisibility),
          icon: Icons.tag_outlined,
        ),
        WebTuiSettingRow(
          title: tr('Thành viên', 'Members'),
          subtitle: tr(
            '${channel?.memberCount ?? 0} người tham gia',
            '${channel?.memberCount ?? 0} participants',
          ),
          icon: Icons.group_outlined,
        ),
        WebTuiSettingRow(
          title: tr('Quyền quản lý', 'Management permissions'),
          subtitle: channel?.canManage == true
              ? tr(
                  'Bạn có thể mời và duyệt thành viên',
                  'You can invite and approve members',
                )
              : tr(
                  'Bạn không có quyền quản lý kênh này',
                  'You can\'t manage this channel',
                ),
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
  return '${file.mimeType.isEmpty ? tr('Tệp', 'File') : file.mimeType} · ${kb}KB';
}

String _visibilityLabel(ChannelVisibility? visibility) {
  return switch (visibility) {
    ChannelVisibility.private => tr('Riêng tư', 'Private'),
    ChannelVisibility.direct => tr('Hội thoại riêng', 'Direct chat'),
    ChannelVisibility.public => tr('Công khai', 'Public'),
    null => tr('Chưa xác định', 'Unknown'),
  };
}

bool _isMedia(ChannelFile file) {
  return file.mimeType.startsWith('image/') ||
      file.mimeType.startsWith('video/');
}
