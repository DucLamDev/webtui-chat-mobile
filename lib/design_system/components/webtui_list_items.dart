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
  final WebTuiPresenceStatus? status;
  final bool muted;
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final square = squareAvatar || avatarIcon != null;
    final channelTone = avatarIcon == null
        ? null
        : webTuiChannelTone(
            avatarIcon!,
            dark: Theme.of(context).brightness == Brightness.dark,
          );
    final highlighted = pinned && !selected;
    final row = Material(
      color: selected
          ? WebTuiColors.primarySoft.withValues(alpha: 0.74)
          : highlighted
          ? WebTuiColors.primarySoft.withValues(alpha: 0.6)
          : WebTuiColors.surface,
      borderRadius: highlighted ? BorderRadius.circular(WebTuiRadii.lg) : null,
      clipBehavior: highlighted ? Clip.antiAlias : Clip.none,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: SizedBox(
          height: WebTuiListDensity.conversationItemHeight,
          child: Stack(
            children: [
              if (selected)
                const Positioned(
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
                padding: const EdgeInsets.symmetric(
                  horizontal: WebTuiSpacing.lg,
                ),
                child: Row(
                  children: [
                    WebTuiAvatar(
                      label: avatarLabel,
                      icon: avatarIcon,
                      color:
                          channelTone?.background ?? WebTuiColors.primarySoft,
                      foregroundColor:
                          channelTone?.icon ?? WebTuiColors.primary,
                      imageUrl: avatarUrl,
                      allowPublicRequest: avatarPublicImage,
                      status: status,
                      square: square,
                      size: WebTuiListDensity.listAvatarSize,
                    ),
                    const SizedBox(width: WebTuiSpacing.md),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: WebTuiTypography.titleMedium.copyWith(
                                    color: WebTuiColors.textPrimary,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              if (badgeLabel != null) ...[
                                const SizedBox(width: WebTuiSpacing.sm),
                                _InlineBadge(label: badgeLabel!),
                              ],
                            ],
                          ),
                          const SizedBox(height: WebTuiSpacing.xs),
                          Row(
                            children: [
                              if (muted) ...[
                                const Icon(
                                  WebTuiIcons.bellOff,
                                  size: 14,
                                  color: WebTuiColors.textMuted,
                                ),
                                const SizedBox(width: WebTuiSpacing.xs),
                              ],
                              Expanded(
                                child: Text(
                                  preview,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: WebTuiTypography.bodyMedium.copyWith(
                                    color: WebTuiColors.textSecondary,
                                    fontWeight: FontWeight.w400,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: WebTuiSpacing.sm),
                    if (trailing != null)
                      trailing!
                    else
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            timeLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: WebTuiTypography.bodySmall.copyWith(
                              color: WebTuiColors.textMuted,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: WebTuiSpacing.xs),
                          if (pinned || unreadCount > 0)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (pinned)
                                  const Padding(
                                    padding: EdgeInsets.only(
                                      right: WebTuiSpacing.xs,
                                    ),
                                    child: Icon(
                                      WebTuiIcons.pin,
                                      size: 16,
                                      color: WebTuiColors.textSecondary,
                                    ),
                                  ),
                                WebTuiUnreadBadge(count: unreadCount),
                              ],
                            )
                          else
                            const SizedBox(
                              height: WebTuiListDensity.unreadBadgeMinSize,
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (!highlighted) return row;
    // Nền ghim thụt vào hai bên như mẫu, không kẻ đường dưới.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: WebTuiSpacing.sm),
      child: row,
    );
  }
}

/// Nhãn xám nhỏ cạnh tên hội thoại (ví dụ BOT).
class _InlineBadge extends StatelessWidget {
  const _InlineBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: WebTuiColors.backgroundMuted,
        borderRadius: BorderRadius.circular(WebTuiRadii.xs),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Text(
          label,
          style: WebTuiTypography.labelSmall.copyWith(
            color: WebTuiColors.textSecondary,
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
      color: WebTuiColors.surface,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: WebTuiListDensity.conversationItemHeight,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: WebTuiSpacing.lg),
            child: Row(
              children: [
                WebTuiAvatar(
                  label: title,
                  icon: icon,
                  color: color.withValues(alpha: 0.13),
                  foregroundColor: color,
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
                          color: WebTuiColors.textMuted,
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
                  const Icon(
                    WebTuiIcons.forward,
                    color: WebTuiColors.textMuted,
                  ),
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
        WebTuiSpacing.lg,
        WebTuiSpacing.lg,
        WebTuiSpacing.xs,
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: WebTuiTypography.labelSmall.copyWith(
          color: WebTuiColors.textMuted,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class WebTuiListSurface extends StatelessWidget {
  const WebTuiListSurface({required this.children, super.key});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: WebTuiColors.surface,
        border: Border.symmetric(
          horizontal: BorderSide(
            color: WebTuiColors.border.withValues(alpha: 0.7),
          ),
        ),
      ),
      child: Column(
        children: [
          for (var index = 0; index < children.length; index++) ...[
            children[index],
            if (index != children.length - 1)
              const Divider(indent: 72, endIndent: WebTuiSpacing.lg),
          ],
        ],
      ),
    );
  }
}

class WebTuiSliverListSurface extends StatelessWidget {
  const WebTuiSliverListSurface({
    required this.itemCount,
    required this.itemBuilder,
    super.key,
  });

  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;

  @override
  Widget build(BuildContext context) {
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) => _LazySurfaceItem(
          index: index,
          itemCount: itemCount,
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
    super.key,
  });

  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final double estimatedItemExtent;
  final double maxHeight;

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
    required this.child,
  });

  final int index;
  final int itemCount;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final border = BorderSide(
      color: WebTuiColors.border.withValues(alpha: 0.7),
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: WebTuiColors.surface,
        border: Border(
          top: index == 0 ? border : BorderSide.none,
          bottom: index == itemCount - 1 ? border : BorderSide.none,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          child,
          if (index != itemCount - 1)
            const Divider(indent: 72, endIndent: WebTuiSpacing.lg),
        ],
      ),
    );
  }
}
