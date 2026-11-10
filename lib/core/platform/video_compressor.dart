import 'dart:async';

/// Video sau khi nén trên máy (bản nhỏ hơn để gửi trong chat).
final class CompressedVideo {
  const CompressedVideo({required this.path, required this.byteSize});

  final String path;
  final int byteSize;
}

/// Nén video trước khi gửi (giống Zalo / Messenger): đưa cạnh ngắn về
/// [VideoCompressor.targetShortSide] điểm ảnh, H.264 + AAC, MP4.
///
/// Không bao giờ chặn việc gửi: máy không hỗ trợ, nén lỗi hay bị huỷ thì trả
/// `null` để nơi gọi gửi bản gốc.
abstract interface class VideoCompressor {
  static const int targetShortSide = 720;
  static const int targetVideoBitrate = 2500000;
  static const int targetAudioBitrate = 128000;

  /// Nén [inputPath] ra [outputPath] (ghi đè nếu đã có). [onProgress] nhận
  /// 0..1. Trả `null` nếu không nén được.
  Future<CompressedVideo?> compress({
    required String inputPath,
    required String outputPath,
    void Function(double progress)? onProgress,
  });

  /// Huỷ lượt nén đang ghi ra [outputPath] (không có thì bỏ qua).
  Future<void> cancel(String outputPath);
}

/// Dùng cho test / nền tảng không có bộ nén: luôn gửi bản gốc.
final class NoopVideoCompressor implements VideoCompressor {
  const NoopVideoCompressor();

  @override
  Future<CompressedVideo?> compress({
    required String inputPath,
    required String outputPath,
    void Function(double progress)? onProgress,
  }) async => null;

  @override
  Future<void> cancel(String outputPath) async {}
}

/// Bộ nén gọi mã native qua kênh `webtui/video_compress`
/// (Android: Media3 Transformer, iOS: AVAssetExportSession).
final class MethodChannelVideoCompressor implements VideoCompressor {
  MethodChannelVideoCompressor();

  @override
  Future<CompressedVideo?> compress({
    required String inputPath,
    required String outputPath,
    void Function(double progress)? onProgress,
  }) {
    // TODO(khung): agent phần native cài đặt.
    throw UnimplementedError();
  }

  @override
  Future<void> cancel(String outputPath) {
    // TODO(khung): agent phần native cài đặt.
    throw UnimplementedError();
  }
}
