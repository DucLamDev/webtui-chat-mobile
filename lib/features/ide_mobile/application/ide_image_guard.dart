import 'dart:typed_data';
import 'dart:ui' as ui;

/// Kích thước ảnh đọc từ phần đầu tệp (chưa giải mã điểm ảnh).
final class IdeImageSize {
  const IdeImageSize(this.width, this.height);
  final int width;
  final int height;
}

/// Đọc kích thước ảnh bằng `ImageDescriptor` (không giải mã cả ảnh). `null`
/// khi không đọc được. Dùng để chặn bom giải nén trước khi giải mã.
Future<IdeImageSize?> ideReadImageSize(Uint8List bytes) async {
  ui.ImmutableBuffer? buffer;
  ui.ImageDescriptor? descriptor;
  try {
    buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    return IdeImageSize(descriptor.width, descriptor.height);
  } on Object {
    return null;
  } finally {
    descriptor?.dispose();
    buffer?.dispose();
  }
}

/// Kích thước nằm trong giới hạn cạnh [maxSide] và [maxPixels]?
bool ideImageSizeWithin(
  IdeImageSize size, {
  required int maxSide,
  int? maxPixels,
}) {
  if (size.width <= 0 || size.height <= 0) return false;
  if (size.width > maxSide || size.height > maxSide) return false;
  if (maxPixels != null && size.width * size.height > maxPixels) return false;
  return true;
}
