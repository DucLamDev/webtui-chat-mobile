import 'ide_session_state.dart' show ideJsonInt;

/// Trần xem / sửa chữ trong app (khớp `too_large` của `files.read`): 3 MB.
const ideFileTextMaxBytes = 3 * 1024 * 1024;

enum IdeEntryType { file, dir, link }

/// Một dòng của `files.list`.
final class IdeFileEntry {
  const IdeFileEntry({
    required this.type,
    required this.name,
    required this.path,
    this.size = 0,
    this.mtime = 0,
    this.secret = false,
    this.git = '',
  });

  final IdeEntryType type;
  final String name;

  /// Đường dẫn tuyệt đối = thư mục đang xem + tên (app tự ghép).
  final String path;
  final int size;
  final int mtime;
  final bool secret;

  /// `M` sửa, `A` mới, `D` xoá, `?` chưa theo dõi, `R` đổi tên; rỗng = sạch.
  final String git;

  bool get isDir => type == IdeEntryType.dir;
  bool get isHidden => name.startsWith('.');
}

/// Kết quả `files.list`: bỏ dòng có tên không hợp lệ (có `/`, `..`).
List<IdeFileEntry> parseIdeFileEntries(String dir, Object? data) {
  final items = data is Map ? data['items'] : null;
  if (items is! List) return const [];
  final out = <IdeFileEntry>[];
  for (final e in items) {
    if (e is! Map) continue;
    final name = e['name'];
    if (name is! String || ideCheckName(name) != null) continue;
    final path = ideJoinPath(dir, name);
    if (path == null) continue;
    final t = e['t'];
    out.add(
      IdeFileEntry(
        type: t == 'd'
            ? IdeEntryType.dir
            : t == 'l'
            ? IdeEntryType.link
            : IdeEntryType.file,
        name: name,
        path: path,
        size: ideJsonInt(e['size']) ?? 0,
        mtime: ideJsonInt(e['mtime']) ?? 0,
        secret: e['secret'] == true,
        git: e['git'] is String ? e['git'] as String : '',
      ),
    );
  }
  return out;
}

/// Một mục trong thùng rác (`files.trash`).
final class IdeTrashItem {
  const IdeTrashItem({
    required this.id,
    required this.path,
    required this.name,
    required this.isDir,
    required this.size,
    required this.deletedAt,
  });

  final String id;
  final String path;
  final String name;
  final bool isDir;
  final int size;
  final DateTime? deletedAt;
}

List<IdeTrashItem> parseIdeTrash(Object? data) {
  final items = data is Map ? data['items'] : null;
  if (items is! List) return const [];
  return [
    for (final e in items)
      if (e is Map && e['id'] is String && (e['id'] as String).isNotEmpty)
        IdeTrashItem(
          id: e['id'] as String,
          path: e['path'] is String ? e['path'] as String : '',
          name: e['name'] is String ? e['name'] as String : '',
          isDir: e['t'] == 'd',
          size: ideJsonInt(e['size']) ?? 0,
          deletedAt: ideJsonInt(e['deleted_at']) == null
              ? null
              : DateTime.fromMillisecondsSinceEpoch(
                  ideJsonInt(e['deleted_at'])!,
                ),
        ),
  ];
}

/// Kết quả `files.find` (theo tên).
final class IdeFindHit {
  const IdeFindHit({
    required this.path,
    required this.name,
    this.isDir = false,
  });
  final String path;
  final String name;
  final bool isDir;
}

/// Kết quả `files.grep` (theo chữ): dòng tính từ 1.
final class IdeGrepHit {
  const IdeGrepHit({
    required this.path,
    required this.line,
    required this.text,
  });
  final String path;
  final int line;
  final String text;
}

final class IdeSearchResult<T> {
  const IdeSearchResult(this.items, {this.truncated = false});
  final List<T> items;
  final bool truncated;
}

IdeSearchResult<IdeFindHit> parseIdeFind(Object? data) {
  final items = data is Map ? data['items'] : null;
  return IdeSearchResult([
    if (items is List)
      for (final e in items)
        if (e is Map &&
            e['path'] is String &&
            ideHasNoDotDot(e['path'] as String))
          IdeFindHit(
            path: e['path'] as String,
            name: e['name'] is String
                ? e['name'] as String
                : ideBaseName(e['path'] as String),
            isDir: e['t'] == 'd',
          ),
  ], truncated: data is Map && data['truncated'] == true);
}

IdeSearchResult<IdeGrepHit> parseIdeGrep(Object? data) {
  final items = data is Map ? data['items'] : null;
  return IdeSearchResult([
    if (items is List)
      for (final e in items)
        if (e is Map &&
            e['path'] is String &&
            ideHasNoDotDot(e['path'] as String))
          IdeGrepHit(
            path: e['path'] as String,
            line: ideJsonInt(e['line']) ?? 1,
            text: e['text'] is String ? e['text'] as String : '',
          ),
  ], truncated: data is Map && data['truncated'] == true);
}

// ---- Tên và đường dẫn ----

/// Lý do tên không hợp lệ; `null` = dùng được.
enum IdeNameError { empty, slash, dots, control, tooLong }

/// Tên mới: không rỗng, không `/` `\`, không NUL / ký tự điều khiển, không
/// phải `.` / `..`, ≤ 255 byte.
IdeNameError? ideCheckName(String name) {
  if (name.trim().isEmpty) return IdeNameError.empty;
  if (name == '.' || name == '..') return IdeNameError.dots;
  if (name.contains('/') || name.contains('\\')) return IdeNameError.slash;
  if (RegExp(r'[\u0000-\u001f\u007f]').hasMatch(name)) {
    return IdeNameError.control;
  }
  if (_utf8Length(name) > 255) return IdeNameError.tooLong;
  return null;
}

int _utf8Length(String s) {
  var n = 0;
  for (final r in s.runes) {
    n += r < 0x80
        ? 1
        : r < 0x800
        ? 2
        : r < 0x10000
        ? 3
        : 4;
  }
  return n;
}

/// Không có đoạn `..` (cũng chặn `\` ngăn cách) và không có NUL.
bool ideHasNoDotDot(String path) {
  if (path.contains('\u0000')) return false;
  return !path.replaceAll('\\', '/').split('/').contains('..');
}

/// Đường dẫn gửi lên IDE: tuyệt đối, không `..`, không NUL.
bool ideIsSafePath(String path) => path.startsWith('/') && ideHasNoDotDot(path);

/// Ghép thư mục + tên đã kiểm; `null` nếu tên hay thư mục không hợp lệ.
String? ideJoinPath(String dir, String name) {
  if (!ideIsSafePath(dir) || ideCheckName(name) != null) return null;
  final base = dir.endsWith('/') ? dir.substring(0, dir.length - 1) : dir;
  return '$base/$name';
}

String ideBaseName(String path) {
  final p = path.endsWith('/') && path.length > 1
      ? path.substring(0, path.length - 1)
      : path;
  final i = p.lastIndexOf('/');
  return i < 0 ? p : p.substring(i + 1);
}

String ideParentPath(String path) {
  final p = path.endsWith('/') && path.length > 1
      ? path.substring(0, path.length - 1)
      : path;
  final i = p.lastIndexOf('/');
  return i <= 0 ? '/' : p.substring(0, i);
}

/// `path` nằm trong (hoặc bằng) `root`.
bool ideIsInside(String root, String path) {
  final r = root.endsWith('/') ? root.substring(0, root.length - 1) : root;
  return path == r || path.startsWith('$r/');
}

/// Các mắt breadcrumb từ [root] tới [path]: (nhãn, đường dẫn). Mắt đầu là
/// thư mục gốc dự án (nhãn = [rootLabel]).
List<(String, String)> ideBreadcrumbs(
  String root,
  String path, {
  String? rootLabel,
}) {
  final r = root.endsWith('/') && root.length > 1
      ? root.substring(0, root.length - 1)
      : root;
  final crumbs = <(String, String)>[(rootLabel ?? ideBaseName(r), r)];
  if (!ideIsInside(r, path) || path == r) return crumbs;
  var acc = r;
  for (final part in path.substring(r.length + 1).split('/')) {
    if (part.isEmpty) continue;
    acc = '$acc/$part';
    crumbs.add((part, acc));
  }
  return crumbs;
}

// ---- Loại tệp ----

enum IdeFileKind { code, markdown, image, video, pdf, office, other }

String _ext(String name) {
  final i = name.lastIndexOf('.');
  return i <= 0 ? '' : name.substring(i + 1).toLowerCase();
}

IdeFileKind ideFileKindOf(String name) {
  final e = _ext(name);
  if (const {'md', 'markdown'}.contains(e)) return IdeFileKind.markdown;
  if (const {'png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp'}.contains(e)) {
    return IdeFileKind.image;
  }
  if (const {'mp4', 'mov', 'm4v', 'webm', 'mkv'}.contains(e)) {
    return IdeFileKind.video;
  }
  if (e == 'pdf') return IdeFileKind.pdf;
  if (const {'docx', 'xlsx', 'pptx', 'doc', 'xls', 'ppt', 'odt'}.contains(e)) {
    return IdeFileKind.office;
  }
  if (const {
    'zip',
    'gz',
    'tar',
    'rar',
    '7z',
    'apk',
    'exe',
    'bin',
    'so',
    'ico',
    'mp3',
    'wav',
    'woff',
    'woff2',
    'ttf',
    'otf',
    'class',
    'jar',
  }.contains(e)) {
    return IdeFileKind.other;
  }
  return IdeFileKind.code;
}

/// Tên ngôn ngữ của bộ tô màu theo đuôi / tên tệp; rỗng = chữ thường.
String ideLanguageFor(String name) {
  final lower = name.toLowerCase();
  if (lower == 'dockerfile') return 'dockerfile';
  if (lower == 'makefile') return 'makefile';
  return switch (_ext(name)) {
    'dart' => 'dart',
    'js' || 'mjs' || 'cjs' || 'jsx' => 'javascript',
    'ts' || 'tsx' => 'typescript',
    'json' => 'json',
    'yaml' || 'yml' => 'yaml',
    'go' => 'go',
    'py' => 'python',
    'rs' => 'rust',
    'java' => 'java',
    'kt' || 'kts' => 'kotlin',
    'swift' => 'swift',
    'c' || 'h' => 'c',
    'cc' || 'cpp' || 'hpp' => 'cpp',
    'cs' => 'csharp',
    'php' => 'php',
    'rb' => 'ruby',
    'sh' || 'bash' || 'zsh' => 'bash',
    'sql' => 'sql',
    'html' || 'htm' || 'xml' || 'svg' || 'vue' => 'xml',
    'css' => 'css',
    'scss' => 'scss',
    'md' || 'markdown' => 'markdown',
    'toml' || 'ini' || 'conf' => 'ini',
    _ => '',
  };
}

// ---- Diff ----

enum IdeDiffLineKind { add, remove, hunk, header, context }

IdeDiffLineKind ideDiffLineKind(String line) {
  if (line.startsWith('+++') ||
      line.startsWith('---') ||
      line.startsWith('diff ') ||
      line.startsWith('index ') ||
      line.startsWith('new file') ||
      line.startsWith('deleted file') ||
      line.startsWith('similarity') ||
      line.startsWith('rename ')) {
    return IdeDiffLineKind.header;
  }
  if (line.startsWith('@@')) return IdeDiffLineKind.hunk;
  if (line.startsWith('+')) return IdeDiffLineKind.add;
  if (line.startsWith('-')) return IdeDiffLineKind.remove;
  return IdeDiffLineKind.context;
}
