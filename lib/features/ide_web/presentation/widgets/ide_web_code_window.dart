import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../design_system/tokens/webtui_colors.dart';

/// Màu của cửa sổ mã: luôn tối ở cả nền sáng và nền tối (như màn Terminal).
abstract final class IdeWebInk {
  static const window = Color(0xFF1A2233);
  static const windowBar = Color(0xFF222C40);
  static const line = Color(0xFF2D3950);
  static const gutter = Color(0xFF4A5975);
  static const sky = Color(0xFF6CB6FF);
  static const mint = Color(0xFF74DDB3);
  static const sand = Color(0xFFF0C674);
  static const lilac = Color(0xFFB9A7FF);
  static const slate = Color(0xFF64748F);

  // Nền của huy hiệu và nút nguy hiểm: đủ tương phản với chữ / biểu tượng trắng
  // ở cả hai nền.
  static const alertRed = Color(0xFFC8372D);
  static const alertAmber = Color(0xFFB0721A);
}

/// Dấu hiệu VPSTTT IDE: ô vuông tối với dấu nhắc lệnh.
class IdeWebMark extends StatelessWidget {
  const IdeWebMark({this.size = 32, super.key});

  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: IdeWebInk.window,
      borderRadius: BorderRadius.circular(size * 0.28),
      border: Border.all(color: IdeWebInk.line),
    ),
    child: CustomPaint(painter: _PromptPainter(size)),
  );
}

class _PromptPainter extends CustomPainter {
  const _PromptPainter(this.size);

  final double size;

  @override
  void paint(Canvas canvas, Size area) {
    final stroke = Paint()
      ..color = IdeWebInk.mint
      ..style = PaintingStyle.stroke
      ..strokeWidth = size * 0.085
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final w = area.width;
    final h = area.height;
    canvas
      ..drawPath(
        Path()
          ..moveTo(w * 0.28, h * 0.33)
          ..lineTo(w * 0.46, h * 0.5)
          ..lineTo(w * 0.28, h * 0.67),
        stroke,
      )
      ..drawLine(
        Offset(w * 0.54, h * 0.67),
        Offset(w * 0.74, h * 0.67),
        stroke..color = Colors.white,
      );
  }

  @override
  bool shouldRepaint(_PromptPainter oldDelegate) => oldDelegate.size != size;
}

enum IdeWebWindowMood {
  /// Mã đang hiện dần.
  opening,

  /// Trang đăng nhập của trình duyệt nằm đè lên cửa sổ mã.
  browser,

  /// Cửa sổ mã mờ đi (lỗi, tắt, khoá, hết hạn).
  resting,
}

/// Hình chính của các màn trạng thái: cửa sổ mã + huy hiệu trạng thái.
class IdeWebCodeWindow extends StatefulWidget {
  const IdeWebCodeWindow({
    required this.mood,
    required this.height,
    this.badge,
    this.badgeColor,
    super.key,
  });

  final IdeWebWindowMood mood;
  final double height;
  final IconData? badge;
  final Color? badgeColor;

  @override
  State<IdeWebCodeWindow> createState() => _IdeWebCodeWindowState();
}

class _IdeWebCodeWindowState extends State<IdeWebCodeWindow>
    with SingleTickerProviderStateMixin {
  late final _motion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2800),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(IdeWebCodeWindow oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    final still =
        widget.mood == IdeWebWindowMood.resting ||
        MediaQuery.disableAnimationsOf(context);
    if (still) {
      _motion
        ..stop()
        ..value = 1;
    } else if (!_motion.isAnimating) {
      _motion.repeat();
    }
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = WebTuiColors.of(context);
    final badge = widget.badge;
    return ExcludeSemantics(
      child: SizedBox(
        height: widget.height + (badge == null ? 0 : 18),
        child: Stack(
          children: [
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              height: widget.height,
              child: RepaintBoundary(
                child: AnimatedBuilder(
                  animation: _motion,
                  builder: (context, _) => CustomPaint(
                    painter: _WindowPainter(
                      progress: _motion.value,
                      mood: widget.mood,
                      pagePrimary: c.primaryFill,
                    ),
                  ),
                ),
              ),
            ),
            if (badge != null)
              Positioned(
                right: 20,
                bottom: 0,
                child: Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: widget.badgeColor ?? c.textSecondary,
                    shape: BoxShape.circle,
                    border: Border.all(color: c.background, width: 4),
                  ),
                  child: Icon(badge, size: 24, color: Colors.white),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Một đoạn mã: vị trí, bề rộng (theo phần trăm bề ngang) và màu.
typedef _Token = (double x, double width, Color color);

const _code = <List<_Token>>[
  [(0.0, 0.16, IdeWebInk.lilac), (0.19, 0.24, IdeWebInk.sky)],
  [
    (0.06, 0.12, IdeWebInk.lilac),
    (0.21, 0.18, IdeWebInk.slate),
    (0.42, 0.2, IdeWebInk.sand),
  ],
  [(0.06, 0.22, IdeWebInk.sky), (0.31, 0.3, IdeWebInk.mint)],
  [
    (0.12, 0.14, IdeWebInk.slate),
    (0.29, 0.26, IdeWebInk.sand),
    (0.58, 0.14, IdeWebInk.slate),
  ],
  [(0.12, 0.3, IdeWebInk.mint), (0.45, 0.16, IdeWebInk.sky)],
  [(0.06, 0.1, IdeWebInk.lilac), (0.19, 0.2, IdeWebInk.slate)],
  [(0.0, 0.07, IdeWebInk.slate)],
];

class _WindowPainter extends CustomPainter {
  const _WindowPainter({
    required this.progress,
    required this.mood,
    required this.pagePrimary,
  });

  final double progress;
  final IdeWebWindowMood mood;
  final Color pagePrimary;

  // Trang trình duyệt luôn sáng: nổi trên cửa sổ mã tối ở cả hai nền.
  static const page = Color(0xFFF7F9FC);
  static const pageInk = Color(0xFF475569);

  @override
  void paint(Canvas canvas, Size size) {
    final frame = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(20),
    );
    canvas
      ..drawRRect(frame, Paint()..color = IdeWebInk.window)
      ..save()
      ..clipRRect(frame);
    _bar(canvas, size);
    _lines(canvas, size);
    canvas.restore();
    if (mood == IdeWebWindowMood.browser) _browser(canvas, size);
  }

  void _bar(Canvas canvas, Size size) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, 36),
      Paint()..color = IdeWebInk.windowBar,
    );
    final dot = Paint()..color = IdeWebInk.gutter;
    for (var i = 0; i < 3; i++) {
      canvas.drawCircle(Offset(20 + i * 16, 18), 4.5, dot);
    }
    // Thẻ tệp đang mở.
    canvas
      ..drawRRect(
        RRect.fromRectAndCorners(
          const Rect.fromLTWH(84, 8, 112, 28),
          topLeft: const Radius.circular(8),
          topRight: const Radius.circular(8),
        ),
        Paint()..color = IdeWebInk.window,
      )
      ..drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(98, 19, 64, 6),
          const Radius.circular(3),
        ),
        Paint()..color = const Color(0xFF8FA0BD),
      );
  }

  void _lines(Canvas canvas, Size size) {
    const top = 54.0;
    const left = 48.0;
    final step = math.max(16.0, (size.height - top - 8) / _code.length);
    final usable = size.width - left - 24;
    final dim = mood == IdeWebWindowMood.resting;
    // Mã hiện dần trong 70% chu kỳ rồi đứng yên.
    final typed = mood == IdeWebWindowMood.opening
        ? (progress / 0.7).clamp(0.0, 1.0) * _code.length
        : _code.length.toDouble();
    Offset? caret;
    for (var row = 0; row < _code.length; row++) {
      final y = top + row * step;
      if (y > size.height - 12) break;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(20, y, 10, 5),
          const Radius.circular(2.5),
        ),
        Paint()..color = IdeWebInk.gutter.withValues(alpha: 0.55),
      );
      final shown = (typed - row).clamp(0.0, 1.0);
      if (shown <= 0) continue;
      final end = _code[row].last.$1 + _code[row].last.$2;
      for (final (x, width, color) in _code[row]) {
        final visible = math.min(width, shown * end - x);
        if (visible <= 0) continue;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(left + x * usable, y - 1, visible * usable, 7),
            const Radius.circular(3.5),
          ),
          Paint()..color = color.withValues(alpha: dim ? 0.34 : 0.95),
        );
      }
      caret = Offset(left + shown * end * usable + 6, y - 5);
    }
    final blink = progress >= 1 || (progress * 5).floor().isEven;
    if (mood == IdeWebWindowMood.opening && caret != null && blink) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(caret.dx, caret.dy, 2.5, 15),
          const Radius.circular(1.5),
        ),
        Paint()..color = Colors.white,
      );
    }
  }

  /// Trang đăng nhập của trình duyệt đè lên nửa phải cửa sổ mã.
  void _browser(Canvas canvas, Size size) {
    final w = math.min(size.width * 0.56, 210.0);
    final h = size.height - 44;
    final rect = Rect.fromLTWH(size.width - w - 18, 26, w, h);
    final card = RRect.fromRectAndRadius(rect, const Radius.circular(14));
    canvas
      ..drawRRect(
        card.shift(const Offset(0, 6)),
        Paint()
          ..color = const Color(0x66000000)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
      )
      ..drawRRect(card, Paint()..color = page);
    final soft = Paint()..color = pageInk.withValues(alpha: 0.16);
    RRect bar(double top, double height, {double inset = 16, double? width}) =>
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            rect.left + inset,
            rect.top + top,
            width ?? w - inset * 2,
            height,
          ),
          Radius.circular(math.min(height / 2, 8)),
        );
    // Thanh địa chỉ có ổ khoá.
    canvas
      ..drawRRect(bar(12, 20), soft)
      ..drawCircle(
        Offset(rect.left + 28, rect.top + 22),
        4,
        Paint()..color = IdeWebInk.mint,
      )
      ..drawRRect(
        bar(20, 4, inset: 38, width: w * 0.42),
        Paint()..color = pageInk.withValues(alpha: 0.4),
      );
    if (h > 92) canvas.drawRRect(bar(46, 18), soft);
    if (h > 122) canvas.drawRRect(bar(72, 18), soft);
    final buttonTop = h > 122 ? 100.0 : (h > 92 ? 72.0 : 44.0);
    final pulse = 0.75 + 0.25 * math.sin(progress * 2 * math.pi);
    if (h > buttonTop + 24) {
      canvas.drawRRect(
        bar(buttonTop, 20),
        Paint()..color = pagePrimary.withValues(alpha: pulse),
      );
    }
  }

  @override
  bool shouldRepaint(_WindowPainter old) =>
      old.progress != progress ||
      old.mood != mood ||
      old.pagePrimary != pagePrimary;
}
