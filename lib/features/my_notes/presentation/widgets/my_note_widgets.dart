import 'package:flutter/material.dart';

import '../../../../design_system/components/webtui_components.dart';
import '../../../../design_system/icons/webtui_icons.dart';
import '../../../../design_system/tokens/webtui_colors.dart';
import '../../../../design_system/tokens/webtui_radii.dart';
import '../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../design_system/tokens/webtui_typography.dart';

/// Giờ địa phương dạng `dd/MM/yyyy HH:mm`.
String formatMyNoteTime(DateTime value) {
  final local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${two(local.day)}/${two(local.month)}/${local.year} '
      '${two(local.hour)}:${two(local.minute)}';
}

/// Thời gian tương đối: "Vừa xong", "5 phút trước", "Hôm qua"...; quá 7 ngày
/// thì ngày đầy đủ `dd/MM/yyyy`.
String formatMyNoteRelativeTime(DateTime value, {DateTime? now}) {
  final current = (now ?? DateTime.now()).toLocal();
  final local = value.toLocal();
  final diff = current.difference(local);
  if (diff.isNegative || diff.inMinutes < 1) return 'Vừa xong';
  if (diff.inMinutes < 60) return '${diff.inMinutes} phút trước';
  final today = DateTime(current.year, current.month, current.day);
  final day = DateTime(local.year, local.month, local.day);
  final days = today.difference(day).inDays;
  if (days == 0) return '${diff.inHours} giờ trước';
  if (days == 1) return 'Hôm qua';
  if (days < 7) return '$days ngày trước';
  String two(int number) => number.toString().padLeft(2, '0');
  return '${two(local.day)}/${two(local.month)}/${local.year}';
}

/// Dải báo đang xem bản lưu trên máy (mất mạng).
class MyNotesOfflineBanner extends StatelessWidget {
  const MyNotesOfflineBanner({this.cachedAt, super.key});

  final DateTime? cachedAt;

  @override
  Widget build(BuildContext context) {
    final saved = cachedAt == null
        ? ''
        : ' (lưu lúc ${formatMyNoteTime(cachedAt!)})';
    return MyNotesNotice(
      key: const Key('my_notes_offline_banner'),
      icon: Icons.cloud_off_rounded,
      color: WebTuiColors.accentAmber,
      message:
          'Đang xem bản lưu ngoại tuyến$saved. Kết nối lại để sửa hoặc tạo '
          'ghi chú.',
    );
  }
}

class MyNotesNotice extends StatelessWidget {
  const MyNotesNotice({
    required this.icon,
    required this.color,
    required this.message,
    this.action,
    super.key,
  });

  final IconData icon;
  final Color color;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(WebTuiSpacing.md),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(WebTuiRadii.md),
        border: Border.all(color: color.withValues(alpha: 0.7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 20, color: WebTuiColors.textPrimary),
              const SizedBox(width: WebTuiSpacing.sm),
              Expanded(
                child: Text(
                  message,
                  style: WebTuiTypography.bodySmall.copyWith(
                    color: WebTuiColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          if (action != null) ...[
            const SizedBox(height: WebTuiSpacing.xs),
            Align(alignment: Alignment.centerRight, child: action),
          ],
        ],
      ),
    );
  }
}

class MyNoteTagChip extends StatelessWidget {
  const MyNoteTagChip({required this.tag, super.key});

  final String tag;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: WebTuiSpacing.sm,
        vertical: WebTuiSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: WebTuiColors.primarySoft,
        borderRadius: BorderRadius.circular(WebTuiRadii.sm),
      ),
      child: Text(
        '#$tag',
        style: WebTuiTypography.labelSmall.copyWith(
          color: WebTuiColors.primary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

Future<String?> showMyNoteTextDialog(
  BuildContext context, {
  required String title,
  required String label,
  required String confirmLabel,
  String initialValue = '',
  int maxLength = 80,
  IconData? icon,
}) {
  return showWebTuiTextInputDialog(
    context,
    title: title,
    label: label,
    confirmLabel: confirmLabel,
    initialValue: initialValue,
    maxLength: maxLength,
    icon: icon,
  );
}

Future<bool> confirmMyNoteAction(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
}) {
  return showWebTuiConfirmDialog(
    context,
    title: title,
    message: message,
    confirmLabel: confirmLabel,
    destructive: true,
    icon: WebTuiIcons.delete,
  );
}

void showMyNoteSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}
