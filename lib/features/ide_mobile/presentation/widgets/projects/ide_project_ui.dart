import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../../design_system/components/webtui_components.dart';
import '../../../../../design_system/tokens/webtui_colors.dart';
import '../../../../../design_system/tokens/webtui_radii.dart';
import '../../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../../design_system/tokens/webtui_typography.dart';
import '../../../../../l10n/app_strings.dart';
import '../../../domain/ide_errors.dart';

/// Chữ lỗi cho thanh báo: ưu tiên `message` tiếng Việt của IDE.
String ideProjectErrorText(Object error) {
  if (error is IdeCancelled) {
    return tr(
      'Đã huỷ, chưa gửi gì lên máy chủ.',
      'Cancelled, nothing was sent.',
    );
  }
  if (error is IdeOffline) {
    return tr('IDE vừa mất kết nối.', 'The IDE just disconnected.');
  }
  if (error is IdeException && error.message.isNotEmpty) return error.message;
  if (error is IdeForbidden) {
    return tr(
      'Bạn không có quyền làm việc này.',
      'You are not allowed to do this.',
    );
  }
  return tr(
    'Chưa làm được, hãy thử lại.',
    'Could not do it, please try again.',
  );
}

/// Trạng thái lỗi / không quyền / không có cho một vùng đang tải.
Widget ideProjectErrorView(
  Object error, {
  required VoidCallback onRetry,
  String? title,
}) {
  if (error is IdeForbidden) {
    return WebTuiEmptyState(
      key: const Key('ide_forbidden'),
      title: tr('Không có quyền', 'No permission'),
      message: error.message.isNotEmpty
          ? error.message
          : tr(
              'Tài khoản này không được xem mục này.',
              'This account cannot view this.',
            ),
      icon: Icons.lock_outline_rounded,
    );
  }
  if (error is IdeNotFound) {
    return WebTuiEmptyState(
      key: const Key('ide_not_found'),
      title: tr('Không tìm thấy', 'Not found'),
      message: error.message.isNotEmpty
          ? error.message
          : tr('Dự án này không còn nữa.', 'This project no longer exists.'),
      icon: Icons.search_off_rounded,
    );
  }
  return WebTuiErrorState(
    title: title ?? tr('Không tải được', 'Could not load'),
    message: error is IdeException && error.message.isNotEmpty
        ? error.message
        : error is IdeOffline
        ? tr('IDE vừa mất kết nối.', 'The IDE just disconnected.')
        : tr('Hãy thử lại.', 'Please try again.'),
    onRetry: onRetry,
  );
}

void ideProjectSnack(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}

/// Chạy [action]; lỗi thì báo bằng thanh dưới và trả `null`.
Future<T?> ideProjectGuard<T>(
  BuildContext context,
  Future<T> Function() action,
) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    return await action();
  } on Object catch (e) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(ideProjectErrorText(e))));
    return null;
  }
}

/// Thời điểm giây Unix → `dd/MM HH:mm` giờ máy.
String ideFormatUnix(int seconds) {
  if (seconds <= 0) return '';
  final d = DateTime.fromMillisecondsSinceEpoch(seconds * 1000).toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.day)}/${two(d.month)} ${two(d.hour)}:${two(d.minute)}';
}

/// Nút hành động cao ≥ 44.
class IdeProjectButton extends StatelessWidget {
  const IdeProjectButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.primary = false,
    this.danger = false,
    super.key,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool primary;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final size = const Size(44, 44);
    if (primary) {
      return FilledButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        label: Text(label),
        style: FilledButton.styleFrom(
          minimumSize: size,
          backgroundColor: danger ? WebTuiColors.danger : null,
        ),
      );
    }
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        minimumSize: size,
        foregroundColor: danger ? WebTuiColors.danger : null,
      ),
    );
  }
}

/// Khối nội dung có viền, dùng chung trong các màn dự án.
class IdeProjectCard extends StatelessWidget {
  const IdeProjectCard({
    required this.child,
    this.title,
    this.trailing,
    super.key,
  });

  final String? title;
  final Widget? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        WebTuiSpacing.lg,
        0,
        WebTuiSpacing.lg,
        WebTuiSpacing.md,
      ),
      child: Material(
        color: WebTuiColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(WebTuiRadii.md),
          side: BorderSide(color: WebTuiColors.border),
        ),
        child: Padding(
          padding: const EdgeInsets.all(WebTuiSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (title != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: WebTuiSpacing.sm),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          title!,
                          style: WebTuiTypography.titleMedium.copyWith(
                            color: WebTuiColors.textPrimary,
                          ),
                        ),
                      ),
                      ?trailing,
                    ],
                  ),
                ),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

/// Khoảng chờ nhìn được: dùng khi chờ job.
class IdeProgressLine extends StatelessWidget {
  const IdeProgressLine({required this.text, super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(width: WebTuiSpacing.md),
        Expanded(
          child: Text(
            text,
            style: WebTuiTypography.bodyMedium.copyWith(
              color: WebTuiColors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}

/// Ghi lại một việc không đợi kết quả (tránh cảnh báo `unawaited`).
void ideFireAndForget(Future<void> f) => unawaited(f);
