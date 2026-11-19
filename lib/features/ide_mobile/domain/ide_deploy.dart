import 'ide_project.dart';
import 'ide_session_state.dart' show ideJsonInt;

/// Bản xem trước chỉ dùng được trong chừng này thời gian (hợp đồng GĐ3).
const ideDeployPreviewMaxAge = Duration(minutes: 15);

/// Tên op theo kiểu dự án (`deploy.*` hay `my.*`).
final class IdeDeployOps {
  const IdeDeployOps._(this._prefix, this.run, this.sync);

  /// Dự án công ty (Git / VPS).
  const IdeDeployOps.company() : this._('deploy', 'deploy.run', false);

  /// Dự án riêng có Git: `my.deploy`.
  const IdeDeployOps.myGit() : this._('my', 'my.deploy', false);

  /// Dự án riêng không Git: `my.sync`.
  const IdeDeployOps.mySync() : this._('my', 'my.sync', true);

  factory IdeDeployOps.of(IdeProject p) {
    if (!p.my) return const IdeDeployOps.company();
    return p.isGit ? const IdeDeployOps.myGit() : const IdeDeployOps.mySync();
  }

  final String _prefix;

  /// Op chạy triển khai thật (★).
  final String run;

  /// Dự án riêng không Git: nút "Đồng bộ" thay "Triển khai".
  final bool sync;

  bool get isMy => _prefix == 'my';
  String get preview => '$_prefix.preview';
  String get pull => '$_prefix.pull';
  String get history => '$_prefix.history';
  String get rollback => '$_prefix.rollback';
  String get restore => '$_prefix.restore';
}

/// Một tệp trong bản xem trước. `s`: A mới, M sửa, D xoá, N máy chủ mới hơn
/// (sẽ bị ghi đè), P chỉ đổi quyền.
final class IdeDeployFile {
  const IdeDeployFile({required this.s, required this.path});

  final String s;
  final String path;
}

final class IdeDeployBase {
  const IdeDeployBase({this.commit = '', this.by = '', this.subject = ''});

  final String commit;
  final String by;
  final String subject;
}

/// "Bản xem trước chuẩn" (`result` của `deploy.preview` / `my.preview`).
final class IdeDeployPreview {
  const IdeDeployPreview({
    this.project = '',
    this.target = '',
    this.kind = '',
    this.sha = '',
    this.subject = '',
    this.base,
    this.files = const [],
    this.total = 0,
    this.truncated = false,
    this.diff = '',
    this.warnings = const [],
    this.deleteMany = false,
  });

  final String project;
  final String target;
  final String kind;
  final String sha;
  final String subject;
  final IdeDeployBase? base;
  final List<IdeDeployFile> files;
  final int total;
  final bool truncated;
  final String diff;
  final List<String> warnings;
  final bool deleteMany;

  /// Số tệp theo ký hiệu `s` (A / M / D / N / P).
  Map<String, int> get counts {
    final out = <String, int>{};
    for (final f in files) {
      out[f.s] = (out[f.s] ?? 0) + 1;
    }
    return out;
  }

  static IdeDeployPreview? tryParse(Object? raw) {
    if (raw is! Map) return null;
    String s(String k) => raw[k] is String ? raw[k] as String : '';
    final files = raw['files'];
    final warnings = raw['warnings'];
    final base = raw['base'];
    final parsed = [
      if (files is List)
        for (final f in files)
          if (f is Map && f['path'] is String)
            IdeDeployFile(
              s: f['s'] is String ? f['s'] as String : 'M',
              path: f['path'] as String,
            ),
    ];
    return IdeDeployPreview(
      project: s('project'),
      target: s('target'),
      kind: s('kind'),
      sha: s('sha'),
      subject: s('subject'),
      base: base is Map
          ? IdeDeployBase(
              commit: base['commit'] is String ? base['commit'] as String : '',
              by: base['by'] is String ? base['by'] as String : '',
              subject: base['subject'] is String
                  ? base['subject'] as String
                  : '',
            )
          : null,
      files: parsed,
      total: ideJsonInt(raw['total']) ?? parsed.length,
      truncated: raw['truncated'] == true,
      diff: s('diff'),
      warnings: [
        if (warnings is List)
          for (final w in warnings)
            if (w is String && w.isNotEmpty) w,
      ],
      deleteMany: raw['delete_many'] == true,
    );
  }
}

/// Bản xem trước đã chạy xong, nhớ lại để cho phép bấm Triển khai.
final class IdePreviewRecord {
  const IdePreviewRecord({
    required this.jobId,
    required this.project,
    required this.target,
    required this.at,
    required this.preview,
    this.used = false,
  });

  /// Mã job xem trước: gửi làm `preview` khi chạy thật.
  final String jobId;
  final String project;
  final String target;
  final DateTime at;
  final IdeDeployPreview preview;
  final bool used;

  IdePreviewRecord markUsed() => IdePreviewRecord(
    jobId: jobId,
    project: project,
    target: target,
    at: at,
    preview: preview,
    used: true,
  );
}

enum IdeDeployBlock {
  none,

  /// Chưa xem trước (hoặc xem trước chưa xong / lỗi).
  missing,

  /// Bản xem trước của dự án khác.
  otherProject,

  /// Bản xem trước của máy khác.
  otherTarget,

  /// Quá 15 phút.
  expired,

  /// Đã dùng một lần.
  used,
}

/// Luật hợp đồng: chỉ triển khai khi có bản xem trước xong ok, cùng dự án và
/// máy đích, chưa quá 15 phút, chưa dùng.
IdeDeployBlock ideDeployBlock(
  IdePreviewRecord? record, {
  required String project,
  required String target,
  required DateTime now,
}) {
  if (record == null) return IdeDeployBlock.missing;
  if (record.project != project) return IdeDeployBlock.otherProject;
  if (record.target != target) return IdeDeployBlock.otherTarget;
  if (record.used) return IdeDeployBlock.used;
  final age = now.difference(record.at);
  if (age >= ideDeployPreviewMaxAge || age.isNegative) {
    return IdeDeployBlock.expired;
  }
  return IdeDeployBlock.none;
}

/// Một dòng lịch sử triển khai (`deploy.history` / `my.history`).
final class IdeHistoryItem {
  const IdeHistoryItem({
    required this.id,
    this.at = 0,
    this.by = '',
    this.subject = '',
    this.stat = '',
  });

  final String id;
  final int at;
  final String by;
  final String subject;
  final String stat;

  static List<IdeHistoryItem> parseList(Object? data) {
    final items = data is Map ? data['items'] : null;
    if (items is! List) return const [];
    return [
      for (final e in items)
        if (e is Map && e['id'] is String && (e['id'] as String).isNotEmpty)
          IdeHistoryItem(
            id: e['id'] as String,
            at: ideJsonInt(e['at']) ?? 0,
            by: e['by'] is String ? e['by'] as String : '',
            subject: e['subject'] is String ? e['subject'] as String : '',
            stat: e['stat'] is String ? e['stat'] as String : '',
          ),
    ];
  }
}

/// `result` của lệnh chạy triển khai / gộp / tạo PR đã chuẩn hoá.
final class IdeRunResult {
  const IdeRunResult({this.ok = false, this.message = ''});

  final bool ok;
  final String message;

  static IdeRunResult parse(Object? raw) {
    if (raw is! Map) return const IdeRunResult();
    return IdeRunResult(
      ok: raw['ok'] == true,
      message: raw['message'] is String ? raw['message'] as String : '',
    );
  }
}

/// `result` của `pr.create`.
final class IdePrResult {
  const IdePrResult({
    this.number = 0,
    this.url,
    this.existed = false,
    this.warnings = const [],
  });

  final int number;
  final String? url;
  final bool existed;
  final List<String> warnings;

  static IdePrResult? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final n = ideJsonInt(raw['number']);
    if (n == null || n <= 0) return null;
    final w = raw['warnings'];
    return IdePrResult(
      number: n,
      url: raw['url'] is String && (raw['url'] as String).isNotEmpty
          ? raw['url'] as String
          : null,
      existed: raw['existed'] == true,
      warnings: [
        if (w is List)
          for (final e in w)
            if (e is String && e.isNotEmpty) e,
      ],
    );
  }
}

/// `result` của `git.merge`.
final class IdeMergeResult {
  const IdeMergeResult({
    this.queued = false,
    this.merged = false,
    this.message = '',
  });

  final bool queued;
  final bool merged;
  final String message;

  static IdeMergeResult parse(Object? raw) {
    if (raw is! Map) return const IdeMergeResult();
    return IdeMergeResult(
      queued: raw['queued'] == true,
      merged: raw['merged'] == true,
      message: raw['message'] is String ? raw['message'] as String : '',
    );
  }
}

/// Số PR hợp lệ (1–999999999) từ chữ người dùng nhập; sai thì `null`.
int? ideParsePrNumber(String text) {
  final t = text.trim().replaceFirst(RegExp(r'^#'), '');
  if (!RegExp(r'^[0-9]{1,9}$').hasMatch(t)) return null;
  final n = int.parse(t);
  return n >= 1 ? n : null;
}

/// Đường dẫn tương đối để khôi phục một tệp: không rỗng, không bắt đầu bằng
/// `/`, không có `..`, không ký tự điều khiển. Trả `null` nếu hợp lệ.
String? ideRelativePathError(String raw) {
  final p = raw.trim();
  if (p.isEmpty) return 'empty';
  if (p.startsWith('/') || p.startsWith('~') || p.contains('\\')) return 'abs';
  if (p.runes.any((c) => c < 0x20 || c == 0x7f)) return 'ctrl';
  if (p.split('/').any((s) => s == '..')) return 'dotdot';
  return null;
}
