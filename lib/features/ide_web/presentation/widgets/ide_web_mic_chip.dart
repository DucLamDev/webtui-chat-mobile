import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../design_system/tokens/webtui_colors.dart';
import '../../../../design_system/tokens/webtui_typography.dart';
import '../../../../l10n/app_strings.dart';
import 'ide_web_buttons.dart';
import 'ide_web_code_window.dart';

/// Chỉ báo trang IDE đang dùng micro: sóng âm và thời gian thu.
class IdeWebMicChip extends StatefulWidget {
  const IdeWebMicChip({required this.capturing, super.key});

  final ValueListenable<bool> capturing;

  @override
  State<IdeWebMicChip> createState() => _IdeWebMicChipState();
}

class _IdeWebMicChipState extends State<IdeWebMicChip>
    with SingleTickerProviderStateMixin {
  late final _wave = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );
  Timer? _clock;
  int _seconds = 0;

  @override
  void initState() {
    super.initState();
    widget.capturing.addListener(_sync);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(IdeWebMicChip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.capturing == widget.capturing) return;
    oldWidget.capturing.removeListener(_sync);
    widget.capturing.addListener(_sync);
    _sync();
  }

  void _sync() {
    if (!mounted) return;
    if (!widget.capturing.value) {
      _clock?.cancel();
      _clock = null;
      _seconds = 0;
      _wave.stop();
    } else {
      if (MediaQuery.disableAnimationsOf(context)) {
        _wave.stop();
      } else if (!_wave.isAnimating) {
        _wave.repeat();
      }
      _clock ??= Timer.periodic(
        const Duration(seconds: 1),
        (_) => setState(() => _seconds++),
      );
    }
    setState(() {});
  }

  @override
  void dispose() {
    widget.capturing.removeListener(_sync);
    _clock?.cancel();
    _wave.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.capturing.value) return const SizedBox.shrink();
    final c = WebTuiColors.of(context);
    final ink = IdeWebInk.recording(context);
    final time =
        '${_seconds ~/ 60}:${(_seconds % 60).toString().padLeft(2, '0')}';
    return Semantics(
      container: true,
      liveRegion: true,
      label: tr('Đang thu micro', 'Microphone is recording'),
      excludeSemantics: true,
      child: Container(
        key: const Key('ide_web_mic_chip'),
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: c.danger.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(17),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 20,
              height: 16,
              child: AnimatedBuilder(
                animation: _wave,
                builder: (_, _) =>
                    CustomPaint(painter: _WavePainter(_wave.value, ink)),
              ),
            ),
            // Chữ to: chỉ giữ sóng âm để tên màn không bị cắt.
            if (!ideWebLargeText(context)) ...[
              const SizedBox(width: 8),
              Text(
                time,
                style: WebTuiTypography.bodySmall.copyWith(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  color: ink,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _WavePainter extends CustomPainter {
  const _WavePainter(this.progress, this.color);

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    const bars = 4;
    final step = size.width / bars;
    for (var i = 0; i < bars; i++) {
      final phase = progress * 2 * math.pi + i * 1.1;
      final height = size.height * (0.38 + 0.56 * math.sin(phase).abs());
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(i * step, (size.height - height) / 2, 3, height),
          const Radius.circular(1.5),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_WavePainter old) =>
      old.progress != progress || old.color != color;
}
