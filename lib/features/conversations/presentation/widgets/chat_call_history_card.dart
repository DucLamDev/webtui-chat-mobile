import 'package:flutter/material.dart';

import '../../../../design_system/icons/webtui_icons.dart';
import '../../../../design_system/tokens/webtui_colors.dart';
import '../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../design_system/tokens/webtui_typography.dart';
import '../../../../l10n/app_strings.dart';

const callCardMissedColor = Color(0xFFE5322D);
Color get callCardIncomingColor => WebTuiColors.accentGreen;
Color get callCardOutgoingColor => WebTuiColors.primary;

/// Thẻ lịch sử cuộc gọi trong phòng chat.
///
/// Trái: ô tròn nền nhạt + MỘT biểu tượng theo hướng gọi (đến xanh lá, đi xanh
/// dương, nhỡ đỏ; video dùng biểu tượng camera). Giữa: dòng đậm "Cuộc gọi thoại
/// đến", dòng xám thời lượng / "Không trả lời" kèm giờ. Phải: nút chữ "Gọi lại"
/// (cuộc gọi video thì gọi lại bằng video).
class ChatCallHistoryCard extends StatelessWidget {
  const ChatCallHistoryCard({
    required this.missed,
    required this.video,
    required this.outgoing,
    required this.durationSeconds,
    required this.timeLabel,
    required this.onRetry,
    super.key,
  });

  final bool missed;
  final bool video;
  final bool outgoing;
  final int durationSeconds;
  final String timeLabel;
  final VoidCallback onRetry;

  static String titleFor({
    required bool missed,
    required bool video,
    required bool outgoing,
  }) {
    if (missed) return tr('Cuộc gọi nhỡ', 'Missed call');
    if (video) {
      return outgoing
          ? tr('Cuộc gọi video đi', 'Outgoing video call')
          : tr('Cuộc gọi video đến', 'Incoming video call');
    }
    return outgoing
        ? tr('Cuộc gọi thoại đi', 'Outgoing voice call')
        : tr('Cuộc gọi thoại đến', 'Incoming voice call');
  }

  static String durationLabel(int durationSeconds) {
    final safe = durationSeconds < 0 ? 0 : durationSeconds;
    final minutes = safe ~/ 60;
    final seconds = safe % 60;
    if (minutes == 0) return tr('$seconds giây', '$seconds sec');
    return tr('$minutes phút $seconds giây', '$minutes min $seconds sec');
  }

  @override
  Widget build(BuildContext context) {
    final tone = missed
        ? callCardMissedColor
        : outgoing
        ? callCardOutgoingColor
        : callCardIncomingColor;
    final icon = missed
        ? (video ? WebTuiIcons.videoOff : WebTuiIcons.phoneMissed)
        : video
        ? WebTuiIcons.video
        : outgoing
        ? WebTuiIcons.phoneOutgoing
        : WebTuiIcons.phoneIncoming;
    final title = titleFor(missed: missed, video: video, outgoing: outgoing);
    final detail = missed
        ? tr('Không trả lời', 'No answer')
        : durationLabel(durationSeconds);

    return LayoutBuilder(
      builder: (context, constraints) {
        // Cùng bề ngang tối đa với bong bóng tin nhắn.
        final factor = constraints.maxWidth >= 700 ? 0.58 : 0.78;
        final maxWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth * factor
            : 320.0;
        return Align(
          alignment: outgoing ? Alignment.centerRight : Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: DecoratedBox(
              key: const Key('chat_call_history_card'),
              decoration: BoxDecoration(
                color: outgoing
                    ? WebTuiColors.messageOutgoing
                    : WebTuiColors.messageIncoming,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: outgoing
                      ? WebTuiColors.messageOutgoingBorder
                      : WebTuiColors.border,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DecoratedBox(
                      key: const Key('chat_call_history_badge'),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: tone.withValues(alpha: 0.14),
                      ),
                      child: SizedBox.square(
                        dimension: 40,
                        child: Icon(icon, size: 20, color: tone),
                      ),
                    ),
                    const SizedBox(width: WebTuiSpacing.md),
                    Flexible(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: WebTuiTypography.bodyMedium.copyWith(
                              color: missed
                                  ? callCardMissedColor
                                  : WebTuiColors.textPrimary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '$detail · $timeLabel',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: WebTuiTypography.labelSmall.copyWith(
                              color: WebTuiColors.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: WebTuiSpacing.sm),
                    Semantics(
                      button: true,
                      label: video
                          ? tr('Gọi lại bằng video', 'Call back by video')
                          : tr('Gọi lại', 'Call back'),
                      excludeSemantics: true,
                      child: InkWell(
                        key: const Key('chat_call_history_retry'),
                        borderRadius: BorderRadius.circular(22),
                        onTap: onRetry,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            minWidth: 56,
                            minHeight: 44,
                          ),
                          child: Center(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: WebTuiColors.primarySoft,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                child: Text(
                                  tr('Gọi lại', 'Call back'),
                                  maxLines: 1,
                                  style: WebTuiTypography.labelSmall.copyWith(
                                    color: WebTuiColors.primary,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
