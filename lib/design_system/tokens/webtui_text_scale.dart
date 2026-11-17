import 'package:flutter/widgets.dart';

/// Cỡ chữ của cả app: cỡ chữ hệ thống (giới hạn 85–135% như trước) nhân hệ số
/// người dùng chọn ở Cài đặt > Cỡ chữ. Tổng giới hạn 80–150% để bố cục không
/// vỡ khi máy đã đặt chữ lớn sẵn. Hệ số 1 thì giữ đúng như trước.
TextScaler webTuiAppTextScaler(TextScaler system, double userScale) {
  final base = system.clamp(minScaleFactor: 0.85, maxScaleFactor: 1.35);
  if (userScale == 1 || userScale.isNaN || userScale <= 0) return base;
  return _MultipliedTextScaler(
    base,
    userScale,
  ).clamp(minScaleFactor: 0.8, maxScaleFactor: 1.5);
}

/// Nhân thêm một hệ số vào cách phóng chữ của hệ thống (giữ được kiểu phóng
/// không tuyến tính của Android 14).
final class _MultipliedTextScaler extends TextScaler {
  const _MultipliedTextScaler(this.base, this.factor);

  final TextScaler base;
  final double factor;

  @override
  double scale(double fontSize) => base.scale(fontSize) * factor;

  /// Chỉ để tương thích ngược: ước lượng theo cỡ chữ 14.
  @override
  double get textScaleFactor => scale(14) / 14;

  @override
  bool operator ==(Object other) =>
      other is _MultipliedTextScaler &&
      other.base == base &&
      other.factor == factor;

  @override
  int get hashCode => Object.hash(base, factor);
}
