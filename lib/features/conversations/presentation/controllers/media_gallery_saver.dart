import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gal/gal.dart';

/// Kết quả lưu ảnh / video vào thư viện ảnh của máy.
enum MediaGallerySaveResult { saved, permissionDenied, failed }

/// Lưu tệp ảnh / video (đã tải về máy) vào thư viện ảnh (Ảnh trên iPhone, Thư viện trên Android).
abstract interface class MediaGallerySaver {
  Future<MediaGallerySaveResult> save(String path, {required bool isVideo});
}

final class GalMediaGallerySaver implements MediaGallerySaver {
  const GalMediaGallerySaver();

  @override
  Future<MediaGallerySaveResult> save(
    String path, {
    required bool isVideo,
  }) async {
    try {
      if (!await Gal.hasPermission() && !await Gal.requestPermission()) {
        return MediaGallerySaveResult.permissionDenied;
      }
      if (isVideo) {
        await Gal.putVideo(path);
      } else {
        await Gal.putImage(path);
      }
      return MediaGallerySaveResult.saved;
    } on GalException catch (error) {
      return error.type == GalExceptionType.permissionDenied
          ? MediaGallerySaveResult.permissionDenied
          : MediaGallerySaveResult.failed;
    } on Object {
      // Máy không hỗ trợ (bản xem trước Linux) hoặc lỗi nền tảng khác.
      return MediaGallerySaveResult.failed;
    }
  }
}

final mediaGallerySaverProvider = Provider<MediaGallerySaver>(
  (ref) => const GalMediaGallerySaver(),
);
