import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as path;

/// Kho đệm ảnh / video tin nhắn trên máy, kiểu Zalo: xem lại là hiện ngay, không tải lại.
///
/// - Mỗi tệp một bản (đường dẫn do [ScopedAttachmentFileStore] đặt theo máy chủ + phiên đăng nhập + mã tệp),
///   nên đăng xuất / đổi máy chủ vẫn xoá sạch như cũ.
/// - Nhiều chỗ cùng mở một tệp thì dùng chung một lượt tải; ai đến sau vẫn nhận tiến độ.
/// - Bộ tải ghi vào tệp tạm rồi mới đổi tên, nên tệp có mặt là tệp đã đủ.
/// - Quá [maxBytes] thì xoá tệp lâu không xem trước (thời điểm xem ghi vào giờ sửa tệp).
final class MediaDiskCache {
  MediaDiskCache({this.maxBytes = defaultMaxBytes, DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  static const int defaultMaxBytes = 500 * 1024 * 1024;

  final int maxBytes;
  final DateTime Function() _clock;
  final Map<String, _CacheJob> _jobs = <String, _CacheJob>{};

  /// Tệp đệm đã đủ thì trả về (và ghi nhận vừa xem), không thì null.
  Future<File?> lookup(File target, {int? expectedBytes}) async {
    if (_jobs.containsKey(target.path)) return null;
    if (!await _isComplete(target, expectedBytes)) return null;
    await _touch(target);
    return target;
  }

  /// Trả tệp đệm [target]; chưa có thì gọi [download] (ghi thẳng vào [target]) một lần duy nhất cho mọi người gọi.
  ///
  /// [download] nhận hàm báo tiến độ để chuyển cho mọi người đang chờ. Lượt tải hỏng thì mọi người chờ cùng nhận lỗi
  /// và lần gọi sau tải lại.
  Future<File> obtain(
    File target, {
    int? expectedBytes,
    void Function(int received, int total)? onProgress,
    required Future<File> Function(void Function(int, int) reportProgress)
    download,
  }) async {
    final running = _jobs[target.path];
    if (running != null) {
      if (onProgress != null) running.listeners.add(onProgress);
      return running.result;
    }
    final cached = await lookup(target, expectedBytes: expectedBytes);
    if (cached != null) return cached;
    // Có thể có người khác vừa bắt đầu trong lúc kiểm tệp.
    final raced = _jobs[target.path];
    if (raced != null) {
      if (onProgress != null) raced.listeners.add(onProgress);
      return raced.result;
    }
    final job = _CacheJob();
    if (onProgress != null) job.listeners.add(onProgress);
    _jobs[target.path] = job;
    job.result = _run(target, job, download);
    return job.result;
  }

  Future<File> _run(
    File target,
    _CacheJob job,
    Future<File> Function(void Function(int, int) reportProgress) download,
  ) async {
    try {
      await target.parent.create(recursive: true);
      final file = await download((received, total) {
        for (final listener in List.of(job.listeners)) {
          listener(received, total);
        }
      });
      await _touch(file);
      unawaited(trim(file.parent, keep: file.path));
      return file;
    } finally {
      _jobs.remove(target.path);
    }
  }

  /// Giữ tổng dung lượng thư mục đệm [root] ≤ [maxBytes]: xoá tệp lâu không xem trước.
  /// Không xoá tệp [keep] (vừa tải) và tệp đang tải dở của lượt khác.
  Future<void> trim(Directory root, {String? keep}) async {
    try {
      if (!await root.exists()) return;
      final entries = <(File, int, DateTime)>[];
      var total = 0;
      await for (final entity in root.list(recursive: true)) {
        if (entity is! File) continue;
        final stat = await entity.stat();
        total += stat.size;
        if (entity.path == keep ||
            _jobs.containsKey(entity.path) ||
            path.basename(entity.path).contains('.part-')) {
          continue;
        }
        entries.add((entity, stat.size, stat.modified));
      }
      if (total <= maxBytes) return;
      entries.sort((a, b) => a.$3.compareTo(b.$3));
      for (final (file, size, _) in entries) {
        if (total <= maxBytes) break;
        try {
          await file.delete();
          total -= size;
        } on FileSystemException {
          // Tệp vừa bị xoá ở chỗ khác: bỏ qua.
        }
      }
    } on FileSystemException {
      // Dọn đệm là việc phụ, lỗi thì để lần sau.
    }
  }

  Future<bool> _isComplete(File file, int? expectedBytes) async {
    try {
      if (!await file.exists()) return false;
      final length = await file.length();
      if (length <= 0) return false;
      return expectedBytes == null || expectedBytes <= 0
          ? true
          : length == expectedBytes;
    } on FileSystemException {
      return false;
    }
  }

  Future<void> _touch(File file) async {
    try {
      await file.setLastModified(_clock());
    } on FileSystemException {
      // Không ghi được giờ xem thì tệp chỉ bị dọn sớm hơn.
    }
  }
}

final class _CacheJob {
  final List<void Function(int, int)> listeners = [];
  late Future<File> result;
}

/// Kho đệm ảnh / video tin nhắn dùng chung cả app.
final MediaDiskCache messageMediaCache = MediaDiskCache();
