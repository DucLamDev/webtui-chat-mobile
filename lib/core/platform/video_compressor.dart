import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Video sau khi nén trên máy (bản nhỏ hơn để gửi trong chat).
final class CompressedVideo {
  const CompressedVideo({required this.path, required this.byteSize});

  final String path;
  final int byteSize;
}

/// Ảnh bìa lấy từ một khung hình của video, kèm kích thước / thời lượng video.
final class VideoPoster {
  const VideoPoster({
    required this.path,
    required this.byteSize,
    required this.width,
    required this.height,
    required this.durationMs,
  });

  /// Tệp JPEG ảnh bìa.
  final String path;
  final int byteSize;

  /// Kích thước video gốc theo chiều hiển thị (đã tính xoay), 0 nếu không rõ.
  final int width;
  final int height;
  final int durationMs;
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
  static const int posterMaxSide = 480;
  static const int posterTimeMs = 1000;

  /// Nén [inputPath] ra [outputPath] (ghi đè nếu đã có). [onProgress] nhận
  /// 0..1. Trả `null` nếu không nén được.
  Future<CompressedVideo?> compress({
    required String inputPath,
    required String outputPath,
    void Function(double progress)? onProgress,
  });

  /// Huỷ lượt nén đang ghi ra [outputPath] (không có thì bỏ qua).
  Future<void> cancel(String outputPath);

  /// Lấy ảnh bìa JPEG (cạnh dài tối đa [posterMaxSide]) của [inputPath] ghi ra
  /// [outputPath]. Trả `null` nếu không lấy được.
  Future<VideoPoster?> poster({
    required String inputPath,
    required String outputPath,
  });
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

  @override
  Future<VideoPoster?> poster({
    required String inputPath,
    required String outputPath,
  }) async => null;
}

/// Bộ nén gọi mã native qua kênh `webtui/video_compress`
/// (Android: Media3 Transformer, iOS: AVAssetExportSession).
final class MethodChannelVideoCompressor implements VideoCompressor {
  MethodChannelVideoCompressor({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('webtui/video_compress') {
    _channel.setMethodCallHandler(_onNativeCall);
  }

  final MethodChannel _channel;
  final Map<String, void Function(double progress)> _progressById = {};

  bool get _supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  Future<void> _onNativeCall(MethodCall call) async {
    if (call.method != 'progress') {
      return;
    }
    final arguments = call.arguments;
    if (arguments is! Map) {
      return;
    }
    final id = arguments['id'];
    final value = arguments['progress'];
    if (id is! String || value is! num) {
      return;
    }
    _progressById[id]?.call(value.toDouble().clamp(0.0, 1.0));
  }

  @override
  Future<CompressedVideo?> compress({
    required String inputPath,
    required String outputPath,
    void Function(double progress)? onProgress,
  }) async {
    if (!_supported) {
      return null;
    }
    if (onProgress != null) {
      _progressById[outputPath] = onProgress;
    }
    try {
      final result = await _channel
          .invokeMapMethod<String, Object?>('compress', <String, Object>{
            'id': outputPath,
            'input': inputPath,
            'output': outputPath,
            'shortSide': VideoCompressor.targetShortSide,
            'videoBitrate': VideoCompressor.targetVideoBitrate,
            'audioBitrate': VideoCompressor.targetAudioBitrate,
          });
      final path = result?['path'];
      final byteSize = result?['byteSize'];
      if (path is! String || byteSize is! num || byteSize <= 0) {
        return null;
      }
      if (!await File(path).exists()) {
        return null;
      }
      return CompressedVideo(path: path, byteSize: byteSize.toInt());
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    } on Exception {
      return null;
    } finally {
      _progressById.remove(outputPath);
    }
  }

  @override
  Future<void> cancel(String outputPath) async {
    if (!_supported) {
      return;
    }
    try {
      await _channel.invokeMethod<void>('cancel', <String, Object>{
        'id': outputPath,
      });
    } on PlatformException {
      // Không có lượt nào để huỷ.
    } on MissingPluginException {
      // Máy không có bộ nén native.
    }
  }

  @override
  Future<VideoPoster?> poster({
    required String inputPath,
    required String outputPath,
  }) async {
    if (!_supported) {
      return null;
    }
    try {
      final result = await _channel
          .invokeMapMethod<String, Object?>('poster', <String, Object>{
            'id': outputPath,
            'input': inputPath,
            'output': outputPath,
            'maxSide': VideoCompressor.posterMaxSide,
            'timeMs': VideoCompressor.posterTimeMs,
          });
      final path = result?['path'];
      final byteSize = result?['byteSize'];
      if (path is! String || byteSize is! num || byteSize <= 0) {
        return null;
      }
      if (!await File(path).exists()) {
        return null;
      }
      int number(Object? value) =>
          value is num && value > 0 ? value.toInt() : 0;
      return VideoPoster(
        path: path,
        byteSize: byteSize.toInt(),
        width: number(result?['width']),
        height: number(result?['height']),
        durationMs: number(result?['durationMs']),
      );
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    } on Exception {
      return null;
    }
  }
}
