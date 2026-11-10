import 'package:flutter/material.dart';

import '../../../../../design_system/tokens/webtui_colors.dart';
import '../../../../../design_system/tokens/webtui_radii.dart';
import '../../../../../design_system/tokens/webtui_shadows.dart';
import '../../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../../design_system/tokens/webtui_typography.dart';
import '../../../application/use_cases/message_stream_merger.dart';

/// Bong bóng tin đang chạy dần (AI / bot trả lời từng đoạn): chữ đã có và con
/// trỏ nhấp nháy ở cuối. Hệ thống bật giảm chuyển động thì con trỏ đứng yên.
class StreamingMessageBubble extends StatefulWidget {
  const StreamingMessageBubble({
    required this.text,
    required this.timeLabel,
    super.key,
  });

  final String text;
  final String timeLabel;

  @override
  State<StreamingMessageBubble> createState() => _StreamingMessageBubbleState();
}

class _StreamingMessageBubbleState extends State<StreamingMessageBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _blink = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1000),
  );
  late final Animation<double> _opacity = CurvedAnimation(
    parent: _blink,
    curve: const _BlinkCurve(),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.of(context).disableAnimations) {
      _blink
        ..stop()
        ..value = 1;
    } else if (!_blink.isAnimating) {
      _blink.repeat();
    }
  }

  @override
  void dispose() {
    _blink.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final trimmed = widget.text.trim();
    final waiting = trimmed.isEmpty || trimmed == messageStreamPlaceholder;
    final style = WebTuiTypography.bodyMedium.copyWith(
      color: WebTuiColors.textPrimary,
      fontWeight: FontWeight.w500,
      height: 1.38,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final widthFactor = constraints.maxWidth >= 700 ? 0.58 : 0.68;
        final maxWidth = (constraints.maxWidth * widthFactor)
            .clamp(64.0, 520.0)
            .toDouble();
        return Align(
          alignment: Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: WebTuiColors.messageIncoming,
                border: Border.all(
                  color: WebTuiColors.border.withValues(alpha: 0.58),
                ),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(WebTuiRadii.lg),
                  topRight: Radius.circular(WebTuiRadii.lg),
                  bottomLeft: Radius.circular(WebTuiRadii.xs),
                  bottomRight: Radius.circular(WebTuiRadii.lg),
                ),
                boxShadow: WebTuiShadows.soft,
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 7),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Semantics(
                      liveRegion: true,
                      label: waiting ? 'Đang trả lời' : null,
                      child: Text.rich(
                        TextSpan(
                          children: [
                            if (!waiting) TextSpan(text: widget.text),
                            WidgetSpan(
                              alignment: PlaceholderAlignment.middle,
                              child: ExcludeSemantics(
                                child: FadeTransition(
                                  opacity: _opacity,
                                  child: Container(
                                    key: const ValueKey('streaming-cursor'),
                                    width: 2,
                                    height: 16,
                                    margin: const EdgeInsets.only(left: 2),
                                    color: WebTuiColors.primary,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        style: style,
                      ),
                    ),
                    const SizedBox(height: WebTuiSpacing.xs),
                    Text(
                      waiting
                          ? 'Đang trả lời…'
                          : '${widget.timeLabel} · Đang trả lời…',
                      style: WebTuiTypography.labelSmall.copyWith(
                        color: WebTuiColors.textMuted,
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

/// Bật nửa đầu chu kỳ, tắt nửa sau (nhấp nháy như con trỏ gõ chữ).
final class _BlinkCurve extends Curve {
  const _BlinkCurve();

  @override
  double transformInternal(double t) => t < 0.5 ? 1 : 0;
}
