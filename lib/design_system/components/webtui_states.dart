import 'package:flutter/material.dart';

import '../tokens/webtui_colors.dart';
import '../tokens/webtui_radii.dart';
import '../tokens/webtui_spacing.dart';
import '../tokens/webtui_typography.dart';

class WebTuiEmptyState extends StatelessWidget {
  const WebTuiEmptyState({
    required this.title,
    required this.message,
    this.icon = Icons.inbox_outlined,
    super.key,
  });

  final String title;
  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return _StateFrame(
      icon: icon,
      title: title,
      message: message,
      color: WebTuiColors.primary,
    );
  }
}

class WebTuiLoadingState extends StatelessWidget {
  const WebTuiLoadingState({this.message = 'Đang tải dữ liệu...', super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 92,
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2.2),
            ),
            const SizedBox(width: WebTuiSpacing.md),
            Flexible(
              child: Text(
                message,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: WebTuiTypography.bodySmall.copyWith(
                  color: WebTuiColors.textMuted,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class WebTuiErrorState extends StatelessWidget {
  const WebTuiErrorState({
    required this.title,
    required this.message,
    this.onRetry,
    super.key,
  });

  final String title;
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return _StateFrame(
      icon: Icons.wifi_off_rounded,
      title: title,
      message: message,
      color: WebTuiColors.danger,
      action: onRetry == null
          ? null
          : TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Thử lại'),
            ),
    );
  }
}

class _StateFrame extends StatelessWidget {
  const _StateFrame({
    required this.icon,
    required this.title,
    required this.message,
    required this.color,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Color color;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(WebTuiSpacing.lg),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: WebTuiColors.surfaceElevated,
          borderRadius: BorderRadius.circular(WebTuiRadii.md),
          border: Border.all(color: WebTuiColors.border.withValues(alpha: 0.8)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(WebTuiSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 28),
              const SizedBox(height: WebTuiSpacing.sm),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: WebTuiTypography.bodyMedium.copyWith(
                  color: WebTuiColors.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: WebTuiSpacing.xs),
              Text(
                message,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: WebTuiTypography.bodySmall.copyWith(
                  color: WebTuiColors.textMuted,
                ),
              ),
              if (action != null) ...[
                const SizedBox(height: WebTuiSpacing.sm),
                action!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}
