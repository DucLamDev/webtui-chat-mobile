import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../../design_system/tokens/webtui_colors.dart';
import '../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../design_system/tokens/webtui_typography.dart';

/// Màn quét mã QR toàn màn hình (quét QR trong chat, quét mã đăng nhập máy
/// tính). Trả về nội dung mã qua `Navigator.pop`, đóng thì trả `null`.
class QrScannerScreen extends StatefulWidget {
  const QrScannerScreen({
    this.title = 'Quét mã QR',
    this.hint = 'Đưa mã vào khung, nội dung sẽ được chèn vào tin nhắn.',
    super.key,
  });

  final String title;
  final String hint;

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> {
  late final MobileScannerController _controller;
  bool _handled = false;

  @override
  void initState() {
    super.initState();
    _controller = MobileScannerController(
      detectionSpeed: DetectionSpeed.noDuplicates,
      facing: CameraFacing.back,
      formats: const [BarcodeFormat.qrCode],
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: ValueListenableBuilder<MobileScannerState>(
        valueListenable: _controller,
        // Giữ nguyên một widget camera, chỉ dựng lại lớp phủ khi trạng thái
        // đèn / lỗi đổi.
        child: MobileScanner(
          controller: _controller,
          fit: BoxFit.cover,
          onDetect: _handleCapture,
          errorBuilder: (_, _) => const ColoredBox(color: Colors.black),
        ),
        builder: (context, state, preview) => QrScannerLayout(
          preview: preview!,
          title: widget.title,
          hint: widget.hint,
          torchState: state.torchState,
          errorMessage: state.error == null
              ? null
              : qrScannerErrorMessage(state.error!.errorCode),
          onClose: () => Navigator.of(context).pop(),
          onToggleTorch: () => unawaited(_controller.toggleTorch()),
          onRetry: _retry,
        ),
      ),
    );
  }

  Future<void> _retry() async {
    try {
      await _controller.start();
    } on MobileScannerException {
      // Lỗi đã nằm trong trạng thái của controller, lớp phủ tự hiện lại.
    }
  }

  void _handleCapture(BarcodeCapture capture) {
    if (_handled) {
      return;
    }
    for (final barcode in capture.barcodes) {
      final value = (barcode.rawValue ?? barcode.displayValue)?.trim();
      if (value == null || value.isEmpty) {
        continue;
      }
      _handled = true;
      unawaited(HapticFeedback.mediumImpact());
      Navigator.of(context).pop(value);
      return;
    }
  }
}

/// Lời báo lỗi camera cho người dùng.
String qrScannerErrorMessage(MobileScannerErrorCode code) {
  return switch (code) {
    MobileScannerErrorCode.permissionDenied =>
      'Ứng dụng chưa được phép dùng camera. Hãy bật quyền Camera cho ứng '
          'dụng trong Cài đặt của điện thoại rồi thử lại.',
    MobileScannerErrorCode.unsupported =>
      'Thiết bị này không hỗ trợ quét mã bằng camera.',
    _ =>
      'Camera đang bận hoặc gặp lỗi. Hãy đóng các ứng dụng đang dùng '
          'camera rồi thử lại.',
  };
}

/// Chiều cao thanh tiêu đề (nút đóng + tên màn) dưới tai thỏ.
const double _topBarHeight = 64;

/// Khoảng dành cho dòng hướng dẫn ngay dưới khung.
const double _hintSpace = 76;

/// Khoảng dành cho nút đèn pin ở đáy (chưa tính vùng an toàn).
const double _bottomBarHeight = 132;

/// Vị trí khung quét: vuông, rộng ~72% màn (tối đa 320), nằm giữa phần màn
/// còn trống giữa thanh tiêu đề và dòng hướng dẫn + nút đèn.
Rect qrScanFrameRect(Size size, EdgeInsets padding) {
  final top = padding.top + _topBarHeight;
  final bottom = size.height - padding.bottom - _bottomBarHeight - _hintSpace;
  final available = math.max(0.0, bottom - top);
  final side = math.max(
    120.0,
    math.min(math.min(size.width * 0.72, 320.0), available - 24),
  );
  final centerY = available >= side ? top + available / 2 : top + side / 2;
  return Rect.fromCenter(
    center: Offset(size.width / 2, centerY),
    width: side,
    height: side,
  );
}

/// Lớp giao diện của màn quét, tách khỏi camera để test được bố cục.
class QrScannerLayout extends StatefulWidget {
  const QrScannerLayout({
    required this.preview,
    required this.title,
    required this.hint,
    required this.torchState,
    required this.onClose,
    required this.onToggleTorch,
    required this.onRetry,
    this.errorMessage,
    super.key,
  });

  final Widget preview;
  final String title;
  final String hint;
  final TorchState torchState;
  final VoidCallback onClose;
  final VoidCallback onToggleTorch;
  final VoidCallback onRetry;

  /// Khác `null` thì camera không mở được: hiện thông báo thay cho khung.
  final String? errorMessage;

  @override
  State<QrScannerLayout> createState() => _QrScannerLayoutState();
}

class _QrScannerLayoutState extends State<QrScannerLayout>
    with SingleTickerProviderStateMixin {
  late final AnimationController _sweep = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    if (reduceMotion) {
      _sweep.stop();
    } else if (!_sweep.isAnimating) {
      _sweep.repeat();
    }
  }

  @override
  void dispose() {
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final reduceMotion = media.disableAnimations;
    final error = widget.errorMessage;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      // StackFit.expand: phần thân Scaffold chỉ cho ràng buộc lỏng, thiếu nó
      // thì Stack co về chiều cao thanh tiêu đề và camera chỉ chiếm một dải
      // nhỏ ở đỉnh màn hình.
      child: Stack(
        fit: StackFit.expand,
        children: [
          widget.preview,
          LayoutBuilder(
            builder: (context, constraints) {
              if (error != null) {
                return _CameraErrorView(
                  message: error,
                  onRetry: widget.onRetry,
                );
              }
              final frame = qrScanFrameRect(constraints.biggest, media.padding);
              return Stack(
                fit: StackFit.expand,
                children: [
                  IgnorePointer(
                    child: CustomPaint(
                      painter: _QrScannerOverlayPainter(frame: frame),
                    ),
                  ),
                  Positioned.fromRect(
                    rect: frame,
                    child: const IgnorePointer(
                      child: SizedBox.expand(key: Key('qr_scanner_frame')),
                    ),
                  ),
                  if (!reduceMotion)
                    IgnorePointer(
                      key: const Key('qr_scanner_sweep'),
                      child: AnimatedBuilder(
                        animation: _sweep,
                        builder: (context, child) {
                          final t = Curves.easeInOut.transform(
                            _sweep.value < 0.5
                                ? _sweep.value * 2
                                : (1 - _sweep.value) * 2,
                          );
                          final inset = frame.width * 0.08;
                          return Stack(
                            children: [
                              Positioned(
                                left: frame.left + inset,
                                width: frame.width - inset * 2,
                                top:
                                    frame.top +
                                    inset +
                                    t * (frame.height - inset * 2),
                                height: 2,
                                child: child!,
                              ),
                            ],
                          );
                        },
                        child: const _ScanLine(),
                      ),
                    ),
                  Positioned(
                    top: frame.bottom + WebTuiSpacing.xl,
                    left: WebTuiSpacing.xxl,
                    right: WebTuiSpacing.xxl,
                    child: Text(
                      widget.hint,
                      key: const Key('qr_scanner_hint'),
                      textAlign: TextAlign.center,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: WebTuiTypography.bodyMedium.copyWith(
                        color: Colors.white,
                        fontSize: 15,
                        height: 1.4,
                        shadows: const [
                          Shadow(color: Colors.black54, blurRadius: 8),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: media.padding.bottom + WebTuiSpacing.xxl + 4,
                    child: Center(
                      child: _TorchButton(
                        state: widget.torchState,
                        onPressed: widget.onToggleTorch,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
          _TopBar(title: widget.title, onClose: widget.onClose),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.title, required this.onClose});

  final String title;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: _topBarHeight,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: WebTuiSpacing.md),
            child: Row(
              children: [
                IconButton(
                  key: const Key('qr_scanner_close'),
                  tooltip: 'Đóng',
                  onPressed: onClose,
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.black.withValues(alpha: 0.38),
                    foregroundColor: Colors.white,
                    fixedSize: const Size.square(44),
                  ),
                  icon: const Icon(Icons.close_rounded, size: 24),
                ),
                Expanded(
                  child: Text(
                    title,
                    key: const Key('qr_scanner_title'),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: WebTuiTypography.titleMedium.copyWith(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      shadows: const [
                        Shadow(color: Colors.black54, blurRadius: 8),
                      ],
                    ),
                  ),
                ),
                // Cân với nút đóng để tiêu đề nằm đúng giữa.
                const SizedBox(width: 44),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ScanLine extends StatelessWidget {
  const _ScanLine();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(2),
        gradient: LinearGradient(
          colors: [
            WebTuiColors.chatHeader.withValues(alpha: 0),
            WebTuiColors.chatHeader,
            WebTuiColors.chatHeader.withValues(alpha: 0),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: WebTuiColors.chatHeader.withValues(alpha: 0.55),
            blurRadius: 12,
            spreadRadius: 1,
          ),
        ],
      ),
    );
  }
}

class _TorchButton extends StatelessWidget {
  const _TorchButton({required this.state, required this.onPressed});

  final TorchState state;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final available = state != TorchState.unavailable;
    final on = state == TorchState.on;
    return Opacity(
      opacity: available ? 1 : 0.45,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            key: const Key('qr_scanner_torch'),
            tooltip: on ? 'Tắt đèn pin' : 'Bật đèn pin',
            onPressed: available ? onPressed : null,
            style: IconButton.styleFrom(
              backgroundColor: on
                  ? Colors.white
                  : Colors.white.withValues(alpha: 0.18),
              disabledBackgroundColor: Colors.white.withValues(alpha: 0.18),
              foregroundColor: on ? WebTuiColors.textPrimary : Colors.white,
              disabledForegroundColor: Colors.white,
              fixedSize: const Size.square(56),
              side: BorderSide(
                color: Colors.white.withValues(alpha: on ? 0 : 0.28),
              ),
            ),
            // Nền trắng = đèn đang bật (giống nút đèn ở Trung tâm điều khiển).
            icon: const Icon(Icons.flashlight_on_rounded, size: 26),
          ),
          const SizedBox(height: WebTuiSpacing.sm),
          Text(
            on ? 'Tắt đèn' : 'Đèn pin',
            style: WebTuiTypography.bodySmall.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _CameraErrorView extends StatelessWidget {
  const _CameraErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              WebTuiSpacing.xxl,
              _topBarHeight,
              WebTuiSpacing.xxl,
              WebTuiSpacing.xxl,
            ),
            child: Column(
              key: const Key('qr_scanner_error'),
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.no_photography_outlined,
                    color: Colors.white,
                    size: 34,
                  ),
                ),
                const SizedBox(height: WebTuiSpacing.lg),
                Text(
                  'Không mở được camera',
                  textAlign: TextAlign.center,
                  style: WebTuiTypography.titleMedium.copyWith(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: WebTuiSpacing.sm),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: WebTuiTypography.bodyMedium.copyWith(
                    color: Colors.white70,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: WebTuiSpacing.xxl),
                FilledButton(
                  key: const Key('qr_scanner_retry'),
                  onPressed: onRetry,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(160, 48),
                  ),
                  child: const Text('Thử lại'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Làm tối phần ngoài khung và vẽ 4 góc trắng bo tròn của khung quét.
class _QrScannerOverlayPainter extends CustomPainter {
  _QrScannerOverlayPainter({required this.frame});

  final Rect frame;

  static const double _radius = 22;

  @override
  void paint(Canvas canvas, Size size) {
    final cutout = RRect.fromRectAndRadius(
      frame,
      const Radius.circular(_radius),
    );
    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(Offset.zero & size),
        Path()..addRRect(cutout),
      ),
      Paint()..color = Colors.black.withValues(alpha: 0.58),
    );

    // Viền mảnh cả khung để mắt thấy rõ vùng quét.
    canvas.drawRRect(
      cutout,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.22)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    final corner = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    final arm = math.min(44.0, frame.width * 0.18);
    const r = _radius;
    final l = frame.left, t = frame.top, rt = frame.right, b = frame.bottom;

    // Mỗi góc: đoạn thẳng → cung bo → đoạn thẳng.
    canvas.drawPath(
      Path()
        ..moveTo(l, t + arm)
        ..lineTo(l, t + r)
        ..arcToPoint(Offset(l + r, t), radius: const Radius.circular(r))
        ..lineTo(l + arm, t),
      corner,
    );
    canvas.drawPath(
      Path()
        ..moveTo(rt - arm, t)
        ..lineTo(rt - r, t)
        ..arcToPoint(Offset(rt, t + r), radius: const Radius.circular(r))
        ..lineTo(rt, t + arm),
      corner,
    );
    canvas.drawPath(
      Path()
        ..moveTo(rt, b - arm)
        ..lineTo(rt, b - r)
        ..arcToPoint(Offset(rt - r, b), radius: const Radius.circular(r))
        ..lineTo(rt - arm, b),
      corner,
    );
    canvas.drawPath(
      Path()
        ..moveTo(l + arm, b)
        ..lineTo(l + r, b)
        ..arcToPoint(Offset(l, b - r), radius: const Radius.circular(r))
        ..lineTo(l, b - arm),
      corner,
    );
  }

  @override
  bool shouldRepaint(covariant _QrScannerOverlayPainter oldDelegate) =>
      oldDelegate.frame != frame;
}
