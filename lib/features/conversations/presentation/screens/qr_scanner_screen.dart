import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../../design_system/tokens/webtui_colors.dart';
import '../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../design_system/tokens/webtui_typography.dart';

class QrScannerScreen extends StatefulWidget {
  const QrScannerScreen({super.key});

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
      body: Stack(
        children: [
          Positioned.fill(
            child: MobileScanner(
              controller: _controller,
              fit: BoxFit.cover,
              onDetect: _handleCapture,
              errorBuilder: (context, error) => _ScannerError(error: error),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(painter: _QrScannerOverlayPainter()),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(WebTuiSpacing.md),
              child: Row(
                children: [
                  IconButton.filledTonal(
                    tooltip: 'Đóng',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                  const Spacer(),
                  IconButton.filledTonal(
                    tooltip: 'Bật/tắt đèn',
                    onPressed: () => _controller.toggleTorch(),
                    icon: const Icon(Icons.flashlight_on_rounded),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            left: WebTuiSpacing.lg,
            right: WebTuiSpacing.lg,
            bottom: WebTuiSpacing.xl + MediaQuery.of(context).padding.bottom,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.62),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white24),
              ),
              child: Padding(
                padding: const EdgeInsets.all(WebTuiSpacing.md),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Quét mã QR',
                      textAlign: TextAlign.center,
                      style: WebTuiTypography.titleMedium.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: WebTuiSpacing.xs),
                    Text(
                      'Đưa mã vào khung, nội dung sẽ được chèn vào tin nhắn.',
                      textAlign: TextAlign.center,
                      style: WebTuiTypography.bodySmall.copyWith(
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
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
      Navigator.of(context).pop(value);
      return;
    }
  }
}

class _ScannerError extends StatelessWidget {
  const _ScannerError({required this.error});

  final MobileScannerException error;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(WebTuiSpacing.lg),
          child: Text(
            'Không mở được camera. Hãy kiểm tra quyền camera rồi thử lại.',
            textAlign: TextAlign.center,
            style: WebTuiTypography.bodyMedium.copyWith(color: Colors.white),
          ),
        ),
      ),
    );
  }
}

class _QrScannerOverlayPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final overlayPaint = Paint()..color = Colors.black.withValues(alpha: 0.48);
    final cutoutSize = size.shortestSide * 0.72;
    final cutout = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(size.width / 2, size.height / 2),
        width: cutoutSize,
        height: cutoutSize,
      ),
      const Radius.circular(24),
    );
    final overlay = Path()..addRect(Offset.zero & size);
    final hole = Path()..addRRect(cutout);
    canvas.drawPath(
      Path.combine(PathOperation.difference, overlay, hole),
      overlayPaint,
    );

    final borderPaint = Paint()
      ..color = WebTuiColors.primary
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    canvas.drawRRect(cutout, borderPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
