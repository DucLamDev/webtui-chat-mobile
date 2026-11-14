import 'package:flutter/material.dart';

import '../../../../design_system/icons/webtui_icons.dart';
import '../../../../design_system/tokens/webtui_colors.dart';
import '../../../../design_system/tokens/webtui_typography.dart';

/// Thẻ trắng bo góc lớn, đổ bóng nhẹ của tab Công việc.
class WorkCard extends StatelessWidget {
  const WorkCard({
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(16),
    this.radius = 24,
    super.key,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final shape = BorderRadius.circular(radius);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: WebTuiColors.surface,
        borderRadius: shape,
        border: Border.all(color: WebTuiColors.border.withValues(alpha: 0.55)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1E3A64).withValues(alpha: 0.05),
            blurRadius: 16,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: shape,
        child: InkWell(
          onTap: onTap,
          borderRadius: shape,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// Ô vuông bo góc chứa biểu tượng (nền nhạt, biểu tượng đậm màu).
class WorkIconBox extends StatelessWidget {
  const WorkIconBox({
    required this.icon,
    this.background = WebTuiColors.primarySoft,
    this.foreground = WebTuiColors.primary,
    this.size = 52,
    this.iconSize,
    this.radius = 16,
    super.key,
  });

  final IconData icon;
  final Color background;
  final Color foreground;
  final double size;
  final double? iconSize;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Icon(icon, color: foreground, size: iconSize ?? size * 0.5),
    );
  }
}

/// Khung xám giữ chỗ khi đang tải.
class WorkSkeleton extends StatelessWidget {
  const WorkSkeleton({
    this.height = 16,
    this.width,
    this.radius = 8,
    super.key,
  });

  final double height;
  final double? width;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      width: width,
      decoration: BoxDecoration(
        color: WebTuiColors.backgroundMuted,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

/// Dòng báo lỗi kèm nút "Thử lại".
class WorkErrorBox extends StatelessWidget {
  const WorkErrorBox({required this.message, required this.onRetry, super.key});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            message,
            textAlign: TextAlign.center,
            style: WebTuiTypography.bodySmall.copyWith(
              color: WebTuiColors.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          TextButton(onPressed: onRetry, child: const Text('Thử lại')),
        ],
      ),
    );
  }
}

/// Trạng thái rỗng gọn (biểu tượng + một dòng chữ) dùng trong màn con.
class WorkEmptyBox extends StatelessWidget {
  const WorkEmptyBox({
    required this.message,
    this.icon = WebTuiIcons.tasks,
    super.key,
  });

  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            WorkIconBox(icon: icon),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: WebTuiTypography.bodyMedium.copyWith(
                color: WebTuiColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Ngày hạn dạng dd/MM.
String workShortDate(DateTime value) {
  final local = value.toLocal();
  return '${local.day.toString().padLeft(2, '0')}/'
      '${local.month.toString().padLeft(2, '0')}';
}
