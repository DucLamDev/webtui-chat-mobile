import 'dart:async';

import '../data/ide_rpc_client.dart';
import '../domain/ide_errors.dart';
import '../domain/ide_file_models.dart';
import '../domain/ide_session_state.dart' show ideJsonInt;

/// Nội dung `files.read`.
final class IdeFileText {
  const IdeFileText({required this.text, required this.mtime, this.size = 0});
  final String text;
  final int mtime;
  final int size;
}

/// Một việc nền (`files.fetch` / `files.zip` / `files.office_pdf`) đã kết thúc.
final class IdeFileJobOutcome {
  const IdeFileJobOutcome({required this.status, this.path = ''});
  final String status;

  /// Tệp tạo ra (`result.path`), rỗng nếu không có.
  final String path;

  bool get ok => const {'done', 'ok', 'success', 'finished'}.contains(status);
  bool get cancelled => status == 'cancelled' || status == 'canceled';
}

bool ideJobFinished(String status) => const {
  'done',
  'ok',
  'success',
  'finished',
  'failed',
  'error',
  'cancelled',
  'canceled',
}.contains(status);

/// Các thao tác `files.*` của IDE. MỌI đường dẫn / tên đều được kiểm ở đây
/// trước khi gửi: tuyệt đối, không `..`; tên không có `/`, không rỗng.
class IdeFilesService {
  IdeFilesService(this._rpc);

  final IdeRpcClient _rpc;

  String _path(String path) {
    if (!ideIsSafePath(path)) {
      throw const IdeBadRequest('Đường dẫn không hợp lệ.');
    }
    return path;
  }

  String _name(String name) {
    if (ideCheckName(name) != null) {
      throw const IdeBadRequest('Tên không hợp lệ.');
    }
    return name;
  }

  Future<List<IdeFileEntry>> list(String dir, {bool hidden = false}) async {
    final data = await _rpc.call('files.list', {
      'path': _path(dir),
      if (hidden) 'hidden': true,
    });
    return parseIdeFileEntries(dir, data);
  }

  /// Kích cỡ + loại; dùng khi mở tệp từ kết quả tìm (chưa biết cỡ).
  Future<({int size, int mtime, bool secret})> stat(String path) async {
    final data = await _rpc.call('files.stat', {'path': _path(path)});
    final m = data is Map ? data : const {};
    return (
      size: ideJsonInt(m['size']) ?? 0,
      mtime: ideJsonInt(m['mtime']) ?? 0,
      secret: m['secret'] == true,
    );
  }

  Future<IdeFileText> read(String path) async {
    final data = await _rpc.call('files.read', {'path': _path(path)});
    final m = data is Map ? data : const {};
    return IdeFileText(
      text: m['text'] is String ? m['text'] as String : '',
      mtime: ideJsonInt(m['mtime']) ?? 0,
      size: ideJsonInt(m['size']) ?? 0,
    );
  }

  /// Trả `mtime` mới. `conflict` khi máy tính vừa sửa (trừ khi [force]).
  Future<int> write(
    String path,
    String text, {
    required int baseMtime,
    bool force = false,
  }) async {
    final data = await _rpc.call('files.write', {
      'path': _path(path),
      'text': text,
      'baseMtime': baseMtime,
      if (force) 'force': true,
    });
    return data is Map ? ideJsonInt(data['mtime']) ?? 0 : 0;
  }

  Future<String> mkdir(String dir, String name) async => _pathOf(
    await _rpc.call('files.mkdir', {'dir': _path(dir), 'name': _name(name)}),
  );

  Future<String> create(String dir, String name, {bool agents = false}) async =>
      _pathOf(
        await _rpc.call('files.create', {
          'dir': _path(dir),
          'name': _name(name),
          if (agents) 'template': 'agents',
        }),
      );

  Future<String> rename(String path, String name) async => _pathOf(
    await _rpc.call('files.rename', {'path': _path(path), 'name': _name(name)}),
  );

  Future<String> copy(String path, String destDir) async => _pathOf(
    await _rpc.call('files.copy', {
      'path': _path(path),
      'dest_dir': _path(destDir),
    }),
  );

  Future<String> move(String path, String destDir) async => _pathOf(
    await _rpc.call('files.move', {
      'path': _path(path),
      'dest_dir': _path(destDir),
    }),
  );

  /// Vào thùng rác; trả mã trong thùng.
  Future<String> delete(String path) async {
    final data = await _rpc.call('files.delete', {'path': _path(path)});
    return data is Map && data['id'] is String ? data['id'] as String : '';
  }

  Future<List<IdeTrashItem>> trash(String root) async =>
      parseIdeTrash(await _rpc.call('files.trash', {'root': _path(root)}));

  Future<String> restore(String id) async =>
      _pathOf(await _rpc.call('files.restore', {'id': id}));

  /// ★ cần vân tay: `need_step` do [IdeRpcClient] giao cho bộ xử lý bước.
  Future<void> purge(String id) async {
    await _rpc.call('files.purge', {'id': id});
  }

  /// ★ cần vân tay. Trả số mục đã xoá.
  Future<int> trashPurge(String root) async {
    final data = await _rpc.call('files.trash_purge', {'root': _path(root)});
    return data is Map ? ideJsonInt(data['count']) ?? 0 : 0;
  }

  Future<IdeSearchResult<IdeFindHit>> find(String root, String q) async =>
      parseIdeFind(
        await _rpc.call('files.find', {'root': _path(root), 'q': q}),
      );

  Future<IdeSearchResult<IdeGrepHit>> grep(
    String root,
    String q, {
    bool matchCase = false,
  }) async => ideCapGrep(
    parseIdeGrep(
      await _rpc.call('files.grep', {
        'root': _path(root),
        'q': q,
        if (matchCase) 'case': true,
      }),
    ),
  );

  /// `git diff HEAD` của cả dự án hoặc một tệp.
  Future<String> diff(String root, {String? path}) async {
    final data = await _rpc.call('files.diff', {
      'root': _path(root),
      'path': ?(path == null ? null : _path(path)),
    });
    return data is Map && data['diff'] is String ? data['diff'] as String : '';
  }

  /// Chỉ nhận `https://` có tên máy (hợp đồng GĐ2); IDE vẫn kiểm lại.
  Future<String> fetch(String dir, String url) async {
    final u = Uri.tryParse(url);
    if (u == null || u.scheme != 'https' || u.host.isEmpty) {
      throw const IdeBadRequest('Chỉ nhận liên kết https://');
    }
    return _jobOf(
      await _rpc.call('files.fetch', {'dir': _path(dir), 'url': url}),
    );
  }

  Future<String> zip(String path) async =>
      _jobOf(await _rpc.call('files.zip', {'path': _path(path)}));

  Future<String> officePdf(String path) async =>
      _jobOf(await _rpc.call('files.office_pdf', {'path': _path(path)}));

  /// Hỏi `jobs.list` một lượt: trạng thái + tệp tạo ra của [job].
  Future<({String status, String path})> jobState(String job) async {
    final data = await _rpc.call('jobs.list', const {});
    final items = data is Map ? data['items'] : null;
    if (items is List) {
      for (final e in items) {
        if (e is Map && e['job'] == job) {
          final r = e['result'];
          return (
            status: e['status'] is String ? e['status'] as String : '',
            path: r is Map && r['path'] is String ? r['path'] as String : '',
          );
        }
      }
    }
    return (status: '', path: '');
  }

  /// Tải tệp từ điện thoại lên thư mục [dir] (`files.put`); trả đường dẫn mới.
  Future<String> put(
    String dir,
    String name,
    Stream<List<int>> bytes, {
    required int size,
    String mime = 'application/octet-stream',
  }) async => _pathOf(
    await _rpc.upload('files.put', {
      'dir': _path(dir),
      'name': _name(name),
      'size': size,
      'mime': mime,
    }, bytes),
  );

  Future<void> cancelJob(String job) async {
    await _rpc.call('jobs.cancel', {'job': job});
  }

  String _pathOf(Object? data) {
    final p = data is Map && data['path'] is String
        ? data['path'] as String
        : '';
    return p;
  }

  String _jobOf(Object? data) {
    final j = data is Map && data['job'] is String ? data['job'] as String : '';
    if (j.isEmpty) {
      throw const IdeError('ide_error', 'Không nhận được mã việc.');
    }
    return j;
  }
}

/// Trần số dòng khớp của `files.grep` hiện trên app.
const ideGrepMaxHits = 2000;

/// Trần diff: số ký tự và số dòng.
const ideDiffMaxChars = 1000000;
const ideDiffMaxLines = 20000;

/// Chỉ giữ phần đầu của kết quả tìm chữ nếu quá [ideGrepMaxHits] (báo cắt).
IdeSearchResult<IdeGrepHit> ideCapGrep(IdeSearchResult<IdeGrepHit> r) {
  if (r.items.length <= ideGrepMaxHits) return r;
  return IdeSearchResult(r.items.sublist(0, ideGrepMaxHits), truncated: true);
}

/// Cắt diff quá dài: trả (các dòng, đã cắt?). Diff rỗng → không dòng.
(List<String>, bool) ideClipDiff(String diff) {
  if (diff.trim().isEmpty) return (const [], false);
  var clipped = false;
  var text = diff;
  if (text.length > ideDiffMaxChars) {
    // Cắt ở hết một dòng để không dở dang.
    final cut = text.lastIndexOf('\n', ideDiffMaxChars);
    text = text.substring(0, cut > 0 ? cut : ideDiffMaxChars);
    clipped = true;
  }
  var lines = text.split('\n');
  if (lines.length > ideDiffMaxLines) {
    lines = lines.sublist(0, ideDiffMaxLines);
    clipped = true;
  }
  return (lines, clipped);
}
