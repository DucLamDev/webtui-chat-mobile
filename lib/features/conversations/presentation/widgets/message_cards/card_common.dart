import 'package:flutter/material.dart';

import '../../../../../design_system/tokens/webtui_colors.dart';
import '../../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../../design_system/tokens/webtui_typography.dart';
import '../../../domain/entities/message_card.dart';

/// Màu theo trạng thái thẻ (design system WebTui).
Color messageCardToneColor(MessageCardTone tone) => switch (tone) {
  MessageCardTone.success => WebTuiColors.accentGreen,
  MessageCardTone.error => WebTuiColors.danger,
  MessageCardTone.warning => WebTuiColors.accentAmber,
  MessageCardTone.pending => WebTuiColors.accentAmber,
  MessageCardTone.info => WebTuiColors.primary,
};

IconData messageCardToneIcon(MessageCardTone tone) => switch (tone) {
  MessageCardTone.success => Icons.check_circle_rounded,
  MessageCardTone.error => Icons.error_rounded,
  MessageCardTone.warning => Icons.warning_amber_rounded,
  MessageCardTone.pending => Icons.schedule_rounded,
  MessageCardTone.info => Icons.info_outline_rounded,
};

/// Nhãn mặc định khi thẻ không có `status_label` (thông tin thì không hiện nhãn).
String? messageCardDefaultStatusLabel(MessageCardTone tone) => switch (tone) {
  MessageCardTone.success => 'Thành công',
  MessageCardTone.error => 'Lỗi',
  MessageCardTone.warning => 'Cảnh báo',
  MessageCardTone.pending => 'Đang chờ',
  MessageCardTone.info => null,
};

/// `dd/MM/yyyy` theo giờ máy.
String formatCardDay(DateTime value) {
  final local = value.isUtc ? value.toLocal() : value;
  return '${local.day.toString().padLeft(2, '0')}/'
      '${local.month.toString().padLeft(2, '0')}/${local.year}';
}

/// `HH:mm dd/MM/yyyy` theo giờ máy.
String formatCardDateTime(DateTime value) {
  final local = value.toLocal();
  return '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')} ${formatCardDay(local)}';
}

/// Dòng chữ nhạt cho phần không có dữ liệu.
class MessageCardEmptyNote extends StatelessWidget {
  const MessageCardEmptyNote(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: WebTuiSpacing.xs),
      child: Text(
        text,
        style: WebTuiTypography.bodySmall.copyWith(
          color: WebTuiColors.textMuted,
          fontStyle: FontStyle.italic,
        ),
      ),
    );
  }
}

/// Tiêu đề nhỏ của một phần trong thẻ.
class MessageCardSectionTitle extends StatelessWidget {
  const MessageCardSectionTitle(this.title, {super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: WebTuiSpacing.xs),
      child: Text(
        title,
        style: WebTuiTypography.labelSmall.copyWith(
          color: WebTuiColors.textSecondary,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}
