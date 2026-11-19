import 'dart:typed_data';
import 'dart:ui' as ui;

/// Ảnh quá lớn dù đã thu nhỏ hết mức.
final class IdeAvatarTooLarge implements Exception {
  const IdeAvatarTooLarge();
}

/// Ảnh không đọc được (hỏng / định dạng lạ).
final class IdeAvatarUnreadable implements Exception {
  const IdeAvatarUnreadable();
}

/// Bộ mã ảnh đại diện: nhận ảnh gốc, trả PNG vuông 256 × 256 (≤ 300 KB).
/// Đặt sau interface để test thay được.
abstract interface class IdeAvatarEncoder {
  Future<Uint8List> encode(Uint8List source);
}

/// Cắt vuông giữa, thu 256 × 256, mã PNG bằng `dart:ui`. Quá [maxBytes] thì
/// thu 192 × 192 rồi vẽ lại 256 × 256; vẫn quá thì ném [IdeAvatarTooLarge].
final class DartUiAvatarEncoder implements IdeAvatarEncoder {
  const DartUiAvatarEncoder({this.maxBytes = 300 * 1024});

  static const side = 256;
  static const smallSide = 192;

  final int maxBytes;

  @override
  Future<Uint8List> encode(Uint8List source) async {
    final original = await _decode(source);
    try {
      final first = await _render(original, side);
      if (first.length <= maxBytes) return first;
      final small = await _render(original, smallSide);
      final smallImage = await _decode(small);
      try {
        final second = await _render(smallImage, side);
        if (second.length <= maxBytes) return second;
      } finally {
        smallImage.dispose();
      }
      throw const IdeAvatarTooLarge();
    } finally {
      original.dispose();
    }
  }

  Future<ui.Image> _decode(Uint8List bytes) async {
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      try {
        final frame = await codec.getNextFrame();
        return frame.image;
      } finally {
        codec.dispose();
      }
    } on Exception {
      throw const IdeAvatarUnreadable();
    }
  }

  /// Cắt vuông giữa của [image] rồi vẽ vào ô [size] × [size], mã PNG.
  Future<Uint8List> _render(ui.Image image, int size) async {
    final w = image.width.toDouble();
    final h = image.height.toDouble();
    final s = w < h ? w : h;
    if (s <= 0) throw const IdeAvatarUnreadable();
    final src = ui.Rect.fromLTWH((w - s) / 2, (h - s) / 2, s, s);
    final dst = ui.Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble());
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawImageRect(
      image,
      src,
      dst,
      ui.Paint()..filterQuality = ui.FilterQuality.high,
    );
    final picture = recorder.endRecording();
    final out = await picture.toImage(size, size);
    try {
      final data = await out.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw const IdeAvatarUnreadable();
      return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } finally {
      out.dispose();
      picture.dispose();
    }
  }
}
