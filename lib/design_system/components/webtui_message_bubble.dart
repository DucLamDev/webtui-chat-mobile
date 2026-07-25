import 'package:flutter/material.dart';

import '../tokens/webtui_colors.dart';
import '../tokens/webtui_radii.dart';
import '../tokens/webtui_shadows.dart';
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
    super.key,
  });

  final String text;
  final String timeLabel;
  final bool outgoing;
  final String? statusLabel;
  final List<String> reactions;
  final InlineSpan? textSpan;

  TextStyle get _bodyStyle => WebTuiTypography.bodyMedium.copyWith(
    color: WebTuiColors.textPrimary,
    fontWeight: FontWeight.w500,
    height: 1.38,
  );

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final widthFactor = constraints.maxWidth >= 700 ? 0.58 : 0.68;
        final maxWidth = (constraints.maxWidth * widthFactor)
            .clamp(64.0, 520.0)
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
                        ? WebTuiColors.messageOutgoing
                        : WebTuiColors.messageIncoming,
                    border: Border.all(
                      color: outgoing
                          ? WebTuiColors.messageOutgoingBorder
                          : WebTuiColors.border.withValues(alpha: 0.58),
                    ),
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(WebTuiRadii.lg),
                      topRight: const Radius.circular(WebTuiRadii.lg),
                      bottomLeft: Radius.circular(
                        outgoing ? WebTuiRadii.lg : WebTuiRadii.xs,
                      ),
                      bottomRight: Radius.circular(
                        outgoing ? WebTuiRadii.xs : WebTuiRadii.lg,
                      ),
                    ),
                    boxShadow: outgoing ? null : WebTuiShadows.soft,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 7),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        textSpan == null
                            ? Text(text, style: _bodyStyle)
                            : RichText(text: textSpan!),
                        const SizedBox(height: WebTuiSpacing.xs),
                        Semantics(
                          label: statusLabel == null
                              ? timeLabel
                              : '$timeLabel, $statusLabel',
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                timeLabel,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: WebTuiTypography.labelSmall.copyWith(
                                  color: outgoing
                                      ? WebTuiColors.textMuted
                                      : WebTuiColors.textMuted,
                                ),
                              ),
                              if (outgoing) ...[
                                const SizedBox(width: WebTuiSpacing.xs),
                                Icon(
                                  Icons.done_all_rounded,
                                  size: 14,
                                  color: WebTuiColors.primary,
                                ),
                              ],
                            ],
                          ),
                        ),
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
                Icons.thumb_up_alt_outlined,
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
