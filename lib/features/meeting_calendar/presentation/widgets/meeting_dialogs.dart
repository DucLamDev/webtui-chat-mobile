import 'package:flutter/material.dart';

import '../../../../design_system/tokens/webtui_colors.dart';
import '../../../../design_system/tokens/webtui_typography.dart';
import '../../../../l10n/app_strings.dart';
import '../../domain/entities/calendar_meeting.dart';
import 'meeting_widgets.dart';

/// Hỏi "Chỉ buổi này / Cả chuỗi" cho buổi họp lặp lại. `null`: người dùng đóng.
Future<MeetingScope?> askMeetingScope(
  BuildContext context, {
  required String title,
}) {
  return showDialog<MeetingScope>(
    context: context,
    builder: (dialogContext) => SimpleDialog(
      title: Text(title),
      children: [
        _ScopeOption(
          key: const Key('meeting_scope_this'),
          label: tr('Chỉ buổi này', 'This meeting only'),
          onTap: () => Navigator.of(dialogContext).pop(MeetingScope.occurrence),
        ),
        _ScopeOption(
          key: const Key('meeting_scope_series'),
          label: tr(
            'Cả chuỗi (từ buổi này trở đi)',
            'This and following meetings',
          ),
          onTap: () => Navigator.of(dialogContext).pop(MeetingScope.series),
        ),
        _ScopeOption(
          label: tr('Thôi', 'Cancel'),
          onTap: () => Navigator.of(dialogContext).pop(),
        ),
      ],
    ),
  );
}

class _ScopeOption extends StatelessWidget {
  const _ScopeOption({required this.label, required this.onTap, super.key});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SimpleDialogOption(
      onPressed: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: meetingMinTapSize - 16),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            label,
            style: WebTuiTypography.bodyMedium.copyWith(
              color: WebTuiColors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}

/// Hỏi xác nhận (Huỷ họp, Gửi biên bản…).
Future<bool> confirmMeetingAction(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  bool destructive = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(tr('Thôi', 'Cancel')),
        ),
        TextButton(
          key: const Key('meeting_confirm'),
          style: TextButton.styleFrom(
            foregroundColor: destructive
                ? MeetingTones.dangerText
                : MeetingTones.accentText,
          ),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}
