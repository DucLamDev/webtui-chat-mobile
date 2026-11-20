import 'ide_session_state.dart' show ideJsonInt;

String _s(Map m, String k) => m[k] is String ? m[k] as String : '';
int _i(Map m, String k) => ideJsonInt(m[k]) ?? 0;

/// Một commit (`projects.info.last_commit`, `git.log.items`). `at` là giây Unix.
final class IdeCommit {
  const IdeCommit({
    required this.sha,
    required this.at,
    required this.by,
    required this.subject,
  });

  final String sha;
  final int at;
  final String by;
  final String subject;

  String get shortSha => sha.length > 7 ? sha.substring(0, 7) : sha;

  static IdeCommit? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final sha = _s(raw, 'sha');
    if (sha.isEmpty) return null;
    return IdeCommit(
      sha: sha,
      at: _i(raw, 'at'),
      by: _s(raw, 'by'),
      subject: _s(raw, 'subject'),
    );
  }
}

List<IdeCommit> parseIdeCommits(Object? data) {
  final items = data is Map ? data['items'] : null;
  if (items is! List) return const [];
  return [for (final e in items) ?IdeCommit.tryParse(e)];
}

/// `projects.info`.
final class IdeProjectInfo {
  const IdeProjectInfo({
    this.branch = '',
    this.ahead = 0,
    this.behind = 0,
    this.dirty = 0,
    this.lastCommit,
  });

  final String branch;
  final int ahead;
  final int behind;
  final int dirty;
  final IdeCommit? lastCommit;

  static IdeProjectInfo parse(Object? data) {
    if (data is! Map) return const IdeProjectInfo();
    return IdeProjectInfo(
      branch: _s(data, 'branch'),
      ahead: _i(data, 'ahead'),
      behind: _i(data, 'behind'),
      dirty: _i(data, 'dirty'),
      lastCommit: IdeCommit.tryParse(data['last_commit']),
    );
  }
}

/// Một tệp trong `git.status` (`x`, `y` một ký tự `M A D R ? .`).
final class IdeGitFile {
  const IdeGitFile({required this.x, required this.y, required this.path});

  final String x;
  final String y;
  final String path;

  /// Ký tự hiển thị: ưu tiên cột đã đổi (`y`), không có thì cột đã xếp (`x`).
  String get code => y != '.' && y.isNotEmpty ? y : (x.isEmpty ? '?' : x);
}

final class IdeGitStatus {
  const IdeGitStatus({this.files = const [], this.truncated = false});

  final List<IdeGitFile> files;
  final bool truncated;

  static IdeGitStatus parse(Object? data) {
    if (data is! Map) return const IdeGitStatus();
    final raw = data['files'];
    return IdeGitStatus(
      files: [
        if (raw is List)
          for (final f in raw)
            if (f is Map && _s(f, 'path').isNotEmpty)
              IdeGitFile(x: _s(f, 'x'), y: _s(f, 'y'), path: _s(f, 'path')),
      ],
      truncated: data['truncated'] == true,
    );
  }
}

/// Hàng kiểm tra của `to_git.check`.
enum IdeCheckLevel { ok, warn, bad }

final class IdeToGitRow {
  const IdeToGitRow({
    required this.level,
    required this.name,
    this.detail = '',
    this.fix = '',
  });

  final IdeCheckLevel level;
  final String name;
  final String detail;
  final String fix;
}

final class IdeToGitCheck {
  const IdeToGitCheck({
    this.repoName = '',
    this.rows = const [],
    this.files = 0,
    this.bytes = 0,
    this.ok = false,
  });

  final String repoName;
  final List<IdeToGitRow> rows;
  final int files;
  final int bytes;

  /// Chỉ khi `true` mới được chuyển sang Git.
  final bool ok;

  static IdeToGitCheck parse(Object? data) {
    if (data is! Map) return const IdeToGitCheck();
    final rows = data['rows'];
    return IdeToGitCheck(
      repoName: _s(data, 'repo_name'),
      rows: [
        if (rows is List)
          for (final r in rows)
            if (r is Map)
              IdeToGitRow(
                level: switch (_s(r, 'level')) {
                  'ok' => IdeCheckLevel.ok,
                  'warn' => IdeCheckLevel.warn,
                  _ => IdeCheckLevel.bad,
                },
                name: _s(r, 'name'),
                detail: _s(r, 'detail'),
                fix: _s(r, 'fix'),
              ),
      ],
      files: _i(data, 'files'),
      bytes: _i(data, 'bytes'),
      ok: data['ok'] == true,
    );
  }
}

/// Máy đích riêng (`targets.show`); không có mật khẩu / khoá.
final class IdeMyTarget {
  const IdeMyTarget({
    required this.ref,
    this.host = '',
    this.path = '',
    this.auto = false,
    this.last = '',
  });

  final String ref;
  final String host;
  final String path;
  final bool auto;
  final String last;

  static IdeMyTarget? parse(Object? data) {
    final t = data is Map ? data['target'] : null;
    if (t is! Map) return null;
    return IdeMyTarget(
      ref: _s(t, 'ref'),
      host: _s(t, 'host'),
      path: _s(t, 'path'),
      auto: t['auto'] == true,
      last: t['last'] == null ? '' : '${t['last']}',
    );
  }
}

/// Yêu cầu quyền máy chủ tạm (`vps.requests`).
final class IdeVpsRequest {
  const IdeVpsRequest({
    required this.id,
    required this.project,
    required this.target,
    required this.hours,
    required this.reason,
    required this.at,
    required this.status,
  });

  final String id;
  final String project;
  final String target;
  final int hours;
  final String reason;
  final int at;

  /// `pending` | `approved` | `rejected`.
  final String status;

  static List<IdeVpsRequest> parseList(Object? data) {
    final items = data is Map ? data['items'] : null;
    if (items is! List) return const [];
    return [
      for (final e in items)
        if (e is Map && '${e['id'] ?? ''}'.isNotEmpty)
          IdeVpsRequest(
            id: '${e['id']}',
            project: _s(e, 'project'),
            target: _s(e, 'target'),
            hours: _i(e, 'hours'),
            reason: _s(e, 'reason'),
            at: _i(e, 'at'),
            status: _s(e, 'status'),
          ),
    ];
  }
}

/// Kiểm lý do / số giờ xin quyền máy chủ tạm (hợp đồng: 1–8 giờ, 5–300 ký tự).
String? ideVpsRequestError({required int hours, required String reason}) {
  if (hours < 1 || hours > 8) return 'hours';
  final n = reason.trim().runes.length;
  if (n < 5 || n > 300) return 'reason';
  return null;
}
