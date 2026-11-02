import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../design_system/components/webtui_components.dart';
import '../../../../design_system/tokens/webtui_colors.dart';
import '../../../../design_system/tokens/webtui_radii.dart';
import '../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../design_system/tokens/webtui_typography.dart';
import '../../../workspace/presentation/controllers/workspace_controller.dart';
import '../../domain/entities/mobile_notification.dart';
import '../controllers/notification_center_controller.dart';

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({this.workspaceId, super.key});

  final String? workspaceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeWorkspaceId =
        workspaceId ??
        ref.watch(workspaceControllerProvider).activeWorkspace?.id;
    if (activeWorkspaceId == null || activeWorkspaceId.trim().isEmpty) {
      return const Scaffold(
        body: SafeArea(
          child: WebTuiEmptyState(
            title: 'Chưa chọn workspace',
            message: 'Chọn workspace trước khi xem thông báo.',
            icon: Icons.notifications_none_rounded,
          ),
        ),
      );
    }

    final provider = notificationCenterControllerProvider(activeWorkspaceId);
    final state = ref.watch(provider);
    final controller = ref.read(provider.notifier);

    return Scaffold(
      backgroundColor: WebTuiColors.background,
      appBar: AppBar(
        title: const Text('Thông báo'),
        surfaceTintColor: Colors.transparent,
        actions: [
          TextButton(
            onPressed: state.isMarkingAll || state.unreadCount == 0
                ? null
                : controller.markAllRead,
            child: state.isMarkingAll
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Đã đọc hết'),
          ),
          IconButton(
            key: const Key('notifications_delete_all'),
            tooltip: 'Xoá tất cả thông báo',
            onPressed: state.isDeletingAll || state.notifications.isEmpty
                ? null
                : () => _confirmDeleteAll(context, controller),
            icon: state.isDeletingAll
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.delete_sweep_outlined),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: controller.load,
          child: Builder(
            builder: (context) {
              if (state.isLoading && state.notifications.isEmpty) {
                return const WebTuiLoadingState(
                  message: 'Đang tải thông báo...',
                );
              }
              if (state.errorMessage != null && state.notifications.isEmpty) {
                return WebTuiErrorState(
                  title: 'Không tải được thông báo',
                  message: state.errorMessage!,
                  onRetry: controller.load,
                );
              }
              if (state.notifications.isEmpty) {
                return ListView(
                  children: const [
                    SizedBox(height: 120),
                    WebTuiEmptyState(
                      title: 'Chưa có thông báo',
                      message: 'Tin nhắn, lời mời và cảnh báo sẽ hiện ở đây.',
                      icon: Icons.notifications_none_rounded,
                    ),
                  ],
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(
                  WebTuiSpacing.md,
                  WebTuiSpacing.md,
                  WebTuiSpacing.md,
                  WebTuiSpacing.xl,
                ),
                itemCount: state.notifications.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(height: WebTuiSpacing.sm),
                itemBuilder: (context, index) {
                  final notification = state.notifications[index];
                  // Vuốt sang trái để xoá; giữ lâu để mở menu xoá (dễ thấy hơn).
                  return Dismissible(
                    key: ValueKey('notification_${notification.id}'),
                    direction: DismissDirection.endToStart,
                    background: const _DeleteSwipeBackground(),
                    onDismissed: (_) =>
                        _delete(context, controller, notification),
                    child: _NotificationTile(
                      notification: notification,
                      onTap: () async {
                        await controller.markRead(notification);
                        if (!context.mounted) {
                          return;
                        }
                        final location = _locationFor(notification.target);
                        if (location != null) {
                          context.push(location);
                        }
                      },
                      onLongPress: () =>
                          _showActions(context, controller, notification),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}

Future<void> _delete(
  BuildContext context,
  NotificationCenterController controller,
  MobileNotification notification,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final error = await controller.delete(notification);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(error ?? 'Đã xoá thông báo.')));
}

Future<void> _showActions(
  BuildContext context,
  NotificationCenterController controller,
  MobileNotification notification,
) async {
  final delete = await showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: ListTile(
        key: const Key('notification_action_delete'),
        leading: const Icon(
          Icons.delete_outline_rounded,
          color: WebTuiColors.danger,
        ),
        title: const Text(
          'Xoá thông báo này',
          style: TextStyle(color: WebTuiColors.danger),
        ),
        onTap: () => Navigator.of(sheetContext).pop(true),
      ),
    ),
  );
  if (delete == true && context.mounted) {
    await _delete(context, controller, notification);
  }
}

Future<void> _confirmDeleteAll(
  BuildContext context,
  NotificationCenterController controller,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Xoá tất cả thông báo?'),
      content: const Text(
        'Mọi thông báo của workspace này sẽ bị xoá và không khôi phục được.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Huỷ'),
        ),
        FilledButton(
          key: const Key('notifications_delete_all_confirm'),
          style: FilledButton.styleFrom(backgroundColor: WebTuiColors.danger),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Xoá tất cả'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  final error = await controller.deleteAll();
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(content: Text(error ?? 'Đã xoá tất cả thông báo.')),
    );
}

class _DeleteSwipeBackground extends StatelessWidget {
  const _DeleteSwipeBackground();

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.symmetric(horizontal: WebTuiSpacing.lg),
      decoration: BoxDecoration(
        color: WebTuiColors.danger,
        borderRadius: BorderRadius.circular(WebTuiRadii.lg),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.delete_outline_rounded, color: WebTuiColors.textOnPrimary),
          SizedBox(width: WebTuiSpacing.xs),
          Text(
            'Xoá',
            style: TextStyle(
              color: WebTuiColors.textOnPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({
    required this.notification,
    required this.onTap,
    required this.onLongPress,
  });

  final MobileNotification notification;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final unread = !notification.isRead;
    return Material(
      color: unread ? WebTuiColors.primarySoft : WebTuiColors.surface,
      borderRadius: BorderRadius.circular(WebTuiRadii.lg),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(WebTuiRadii.lg),
        child: Container(
          padding: const EdgeInsets.all(WebTuiSpacing.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(WebTuiRadii.lg),
            border: Border.all(
              color: unread
                  ? WebTuiColors.primary.withValues(alpha: 0.26)
                  : WebTuiColors.border,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: unread
                    ? WebTuiColors.primary
                    : WebTuiColors.backgroundMuted,
                child: Icon(
                  _iconFor(notification.type),
                  color: unread
                      ? WebTuiColors.textOnPrimary
                      : WebTuiColors.textSecondary,
                  size: 18,
                ),
              ),
              const SizedBox(width: WebTuiSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            notification.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: WebTuiTypography.bodyMedium.copyWith(
                              color: WebTuiColors.textPrimary,
                              fontWeight: unread
                                  ? FontWeight.w800
                                  : FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: WebTuiSpacing.sm),
                        Text(
                          _timeAgo(notification.createdAt),
                          style: WebTuiTypography.labelSmall.copyWith(
                            color: WebTuiColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                    if (notification.body.trim().isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        notification.body,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: WebTuiTypography.bodySmall.copyWith(
                          color: WebTuiColors.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (unread) ...[
                const SizedBox(width: WebTuiSpacing.sm),
                const Icon(Icons.circle, size: 9, color: WebTuiColors.primary),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

String? _locationFor(NotificationTarget target) {
  if (target.canOpenContacts) {
    return Uri(
      path: '/',
      queryParameters: <String, String>{
        'tab': 'contacts',
        'workspaceId': target.workspaceId,
      },
    ).toString();
  }
  final channelId = target.channelId?.trim();
  if (channelId == null || channelId.isEmpty) {
    return null;
  }
  final params = <String, String>{
    'workspaceId': target.workspaceId,
    'title': 'Hội thoại',
    if (target.messageId?.trim().isNotEmpty == true)
      'messageId': target.messageId!.trim(),
  };
  return Uri(
    path: '/conversations/$channelId',
    queryParameters: params,
  ).toString();
}

IconData _iconFor(String type) {
  final normalized = type.trim().toLowerCase();
  if (normalized.contains('mention')) {
    return CupertinoIcons.at;
  }
  if (normalized.contains('call')) {
    return CupertinoIcons.phone;
  }
  if (normalized.contains('invite')) {
    return CupertinoIcons.person_add;
  }
  return CupertinoIcons.bell;
}

String _timeAgo(DateTime value) {
  final diff = DateTime.now().difference(value.toLocal());
  if (diff.inMinutes < 1) {
    return 'Vừa xong';
  }
  if (diff.inHours < 1) {
    return '${diff.inMinutes}p';
  }
  if (diff.inDays < 1) {
    return '${diff.inHours}h';
  }
  if (diff.inDays < 7) {
    return '${diff.inDays}d';
  }
  final local = value.toLocal();
  return '${local.day.toString().padLeft(2, '0')}/'
      '${local.month.toString().padLeft(2, '0')}';
}
