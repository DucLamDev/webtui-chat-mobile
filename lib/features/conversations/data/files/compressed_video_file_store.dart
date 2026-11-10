import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Nơi lưu video đã nén chờ tải lên (thư mục tạm của app).
final class CompressedVideoFileStore {
  const CompressedVideoFileStore({Future<Directory> Function()? rootDirectory})
    : _rootDirectory = rootDirectory;

  final Future<Directory> Function()? _rootDirectory;

  static const String folderName = 'webtui-video-upload';
  static const Duration maxAge = Duration(hours: 24);
  static final RegExp _safeName = RegExp(r'^[A-Za-z0-9_-]{1,80}$');

  // Các thư mục đã dọn tệp cũ trong phiên app này.
  static final Set<String> _cleaned = <String>{};

  /// Đường dẫn tệp nén của [clientAttachmentId] (tên tệp đã lọc ký tự, không
  /// thoát ra ngoài thư mục riêng).
  Future<String> pathFor(String clientAttachmentId) async {
    final root = await (_rootDirectory ?? getTemporaryDirectory)();
    final dir = Directory(p.join(root.path, folderName));
    await dir.create(recursive: true);
    if (_cleaned.add(dir.path)) {
      await _deleteOldFiles(dir);
    }
    final name = _safeName.hasMatch(clientAttachmentId)
        ? clientAttachmentId
        : sha256.convert(utf8.encode(clientAttachmentId)).toString();
    return p.join(dir.path, '$name.mp4');
  }

  Future<void> _deleteOldFiles(Directory dir) async {
    try {
      final limit = DateTime.now().subtract(maxAge);
      await for (final entity in dir.list(followLinks: false)) {
        try {
          if (entity is! File) continue;
          if ((await entity.lastModified()).isBefore(limit)) {
            await entity.delete();
          }
        } catch (_) {
          // Bỏ qua tệp không xoá được.
        }
      }
    } catch (_) {
      // Dọn dẹp lỗi thì thôi, không ảnh hưởng việc gửi.
    }
  }
}
