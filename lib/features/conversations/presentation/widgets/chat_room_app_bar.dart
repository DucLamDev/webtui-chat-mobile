import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../design_system/components/webtui_components.dart';
import '../../../../design_system/icons/webtui_icons.dart';
import '../../../../design_system/tokens/webtui_colors.dart';
import '../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../design_system/tokens/webtui_typography.dart';
import '../../../../l10n/app_strings.dart';
import '../../domain/entities/call_session.dart';
import '../controllers/peer_presence.dart';
import 'channel_exit_actions.dart';

/// Đầu phòng chat: quay lại, ảnh đại diện (chấm xanh khi 1-1) + tên + dòng phụ,
/// chỉ hai nút gọi thoại / gọi video và nút ba gạch (≡) gom: tìm tin nhắn, báo
/// cáo hoặc chặn, công cụ làm việc, chi tiết nhóm (chat 1-1: "Xem hồ sơ" người
/// kia), rời / xoá nhóm (khi máy chủ cho phép). Bấm ảnh / tên: chat 1-1 mở hồ
/// sơ, nhóm mở chi tiết nhóm. Các phần đều gọn (nút 44
/// điểm, ảnh 38 điểm) và chữ tên tự nhỏ dần khi thiếu chỗ để tên người thường
/// gặp (vd. "Nguyễn Thanh Tiền") hiện đủ trên điện thoại khổ 360–390 điểm.
///
/// Chat bot thông báo: thay hai nút gọi bằng [notificationAction] (menu tắt /
/// bật thông báo), menu ≡ chỉ còn "Tìm tin nhắn".
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
    this.onViewProfile,
    this.avatarUrl,
    this.avatarGender,
    this.publicAvatar = false,
    this.onSafety,
    this.notificationAction,
    this.onLeaveGroup,
    this.onDeleteGroup,
    this.deleteGroupLabel,
    super.key,
  });

  final String title;
  final String? avatarUrl;

  /// Giới tính người đối diện (chat 1-1 với người); null cho nhóm / bot.
  final WebTuiAvatarGender? avatarGender;

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

  /// Chat 1-1: mở hồ sơ người kia (bấm ảnh / tên, mục "Xem hồ sơ" trong menu
  /// thay cho "Chi tiết nhóm"). `null`: chưa biết người kia, ẩn mục.
  final VoidCallback? onViewProfile;
  final Widget? notificationAction;

  /// "Rời nhóm" trong menu ≡ (`null`: ẩn — không phải nhóm / máy chủ không
  /// cho rời).
  final VoidCallback? onLeaveGroup;

  /// "Xoá nhóm" (đỏ, ghi rõ xoá cho mọi thành viên) (`null`: ẩn).
  final VoidCallback? onDeleteGroup;

  /// Tên mục xoá ("Xoá nhóm" / "Xoá kênh"); mặc định "Xoá nhóm".
  final String? deleteGroupLabel;

  @override
  Size get preferredSize => const Size.fromHeight(64);

  @override
  Widget build(BuildContext context) {
    final subtitle = noticeBot
        ? null
        : directChat
        ? presence?.text
        : memberCount > 0
        ? tr(
            '$memberCount thành viên',
            memberCount == 1 ? '1 member' : '$memberCount members',
          )
        : null;
    // Kiểu Zalo: nền sáng = thanh xanh (gradient nhẹ) chữ / nút trắng; nền tối
    // = nền tối đậm của theme, chữ / nút sáng.
    final dark = WebTuiColors.brightness == Brightness.dark;
    final fg = dark ? WebTuiColors.textPrimary : Colors.white;
    final subFg = dark ? WebTuiColors.textMuted : const Color(0xE6FFFFFF);
    return AppBar(
      toolbarHeight: 64,
      backgroundColor: dark ? WebTuiColors.surface : WebTuiColors.primary,
      foregroundColor: fg,
      iconTheme: IconThemeData(color: fg),
      actionsIconTheme: IconThemeData(color: fg),
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      systemOverlayStyle: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
      flexibleSpace: dark
          ? DecoratedBox(
              decoration: BoxDecoration(
                color: WebTuiColors.surface,
                border: Border(
                  bottom: BorderSide(
                    color: WebTuiColors.border.withValues(alpha: 0.8),
                  ),
                ),
              ),
            )
          : DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    WebTuiColors.primary,
                    Color.lerp(WebTuiColors.primary, Colors.white, 0.14)!,
                  ],
                ),
              ),
            ),
      automaticallyImplyLeading: false,
      leadingWidth: _actionSize,
      leading: IconButton(
        key: const Key('chat_room_back'),
        tooltip: tr('Quay lại', 'Back'),
        style: _actionStyle,
        onPressed: () => Navigator.of(context).maybePop(),
        icon: const Icon(WebTuiIcons.back, size: 28),
      ),
      titleSpacing: 0,
      // Bấm ảnh / tên: chat 1-1 mở hồ sơ người kia, nhóm mở chi tiết nhóm (như
      // Zalo); chat bot thông báo không có trang chi tiết.
      title: _TappableTitle(
        onTap: noticeBot ? null : (directChat ? onViewProfile : onDetails),
        semanticLabel: directChat
            ? tr('Xem hồ sơ $title', 'View $title profile')
            : tr('Xem chi tiết nhóm $title', 'View $title group details'),
        child: Row(
          children: [
            WebTuiAvatar(
              label: title,
              imageUrl: avatarUrl,
              gender: avatarGender,
              allowPublicRequest: publicAvatar,
              status: presence?.online == true
                  ? WebTuiPresenceStatus.online
                  : null,
              size: 38,
            ),
            const SizedBox(width: WebTuiSpacing.sm),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ChatRoomTitle(title, color: fg),
                  if (subtitle != null)
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: WebTuiTypography.bodySmall.copyWith(color: subFg),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        if (noticeBot)
          ?notificationAction
        else if (callsEnabled) ...[
          IconButton(
            key: const Key('chat_room_call_audio'),
            tooltip: tr('Gọi thoại', 'Voice call'),
            style: _actionStyle,
            onPressed: () => onCall(CallMode.audio),
            icon: const Icon(WebTuiIcons.phone, size: 24),
          ),
          IconButton(
            key: const Key('chat_room_call_video'),
            tooltip: tr('Gọi video', 'Video call'),
            style: _actionStyle,
            onPressed: () => onCall(CallMode.video),
            icon: const Icon(WebTuiIcons.video, size: 26),
          ),
        ],
        PopupMenuButton<String>(
          key: const Key('chat_room_more_menu'),
          tooltip: tr('Thêm tuỳ chọn', 'More options'),
          padding: EdgeInsets.zero,
          style: _actionStyle,
          icon: const Icon(WebTuiIcons.menu, size: 26),
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
              case 'profile':
                onViewProfile?.call();
              case 'leave':
                onLeaveGroup?.call();
              case 'delete':
                onDeleteGroup?.call();
            }
          },
          itemBuilder: (_) => [
            PopupMenuItem(
              value: 'search',
              child: _ChatMenuRow(
                icon: WebTuiIcons.search,
                label: tr('Tìm tin nhắn', 'Search messages'),
              ),
            ),
            if (!noticeBot && onSafety != null)
              PopupMenuItem(
                value: 'safety',
                child: _ChatMenuRow(
                  icon: WebTuiIcons.shieldCheck,
                  label: tr(
                    'Báo cáo hoặc chặn người dùng',
                    'Report or block user',
                  ),
                ),
              ),
            if (!noticeBot)
              PopupMenuItem(
                key: const Key('chat_collaboration_tools_action'),
                value: 'tools',
                child: _ChatMenuRow(
                  icon: WebTuiIcons.work,
                  label: tr('Công cụ làm việc', 'Work tools'),
                ),
              ),
            // Chat 1-1 không phải nhóm: "Xem hồ sơ" người kia thay cho
            // "Chi tiết nhóm".
            if (!noticeBot && directChat && onViewProfile != null)
              PopupMenuItem(
                key: const Key('chat_room_view_profile'),
                value: 'profile',
                child: _ChatMenuRow(
                  icon: WebTuiIcons.profile,
                  label: tr('Xem hồ sơ', 'View profile'),
                ),
              ),
            if (!noticeBot && !directChat)
              PopupMenuItem(
                key: const Key('chat_room_group_details'),
                value: 'details',
                child: _ChatMenuRow(
                  icon: WebTuiIcons.channel,
                  label: tr('Chi tiết nhóm', 'Group details'),
                ),
              ),
            if (!noticeBot && onLeaveGroup != null)
              PopupMenuItem(
                key: const Key('chat_room_leave_group'),
                value: 'leave',
                child: _ChatMenuRow(
                  icon: WebTuiIcons.leaveGroup,
                  label: tr('Rời nhóm', 'Leave group'),
                  color: channelExitDangerText,
                ),
              ),
            if (!noticeBot && onDeleteGroup != null)
              PopupMenuItem(
                key: const Key('chat_room_delete_group'),
                value: 'delete',
                child: _ChatMenuRow(
                  icon: WebTuiIcons.delete,
                  label: deleteGroupLabel ?? tr('Xoá nhóm', 'Delete group'),
                  subtitle: tr(
                    'Xoá cho mọi thành viên',
                    'Deletes it for every member',
                  ),
                  color: channelExitDangerText,
                  strong: true,
                ),
              ),
          ],
        ),
        const SizedBox(width: WebTuiSpacing.xs),
      ],
    );
  }
}

/// Vùng ảnh + tên ở đầu phòng chat bấm được (cao bằng thanh đầu, gợn nhẹ khi
/// bấm); [onTap] `null` thì chỉ là chữ.
class _TappableTitle extends StatelessWidget {
  const _TappableTitle({
    required this.onTap,
    required this.semanticLabel,
    required this.child,
  });

  final VoidCallback? onTap;
  final String semanticLabel;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final onTap = this.onTap;
    if (onTap == null) return child;
    return Semantics(
      button: true,
      label: semanticLabel,
      child: InkWell(
        key: const Key('chat_room_title_tap'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(height: 56, child: child),
      ),
    );
  }
}

/// Vùng bấm của mỗi nút đầu trang: đúng 44 điểm (mức tối thiểu của iOS), không
/// nới thêm thành 48 như mặc định của Material để dành chỗ cho tên.
const double _actionSize = 44;
final ButtonStyle _actionStyle = IconButton.styleFrom(
  fixedSize: const Size.square(_actionSize),
  minimumSize: const Size.square(_actionSize),
  padding: EdgeInsets.zero,
  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
);

/// Tên ở đầu phòng chat: chữ 17; thiếu chỗ thì nhỏ dần còn 16 rồi 15 để tên ba
/// chữ thường gặp vẫn hiện đủ trên máy khổ hẹp. Nhỏ tới 15 vẫn không vừa (tên
/// nhóm dài) mới cắt bằng "…".
class _ChatRoomTitle extends StatelessWidget {
  const _ChatRoomTitle(this.title, {required this.color});

  final String title;
  final Color color;

  static const List<double> _fontSizes = [17, 16, 15];

  @override
  Widget build(BuildContext context) {
    final style = DefaultTextStyle.of(context).style.merge(
      WebTuiTypography.titleMedium.copyWith(
        color: color,
        fontWeight: FontWeight.w700,
      ),
    );
    final textScaler = MediaQuery.textScalerOf(context);
    final textDirection = Directionality.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        bool fits(double fontSize) {
          final painter = TextPainter(
            text: TextSpan(
              text: title,
              style: style.copyWith(fontSize: fontSize),
            ),
            maxLines: 1,
            ellipsis: '…',
            textDirection: textDirection,
            textScaler: textScaler,
          )..layout(maxWidth: constraints.maxWidth);
          final exceeded = painter.didExceedMaxLines;
          painter.dispose();
          return !exceeded;
        }

        final fontSize = _fontSizes.firstWhere(
          fits,
          orElse: () => _fontSizes.last,
        );
        return Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: style.copyWith(fontSize: fontSize),
        );
      },
    );
  }
}

class _ChatMenuRow extends StatelessWidget {
  const _ChatMenuRow({
    required this.icon,
    required this.label,
    this.subtitle,
    this.color,
    this.strong = false,
  });

  final IconData icon;
  final String label;
  final String? subtitle;

  /// Màu chữ và biểu tượng (`null`: màu thường).
  final Color? color;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final subtitle = this.subtitle;
    return Row(
      children: [
        Icon(icon, size: 20, color: color ?? WebTuiColors.textSecondary),
        const SizedBox(width: 12),
        Flexible(
          child: subtitle == null
              ? Text(
                  label,
                  style: color == null
                      ? null
                      : TextStyle(
                          color: color,
                          fontWeight: strong
                              ? FontWeight.w700
                              : FontWeight.w600,
                        ),
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        color: color,
                        fontWeight: strong ? FontWeight.w700 : FontWeight.w600,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: WebTuiTypography.bodySmall.copyWith(
                        color: WebTuiColors.textMuted,
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}
