import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart' show LucideIcons;

import '../../../../design_system/components/webtui_components.dart';
import '../../../../design_system/icons/webtui_icons.dart';
import '../../../../design_system/tokens/webtui_colors.dart';
import '../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../design_system/tokens/webtui_typography.dart';
import '../../domain/entities/call_session.dart';
import '../controllers/peer_presence.dart';

/// Đầu phòng chat: quay lại, ảnh đại diện (chấm xanh khi 1-1) + tên + dòng phụ,
/// gọi thoại / gọi video (xanh, nét mảnh) và nút "…" gom: tìm tin nhắn, báo cáo
/// hoặc chặn, công cụ làm việc, chi tiết kênh.
///
/// Chat bot thông báo: thay hai nút gọi bằng [notificationAction] (menu tắt /
/// bật thông báo), menu "…" chỉ còn "Tìm tin nhắn".
class ChatRoomAppBar extends StatelessWidget implements PreferredSizeWidget {
  const ChatRoomAppBar({
    required this.title,
    required this.noticeBot,
    this.presence,
    required this.directChat,
    required this.memberCount,
    required this.callsEnabled,
    required this.onCall,
    required this.onSearch,
    required this.onTools,
    required this.onDetails,
    this.avatarUrl,
    this.publicAvatar = false,
    this.onSafety,
    this.notificationAction,
    super.key,
  });

  final String title;
  final String? avatarUrl;

  /// Ảnh đại diện công khai (logo chat bot), không cần đăng nhập để tải.
  final bool publicAvatar;
  final bool noticeBot;

  /// Chat 1-1: trạng thái hoạt động của người kia (`null`: ẩn dòng phụ và chấm).
  final PeerPresenceLabel? presence;
  final bool directChat;
  final int memberCount;
  final bool callsEnabled;
  final ValueChanged<CallMode> onCall;
  final VoidCallback onSearch;
  final VoidCallback? onSafety;
  final VoidCallback onTools;
  final VoidCallback onDetails;
  final Widget? notificationAction;

  @override
  Size get preferredSize => const Size.fromHeight(64);

  @override
  Widget build(BuildContext context) {
    final subtitle = noticeBot
        ? null
        : directChat
        ? presence?.text
        : memberCount > 0
        ? '$memberCount thành viên'
        : null;
    return AppBar(
      toolbarHeight: 64,
      backgroundColor: WebTuiColors.surface,
      foregroundColor: WebTuiColors.textPrimary,
      iconTheme: const IconThemeData(color: WebTuiColors.primary),
      actionsIconTheme: const IconThemeData(color: WebTuiColors.primary),
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      shape: Border(
        bottom: BorderSide(color: WebTuiColors.border.withValues(alpha: 0.8)),
      ),
      automaticallyImplyLeading: false,
      leadingWidth: 48,
      leading: IconButton(
        key: const Key('chat_room_back'),
        tooltip: 'Quay lại',
        onPressed: () => Navigator.of(context).maybePop(),
        icon: const Icon(WebTuiIcons.back, size: 30),
      ),
      titleSpacing: 0,
      title: Row(
        children: [
          WebTuiAvatar(
            label: title,
            imageUrl: avatarUrl,
            allowPublicRequest: publicAvatar,
            status: presence?.online == true
                ? WebTuiPresenceStatus.online
                : null,
            size: 44,
          ),
          const SizedBox(width: WebTuiSpacing.md),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: WebTuiTypography.titleMedium.copyWith(
                    color: WebTuiColors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: WebTuiTypography.bodySmall.copyWith(
                      color: WebTuiColors.textMuted,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        if (noticeBot)
          ?notificationAction
        else if (callsEnabled) ...[
          IconButton(
            key: const Key('chat_room_call_audio'),
            tooltip: 'Gọi thoại',
            onPressed: () => onCall(CallMode.audio),
            icon: const Icon(WebTuiIcons.phone, size: 25),
          ),
          IconButton(
            key: const Key('chat_room_call_video'),
            tooltip: 'Gọi video',
            onPressed: () => onCall(CallMode.video),
            icon: const Icon(WebTuiIcons.video, size: 27),
          ),
        ],
        PopupMenuButton<String>(
          key: const Key('chat_room_more_menu'),
          tooltip: 'Thêm',
          icon: const Icon(WebTuiIcons.more, size: 26),
          onSelected: (value) {
            switch (value) {
              case 'search':
                onSearch();
              case 'safety':
                onSafety?.call();
              case 'tools':
                onTools();
              case 'details':
                onDetails();
            }
          },
          itemBuilder: (_) => [
            const PopupMenuItem(
              value: 'search',
              child: _ChatMenuRow(
                icon: WebTuiIcons.search,
                label: 'Tìm tin nhắn',
              ),
            ),
            if (!noticeBot && onSafety != null)
              const PopupMenuItem(
                value: 'safety',
                child: _ChatMenuRow(
                  icon: LucideIcons.shield,
                  label: 'Báo cáo hoặc chặn người dùng',
                ),
              ),
            if (!noticeBot)
              const PopupMenuItem(
                key: Key('chat_collaboration_tools_action'),
                value: 'tools',
                child: _ChatMenuRow(
                  icon: WebTuiIcons.work,
                  label: 'Công cụ làm việc',
                ),
              ),
            if (!noticeBot)
              const PopupMenuItem(
                value: 'details',
                child: _ChatMenuRow(
                  icon: WebTuiIcons.channel,
                  label: 'Chi tiết kênh',
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _ChatMenuRow extends StatelessWidget {
  const _ChatMenuRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: WebTuiColors.textSecondary),
        const SizedBox(width: 12),
        Flexible(child: Text(label)),
      ],
    );
  }
}
