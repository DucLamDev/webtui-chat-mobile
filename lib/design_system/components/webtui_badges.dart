import 'package:flutter/material.dart';

import '../tokens/webtui_colors.dart';
import '../tokens/webtui_density.dart';
import '../tokens/webtui_radii.dart';
import '../tokens/webtui_spacing.dart';
import '../tokens/webtui_typography.dart';

/// Trần số trên huy hiệu chưa đọc: chat 1-1 / bot hiện 1–5 rồi "5+", nhóm /
/// kênh hiện 1–99 rồi "99+" (cùng luật với web, model/unread-badge.ts).
const int webTuiUnreadMaxDirect = 5;
const int webTuiUnreadMaxGroup = 99;

/// Chữ trên huy hiệu chưa đọc; rỗng khi không có tin chưa đọc.
String webTuiUnreadLabel(int count, {int max = webTuiUnreadMaxGroup}) {
  if (count <= 0) return '';
  final cap = max < 1 ? 1 : max;
  return count > cap ? '$cap+' : '$count';
}

class WebTuiUnreadBadge extends StatelessWidget {
  const WebTuiUnreadBadge({
    required this.count,
    this.max = webTuiUnreadMaxGroup,
    this.muted = false,
    super.key,
  });

  final int count;

  /// Hội thoại tắt thông báo: huy hiệu xám.
  final bool muted;

  /// Quá số này thì hiện `max+` (mặc định 99; chat 1-1 dùng 5).
  final int max;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) {
      return const SizedBox.shrink();
    }

    final label = webTuiUnreadLabel(count, max: max);

    return ConstrainedBox(
      constraints: const BoxConstraints(
        minWidth: WebTuiListDensity.unreadBadgeMinSize,
        minHeight: WebTuiListDensity.unreadBadgeMinSize,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: muted
              ? (WebTuiColors.brightness == Brightness.dark
                    ? const Color(0xFF4E5A6E)
                    : WebTuiColors.textMuted)
              : WebTuiColors.primaryFill,
          borderRadius: BorderRadius.circular(WebTuiRadii.lg),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
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
                fontSize: 12,
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
