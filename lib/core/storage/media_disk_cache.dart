import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

/// Kho tệp đã tải về máy, dùng chung cho ảnh, ảnh thu nhỏ, video, ghi âm, tệp
/// và ảnh đại diện: mở lại không phải tải lại từ máy chủ.
///
/// - Tệp không được dùng quá [maxAge] (mặc định 7 ngày) thì bị xoá; mỗi lần
///   dùng lại tính lại từ đầu (giờ sửa của tệp là lần dùng cuối).
/// - Tổng dung lượng dưới thư mục gốc vượt [maxBytes] (mặc định 1 GB) thì xoá
///   tệp lâu không dùng nhất trước.
/// - Ghi nguyên khối (ghi tệp tạm rồi đổi tên): không bao giờ đọc phải tệp dở.
/// - Nhiều chỗ cùng xin một tệp một lúc thì chỉ tải một lần.
///
/// Kho không tự chọn thư mục theo máy chủ / tài khoản: nơi gọi truyền đúng tệp
/// đích (xem `ScopedAttachmentFileStore.cacheFileFor`).
final class MediaDiskCache {
  MediaDiskCache({
    required Future<Directory> Function() root,
    this.maxAge = const Duration(days: 7),
    this.maxBytes = 1024 * 1024 * 1024,
    this.trimInterval = const Duration(minutes: 15),
    DateTime Function()? now,
  }) : assert(maxBytes > 0),
       _root = root,
       _now = now ?? DateTime.now;

  final Future<Directory> Function() _root;
  final Duration maxAge;
  final int maxBytes;

  /// Khoảng cách tối thiểu giữa hai lần tự dọn ([scheduleTrim]).
  final Duration trimInterval;
  final DateTime Function() _now;

  /// Tệp vừa được đánh dấu dùng trong khoảng này thì không ghi lại giờ sửa
  /// (đỡ ghi đĩa khi cuộn qua cùng một ảnh nhiều lần).
  static const touchGranularity = Duration(hours: 1);

  /// Tệp tải dở / thư mục rỗng cũ hơn mức này coi như bị bỏ, được dọn đi.
  /// Mới hơn thì để yên: có thể đang có lượt tải ghi vào.
  static const abandonedAge = Duration(hours: 1);

  static final RegExp _partialName = RegExp(r'\.part(-\d+)?$');

  final Map<String, Future<Object>> _inFlight = {};
  Future<void>? _trimming;
  DateTime? _lastTrimStarted;
  int _partCounter = 0;

  /// Tệp còn dùng được trong kho (và đánh dấu vừa dùng); `null` khi chưa có,
  /// đã quá hạn hoặc sai cỡ ([expectedBytes] > 0) — hai trường hợp sau xoá
  /// luôn tệp cũ.
  Future<File?> lookup(File file, {int? expectedBytes}) async {
    try {
      final stat = await file.stat();
      if (stat.type != FileSystemEntityType.file) return null;
      final now = _now();
      final idle = now.difference(stat.modified);
      final wrongSize =
          stat.size <= 0 ||
          (expectedBytes != null &&
              expectedBytes > 0 &&
              stat.size != expectedBytes);
      if (idle > maxAge || wrongSize) {
        await _deleteQuietly(file);
        return null;
      }
      if (idle > touchGranularity) {
        try {
          await file.setLastModified(now);
        } on FileSystemException {
          // Không đánh dấu được thì tệp chỉ bị dọn sớm hơn, vẫn dùng được.
        }
      }
      return file;
    } on FileSystemException {
      return null;
    }
  }

  /// Trả tệp đã có trong kho; chưa có thì gọi [download] ghi vào [file] (tải
  /// về tệp tạm rồi đổi tên, như `RedirectSafeFileDownloader.download`).
  Future<File> ensureFile(
    File file, {
    int? expectedBytes,
    required Future<File> Function(File target) download,
  }) {
    return _dedupe<File>('file:${file.path}', () async {
      final cached = await lookup(file, expectedBytes: expectedBytes);
      if (cached != null) return cached;
      await file.parent.create(recursive: true);
      final downloaded = await download(file);
      scheduleTrim();
      return downloaded;
    });
  }

  /// Bytes của một tệp nhỏ (ảnh, ảnh đại diện): đọc từ kho, chưa có thì gọi
  /// [download] rồi ghi vào kho. Ghi kho lỗi (đầy bộ nhớ...) vẫn trả bytes.
  Future<Uint8List> ensureBytes(
    File file, {
    required int maxBytes,
    required Future<Uint8List> Function() download,
  }) {
    return _dedupe<Uint8List>('bytes:${file.path}', () async {
      final cached = await lookup(file);
      if (cached != null) {
        try {
          final length = await cached.length();
          if (length > 0 && length <= maxBytes) {
            return await cached.readAsBytes();
          }
        } on FileSystemException {
          // Tệp vừa bị dọn / hỏng: tải lại bên dưới.
        }
      }
      final bytes = await download();
      if (bytes.isNotEmpty && bytes.lengthInBytes <= maxBytes) {
        await _writeAtomically(file, bytes);
        scheduleTrim();
      }
      return bytes;
    });
  }

  /// Dọn kho: xoá tệp quá [maxAge], tệp tải dở bị bỏ, rồi tệp lâu không dùng
  /// nhất tới khi tổng dung lượng <= [maxBytes]; cuối cùng xoá thư mục rỗng cũ.
  Future<MediaDiskCacheTrimResult> trim() async {
    final root = await _root();
    if (!await root.exists()) return const MediaDiskCacheTrimResult();
    final now = _now();
    final kept = <_CachedEntry>[];
    final directories = <Directory>[];
    var totalBytes = 0;
    var deletedFiles = 0;
    var deletedBytes = 0;

    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is Directory) {
        directories.add(entity);
        continue;
      }
      if (entity is! File) continue;
      final FileStat stat;
      try {
        stat = await entity.stat();
      } on FileSystemException {
        continue;
      }
      if (stat.type != FileSystemEntityType.file) continue;
      final idle = now.difference(stat.modified);
      final partial = _partialName.hasMatch(entity.path);
      final expired = partial ? idle > abandonedAge : idle > maxAge;
      if (expired) {
        if (await _deleteQuietly(entity)) {
          deletedFiles += 1;
          deletedBytes += stat.size;
        }
        continue;
      }
      totalBytes += stat.size;
      // Tệp đang tải dở vẫn tính vào dung lượng nhưng không xoá giữa chừng.
      if (!partial) kept.add(_CachedEntry(entity, stat.size, stat.modified));
    }

    if (totalBytes > maxBytes) {
      kept.sort((left, right) => left.modified.compareTo(right.modified));
      for (final entry in kept) {
        if (totalBytes <= maxBytes) break;
        if (await _deleteQuietly(entry.file)) {
          totalBytes -= entry.size;
          deletedFiles += 1;
          deletedBytes += entry.size;
        }
      }
    }

    // Thư mục sâu nhất trước, để thư mục cha thành rỗng thì xoá được luôn.
    directories.sort(
      (left, right) => right.path.length.compareTo(left.path.length),
    );
    for (final directory in directories) {
      try {
        final stat = await directory.stat();
        if (now.difference(stat.modified) <= abandonedAge) continue;
        if (await directory.list(followLinks: false).isEmpty) {
          await directory.delete();
        }
      } on FileSystemException {
        // Thư mục vừa có tệp mới / đã bị xoá: bỏ qua.
      }
    }

    return MediaDiskCacheTrimResult(
      deletedFiles: deletedFiles,
      deletedBytes: deletedBytes,
      remainingBytes: totalBytes,
    );
  }

  /// Dọn kho ở nền, tối đa mỗi [trimInterval] một lần; lỗi chỉ bỏ qua.
  void scheduleTrim() {
    if (_trimming != null) return;
    final now = _now();
    final last = _lastTrimStarted;
    if (last != null && now.difference(last) < trimInterval) return;
    _lastTrimStarted = now;
    _trimming = () async {
      try {
        await trim();
      } on Object {
        // Dọn là việc phụ: lần sau thử lại.
      } finally {
        _trimming = null;
      }
    }();
  }

  /// Chạy [run] một lần cho mỗi [key] đang chạy. Lượt đang chạy của nơi khác
  /// hỏng (vd. màn hình đó đã đóng nên huỷ tải) thì tự chạy lại một lần.
  Future<T> _dedupe<T extends Object>(
    String key,
    Future<T> Function() run,
  ) async {
    final pending = _inFlight[key];
    if (pending != null) {
      try {
        return await pending as T;
      } on Object {
        // Chạy lại bên dưới với [run] của chính nơi gọi này.
      }
    }
    final future = run();
    _inFlight[key] = future;
    try {
      return await future;
    } finally {
      if (identical(_inFlight[key], future)) _inFlight.remove(key);
    }
  }

  Future<void> _writeAtomically(File file, Uint8List bytes) async {
    _partCounter += 1;
    final part = File(
      '${file.path}.part-${_now().microsecondsSinceEpoch}$_partCounter',
    );
    try {
      await file.parent.create(recursive: true);
      await part.writeAsBytes(bytes, flush: true);
      await part.rename(file.path);
    } on FileSystemException {
      await _deleteQuietly(part);
    }
  }

  Future<bool> _deleteQuietly(File file) async {
    try {
      await file.delete();
      return true;
    } on FileSystemException {
      return false;
    }
  }
}

final class MediaDiskCacheTrimResult {
  const MediaDiskCacheTrimResult({
    this.deletedFiles = 0,
    this.deletedBytes = 0,
    this.remainingBytes = 0,
  });

  final int deletedFiles;
  final int deletedBytes;
  final int remainingBytes;
}

final class _CachedEntry {
  const _CachedEntry(this.file, this.size, this.modified);

  final File file;
  final int size;
  final DateTime modified;
}
