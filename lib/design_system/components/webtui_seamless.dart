import 'package:flutter/material.dart';

import '../tokens/webtui_colors.dart';
import '../tokens/webtui_spacing.dart';
import '../tokens/webtui_typography.dart';

/// Đầu màn tab kiểu iOS: tiêu đề lớn đậm bên trái, nút hành động trơn (không
/// khung) màu nhấn bên phải. Thay cho thanh tiêu đề "Tổ chức · Tab".
class WebTuiLargeTitleBar extends StatelessWidget {
  const WebTuiLargeTitleBar({
    required this.title,
    this.actions = const [],
    super.key,
  });

  final String title;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: Padding(
        padding: const EdgeInsets.only(left: WebTuiSpacing.lg, right: 6),
        child: Row(
          children: [
            Expanded(
              child: Semantics(
                header: true,
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: WebTuiTypography.titleLarge.copyWith(
                    fontSize: 31,
                    height: 1.1,
                    letterSpacing: -0.6,
                    fontWeight: FontWeight.w700,
                    color: WebTuiColors.textPrimary,
                  ),
                ),
              ),
            ),
            ...actions,
          ],
        ),
      ),
    );
  }
}

/// Nút biểu tượng trên đầu màn: biểu tượng 26px màu nhấn, không nền / khung,
/// vùng bấm 44 × 44. [badge] > 0 thì có số đỏ ở góc (vd thông báo chưa đọc).
class WebTuiHeaderIconButton extends StatelessWidget {
  const WebTuiHeaderIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.badge = 0,
    super.key,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final int badge;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
      padding: EdgeInsets.zero,
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          Icon(icon, size: 26, color: WebTuiColors.primary),
          if (badge > 0)
            Positioned(
              right: -6,
              top: -4,
              child: Container(
                constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                padding: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  color: WebTuiColors.badge,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: WebTuiColors.page, width: 1.5),
                ),
                child: Center(
                  widthFactor: 1,
                  heightFactor: 1,
                  child: Text(
                    badge > 99 ? '99+' : '$badge',
                    style: const TextStyle(
                      fontSize: 10,
                      height: 1.1,
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Nút chữ trên đầu màn (vd "Sửa hồ sơ"): chữ màu nhấn, vùng bấm 44.
class WebTuiHeaderTextButton extends StatelessWidget {
  const WebTuiHeaderTextButton({
    required this.label,
    required this.onPressed,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        minimumSize: const Size(44, 44),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        foregroundColor: WebTuiColors.primary,
        textStyle: WebTuiTypography.bodyMedium.copyWith(
          fontSize: 16,
          fontWeight: FontWeight.w500,
        ),
      ),
      child: Text(label),
    );
  }
}

/// Dải xám 8px ngăn giữa các nhóm dòng (thay cho thẻ bo góc).
class WebTuiGroupGap extends StatelessWidget {
  const WebTuiGroupGap({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 8,
      width: double.infinity,
      child: ColoredBox(color: WebTuiColors.groupBackground),
    );
  }
}

/// Tiêu đề nhóm (18px đậm) kèm liên kết bên phải (vd "Xem tất cả").
class WebTuiGroupHeader extends StatelessWidget {
  const WebTuiGroupHeader({
    required this.title,
    this.actionLabel,
    this.onAction,
    this.actionKey,
    super.key,
  });

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Key? actionKey;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: WebTuiColors.page,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(WebTuiSpacing.lg, 4, 6, 0),
        child: Row(
          children: [
            Expanded(
              child: Semantics(
                header: true,
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: WebTuiTypography.titleMedium.copyWith(
                    fontSize: 18,
                    letterSpacing: -0.2,
                    fontWeight: FontWeight.w700,
                    color: WebTuiColors.textPrimary,
                  ),
                ),
              ),
            ),
            if (actionLabel != null)
              WebTuiHeaderTextButton(
                key: actionKey,
                label: actionLabel!,
                onPressed: onAction,
              )
            else
              const SizedBox(height: 44),
          ],
        ),
      ),
    );
  }
}
