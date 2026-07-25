import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

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
    this.unreadCount = 0,
    this.status,
    this.muted = false,
    this.selected = false,
    this.onTap,
    super.key,
  });

  final String title;
  final String preview;
  final String timeLabel;
  final String avatarLabel;
  final String? avatarUrl;
  final int unreadCount;
  final WebTuiPresenceStatus? status;
  final bool muted;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? WebTuiColors.primarySoft.withValues(alpha: 0.74)
          : WebTuiColors.surface,
      child: InkWell(
        onTap: onTap,
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
                      imageUrl: avatarUrl,
                      status: status,
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
                              fontWeight: unreadCount > 0
                                  ? FontWeight.w800
                                  : FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: WebTuiSpacing.xs),
                          Row(
                            children: [
                              if (muted) ...[
                                const Icon(
                                  CupertinoIcons.bell_slash,
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
                                  style: WebTuiTypography.bodySmall.copyWith(
                                    color: unreadCount > 0
                                        ? WebTuiColors.textSecondary
                                        : WebTuiColors.textMuted,
                                    fontWeight: unreadCount > 0
                                        ? FontWeight.w600
                                        : FontWeight.w400,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: WebTuiSpacing.sm),
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          timeLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: WebTuiTypography.labelSmall.copyWith(
                            color: unreadCount > 0
                                ? WebTuiColors.primary
                                : WebTuiColors.textMuted,
                            fontWeight: unreadCount > 0
                                ? FontWeight.w800
                                : FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: WebTuiSpacing.sm),
                        WebTuiUnreadBadge(count: unreadCount),
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
                    CupertinoIcons.chevron_right,
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
