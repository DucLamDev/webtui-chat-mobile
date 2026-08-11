import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../design_system/components/webtui_components.dart';
import '../../../../design_system/tokens/webtui_colors.dart';
import '../../../../design_system/tokens/webtui_radii.dart';
import '../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../design_system/tokens/webtui_typography.dart';
import '../../../moderation/presentation/controllers/moderation_controller.dart';
import '../../domain/entities/conversation_summary.dart';
import '../controllers/conversation_home_controller.dart';
import '../widgets/collaboration_room_sheet.dart';

bool workspaceToolsSharedContentBlocked(
  ConversationSummary room,
  ModerationState moderationState,
) {
  if (room.kind != ConversationKind.direct) return false;
  if (moderationState.isLoadingBlockedUsers ||
      moderationState.errorMessage != null) {
    return true;
  }
  final peerUserId = room.directCallTargetUserId();
  if (peerUserId == null || peerUserId.trim().isEmpty) return true;
  return moderationState.isBlocked(peerUserId);
}

/// A mobile-first entry point for the shared workspace tools that were
/// previously only discoverable through an icon inside a conversation.
class WorkspaceToolsScreen extends ConsumerStatefulWidget {
  const WorkspaceToolsScreen({required this.workspaceId, super.key});

  final String workspaceId;

  @override
  ConsumerState<WorkspaceToolsScreen> createState() =>
      _WorkspaceToolsScreenState();
}

class _WorkspaceToolsScreenState extends ConsumerState<WorkspaceToolsScreen> {
  String? _selectedRoomId;

  @override
  Widget build(BuildContext context) {
    final provider = conversationHomeControllerProvider(widget.workspaceId);
    final state = ref.watch(provider);
    final moderationState = ref.watch(
      moderationControllerProvider(widget.workspaceId),
    );
    final controller = ref.read(provider.notifier);
    final rooms = <ConversationSummary>[
      ...state.channels.where((channel) => channel.isMember),
      ...state.conversations,
    ];
    final selected = _selectedRoom(rooms);
    final sharedContentBlocked =
        selected != null &&
        workspaceToolsSharedContentBlocked(selected, moderationState);

    if (state.isLoading && rooms.isEmpty) {
      return const _WorkspaceToolsSkeleton();
    }

    if (state.errorMessage != null && rooms.isEmpty) {
      return WebTuiErrorState(
        title: 'Chưa tải được công cụ làm việc',
        message: state.errorMessage!,
        onRetry: controller.load,
      );
    }

    if (rooms.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(WebTuiSpacing.lg),
        children: [
          const SizedBox(height: 72),
          const WebTuiEmptyState(
            title: 'Chưa có cuộc trò chuyện để làm việc chung',
            message:
                'Tạo hoặc tham gia một kênh, sau đó bạn có thể họp, chia sẻ tệp và giao việc ngay trên điện thoại.',
            icon: Icons.workspaces_outline,
          ),
          const SizedBox(height: WebTuiSpacing.lg),
          FilledButton.icon(
            onPressed: () => context.push('/channels/new'),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Tạo kênh mới'),
          ),
        ],
      );
    }

    return RefreshIndicator(
      onRefresh: controller.refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          WebTuiSpacing.lg,
          WebTuiSpacing.md,
          WebTuiSpacing.lg,
          WebTuiSpacing.xl,
        ),
        children: [
          _RoomPicker(
            rooms: rooms,
            selected: selected!,
            onChanged: (room) => setState(() => _selectedRoomId = room.id),
            onOpenChat: () => _openChat(context, selected),
          ),
          const SizedBox(height: WebTuiSpacing.lg),
          Text(
            'Bạn muốn làm gì?',
            style: WebTuiTypography.titleMedium.copyWith(
              color: WebTuiColors.textPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: WebTuiSpacing.xs),
          Text(
            'Chọn một công cụ để mở thẳng vào ${selected.title}.',
            style: WebTuiTypography.bodySmall.copyWith(
              color: WebTuiColors.textSecondary,
            ),
          ),
          const SizedBox(height: WebTuiSpacing.md),
          if (sharedContentBlocked) ...[
            Container(
              key: const Key('workspace_tools_blocked_notice'),
              padding: const EdgeInsets.all(WebTuiSpacing.md),
              decoration: BoxDecoration(
                color: WebTuiColors.accentAmber.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(WebTuiRadii.md),
                border: Border.all(color: WebTuiColors.accentAmber),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.block_rounded, size: 20),
                  SizedBox(width: WebTuiSpacing.sm),
                  Expanded(
                    child: Text(
                      'Công cụ tạo nội dung dùng chung bị tắt cho hội thoại này. Hãy bỏ chặn người dùng trong phần an toàn trước khi tiếp tục.',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: WebTuiSpacing.md),
          ],
          LayoutBuilder(
            builder: (context, constraints) {
              final width = (constraints.maxWidth - WebTuiSpacing.sm) / 2;
              return Wrap(
                spacing: WebTuiSpacing.sm,
                runSpacing: WebTuiSpacing.sm,
                children: [
                  _ToolCard(
                    width: width,
                    icon: Icons.video_call_outlined,
                    title: 'Họp nhóm',
                    description: 'Họp, phòng chờ và khách ngoài',
                    onTap: sharedContentBlocked
                        ? null
                        : () => _openTools(context, selected, 1),
                  ),
                  _ToolCard(
                    width: width,
                    icon: Icons.folder_copy_outlined,
                    title: 'Đã chia sẻ',
                    description: 'Tệp, bình chọn và bản ghi',
                    onTap: sharedContentBlocked
                        ? null
                        : () => _openTools(context, selected, 2),
                  ),
                  _ToolCard(
                    width: width,
                    icon: Icons.description_outlined,
                    title: 'Ghi chú chung',
                    description: 'Cùng ghi biên bản và quyết định',
                    onTap: sharedContentBlocked
                        ? null
                        : () => _openTools(context, selected, 3),
                  ),
                  _ToolCard(
                    width: width,
                    icon: Icons.draw_outlined,
                    title: 'Bảng trắng',
                    description: 'Phác thảo nhanh cùng mọi người',
                    onTap: sharedContentBlocked
                        ? null
                        : () => _openTools(context, selected, 4),
                  ),
                  _ToolCard(
                    width: width,
                    icon: Icons.task_alt_outlined,
                    title: 'Việc cần làm',
                    description: 'Tạo và theo dõi công việc chung',
                    onTap: sharedContentBlocked
                        ? null
                        : () => _openTools(context, selected, 5),
                  ),
                  _ToolCard(
                    width: width,
                    icon: Icons.more_horiz_rounded,
                    title: 'Tất cả công cụ',
                    description: 'Xem đầy đủ công cụ của phòng',
                    onTap: sharedContentBlocked
                        ? null
                        : () => _openTools(context, selected, 0),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  ConversationSummary? _selectedRoom(List<ConversationSummary> rooms) {
    if (rooms.isEmpty) return null;
    final selectedId = _selectedRoomId;
    if (selectedId == null) return rooms.first;
    return rooms.cast<ConversationSummary?>().firstWhere(
      (room) => room?.id == selectedId,
      orElse: () => rooms.first,
    );
  }

  void _openTools(
    BuildContext context,
    ConversationSummary room,
    int initialTab,
  ) {
    showCollaborationRoomSheet(
      context,
      workspaceId: widget.workspaceId,
      channelId: room.channelId,
      title: room.title,
      conversation: room,
      initialTab: initialTab,
    );
  }

  void _openChat(BuildContext context, ConversationSummary room) {
    context.push(
      Uri(
        path: '/conversations/${room.channelId}',
        queryParameters: {
          'workspaceId': widget.workspaceId,
          'title': room.title,
          if (room.avatarUrl != null) 'avatarUrl': room.avatarUrl,
          if (room.peerUserId != null) 'peerUserId': room.peerUserId,
        },
      ).toString(),
      extra: room,
    );
  }
}

class _RoomPicker extends StatelessWidget {
  const _RoomPicker({
    required this.rooms,
    required this.selected,
    required this.onChanged,
    required this.onOpenChat,
  });

  final List<ConversationSummary> rooms;
  final ConversationSummary selected;
  final ValueChanged<ConversationSummary> onChanged;
  final VoidCallback onOpenChat;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(WebTuiSpacing.md),
      decoration: BoxDecoration(
        color: WebTuiColors.surface,
        borderRadius: BorderRadius.circular(WebTuiRadii.lg),
        border: Border.all(color: WebTuiColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: WebTuiColors.primarySoft,
                  borderRadius: BorderRadius.circular(WebTuiRadii.md),
                ),
                child: const Icon(
                  Icons.workspaces_outline,
                  color: WebTuiColors.primary,
                ),
              ),
              const SizedBox(width: WebTuiSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Phòng đang làm việc',
                      style: WebTuiTypography.bodyMedium.copyWith(
                        color: WebTuiColors.textPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      'Các công cụ bên dưới sẽ dùng cho phòng này.',
                      style: WebTuiTypography.bodySmall.copyWith(
                        color: WebTuiColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: WebTuiSpacing.md),
          DropdownButtonFormField<String>(
            key: ValueKey(selected.id),
            initialValue: selected.id,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Chọn cuộc trò chuyện',
              prefixIcon: Icon(Icons.forum_outlined),
            ),
            items: [
              for (final room in rooms)
                DropdownMenuItem(value: room.id, child: Text(room.title)),
            ],
            onChanged: (id) {
              if (id == null) return;
              onChanged(rooms.firstWhere((room) => room.id == id));
            },
          ),
          const SizedBox(height: WebTuiSpacing.sm),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onOpenChat,
              icon: const Icon(Icons.chat_bubble_outline_rounded),
              label: const Text('Mở cuộc trò chuyện'),
            ),
          ),
        ],
      ),
    );
  }
}

class _ToolCard extends StatelessWidget {
  const _ToolCard({
    required this.width,
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
  });

  final double width;
  final IconData icon;
  final String title;
  final String description;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Material(
        color: WebTuiColors.surface,
        borderRadius: BorderRadius.circular(WebTuiRadii.lg),
        child: InkWell(
          borderRadius: BorderRadius.circular(WebTuiRadii.lg),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 142),
            padding: const EdgeInsets.all(WebTuiSpacing.md),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(WebTuiRadii.lg),
              border: Border.all(color: WebTuiColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: WebTuiColors.primarySoft,
                    borderRadius: BorderRadius.circular(WebTuiRadii.md),
                  ),
                  child: Icon(icon, color: WebTuiColors.primary, size: 21),
                ),
                const SizedBox(height: WebTuiSpacing.sm),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: WebTuiTypography.bodyMedium.copyWith(
                    color: WebTuiColors.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: WebTuiTypography.bodySmall.copyWith(
                    color: WebTuiColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WorkspaceToolsSkeleton extends StatelessWidget {
  const _WorkspaceToolsSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(WebTuiSpacing.lg),
      children: const [
        WebTuiLoadingState(message: 'Đang chuẩn bị công cụ làm việc...'),
      ],
    );
  }
}
