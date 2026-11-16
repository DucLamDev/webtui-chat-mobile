import 'package:flutter/material.dart';
import 'package:webtui_chat/l10n/app_strings.dart';

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
    this.background,
    this.foreground,
    this.size = 52,
    this.iconSize,
    this.radius = 16,
    super.key,
  });

  final IconData icon;
  final Color? background;
  final Color? foreground;
  final double size;
  final double? iconSize;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: background ?? WebTuiColors.primarySoft,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Icon(
        icon,
        color: foreground ?? WebTuiColors.primary,
        size: iconSize ?? size * 0.5,
      ),
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
          TextButton(onPressed: onRetry, child: Text(tr('Thử lại', 'Retry'))),
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

/// Dòng liền mạch trên nền trang của tab Công việc (không thẻ, không ô nền):
/// cột đầu [leading] rộng [leadingWidth] cách mép trái 16, tiêu đề 16 + dòng
/// phụ 13,5 mờ, mũi tên bên phải. Kẻ mảnh dưới phần chữ (tràn mép phải) khi
/// [divider]; dòng cuối nhóm thì tắt.
class WorkSeamlessRow extends StatelessWidget {
  const WorkSeamlessRow({
    required this.leading,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.leadingWidth = 24,
    this.leadingStart = edge,
    this.leadingGap = gap,
    this.divider = true,
    this.titleDecoration,
    super.key,
  });

  /// Khoảng từ mép trái tới cột đầu và từ cột đầu tới phần chữ.
  static const double edge = 16;
  static const double gap = 14;

  final Widget leading;
  final double leadingWidth;

  /// Lề trái trước cột đầu và khoảng tới phần chữ: cột đầu là nút bấm 44 thì
  /// lùi lề (6 + 44 + 4) để biểu tượng 24 vẫn đứng đúng chỗ 16 + 24 + 14.
  final double leadingStart;
  final double leadingGap;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final bool divider;
  final TextDecoration? titleDecoration;

  @override
  Widget build(BuildContext context) {
    final sub = subtitle?.trim();
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 52),
        child: Row(
          children: [
            SizedBox(width: leadingStart),
            SizedBox(width: leadingWidth, child: leading),
            SizedBox(width: leadingGap),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: WebTuiTypography.bodyMedium.copyWith(
                                    fontSize: 16,
                                    height: 1.2,
                                    fontWeight: FontWeight.w400,
                                    color: WebTuiColors.textPrimary,
                                    decoration: titleDecoration,
                                  ),
                                ),
                                if (sub != null && sub.isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    sub,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: WebTuiTypography.bodySmall.copyWith(
                                      fontSize: 13.5,
                                      height: 1.2,
                                      color: WebTuiColors.textMuted,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          WebTuiIcons.forward,
                          size: 18,
                          color: WebTuiColors.textMuted,
                        ),
                      ],
                    ),
                  ),
                  if (divider)
                    SizedBox(
                      height: 0.5,
                      width: double.infinity,
                      child: ColoredBox(color: WebTuiColors.hairline),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Dòng gọn một câu (rỗng / đang tải) trong nhóm liền mạch, thụt như dòng.
class WorkSeamlessNote extends StatelessWidget {
  const WorkSeamlessNote({required this.message, super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Text(
        message,
        style: WebTuiTypography.bodyMedium.copyWith(
          fontSize: 15,
          color: WebTuiColors.textMuted,
        ),
      ),
    );
  }
}

/// Dòng báo lỗi gọn: câu báo + "Thử lại" trên cùng một hàng.
class WorkSeamlessError extends StatelessWidget {
  const WorkSeamlessError({
    required this.message,
    required this.onRetry,
    super.key,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 6, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              message,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: WebTuiTypography.bodySmall.copyWith(
                fontSize: 14,
                color: WebTuiColors.textSecondary,
              ),
            ),
          ),
          TextButton(
            style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
            onPressed: onRetry,
            child: Text(tr('Thử lại', 'Retry')),
          ),
        ],
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
