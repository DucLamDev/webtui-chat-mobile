import '../data/ide_rpc_client.dart';
import '../domain/ide_errors.dart';
import '../domain/ide_insight_models.dart';
import '../domain/ide_log_models.dart';
import '../domain/ide_note_models.dart';
import '../domain/ide_task_models.dart';

/// Gọi các `op` của tab Thêm (việc, nhật ký, ghi chú, báo cáo, kiến trúc,
/// changelog) và trả mô hình đã đọc. Thao tác ★ do [IdeRpcClient] tự xử lý
/// `need_step`.
class IdeMoreService {
  IdeMoreService(this._rpc);

  final IdeRpcClient _rpc;

  // --- việc
  Future<IdeTaskList> tasks({String? project, bool mine = false}) async =>
      IdeTaskList.parse(
        await _rpc.call('tasks.list', {
          if (project != null && project.isNotEmpty) 'project': project,
          if (mine) 'mine': true,
        }),
      );

  Future<IdeTask> task(String id) async {
    final t = IdeTask.tryParse(await _rpc.call('tasks.get', {'id': id}));
    if (t == null) throw const IdeNotFound('Không tìm thấy việc này.');
    return t;
  }

  Future<IdeTask?> addTask({
    required String project,
    required String assignee,
    required String title,
    String? due,
    String detail = '',
    bool noAi = false,
  }) async => IdeTask.tryParse(
    await _rpc.call('tasks.add', {
      'project': project,
      'assignee': assignee,
      'title': title,
      if (due != null && due.isNotEmpty) 'due': due,
      if (detail.isNotEmpty) 'detail': detail,
      if (noAi) 'no_ai': true,
    }),
  );

  Future<void> setTaskStatus(String id, String status, {String note = ''}) =>
      _rpc.call('tasks.status', {
        'id': id,
        'status': status,
        if (note.isNotEmpty) 'note': note,
      });

  /// `due` = `""` để xoá hạn; `null` = không đổi.
  Future<void> editTask(
    String id, {
    String? title,
    String? due,
    String? assignee,
    String? detail,
  }) => _rpc.call('tasks.edit', {
    'id': id,
    'title': ?title,
    'due': ?due,
    'assignee': ?assignee,
    'detail': ?detail,
  });

  Future<void> deleteTask(String id) => _rpc.call('tasks.delete', {'id': id});

  Future<void> suggestTask(String id) => _rpc.call('tasks.suggest', {'id': id});

  // --- nhật ký
  Future<IdeAiLog> aiLog(String project) async =>
      IdeAiLog.parse(await _rpc.call('ailog.list', {'project': project}));

  Future<IdeOplogPage> oplog(
    String project, {
    int days = 7,
    double? before,
    List<String> kinds = const [],
    String q = '',
    int limit = 100,
  }) async => IdeOplogPage.parse(
    await _rpc.call('oplog.list', {
      'project': project,
      'days': days,
      'before': ?before,
      if (kinds.isNotEmpty) 'kinds': kinds,
      if (q.isNotEmpty) 'q': q,
      'limit': limit,
    }),
  );

  // --- ghi chú
  Future<IdeNoteList> notes(String project) async =>
      IdeNoteList.parse(await _rpc.call('notes.list', {'project': project}));

  Future<IdeNote> note(String project, String id) async {
    final n = IdeNote.tryParse(
      await _rpc.call('notes.read', {'project': project, 'id': id}),
    );
    if (n == null) throw const IdeNotFound('Không tìm thấy ghi chú này.');
    return n;
  }

  /// Trả `id` ghi chú mới.
  Future<String> createNote(String project, String title, String body) async {
    final data = await _rpc.call('notes.create', {
      'project': project,
      'title': title,
      'body': body,
    });
    return data is Map && data['id'] is String ? data['id'] as String : '';
  }

  /// Trả `sha` mới. Lệch `sha` → [IdeConflict].
  Future<String> saveNote(
    String project,
    String id,
    String sha,
    String title,
    String body,
  ) async {
    final data = await _rpc.call('notes.save', {
      'project': project,
      'id': id,
      'sha': sha,
      'title': title,
      'body': body,
    });
    return data is Map && data['sha'] is String ? data['sha'] as String : sha;
  }

  Future<void> deleteNote(String project, String id, String sha) =>
      _rpc.call('notes.delete', {'project': project, 'id': id, 'sha': sha});

  Future<List<IdeNoteVersion>> noteVersions(String project, String id) async =>
      IdeNoteVersion.parseList(
        await _rpc.call('notes.versions', {'project': project, 'id': id}),
      );

  Future<void> restoreNote(String project, String id, int n) =>
      _rpc.call('notes.restore', {'project': project, 'id': id, 'n': n});

  // --- báo cáo, kiến trúc, changelog
  /// Bắt đầu báo cáo, trả mã job.
  Future<String> startReport(String project, {bool ai = false}) async {
    final data = await _rpc.call('report.self', {
      'project': project,
      if (ai) 'ai': true,
    });
    final job = data is Map ? data['job'] : null;
    if (job is! String || job.isEmpty) {
      throw const IdeError('ide_error', 'IDE không trả mã việc.');
    }
    return job;
  }

  Future<IdeJobTail> jobTail(String job, int from) async => IdeJobTail.parse(
    await _rpc.call('jobs.tail', {'job': job, 'from': from}),
  );

  Future<IdeKientruc> kientruc(String project) async =>
      IdeKientruc.parse(await _rpc.call('kientruc.read', {'project': project}));

  Future<IdeKientrucCheck> kientrucCheck(String project) async =>
      IdeKientrucCheck.parse(
        await _rpc.call('kientruc.check', {'project': project}),
      );

  Future<IdeChangelog> changelog() async =>
      IdeChangelog.parse(await _rpc.call('changelog.read', const {}));
}
