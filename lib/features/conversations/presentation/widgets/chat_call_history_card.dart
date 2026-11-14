import 'package:flutter/material.dart';

import '../../../../design_system/icons/webtui_icons.dart';
import '../../../../design_system/tokens/webtui_colors.dart';
import '../../../../design_system/tokens/webtui_typography.dart';

const _missedRed = Color(0xFFE5322D);
const _outgoingBackground = Color(0xFFE3F0FF);
const _outgoingBorder = Color(0xFFCFE3FA);

/// Thẻ lịch sử cuộc gọi trong phòng chat: một dòng gọn trong viên bo tròn,
/// biểu tượng điện thoại, chữ "Cuộc gọi thoại đi · 17 giây" và nút gọi lại.
/// Cuộc gọi nhỡ hiện biểu tượng + chữ đỏ.
class ChatCallHistoryCard extends StatelessWidget {
  const ChatCallHistoryCard({
    required this.label,
    required this.missed,
    required this.video,
    required this.outgoing,
    required this.onRetry,
    super.key,
  });

  /// Chữ đã ghép sẵn, ví dụ `Cuộc gọi thoại đi · 17 giây`.
  final String label;
  final bool missed;
  final bool video;
  final bool outgoing;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final tone = missed ? _missedRed : WebTuiColors.primary;
    final background = outgoing
        ? _outgoingBackground
        : WebTuiColors.messageIncoming;
    final icon = missed
        ? WebTuiIcons.phoneMissed
        : video
        ? WebTuiIcons.video
        : WebTuiIcons.phone;

    return Align(
      alignment: outgoing ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        key: const Key('chat_call_history_card'),
        padding: const EdgeInsets.fromLTRB(14, 4, 4, 4),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: outgoing
                ? _outgoingBorder
                : WebTuiColors.border.withValues(alpha: 0.6),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20, color: tone),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: WebTuiTypography.bodyMedium.copyWith(
                  color: missed ? tone : WebTuiColors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Semantics(
              button: true,
              label: 'Gọi lại',
              child: Material(
                color: outgoing
                    ? WebTuiColors.surface
                    : WebTuiColors.primarySoft,
                shape: const CircleBorder(),
                child: InkWell(
                  key: const Key('chat_call_history_retry'),
                  customBorder: const CircleBorder(),
                  onTap: onRetry,
                  child: SizedBox.square(
                    dimension: 34,
                    child: Icon(
                      video ? WebTuiIcons.video : WebTuiIcons.phone,
                      size: 18,
                      color: WebTuiColors.primary,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
