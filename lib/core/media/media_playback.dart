import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';

/// iPhone / iPad / Mac: trình phát gốc (AVPlayer) phát thẳng từ đường dẫn
/// phát dần của máy chủ (đường có mã, không có đuôi tệp) hay đứng ở khung đầu:
/// chỉ thấy ảnh bìa, đồng hồ không chạy, không báo lỗi (gặp trên bản TestFlight
/// 1.36.0 với video trong nhóm, video và ghi âm ở mục Tệp). Tin thoại tải hẳn
/// về máy rồi phát thì chạy bình thường, nên trên các máy này video / âm thanh
/// luôn tải về máy rồi phát tệp cục bộ.
bool preferLocalMediaPlayback([TargetPlatform? platform]) {
  final target = platform ?? defaultTargetPlatform;
  return target == TargetPlatform.iOS || target == TargetPlatform.macOS;
}

/// Thời gian chờ tối đa để trình phát sẵn sàng với đường phát dần. Quá hạn thì
/// bỏ phát dần, tải tệp về rồi phát: không bao giờ treo mãi ở ảnh bìa.
const mediaStreamStartTimeout = Duration(seconds: 12);

/// Chờ trình phát phát dần sẵn sàng tối đa [timeout]. Lỗi hoặc quá hạn thì
/// huỷ trình phát và trả null để nơi gọi lùi về tải tệp rồi phát.
Future<VideoPlayerController?> initializeStreamOrNull(
  VideoPlayerController controller, {
  Duration timeout = mediaStreamStartTimeout,
}) async {
  try {
    await controller.initialize().timeout(timeout);
    return controller;
  } on Object {
    // Không chờ huỷ xong: trình phát treo không được giữ chân bước lùi.
    unawaited(controller.dispose().catchError((Object _) {}));
    return null;
  }
}
