import 'dart:io';
import 'dart:typed_data';

import '../network/recent_download_failures.dart';
import 'media_disk_cache.dart';

/// Bytes của một ảnh nhỏ (ảnh đại diện, ảnh trong tin, ảnh bìa video) qua kho
/// đệm trên máy:
/// - [failureKey] vừa bị máy chủ từ chối (403 / 404 / 410) thì trả `null` ngay,
///   không hỏi lại máy chủ;
/// - có trong kho ([file] còn hạn) thì đọc từ máy; chưa có thì [download] rồi
///   lưu vào kho.
///
/// Lỗi tải trả `null` (ảnh hiện ô trống như trước); lỗi từ chối được nhớ vào
/// [failures] để lần vẽ lại sau không hỏi lại máy chủ.
Future<Uint8List?> loadCachedImageBytes({
  required MediaDiskCache cache,
  required RecentDownloadFailures failures,
  required String failureKey,
  required File file,
  required int maxBytes,
  required Future<Uint8List> Function() download,
}) async {
  if (failures.isBlocked(failureKey)) return null;
  try {
    return await cache.ensureBytes(
      file,
      maxBytes: maxBytes,
      download: download,
    );
  } on Object catch (error) {
    failures.record(failureKey, error);
    return null;
  }
}
