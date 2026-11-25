import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import '../domain/ide_web_file.dart';
import '../domain/ide_web_ports.dart';

/// Ghi tệp vào thư mục tạm tên ngẫu nhiên rồi trao cho kênh `webtui/downloads`
/// (Android: thư mục Tải về; iOS: bảng chia sẻ).
final class PlatformIdeWebFileSaver implements IdeWebFileSaver {
  PlatformIdeWebFileSaver({
    MethodChannel channel = const MethodChannel('webtui/downloads'),
    Future<Directory> Function()? tempDir,
    Future<bool> Function(String path)? openFile,
    TargetPlatform? platform,
  }) : _channel = channel,
       _tempDir = tempDir ?? getTemporaryDirectory,
       _openFile = openFile ?? _open,
       _platform = platform ?? defaultTargetPlatform;

  final MethodChannel _channel;
  final Future<Directory> Function() _tempDir;
  final Future<bool> Function(String path) _openFile;
  final TargetPlatform _platform;
  final _dirs = <Directory>{};

  static Future<bool> _open(String path) async =>
      (await OpenFilex.open(path)).type == ResultType.done;

  @override
  Future<IdeWebFileSaveResult> save(
    IdeWebFile file, {
    required Future<bool> Function() confirmOpen,
  }) async {
    try {
      final dir = await (await _tempDir()).createTemp('ide-web-');
      _dirs.add(dir);
      final target = File('${dir.path}/${file.name}');
      await target.writeAsBytes(file.bytes, flush: true);
      if (_platform == TargetPlatform.iOS) {
        // Bảng chia sẻ còn đọc tệp sau khi hiện: xoá lúc đóng màn.
        await _channel.invokeMethod<void>('shareFile', {
          'path': target.path,
          'name': file.name,
        });
        return IdeWebFileSaveResult.saved;
      }
      final saved = await _channel.invokeMethod<bool>('saveToDownloads', {
        'path': target.path,
        'name': file.name,
        'mime': file.mime,
      });
      if (saved == true) {
        await _delete(dir);
        return IdeWebFileSaveResult.saved;
      }
      // Android dưới 10: hỏi rồi mở bằng ứng dụng khác.
      if (!await confirmOpen()) {
        await _delete(dir);
        return IdeWebFileSaveResult.cancelled;
      }
      return await _openFile(target.path)
          ? IdeWebFileSaveResult.saved
          : IdeWebFileSaveResult.failed;
    } on Object {
      return IdeWebFileSaveResult.failed;
    }
  }

  @override
  Future<void> disposeTemp() async {
    for (final dir in _dirs.toList()) {
      await _delete(dir);
    }
  }

  Future<void> _delete(Directory dir) async {
    _dirs.remove(dir);
    try {
      await dir.delete(recursive: true);
    } on Object {
      // Hệ điều hành tự dọn thư mục tạm.
    }
  }
}
