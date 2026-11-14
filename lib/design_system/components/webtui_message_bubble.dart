import 'package:flutter/material.dart';

import '../icons/webtui_icons.dart';
import '../tokens/webtui_colors.dart';
import '../tokens/webtui_spacing.dart';
import '../tokens/webtui_typography.dart';

class WebTuiMessageBubble extends StatelessWidget {
  const WebTuiMessageBubble({
    required this.text,
    required this.timeLabel,
    this.outgoing = false,
    this.statusLabel,
    this.reactions = const [],
    this.textSpan,
    this.showFooter = true,
    super.key,
  });

  final String text;
  final String timeLabel;
  final bool outgoing;
  final String? statusLabel;
  final List<String> reactions;
  final InlineSpan? textSpan;

  /// `false`: bong bóng chỉ có chữ; giờ và trạng thái do nơi gọi hiện ở dòng
  /// riêng dưới nhóm tin (phòng chat).
  final bool showFooter;

  TextStyle get _bodyStyle => WebTuiTypography.bodyMedium.copyWith(
    fontSize: 16,
    color: outgoing ? WebTuiColors.textOnPrimary : WebTuiColors.textPrimary,
    fontWeight: FontWeight.w400,
    height: 1.35,
  );

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final widthFactor = constraints.maxWidth >= 700 ? 0.58 : 0.78;
        final maxWidth = (constraints.maxWidth * widthFactor)
            .clamp(64.0, 560.0)
            .toDouble();

        return Align(
          alignment: outgoing ? Alignment.centerRight : Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: outgoing
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: outgoing
                        ? WebTuiColors.primary
                        : WebTuiColors.messageIncoming,
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: outgoing
                        ? null
                        : const [
                            BoxShadow(
                              color: Color(0x14172033),
                              blurRadius: 6,
                              offset: Offset(0, 1),
                            ),
                          ],
                  ),
                  child: Padding(
                    padding: showFooter
                        ? const EdgeInsets.fromLTRB(14, 9, 14, 7)
                        : const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        textSpan == null
                            ? Text(text, style: _bodyStyle)
                            : RichText(text: textSpan!),
                        if (showFooter) ...[
                          const SizedBox(height: WebTuiSpacing.xs),
                          Semantics(
                            label: statusLabel == null
                                ? timeLabel
                                : '$timeLabel, $statusLabel',
                            child: Text(
                              timeLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: WebTuiTypography.labelSmall.copyWith(
                                color: outgoing
                                    ? WebTuiColors.textOnPrimary.withValues(
                                        alpha: 0.78,
                                      )
                                    : WebTuiColors.textMuted,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                if (reactions.isNotEmpty) ...[
                  const SizedBox(height: WebTuiSpacing.xs),
                  Wrap(
                    spacing: WebTuiSpacing.xs,
                    runSpacing: WebTuiSpacing.xs,
                    children: [
                      for (final reaction in reactions)
                        _ReactionChip(label: reaction),
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ReactionChip extends StatelessWidget {
  const _ReactionChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    const likeEmoji = '\u{1F44D}';
    final trimmedLabel = label.trim();
    final isLike = trimmedLabel.startsWith(likeEmoji);
    final count = isLike
        ? trimmedLabel.substring(likeEmoji.length).trim()
        : trimmedLabel;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: WebTuiColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: WebTuiColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: WebTuiSpacing.sm,
          vertical: WebTuiSpacing.xs,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isLike)
              const Icon(
                WebTuiIcons.check,
                size: 13,
                color: WebTuiColors.primary,
              )
            else
              Text(
                count,
                style: WebTuiTypography.labelSmall.copyWith(
                  color: WebTuiColors.textSecondary,
                ),
              ),
            if (isLike && count.isNotEmpty) ...[
              const SizedBox(width: WebTuiSpacing.xs),
              Text(
                count,
                style: WebTuiTypography.labelSmall.copyWith(
                  color: WebTuiColors.textSecondary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
