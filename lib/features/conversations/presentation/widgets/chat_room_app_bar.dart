import 'package:flutter/material.dart';

import '../../../../design_system/components/webtui_components.dart';
import '../../../../design_system/icons/webtui_icons.dart';
import '../../../../design_system/tokens/webtui_colors.dart';
import '../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../design_system/tokens/webtui_typography.dart';
import '../../../../l10n/app_strings.dart';
import '../../domain/entities/call_session.dart';
import '../controllers/peer_presence.dart';

/// Đầu phòng chat: quay lại, ảnh đại diện (chấm xanh khi 1-1) + tên + dòng phụ,
/// chỉ hai nút gọi thoại / gọi video và nút ba gạch (≡) gom: tìm tin nhắn, báo
/// cáo hoặc chặn, công cụ làm việc, chi tiết kênh. Các phần đều gọn (nút 44
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
        ? tr(
            '$memberCount thành viên',
            memberCount == 1 ? '1 member' : '$memberCount members',
          )
        : null;
    return AppBar(
      toolbarHeight: 64,
      backgroundColor: WebTuiColors.surface,
      foregroundColor: WebTuiColors.textPrimary,
      iconTheme: IconThemeData(color: WebTuiColors.primary),
      actionsIconTheme: IconThemeData(color: WebTuiColors.primary),
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      shape: Border(
        bottom: BorderSide(color: WebTuiColors.border.withValues(alpha: 0.8)),
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
      title: Row(
        children: [
          WebTuiAvatar(
            label: title,
            imageUrl: avatarUrl,
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
                _ChatRoomTitle(title),
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
            if (!noticeBot)
              PopupMenuItem(
                value: 'details',
                child: _ChatMenuRow(
                  icon: WebTuiIcons.channel,
                  label: tr('Chi tiết kênh', 'Channel details'),
                ),
              ),
          ],
        ),
        const SizedBox(width: WebTuiSpacing.xs),
      ],
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
  const _ChatRoomTitle(this.title);

  final String title;

  static const List<double> _fontSizes = [17, 16, 15];

  @override
  Widget build(BuildContext context) {
    final style = DefaultTextStyle.of(context).style.merge(
      WebTuiTypography.titleMedium.copyWith(
        color: WebTuiColors.textPrimary,
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
