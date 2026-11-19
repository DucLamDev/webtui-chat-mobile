import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import '../../../app/providers/foundation_providers.dart';
import '../data/ide_rpc_client.dart';

/// Tên tệp an toàn: bỏ đường dẫn (`../`, `/`, `\`), ký tự điều khiển, đuôi chấm.
String ideSafeFileName(String raw, {String fallback = 'tep-tai-ve'}) {
  var s = raw.replaceAll('\\', '/').split('/').last;
  // Ký tự điều khiển, định dạng Unicode (Cf: ẩn / đảo chiều chữ như U+202E,
  // U+200B, U+2066, U+FEFF), tách dòng / đoạn (U+2028, U+2029).
  s = s
      .replaceAll(
        RegExp(
          r'[\u0000-\u001f\u007f-\u009f\u2028\u2029<>:"|?*]|\p{Cf}',
          unicode: true,
        ),
        '',
      )
      .trim();
  while (s.startsWith('.')) {
    s = s.substring(1);
  }
  s = s.replaceAll(RegExp(r'\.+$'), '');
  if (s.length > 120) {
    final dot = s.lastIndexOf('.');
    final ext = dot > 0 && s.length - dot <= 12 ? s.substring(dot) : '';
    s = s.substring(0, 120 - ext.length) + ext;
  }
  return s.isEmpty ? fallback : s;
}

const _mimeByExt = <String, String>{
  'apk': 'application/vnd.android.package-archive',
  'pdf': 'application/pdf',
  'zip': 'application/zip',
  'txt': 'text/plain',
  'md': 'text/markdown',
  'json': 'application/json',
  'csv': 'text/csv',
  'log': 'text/plain',
  'png': 'image/png',
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'gif': 'image/gif',
  'webp': 'image/webp',
  'mp4': 'video/mp4',
  'mp3': 'audio/mpeg',
  'doc': 'application/msword',
  'docx':
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'xls': 'application/vnd.ms-excel',
  'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
};

/// MIME theo đuôi tệp (bảng nhỏ); không tin MIME do máy IDE khai.
String ideMimeFor(String name) {
  final dot = name.lastIndexOf('.');
  if (dot < 0) return 'application/octet-stream';
  return _mimeByExt[name.substring(dot + 1).toLowerCase()] ??
      'application/octet-stream';
}

/// Trần cứng một lần tải: 2 GB (điện thoại không nên nhận hơn; chặn IDE gửi vô hạn).
const ideDownloadMaxBytes = 2 * 1024 * 1024 * 1024;

/// Đuôi ảnh xem được ngay trong app.
bool ideIsImageName(String name) =>
    RegExp(r'\.(png|jpe?g|gif|webp|bmp)$', caseSensitive: false).hasMatch(name);

/// Lưu tệp đã tải vào chỗ người dùng lấy được.
abstract interface class IdeFileSaver {
  /// Trả về lời báo cho người dùng (null nếu không có gì để báo).
  ///
  /// [confirmOpen]: Android dưới 10 không lưu thẳng vào Tải về được; chỉ mở
  /// bằng ứng dụng khác khi người dùng đồng ý.
  Future<String?> save(
    File file,
    String name,
    String mime, {
    Future<bool> Function()? confirmOpen,
  });
}

class PlatformIdeFileSaver implements IdeFileSaver {
  const PlatformIdeFileSaver({
    MethodChannel channel = const MethodChannel('webtui/downloads'),
  }) : _channel = channel;

  final MethodChannel _channel;

  @override
  Future<String?> save(
    File file,
    String name,
    String mime, {
    Future<bool> Function()? confirmOpen,
  }) async {
    if (Platform.isIOS) {
      await _channel.invokeMethod<void>('shareFile', {
        'path': file.path,
        'name': name,
      });
      return null;
    }
    if (Platform.isAndroid) {
      final bool? saved;
      try {
        saved = await _channel.invokeMethod<bool>('saveToDownloads', {
          'path': file.path,
          'name': name,
          'mime': mime,
        });
      } on PlatformException catch (e) {
        // Đường dẫn ngoài thư mục app: báo lỗi, không đề nghị mở tệp.
        if (e.code == 'BAD_PATH') {
          return 'Không lưu được: tệp nằm ngoài thư mục của app';
        }
        rethrow;
      }
      if (saved == true) return ideSavedNote(name);
      // Android dưới 10: kênh native trả false. Không tự mở: hỏi trước.
      if (confirmOpen == null || !await confirmOpen()) {
        return 'Chưa lưu tệp này';
      }
      final r = await OpenFilex.open(file.path);
      return r.type == ResultType.done ? null : 'Không mở được tệp này';
    }
    return null;
  }
}

/// Lời báo sau khi lưu: chỉ tệp .apk mới nhắc cài đặt (kèm cảnh báo).
String ideSavedNote(String name) => name.toLowerCase().endsWith('.apk')
    ? 'Đã lưu vào Tải về. Chỉ cài tệp bạn tin tưởng (mở bằng ứng dụng Tệp).'
    : 'Đã lưu vào Tải về';

/// Một lượt tải: tiến độ, huỷ, kết quả.
class IdeDownload {
  IdeDownload._();

  final progress = _Progress();
  bool _cancelled = false;
  final _signal = Completer<void>();
  late final Future<IdeDownloadedFile> done;

  bool get cancelled => _cancelled;

  /// Dừng ngay với lỗi (vd vượt dung lượng): không chờ máy IDE ngừng gửi.
  void abort(Object error) {
    if (!_signal.isCompleted) _signal.completeError(error);
  }

  void cancel() {
    _cancelled = true;
    if (!_signal.isCompleted) _signal.complete();
  }
}

class _Progress {
  final _c = StreamController<double?>.broadcast();
  double? value;
  Stream<double?> get stream => _c.stream;
  void set(double? v) {
    value = v;
    if (!_c.isClosed) _c.add(v);
  }

  void close() => _c.close();
}

class IdeDownloadedFile {
  const IdeDownloadedFile({
    required this.file,
    required this.name,
    required this.mime,
    required this.size,
  });
  final File file;
  final String name;
  final String mime;
  final int size;
}

class IdeDownloadCancelled implements Exception {
  const IdeDownloadCancelled();
}

class IdeDownloadTooLarge implements Exception {
  const IdeDownloadTooLarge();
}

class IdeDownloadService {
  IdeDownloadService(
    this._rpc, {
    IdeFileSaver saver = const PlatformIdeFileSaver(),
    Future<Directory> Function()? tempDir,
  }) : _saver = saver,
       _tempDir = tempDir ?? getTemporaryDirectory;

  final IdeRpcClient _rpc;
  final IdeFileSaver _saver;
  final Future<Directory> Function() _tempDir;

  /// Tải [path] trên máy IDE về tệp tạm của app. Huỷ → xoá tệp dở.
  IdeDownload start(String path, {String? name, int? maxBytes}) {
    final d = IdeDownload._();
    final cap = (maxBytes ?? ideDownloadMaxBytes).clamp(0, ideDownloadMaxBytes);
    d.done = _run(d, path, name, cap);
    return d;
  }

  Future<IdeDownloadedFile> _run(
    IdeDownload d,
    String path,
    String? name,
    int cap,
  ) async {
    final dir = await (await _tempDir()).createTemp('ide-dl-');
    final fileName = ideSafeFileName(name ?? path);
    final file = File('${dir.path}/$fileName');
    final sink = _FileSink(file, d, cap);
    try {
      final result = await Future.any<IdeDownloadResult?>([
        _rpc.download('files.get', {'path': path}, sink: sink),
        d._signal.future.then((_) => null),
      ]);
      if (result == null || d.cancelled) throw const IdeDownloadCancelled();
      // Máy khách không chờ sink.close: tự chờ ghi xong rồi mới coi là đã tải.
      await sink.close(ok: true);
      return IdeDownloadedFile(
        file: file,
        name: fileName,
        mime: ideMimeFor(fileName),
        size: result.size,
      );
    } on Object {
      // Đóng sink (kể cả khi đang ghi dở) rồi mới xoá thư mục tạm.
      try {
        await sink.close(ok: false);
      } on Object {
        // bỏ qua
      }
      await _cleanup(dir);
      rethrow;
    } finally {
      d.progress.close();
    }
  }

  Future<void> _cleanup(Directory dir) async {
    try {
      await dir.delete(recursive: true);
    } on Object {
      // Dọn tệp tạm không được thì để hệ điều hành dọn.
    }
  }

  /// Lưu / chia sẻ tệp đã tải; trả lời báo cho người dùng.
  Future<String?> save(
    IdeDownloadedFile f, {
    Future<bool> Function()? confirmOpen,
  }) => _saver.save(f.file, f.name, f.mime, confirmOpen: confirmOpen);

  /// Xoá thư mục tạm `ide-dl-*` của một tệp đã tải (sau khi lưu / xem xong).
  Future<void> discard(IdeDownloadedFile f) async {
    // iOS: bảng chia sẻ còn đọc tệp sau khi hiện; để hệ điều hành dọn thư mục tạm.
    if (Platform.isIOS) return;
    final dir = f.file.parent;
    if (dir.path.contains('ide-dl-')) await _cleanup(dir);
  }
}

class _FileSink implements IdeFileSink {
  _FileSink(this.file, this.d, this.cap);

  final int cap;

  final File file;
  final IdeDownload d;
  IOSink? _out;
  Future<void>? _closing;
  int _got = 0;
  int _total = 0;

  @override
  void onMeta(Map<String, Object?> meta) {
    final s = meta['size'];
    _total = s is num ? s.toInt() : 0;
    if (_total > cap) d.abort(const IdeDownloadTooLarge());
    d.progress.set(_total > 0 ? 0 : null);
  }

  @override
  Future<void> add(List<int> bytes) async {
    if (d.cancelled) {
      throw const IdeDownloadCancelled();
    }
    // Vượt dung lượng đã khai hoặc trần: dừng, xoá tệp dở.
    if (_total > cap) throw const IdeDownloadTooLarge();
    if (_got + bytes.length > cap ||
        (_total > 0 && _got + bytes.length > _total)) {
      d.abort(const IdeDownloadTooLarge());
      await close(ok: false);
      throw const IdeDownloadTooLarge();
    }
    _out ??= file.openWrite();
    _out!.add(bytes);
    _got += bytes.length;
    if (_total > 0) d.progress.set((_got / _total).clamp(0, 1).toDouble());
  }

  @override
  Future<void> close({required bool ok}) {
    return _closing ??= _close(ok);
  }

  Future<void> _close(bool ok) async {
    if (ok && _out == null) {
      // Tệp rỗng: chưa có khúc nào nên chưa tạo tệp.
      try {
        await file.create();
      } on Object {
        // để lưu báo lỗi
      }
    }
    final out = _out;
    _out = null;
    if (out != null) await out.close();
    if (!ok && file.existsSync()) {
      try {
        file.deleteSync();
      } on Object {
        // bỏ qua
      }
    }
  }
}

final ideDownloadServiceProvider = Provider<IdeDownloadService>(
  (ref) => IdeDownloadService(ref.watch(ideRpcClientProvider)),
);
