import 'ide_more_time.dart';

/// Trạng thái việc theo hợp đồng: `todo` / `doing` / `done`.
const ideTaskStatuses = ['todo', 'doing', 'done'];

final _taskId = RegExp(r'^[0-9a-f]{10}$');

/// `id` việc hợp lệ (10 hex); dùng kiểm đường dẫn `/ide/tasks/:id`.
bool isIdeTaskId(String? id) => id != null && _taskId.hasMatch(id);

String _s(Object? v) => v is String ? v : '';

enum IdeSuggestionState { off, queued, running, done, error }

final class IdeTaskSuggestion {
  const IdeTaskSuggestion({
    required this.state,
    this.text = '',
    this.error = '',
  });

  final IdeSuggestionState state;
  final String text;
  final String error;

  /// Còn chạy nền: app phải tải lại `tasks.get` tiếp.
  bool get pending =>
      state == IdeSuggestionState.queued || state == IdeSuggestionState.running;

  static IdeTaskSuggestion? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final state = switch (raw['state']) {
      'queued' => IdeSuggestionState.queued,
      'running' => IdeSuggestionState.running,
      'done' => IdeSuggestionState.done,
      'error' => IdeSuggestionState.error,
      _ => IdeSuggestionState.off,
    };
    return IdeTaskSuggestion(
      state: state,
      text: _s(raw['text']),
      error: _s(raw['error']),
    );
  }
}

final class IdeTask {
  const IdeTask({
    required this.id,
    required this.project,
    required this.title,
    this.detail = '',
    this.assignee = '',
    this.by = '',
    this.created,
    this.updated,
    this.due,
    this.status = 'todo',
    this.note = '',
    this.doneAt,
    this.suggestion,
    this.canManage = false,
    this.mine = false,
  });

  final String id;
  final String project;
  final String title;
  final String detail;
  final String assignee;
  final String by;
  final DateTime? created;
  final DateTime? updated;

  /// `YYYY-MM-DD` hoặc `null` (không hạn).
  final String? due;
  final String status;
  final String note;
  final DateTime? doneAt;
  final IdeTaskSuggestion? suggestion;
  final bool canManage;
  final bool mine;

  bool get isDone => status == 'done';

  static IdeTask? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final id = _s(raw['id']);
    if (!isIdeTaskId(id)) return null;
    final status = _s(raw['status']);
    final due = raw['due'];
    return IdeTask(
      id: id,
      project: _s(raw['project']),
      title: _s(raw['title']),
      detail: _s(raw['detail']),
      assignee: _s(raw['assignee']),
      by: _s(raw['by']),
      created: ideTimeFromSeconds(raw['created']),
      updated: ideTimeFromSeconds(raw['updated']),
      due: ideParseDue(due) == null ? null : due as String,
      status: ideTaskStatuses.contains(status) ? status : 'todo',
      note: _s(raw['note']),
      doneAt: ideTimeFromSeconds(raw['done_at']),
      suggestion: IdeTaskSuggestion.tryParse(raw['suggestion']),
      canManage: raw['can_manage'] == true,
      mine: raw['mine'] == true,
    );
  }
}

final class IdeAssignable {
  const IdeAssignable({
    this.members = const [],
    this.lead = '',
    this.deputies = const [],
  });

  final List<String> members;
  final String lead;
  final List<String> deputies;
}

final class IdeTaskList {
  const IdeTaskList({
    this.viewer = '',
    this.admin = false,
    this.assignable = const {},
    this.tasks = const [],
  });

  final String viewer;
  final bool admin;
  final Map<String, IdeAssignable> assignable;
  final List<IdeTask> tasks;

  /// Dự án người này được thêm việc vào.
  List<String> get projects => assignable.keys.toList()..sort();

  /// Người nhận của [project]; luôn có chính mình để thêm việc cho bản thân.
  List<String> assigneesOf(String project) {
    final a = assignable[project];
    final set = <String>{
      if (viewer.isNotEmpty) viewer,
      ...?a?.members,
      if (a != null && a.lead.isNotEmpty) a.lead,
      ...?a?.deputies,
    };
    return set.toList();
  }

  static IdeTaskList parse(Object? data) {
    if (data is! Map) return const IdeTaskList();
    final assignable = <String, IdeAssignable>{};
    final rawA = data['assignable'];
    if (rawA is Map) {
      for (final e in rawA.entries) {
        final v = e.value;
        if (v is! Map) continue;
        List<String> strs(Object? l) => [
          if (l is List)
            for (final x in l)
              if (x is String && x.isNotEmpty) x,
        ];
        assignable[e.key.toString()] = IdeAssignable(
          members: strs(v['members']),
          lead: _s(v['lead']),
          deputies: strs(v['deputies']),
        );
      }
    }
    final rawT = data['tasks'];
    return IdeTaskList(
      viewer: _s(data['viewer']),
      admin: data['admin'] == true,
      assignable: assignable,
      tasks: [
        if (rawT is List)
          for (final t in rawT) ?IdeTask.tryParse(t),
      ],
    );
  }
}

/// Lọc theo trạng thái (`null` = tất cả), việc chưa xong lên trước, rồi hạn
/// gần trước (không hạn sau cùng), rồi mới cập nhật trước.
List<IdeTask> filterAndSortTasks(List<IdeTask> tasks, String? status) {
  final list = [
    for (final t in tasks)
      if (status == null || t.status == status) t,
  ];
  list.sort((a, b) {
    if (a.isDone != b.isDone) return a.isDone ? 1 : -1;
    final ad = a.due;
    final bd = b.due;
    if (ad != bd) {
      if (ad == null) return 1;
      if (bd == null) return -1;
      return ad.compareTo(bd);
    }
    final au = a.updated?.millisecondsSinceEpoch ?? 0;
    final bu = b.updated?.millisecondsSinceEpoch ?? 0;
    return bu.compareTo(au);
  });
  return list;
}

/// Nội dung chép sang phiên AI khi "Giao cho AI".
String ideTaskAiPrompt(IdeTask t) {
  final b = StringBuffer('Hãy làm việc sau trong dự án ${t.project}:\n')
    ..writeln(t.title);
  if (t.detail.trim().isNotEmpty) b.writeln('\nChi tiết:\n${t.detail.trim()}');
  if (t.due != null) b.writeln('\nHạn: ${ideDueDisplay(t.due!)}');
  return b.toString().trim();
}
