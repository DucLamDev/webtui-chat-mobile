import 'dart:async';
import 'dart:collection';
import 'dart:io';

import '../../domain/entities/work_hub.dart';

/// Ảnh bìa tự cắt trên máy cho video chưa có ảnh bìa trên máy chủ (gửi từ bản
/// cũ). Lưu JPEG theo `<id>-<byteSize>.jpg` trong thư mục cache của phiên; lần
/// sau dùng lại. Không ghi gì lên máy chủ.
///
/// - Tối đa [maxConcurrent] lượt cắt cùng lúc, còn lại xếp hàng.
/// - Cùng một tệp hỏi nhiều lần chỉ cắt một lần.
/// - Cắt lỗi (máy không giải mã được, đường dẫn hết hạn...) thì nhớ lỗi trong
///   phiên và trả null, không thử lại liên tục.
final class SharedVideoPosterCache {
  SharedVideoPosterCache({
    required Future<Directory> Function() directory,
    required Future<Uri?> Function(String fileId) streamUri,
    required Future<bool> Function(Uri url, String outputPath) extract,
    this.maxConcurrent = 2,
  }) : _directory = directory,
       _streamUri = streamUri,
       _extract = extract;

  final Future<Directory> Function() _directory;
  final Future<Uri?> Function(String fileId) _streamUri;
  final Future<bool> Function(Uri url, String outputPath) _extract;
  final int maxConcurrent;

  final _inFlight = <String, Future<File?>>{};
  final _failed = <String>{};
  final _waiting = Queue<Completer<void>>();
  var _running = 0;

  static String _key(SharedFile file) =>
      '${file.id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_')}-${file.byteSize}';

  /// Ảnh bìa cắt được, hoặc null nếu không có / lỗi.
  Future<File?> posterFor(SharedFile file) {
    final key = _key(file);
    if (_failed.contains(key)) return Future.value();
    return _inFlight[key] ??= _load(file, key).whenComplete(() {
      _inFlight.remove(key);
    });
  }

  Future<File?> _load(SharedFile file, String key) async {
    try {
      final dir = await _directory();
      await dir.create(recursive: true);
      final target = File('${dir.path}/$key.jpg');
      if (await target.exists() && await target.length() > 0) {
        return target;
      }
      await _acquire();
      try {
        final url = await _streamUri(file.id);
        if (url == null) {
          _failed.add(key);
          return null;
        }
        final ok = await _extract(url, target.path);
        if (ok && await target.exists() && await target.length() > 0) {
          return target;
        }
        _failed.add(key);
        return null;
      } finally {
        _release();
      }
    } on Object {
      _failed.add(key);
      return null;
    }
  }

  Future<void> _acquire() {
    if (_running < maxConcurrent) {
      _running++;
      return Future.value();
    }
    final waiter = Completer<void>();
    _waiting.add(waiter);
    return waiter.future;
  }

  void _release() {
    if (_waiting.isNotEmpty) {
      _waiting.removeFirst().complete(); // nhường chỗ cho lượt kế tiếp
    } else {
      _running--;
    }
  }
}
