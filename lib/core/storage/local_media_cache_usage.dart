import 'dart:io';

/// Dung lượng kho tệp đã tải về máy của tài khoản đang đăng nhập (ảnh, video,
/// ghi âm, tệp...) và xoá kho đó. Không đăng xuất, không xoá tin nhắn.
abstract interface class LocalMediaCacheUsage {
  /// Tổng số byte đang dùng.
  Future<int> usedBytes();

  /// Xoá hết tệp trong kho của tài khoản.
  Future<void> clear();
}

/// [LocalMediaCacheUsage] trên một thư mục ([directory] trả `null` khi chưa
/// đăng nhập / chưa chọn máy chủ: dung lượng 0, không xoá gì).
final class DirectoryMediaCacheUsage implements LocalMediaCacheUsage {
  const DirectoryMediaCacheUsage({
    required Future<Directory?> Function() directory,
    Future<void> Function()? onCleared,
  }) : _directory = directory,
       _onCleared = onCleared;

  final Future<Directory?> Function() _directory;

  /// Sau khi xoá xong thư mục: bỏ bộ nhớ trong đi kèm (ảnh đã giải mã, danh
  /// sách tệp đã nhớ...).
  final Future<void> Function()? _onCleared;

  @override
  Future<int> usedBytes() async {
    final directory = await _directory();
    if (directory == null || !await directory.exists()) return 0;
    var total = 0;
    await for (final entity in directory.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File) continue;
      try {
        total += await entity.length();
      } on FileSystemException {
        // Tệp vừa bị dọn trong lúc đếm: bỏ qua.
      }
    }
    return total;
  }

  @override
  Future<void> clear() async {
    final directory = await _directory();
    if (directory != null && await directory.exists()) {
      await directory.delete(recursive: true);
    }
    await _onCleared?.call();
  }
}
