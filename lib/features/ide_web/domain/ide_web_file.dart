import 'dart:convert';
import 'dart:typed_data';

/// Trần tệp `file.save` sau khi giải mã.
const ideWebMaxFileBytes = 10 * 1024 * 1024;

/// Đuôi cài đặt / chạy được / trang web / lối tắt: không lưu ra máy. Mã nguồn
/// (`js`, `sh`, `py`...) chỉ là chữ trên điện thoại nên không chặn.
const _blockedExtensions = {
  'aab',
  'apk',
  'apkm',
  'apks',
  'bat',
  'cmd',
  'com',
  'dmg',
  'exe',
  'hta',
  'htm',
  'html',
  'ipa',
  'jar',
  'lnk',
  'mht',
  'mhtml',
  'mobileconfig',
  'mobileprovision',
  'msi',
  'pkg',
  'ps1',
  'scr',
  'shtml',
  'svg',
  'svgz',
  'url',
  'vbs',
  'webloc',
  'xapk',
  'xht',
  'xhtml',
};

/// Trần tên tệp theo byte UTF-8 (hệ thống tệp chỉ cho 255).
const _maxNameBytes = 200;

const _blockedMimes = {
  'application/vnd.android.package-archive',
  'application/x-msdownload',
  'application/x-ms-dos-executable',
  'application/vnd.microsoft.portable-executable',
  'application/x-apple-aspen-config',
  'application/xhtml+xml',
  'image/svg+xml',
  'message/rfc822',
  'multipart/related',
  'text/html',
};

/// MIME theo đuôi, không tin MIME trang khai (Android tự thêm đuôi theo MIME).
const _mimeByExtension = {
  'csv': 'text/csv',
  'doc': 'application/msword',
  'docx':
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'gif': 'image/gif',
  'jpeg': 'image/jpeg',
  'jpg': 'image/jpeg',
  'json': 'application/json',
  'log': 'text/plain',
  'md': 'text/markdown',
  'mp3': 'audio/mpeg',
  'mp4': 'video/mp4',
  'pdf': 'application/pdf',
  'png': 'image/png',
  'pptx':
      'application/vnd.openxmlformats-officedocument.presentationml.presentation',
  'txt': 'text/plain',
  'webp': 'image/webp',
  'xls': 'application/vnd.ms-excel',
  'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  'zip': 'application/zip',
};

final _mimePattern = RegExp(
  r'^[a-z0-9][a-z0-9!#$&^_.+-]{0,63}/[a-z0-9][a-z0-9!#$&^_.+-]{0,63}$',
);

String ideWebExtension(String name) {
  final dot = name.lastIndexOf('.');
  return dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
}

/// Bỏ đường dẫn, ký tự điều khiển, ký tự định dạng Unicode (đảo chiều chữ như
/// U+202E, ẩn như U+200B), dấu chấm / cách ở hai đầu; giữ đuôi khi cắt ngắn.
String ideWebSafeFileName(String raw) {
  var name = raw.replaceAll('\\', '/').split('/').last;
  name = name.replaceAll(
    RegExp(
      r'[\u0000-\u001f\u007f-\u009f  <>:"|?*]|\p{Cf}|\p{Cs}',
      unicode: true,
    ),
    '',
  );
  name = _trimName(name);
  if (utf8.encode(name).length > _maxNameBytes) {
    final dot = name.lastIndexOf('.');
    final ext = dot > 0 && name.length - dot <= 12 ? name.substring(dot) : '';
    final room = _maxNameBytes - utf8.encode(ext).length;
    final base = ext.isEmpty ? name : name.substring(0, dot);
    final kept = StringBuffer();
    var used = 0;
    for (final rune in base.runes) {
      final char = String.fromCharCode(rune);
      used += utf8.encode(char).length;
      if (used > room) break;
      kept.write(char);
    }
    // Cắt xong có thể lộ dấu chấm cuối: bỏ lần nữa để đuôi xét đúng là đuôi lưu.
    name = _trimName('$kept$ext');
  }
  return name.isEmpty ? 'tep-vpsttt-ide' : name;
}

String _trimName(String name) =>
    name.replaceAll(RegExp(r'^[.\s]+'), '').replaceAll(RegExp(r'[.\s]+$'), '');

enum IdeWebFileIssue { malformed, blocked, tooLarge }

final class IdeWebFileException implements Exception {
  const IdeWebFileException(this.issue);

  final IdeWebFileIssue issue;
}

/// Tệp trang IDE nhờ lưu, đã kiểm tên, loại và cỡ.
final class IdeWebFile {
  const IdeWebFile._(this.name, this.mime, this.bytes);

  factory IdeWebFile.fromBridge({
    required String name,
    required String mime,
    required String dataBase64,
  }) {
    final normalizedMime = mime.trim().toLowerCase();
    if (name.isEmpty ||
        name.length > 1024 ||
        !_mimePattern.hasMatch(normalizedMime)) {
      throw const IdeWebFileException(IdeWebFileIssue.malformed);
    }
    final safe = ideWebSafeFileName(name);
    final extension = ideWebExtension(safe);
    if (_blockedExtensions.contains(extension) ||
        _blockedMimes.contains(normalizedMime)) {
      throw const IdeWebFileException(IdeWebFileIssue.blocked);
    }
    if (dataBase64.length > (ideWebMaxFileBytes + 2) ~/ 3 * 4) {
      throw const IdeWebFileException(IdeWebFileIssue.tooLarge);
    }
    final Uint8List bytes;
    try {
      bytes = base64.decode(dataBase64);
    } on FormatException {
      throw const IdeWebFileException(IdeWebFileIssue.malformed);
    }
    if (bytes.length > ideWebMaxFileBytes) {
      throw const IdeWebFileException(IdeWebFileIssue.tooLarge);
    }
    return IdeWebFile._(
      safe,
      _mimeByExtension[extension] ?? 'application/octet-stream',
      bytes,
    );
  }

  final String name;
  final String mime;
  final Uint8List bytes;

  @override
  String toString() => 'IdeWebFile(${bytes.length} byte)';
}
