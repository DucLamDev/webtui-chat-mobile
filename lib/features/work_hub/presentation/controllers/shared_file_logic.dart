import 'dart:async';
import 'dart:io';

import '../../domain/entities/work_hub.dart';

/// Định dạng tệp để vẽ "logo" loại tệp và chọn thao tác.
enum SharedFileFormat { pdf, word, excel, powerpoint, other }

/// Nhận loại theo mime + đuôi tệp (mime lạ thì dựa vào đuôi).
SharedFileFormat sharedFileFormat(SharedFile file) {
  final mime = file.mimeType.trim().toLowerCase();
  final name = file.name.trim().toLowerCase();
  final dot = name.lastIndexOf('.');
  final ext = dot < 0 ? '' : name.substring(dot + 1);
  if (mime == 'application/pdf' || ext == 'pdf') return SharedFileFormat.pdf;
  if (mime == 'application/msword' ||
      mime.contains('wordprocessingml') ||
      const {
        'doc',
        'docx',
        'docm',
        'dot',
        'dotx',
        'rtf',
        'odt',
      }.contains(ext)) {
    return SharedFileFormat.word;
  }
  if (mime == 'application/vnd.ms-excel' ||
      mime.contains('spreadsheetml') ||
      const {'xls', 'xlsx', 'xlsm', 'xlsb', 'csv', 'ods'}.contains(ext)) {
    return SharedFileFormat.excel;
  }
  if (mime == 'application/vnd.ms-powerpoint' ||
      mime.contains('presentationml') ||
      const {'ppt', 'pptx', 'pptm', 'pps', 'ppsx', 'odp'}.contains(ext)) {
    return SharedFileFormat.powerpoint;
  }
  return SharedFileFormat.other;
}

/// Việc xảy ra khi bấm một dòng tệp.
enum SharedFileTapAction {
  /// Ghi âm: phát ngay tại dòng.
  playInline,

  /// Ảnh: mở trình xem ảnh toàn màn.
  openImage,

  /// Video: bảng thao tác Xem / Tải về / Mở bằng ứng dụng khác.
  videoSheet,

  /// PDF: bảng thao tác Xem / Tải về / Mở bằng ứng dụng khác.
  pdfSheet,

  /// Word, Excel, khác: bảng thao tác Mở / Tải về.
  openSheet,
}

SharedFileTapAction sharedFileTapAction(SharedFile file) {
  return switch (file.kind) {
    SharedFileKind.audio => SharedFileTapAction.playInline,
    SharedFileKind.image => SharedFileTapAction.openImage,
    SharedFileKind.video => SharedFileTapAction.videoSheet,
    SharedFileKind.document =>
      sharedFileFormat(file) == SharedFileFormat.pdf
          ? SharedFileTapAction.pdfSheet
          : SharedFileTapAction.openSheet,
  };
}

/// Cắt giữa tên tệp dài, giữ đuôi: "Bao-cao-qu…-2026.pdf".
String shortenFileName(String name, {int maxLength = 34}) {
  if (name.length <= maxLength || maxLength < 8) return name;
  final dot = name.lastIndexOf('.');
  final ext = dot > 0 && name.length - dot <= 6 ? name.substring(dot) : '';
  final tail = ext.isEmpty ? 6 : 5 + ext.length;
  final head = maxLength - tail - 1;
  final stem = ext.isEmpty ? name : name.substring(0, dot);
  final stemTail = ext.isEmpty ? 6 : 5;
  return '${name.substring(0, head)}…'
      '${stem.substring(stem.length - stemTail)}$ext';
}

/// Tên tệp dùng cho tệp trong bộ nhớ đệm: chỉ giữ đuôi an toàn.
String sharedFileCacheName(String id, int size, String originalName) {
  final safeId = id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
  final dot = originalName.lastIndexOf('.');
  var ext = dot < 0 ? '' : originalName.substring(dot + 1).toLowerCase();
  if (!RegExp(r'^[a-z0-9]{1,8}$').hasMatch(ext)) ext = '';
  return ext.isEmpty ? '$safeId-$size' : '$safeId-$size.$ext';
}

/// Bộ nhớ đệm tệp đã tải: `<thư mục>/<id>-<size>.<đuôi>`, giới hạn tổng
/// dung lượng (xoá tệp lâu không dùng trước).
final class SharedFileCache {
  SharedFileCache({
    required Future<Directory> Function() directory,
    this.maxBytes = 300 * 1024 * 1024,
  }) : _directory = directory;

  final Future<Directory> Function() _directory;
  final int maxBytes;
  final _inFlight = <String, Future<File>>{};

  /// Trả tệp đã có (và đánh dấu mới dùng) hoặc gọi [download] ghi vào đích.
  /// Hai lần gọi cùng lúc cho cùng một tệp chỉ tải một lần.
  Future<File> ensure({
    required SharedFile file,
    required Future<void> Function(File target) download,
  }) {
    final name = sharedFileCacheName(file.id, file.byteSize, file.name);
    return _inFlight[name] ??= _ensure(name, file.byteSize, download)
        .whenComplete(() {
          _inFlight.remove(name);
        });
  }

  Future<File> _ensure(
    String name,
    int expectedSize,
    Future<void> Function(File target) download,
  ) async {
    final dir = await _directory();
    await dir.create(recursive: true);
    final target = File('${dir.path}/$name');
    if (await target.exists() &&
        (expectedSize <= 0 || await target.length() == expectedSize)) {
      await target.setLastModified(DateTime.now());
      return target;
    }
    await download(target);
    await trim(keep: target);
    return target;
  }

  /// Xoá tệp lâu không dùng nhất cho tới khi tổng <= [maxBytes].
  Future<void> trim({File? keep}) async {
    final dir = await _directory();
    if (!await dir.exists()) return;
    final entries = <(File, int, DateTime)>[];
    var total = 0;
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final stat = await entity.stat();
      total += stat.size;
      entries.add((entity, stat.size, stat.modified));
    }
    if (total <= maxBytes) return;
    entries.sort((a, b) => a.$3.compareTo(b.$3));
    for (final (entry, size, _) in entries) {
      if (total <= maxBytes) break;
      if (keep != null && entry.path == keep.path) continue;
      try {
        await entry.delete();
        total -= size;
      } on Object {
        // Tệp đang mở: bỏ qua, lần dọn sau thử lại.
      }
    }
  }
}

/// Giữ đường dẫn phát dần còn hạn (trừ hao [margin]) để dùng lại.
final class SharedFileStreamLinkCache {
  SharedFileStreamLinkCache({
    required this.fetch,
    DateTime Function()? now,
    this.margin = const Duration(minutes: 1),
  }) : _now = now ?? DateTime.now;

  /// Xin đường dẫn mới; trả null khi máy chủ không hỗ trợ / lỗi.
  final Future<SharedFileStreamLink?> Function(String fileId) fetch;
  final Duration margin;
  final DateTime Function() _now;
  final _links = <String, SharedFileStreamLink>{};

  Future<SharedFileStreamLink?> linkFor(String fileId) async {
    final cached = _links[fileId];
    if (cached != null && _valid(cached)) return cached;
    _links.remove(fileId);
    final fresh = await fetch(fileId);
    if (fresh != null) _links[fileId] = fresh;
    return fresh;
  }

  bool _valid(SharedFileStreamLink link) {
    final expires = link.expiresAt;
    return expires != null && expires.isAfter(_now().add(margin));
  }
}

/// Nguồn phát: đường dẫn phát dần hoặc tệp cục bộ.
sealed class SharedMediaSource {
  const SharedMediaSource();
}

final class SharedMediaStream extends SharedMediaSource {
  const SharedMediaStream(this.uri);
  final Uri uri;
}

final class SharedMediaLocal extends SharedMediaSource {
  const SharedMediaLocal(this.file);
  final File file;
}

/// Tìm nguồn phát cho tệp: ưu tiên phát dần, lỗi thì tải về (qua bộ nhớ đệm).
final class SharedFileMediaResolver {
  SharedFileMediaResolver({
    required this.links,
    required this.cache,
    required this.download,
    required this.absolute,
  });

  final SharedFileStreamLinkCache links;
  final SharedFileCache cache;

  /// Tải tệp về đích (có kiểm tra phiên đăng nhập).
  final Future<void> Function(SharedFile file, File target) download;

  /// Ghép đường dẫn tương đối với địa chỉ API; null nếu không hợp lệ.
  final Uri? Function(String url) absolute;

  Future<SharedMediaSource> resolve(SharedFile file) async {
    final stream = await streamUri(file);
    if (stream != null) return SharedMediaStream(stream);
    return SharedMediaLocal(await localFile(file));
  }

  Future<Uri?> streamUri(SharedFile file) async {
    try {
      final link = await links.linkFor(file.id);
      return link == null ? null : absolute(link.url);
    } on Object {
      return null;
    }
  }

  Future<File> localFile(SharedFile file) {
    return cache.ensure(file: file, download: (t) => download(file, t));
  }
}
