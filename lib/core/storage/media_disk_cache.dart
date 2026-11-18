import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;

/// Kho tệp đã tải về máy, dùng chung cho ảnh, ảnh thu nhỏ, video, ghi âm, tệp
/// và ảnh đại diện: mở lại không phải tải lại từ máy chủ.
///
/// - Tệp không được dùng quá [maxAge] (mặc định 7 ngày) thì bị xoá; mỗi lần
///   dùng lại tính lại từ đầu (giờ sửa của tệp là lần dùng cuối).
/// - Tổng dung lượng dưới thư mục gốc vượt [maxBytes] (mặc định 1 GB) thì xoá
///   tệp cũ: tệp quá lớn trước, rồi tệp lâu không dùng nhất. Tệp vừa dùng
///   trong [abandonedAge] không bao giờ bị xoá (có thể đang phát / đang mở
///   bằng app khác).
/// - Ghi vào kho nhiều (từ 1/10 [maxBytes]) kể từ lần dọn trước thì dọn ngay,
///   không chờ hết [trimInterval].
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
  /// (đỡ ghi đĩa khi cuộn qua cùng một ảnh nhiều lần). Phải nhỏ hơn hẳn
  /// [abandonedAge]: tệp vừa mở lại (đang phát) luôn được coi là "vừa dùng"
  /// và không bị bước dọn theo dung lượng xoá giữa chừng.
  static const touchGranularity = Duration(minutes: 10);

  /// Tệp tải dở / thư mục rỗng cũ hơn mức này coi như bị bỏ, được dọn đi.
  /// Mới hơn thì để yên: có thể đang có lượt tải ghi vào.
  static const abandonedAge = Duration(hours: 1);

  static final RegExp _partialName = RegExp(r'\.part(-\d+)?$');

  final Map<String, Future<Object>> _inFlight = {};
  Future<void>? _trimming;
  DateTime? _lastTrimStarted;
  int _partCounter = 0;

  /// Số byte đã ghi vào kho từ lần dọn trước (xem [scheduleTrim]).
  int _bytesSinceTrim = 0;

  /// Có ghi nhiều trong lúc đang dọn: dọn xong thì dọn lại một lượt.
  bool _trimAgain = false;

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
      var written = 0;
      try {
        written = await downloaded.length();
      } on FileSystemException {
        // Không đọc được cỡ: chỉ không tính vào mức dọn sớm.
      }
      _noteWritten(written);
      return downloaded;
    });
  }

  /// Bytes của một tệp nhỏ (ảnh, ảnh đại diện): đọc từ kho, chưa có thì gọi
  /// [download] rồi ghi vào kho. Ghi kho lỗi (đầy bộ nhớ...) vẫn trả bytes.
  ///
  /// [isStillCurrent] trả false ngay trước khi ghi (vd. vừa đăng xuất / đổi
  /// máy chủ, thư mục kho của tài khoản vừa bị xoá) thì không ghi, vẫn trả
  /// bytes cho nơi gọi tự quyết.
  Future<Uint8List> ensureBytes(
    File file, {
    required int maxBytes,
    required Future<Uint8List> Function() download,
    Future<bool> Function()? isStillCurrent,
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
      if (bytes.isNotEmpty &&
          bytes.lengthInBytes <= maxBytes &&
          await _stillCurrent(isStillCurrent)) {
        if (await _writeAtomically(file, bytes)) {
          _noteWritten(bytes.lengthInBytes);
        }
      }
      return bytes;
    });
  }

  /// Dọn kho: xoá tệp quá [maxAge], tệp tải dở bị bỏ; vượt [maxBytes] thì xoá
  /// tệp cũ (không dùng trong [abandonedAge]) cho vừa ngân sách; cuối cùng xoá
  /// thư mục rỗng cũ.
  ///
  /// Tệp vừa dùng / đang tải dở không bao giờ bị xoá ở bước dung lượng. Ngân
  /// sách cho tệp cũ = [maxBytes] − min(tổng tệp vừa dùng, [maxBytes] / 2): mở
  /// một video rất lớn không xoá sạch kho (và không xoá luôn chính nó). Tệp
  /// cũ quá lớn (> [maxBytes] / 4) bị xoá trước, sau đó tệp lâu không dùng nhất.
  Future<MediaDiskCacheTrimResult> trim() async {
    final root = await _root();
    if (!await root.exists()) return const MediaDiskCacheTrimResult();
    final now = _now();
    final old = <_CachedEntry>[];
    final directories = <Directory>[];
    var recentBytes = 0;
    var oldBytes = 0;
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
      // Tệp đang tải dở / vừa dùng vẫn tính vào dung lượng nhưng không xoá.
      if (partial || idle <= abandonedAge) {
        recentBytes += stat.size;
      } else {
        oldBytes += stat.size;
        old.add(_CachedEntry(entity, stat.size, stat.modified));
      }
    }

    if (recentBytes + oldBytes > maxBytes) {
      final halfBudget = maxBytes ~/ 2;
      final oldBudget =
          maxBytes - (recentBytes < halfBudget ? recentBytes : halfBudget);
      final oversized = maxBytes ~/ 4;
      old.sort((left, right) {
        final leftLarge = left.size > oversized;
        final rightLarge = right.size > oversized;
        if (leftLarge != rightLarge) return leftLarge ? -1 : 1;
        return left.modified.compareTo(right.modified);
      });
      for (final entry in old) {
        if (oldBytes <= oldBudget) break;
        if (await _deleteQuietly(entry.file)) {
          oldBytes -= entry.size;
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
      remainingBytes: recentBytes + oldBytes,
    );
  }

  /// Dọn kho ở nền, tối đa mỗi [trimInterval] một lần; lỗi chỉ bỏ qua. Đã
  /// ghi vào kho từ 1/10 [maxBytes] kể từ lần dọn trước thì dọn ngay.
  void scheduleTrim() {
    final writtenEnough = _bytesSinceTrim >= maxBytes ~/ 10;
    if (_trimming != null) {
      if (writtenEnough) _trimAgain = true;
      return;
    }
    final now = _now();
    final last = _lastTrimStarted;
    if (!writtenEnough && last != null && now.difference(last) < trimInterval) {
      return;
    }
    _lastTrimStarted = now;
    _bytesSinceTrim = 0;
    _trimAgain = false;
    _trimming = () async {
      try {
        await trim();
      } on Object {
        // Dọn là việc phụ: lần sau thử lại.
      } finally {
        _trimming = null;
      }
      if (_trimAgain) scheduleTrim();
    }();
  }

  /// Lượt dọn nền đang chạy (cho test chờ xong).
  @visibleForTesting
  Future<void>? get pendingTrim => _trimming;

  void _noteWritten(int bytes) {
    if (bytes > 0) _bytesSinceTrim += bytes;
    scheduleTrim();
  }

  Future<bool> _stillCurrent(Future<bool> Function()? isStillCurrent) async {
    if (isStillCurrent == null) return true;
    try {
      return await isStillCurrent();
    } on Object {
      return false;
    }
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

  /// Ghi tệp nguyên khối; trả false khi ghi lỗi (đã dọn tệp tạm).
  Future<bool> _writeAtomically(File file, Uint8List bytes) async {
    _partCounter += 1;
    final part = File(
      '${file.path}.part-${_now().microsecondsSinceEpoch}$_partCounter',
    );
    try {
      await file.parent.create(recursive: true);
      await part.writeAsBytes(bytes, flush: true);
      await part.rename(file.path);
      return true;
    } on FileSystemException {
      await _deleteQuietly(part);
      return false;
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
