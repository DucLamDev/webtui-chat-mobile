import 'package:flutter/material.dart';

import '../tokens/webtui_colors.dart';
import '../tokens/webtui_density.dart';
import '../tokens/webtui_radii.dart';
import '../tokens/webtui_spacing.dart';
import '../tokens/webtui_typography.dart';

class WebTuiUnreadBadge extends StatelessWidget {
  const WebTuiUnreadBadge({required this.count, super.key});

  final int count;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) {
      return const SizedBox.shrink();
    }

    final label = count > 99 ? '99+' : '$count';

    return ConstrainedBox(
      constraints: const BoxConstraints(
        minWidth: WebTuiListDensity.unreadBadgeMinSize,
        minHeight: WebTuiListDensity.unreadBadgeMinSize,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: WebTuiColors.primary,
          borderRadius: BorderRadius.circular(WebTuiRadii.lg),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: WebTuiSpacing.xs),
          // Hệ số 1: không giãn theo chiều cao / rộng chỗ chứa (vd dòng cao cố
          // định), huy hiệu luôn gọn.
          child: Center(
            widthFactor: 1,
            heightFactor: 1,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.fade,
              softWrap: false,
              style: WebTuiTypography.labelSmall.copyWith(
                color: WebTuiColors.textOnPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class WebTuiStatusPill extends StatelessWidget {
  const WebTuiStatusPill({required this.label, this.color, super.key});

  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final color = this.color ?? WebTuiColors.primary;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(WebTuiRadii.sm),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: WebTuiSpacing.sm,
          vertical: WebTuiSpacing.xs,
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: WebTuiTypography.labelSmall.copyWith(
            color: color,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
