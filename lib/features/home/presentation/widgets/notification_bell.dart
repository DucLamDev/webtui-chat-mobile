import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../design_system/tokens/webtui_colors.dart';
import '../../../../design_system/tokens/webtui_typography.dart';
import '../../../notifications/presentation/controllers/notification_center_controller.dart';

/// Nút chuông trên thanh đầu: chỉ có khi máy chủ chưa dùng bot thông báo.
/// Có bot thì trả danh sách rỗng (không tải danh sách thông báo cũ).
List<Widget> notificationBellActions({
  required String workspaceId,
  required bool noticeBot,
}) {
  if (noticeBot) return const [];
  return [NotificationBellEntry(workspaceId: workspaceId)];
}

class NotificationBellEntry extends ConsumerWidget {
  const NotificationBellEntry({required this.workspaceId, super.key});

  final String workspaceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(notificationCenterControllerProvider(workspaceId));
    return NotificationBellButton(
      unreadCount: state.unreadCount,
      onPressed: () => context.push('/notifications?workspaceId=$workspaceId'),
    );
  }
}

class NotificationBellButton extends StatelessWidget {
  const NotificationBellButton({
    required this.unreadCount,
    required this.onPressed,
    super.key,
  });

  final int unreadCount;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          tooltip: 'Thông báo',
          onPressed: onPressed,
          icon: const Icon(CupertinoIcons.bell),
        ),
        if (unreadCount > 0)
          Positioned(
            right: 6,
            top: 6,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: WebTuiColors.danger,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                child: Text(
                  unreadCount > 99 ? '99+' : unreadCount.toString(),
                  style: WebTuiTypography.labelSmall.copyWith(
                    color: WebTuiColors.textOnPrimary,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
