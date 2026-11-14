import 'package:flutter/material.dart';

import '../../../../design_system/tokens/webtui_colors.dart';
import '../../../../design_system/tokens/webtui_spacing.dart';

/// Thay ô nhập tin ở chat bot thông báo: kênh chỉ để đọc.
class NoticeBotReadOnlyBar extends StatelessWidget {
  const NoticeBotReadOnlyBar({super.key});

  static const message = 'Kênh thông báo, không trả lời được';

  @override
  Widget build(BuildContext context) {
    return Material(
      color: WebTuiColors.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            WebTuiSpacing.lg,
            WebTuiSpacing.md,
            WebTuiSpacing.lg,
            WebTuiSpacing.md,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.notifications_none_rounded,
                size: 18,
                color: WebTuiColors.textMuted,
              ),
              const SizedBox(width: WebTuiSpacing.sm),
              Flexible(
                child: Text(
                  message,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: WebTuiColors.textMuted,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
