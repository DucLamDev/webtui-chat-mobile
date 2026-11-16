import 'package:flutter/material.dart';

import '../icons/webtui_icons.dart';
import '../tokens/webtui_channel_colors.dart';
import '../tokens/webtui_colors.dart';
import '../tokens/webtui_density.dart';
import '../tokens/webtui_radii.dart';
import '../tokens/webtui_spacing.dart';
import '../tokens/webtui_typography.dart';
import 'webtui_avatar.dart';
import 'webtui_badges.dart';

class WebTuiConversationListItem extends StatelessWidget {
  const WebTuiConversationListItem({
    required this.title,
    required this.preview,
    required this.timeLabel,
    required this.avatarLabel,
    this.avatarUrl,
    this.avatarPublicImage = false,
    this.avatarIcon,
    this.squareAvatar = false,
    this.pinned = false,
    this.badgeLabel,
    this.unreadCount = 0,
    this.unreadMax = webTuiUnreadMaxGroup,
    this.status,
    this.muted = false,
    this.selected = false,
    this.onTap,
    this.onLongPress,
    this.trailing,
    super.key,
  });

  final String title;
  final String preview;
  final String timeLabel;
  final String avatarLabel;
  final String? avatarUrl;
  final bool avatarPublicImage;

  /// Biểu tượng thay chữ cái đầu (kênh, mục nghiệp vụ như Phê duyệt, Ticket).
  final IconData? avatarIcon;

  /// Ô vuông bo góc (kênh) thay vì ảnh tròn (người). Có [avatarIcon] thì tự
  /// là ô vuông.
  final bool squareAvatar;

  /// Hội thoại ghim: nền xanh nhạt bo góc và biểu tượng ghim cạnh số chưa đọc.
  final bool pinned;

  /// Nhãn nhỏ cạnh tên (ví dụ "BOT").
  final String? badgeLabel;
  final int unreadCount;

  /// Trần số chưa đọc: [webTuiUnreadMaxDirect] cho chat 1-1 / bot, mặc định
  /// [webTuiUnreadMaxGroup] cho nhóm / kênh.
  final int unreadMax;
  final WebTuiPresenceStatus? status;
  final bool muted;
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final unread = unreadCount > 0;
    // Kênh / mục nghiệp vụ: ảnh tròn dải màu theo loại biểu tượng, biểu tượng
    // trắng (không còn ô vuông nền nhạt).
    final channelTone = avatarIcon == null
        ? null
        : webTuiChannelTone(avatarIcon!);
    final row = Material(
      color: selected
          ? WebTuiColors.primarySoft.withValues(alpha: 0.74)
          : WebTuiColors.page,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: SizedBox(
          height: WebTuiListDensity.conversationItemHeight,
          child: Stack(
            children: [
              if (selected)
                Positioned(
                  left: 0,
                  top: 10,
                  bottom: 10,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: WebTuiColors.primary,
                      borderRadius: BorderRadius.only(
                        topRight: Radius.circular(WebTuiRadii.xs),
                        bottomRight: Radius.circular(WebTuiRadii.xs),
                      ),
                    ),
                    child: SizedBox(width: 3),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.only(
                  left: WebTuiListDensity.rowPadding,
                ),
                child: Row(
                  children: [
                    WebTuiAvatar(
                      label: avatarLabel,
                      icon: avatarIcon,
                      gradientBase: channelTone?.icon,
                      imageUrl: avatarUrl,
                      allowPublicRequest: avatarPublicImage,
                      status: status,
                      square: squareAvatar && avatarIcon == null,
                      size: WebTuiListDensity.listAvatarSize,
                    ),
                    const SizedBox(width: WebTuiListDensity.avatarGap),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(
                          right: WebTuiListDensity.rowPadding,
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                // Tên (+ nhãn Bot, chuông tắt) chiếm hết chỗ còn lại để giờ
                                // nằm sát mép phải.
                                Expanded(
                                  child: Row(
                                    children: [
                                      Flexible(
                                        child: Text(
                                          title,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: WebTuiTypography.titleMedium
                                              .copyWith(
                                                color: WebTuiColors.textPrimary,
                                                fontSize: 16.5,
                                                letterSpacing: -0.1,
                                                fontWeight: unread
                                                    ? FontWeight.w700
                                                    : FontWeight.w500,
                                              ),
                                        ),
                                      ),
                                      if (badgeLabel != null) ...[
                                        const SizedBox(width: 6),
                                        _InlineBadge(label: badgeLabel!),
                                      ],
                                      if (muted) ...[
                                        const SizedBox(width: 4),
                                        Icon(
                                          WebTuiIcons.bellOffFilled,
                                          size: 15,
                                          color: WebTuiColors.textMuted,
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                const SizedBox(width: WebTuiSpacing.sm),
                                if (trailing == null) ...[
                                  if (pinned) ...[
                                    Icon(
                                      WebTuiIcons.pinFilled,
                                      size: 15,
                                      color: WebTuiColors.textMuted,
                                    ),
                                    const SizedBox(width: 4),
                                  ],
                                  Text(
                                    timeLabel,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: WebTuiTypography.bodySmall.copyWith(
                                      fontSize: 13,
                                      color: unread
                                          ? WebTuiColors.primary
                                          : WebTuiColors.textMuted,
                                      fontWeight: unread
                                          ? FontWeight.w700
                                          : FontWeight.w400,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    preview,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    // Còn tin chưa đọc: dòng tin đậm, màu chữ
                                    // chính để nhận ra ngay (không chỉ nhờ số).
                                    style: WebTuiTypography.bodyMedium.copyWith(
                                      fontSize: 14.5,
                                      height: 1.35,
                                      color: unread
                                          ? WebTuiColors.textPrimary
                                          : WebTuiColors.textSecondary,
                                      fontWeight: unread
                                          ? FontWeight.w700
                                          : FontWeight.w400,
                                    ),
                                  ),
                                ),
                                if (trailing == null && unread) ...[
                                  const SizedBox(width: WebTuiSpacing.sm),
                                  WebTuiUnreadBadge(
                                    count: unreadCount,
                                    max: unreadMax,
                                    muted: muted,
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (trailing != null)
                      Padding(
                        padding: const EdgeInsets.only(
                          right: WebTuiListDensity.rowPadding,
                        ),
                        child: trailing!,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return row;
  }
}

/// Nhãn nhỏ cạnh tên hội thoại (ví dụ Bot): chữ xanh đậm trên nền xanh nhạt.
class _InlineBadge extends StatelessWidget {
  const _InlineBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final dark = WebTuiColors.brightness == Brightness.dark;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: WebTuiColors.primarySoft,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        child: Text(
          label,
          style: WebTuiTypography.labelSmall.copyWith(
            // Xanh đậm hơn màu nhấn: đạt 4,5:1 trên nền xanh nhạt.
            color: dark ? const Color(0xFF8CC2FF) : const Color(0xFF0957B0),
            fontSize: 11,
            letterSpacing: 0.2,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class WebTuiChannelBotListItem extends StatelessWidget {
  const WebTuiChannelBotListItem({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    this.trailingLabel,
    this.unreadCount = 0,
    this.onTap,
    super.key,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final String? trailingLabel;
  final int unreadCount;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: WebTuiColors.page,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: WebTuiListDensity.conversationItemHeight,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: WebTuiSpacing.lg),
            child: Row(
              children: [
                WebTuiAvatar(label: title, icon: icon, gradientBase: color),
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
                        style: WebTuiTypography.bodyMedium.copyWith(
                          color: WebTuiColors.textPrimary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: WebTuiSpacing.xs),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: WebTuiTypography.bodySmall.copyWith(
                          color: unreadCount > 0
                              ? WebTuiColors.textPrimary
                              : WebTuiColors.textMuted,
                          fontWeight: unreadCount > 0 ? FontWeight.w700 : null,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: WebTuiSpacing.sm),
                if (unreadCount > 0)
                  WebTuiUnreadBadge(count: unreadCount)
                else if (trailingLabel != null)
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 86),
                    child: WebTuiStatusPill(
                      label: trailingLabel!,
                      color: color,
                    ),
                  )
                else
                  Icon(WebTuiIcons.forward, color: WebTuiColors.textMuted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class WebTuiSectionLabel extends StatelessWidget {
  const WebTuiSectionLabel(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        WebTuiSpacing.lg,
        14,
        WebTuiSpacing.lg,
        6,
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: WebTuiTypography.labelSmall.copyWith(
          color: WebTuiColors.textMuted,
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

/// Nhóm dòng liền mạch: nền trang, không viền khối; giữa các dòng là đường kẻ
/// mảnh 0,5px thụt vào tới chữ ([dividerIndent]) và chạy tới mép phải.
class WebTuiListSurface extends StatelessWidget {
  const WebTuiListSurface({
    required this.children,
    this.dividerIndent = WebTuiListDensity.contactDividerIndent,
    super.key,
  });

  final List<Widget> children;
  final double dividerIndent;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: WebTuiColors.page,
      child: Column(
        children: [
          for (var index = 0; index < children.length; index++) ...[
            children[index],
            if (index != children.length - 1)
              WebTuiHairline(indent: dividerIndent),
          ],
        ],
      ),
    );
  }
}

/// Đường kẻ mảnh 0,5px giữa hai dòng (thụt trái [indent], tràn mép phải).
class WebTuiHairline extends StatelessWidget {
  const WebTuiHairline({this.indent = 0, super.key});

  final double indent;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: indent),
      child: SizedBox(
        height: 0.5,
        width: double.infinity,
        child: ColoredBox(color: WebTuiColors.hairline),
      ),
    );
  }
}

class WebTuiSliverListSurface extends StatelessWidget {
  const WebTuiSliverListSurface({
    required this.itemCount,
    required this.itemBuilder,
    this.dividerIndent = WebTuiListDensity.contactDividerIndent,
    super.key,
  });

  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final double dividerIndent;

  @override
  Widget build(BuildContext context) {
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) => _LazySurfaceItem(
          index: index,
          itemCount: itemCount,
          dividerIndent: dividerIndent,
          child: itemBuilder(context, index),
        ),
        childCount: itemCount,
      ),
    );
  }
}

class WebTuiLazyListSurface extends StatelessWidget {
  const WebTuiLazyListSurface({
    required this.itemCount,
    required this.itemBuilder,
    this.estimatedItemExtent = 72,
    this.maxHeight = 432,
    this.dividerIndent = WebTuiListDensity.contactDividerIndent,
    super.key,
  });

  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final double estimatedItemExtent;
  final double maxHeight;
  final double dividerIndent;

  @override
  Widget build(BuildContext context) {
    final estimatedHeight = itemCount * estimatedItemExtent;
    final height = estimatedHeight < maxHeight ? estimatedHeight : maxHeight;
    return SizedBox(
      height: height,
      child: ListView.builder(
        primary: false,
        padding: EdgeInsets.zero,
        itemCount: itemCount,
        itemBuilder: (context, index) => _LazySurfaceItem(
          index: index,
          itemCount: itemCount,
          dividerIndent: dividerIndent,
          child: itemBuilder(context, index),
        ),
      ),
    );
  }
}

class WebTuiLazyGridSurface extends StatelessWidget {
  const WebTuiLazyGridSurface({
    required this.itemCount,
    required this.itemBuilder,
    this.crossAxisCount = 3,
    this.spacing = 4,
    this.maxHeight = 432,
    super.key,
  });

  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final int crossAxisCount;
  final double spacing;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    if (itemCount <= 0 || crossAxisCount <= 0) {
      return const SizedBox.shrink();
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final totalSpacing = spacing * (crossAxisCount - 1);
        final tileExtent =
            (constraints.maxWidth - totalSpacing) / crossAxisCount;
        final rowCount = (itemCount + crossAxisCount - 1) ~/ crossAxisCount;
        final naturalHeight = tileExtent * rowCount + spacing * (rowCount - 1);
        final height = naturalHeight < maxHeight ? naturalHeight : maxHeight;
        return SizedBox(
          height: height,
          child: GridView.builder(
            primary: false,
            padding: EdgeInsets.zero,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              crossAxisSpacing: spacing,
              mainAxisSpacing: spacing,
            ),
            itemCount: itemCount,
            itemBuilder: itemBuilder,
          ),
        );
      },
    );
  }
}

class _LazySurfaceItem extends StatelessWidget {
  const _LazySurfaceItem({
    required this.index,
    required this.itemCount,
    required this.dividerIndent,
    required this.child,
  });

  final int index;
  final int itemCount;
  final double dividerIndent;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: WebTuiColors.page,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          child,
          if (index != itemCount - 1) WebTuiHairline(indent: dividerIndent),
        ],
      ),
    );
  }
}
