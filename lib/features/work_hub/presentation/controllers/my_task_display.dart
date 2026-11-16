import 'package:webtui_chat/l10n/app_strings.dart';

import '../../../conversations/domain/entities/collaboration_room.dart';
import '../../application/use_cases/work_hub_use_cases.dart';

/// Nhóm theo hạn của việc chưa xong (thứ tự hiển thị).
enum TaskDueBucket { overdue, today, tomorrow, nextWeek, later, noDue }

DateTime _day(DateTime value) {
  final local = value.toLocal();
  return DateTime(local.year, local.month, local.day);
}

/// Hạn của việc so với [now] (giờ địa phương): quá hạn (trước lúc này), hôm
/// nay, ngày mai, trong 7 ngày tới, sau nữa, không hạn.
TaskDueBucket taskDueBucket(CollaborationTask task, DateTime now) {
  final due = task.dueAt;
  if (due == null) return TaskDueBucket.noDue;
  if (due.isBefore(now)) return TaskDueBucket.overdue;
  final days = _day(due).difference(_day(now)).inDays;
  if (days <= 0) return TaskDueBucket.today;
  if (days == 1) return TaskDueBucket.tomorrow;
  if (days <= 7) return TaskDueBucket.nextWeek;
  return TaskDueBucket.later;
}

String taskDueBucketTitle(TaskDueBucket bucket) {
  return switch (bucket) {
    TaskDueBucket.overdue => tr('Quá hạn', 'Overdue'),
    TaskDueBucket.today => tr('Hôm nay', 'Today'),
    TaskDueBucket.tomorrow => tr('Ngày mai', 'Tomorrow'),
    TaskDueBucket.nextWeek => tr('7 ngày tới', 'Next 7 days'),
    TaskDueBucket.later => tr('Sau này', 'Later'),
    TaskDueBucket.noDue => tr('Không có hạn', 'No due date'),
  };
}

/// Một nhóm việc trên màn Việc của tôi.
final class TaskSection {
  const TaskSection({
    required this.title,
    required this.tasks,
    this.overdue = false,
  });

  final String title;
  final List<CollaborationTask> tasks;

  /// Nhóm "Quá hạn": tiêu đề tô đỏ.
  final bool overdue;
}

/// Việc chưa xong chia theo hạn; trong nhóm: hạn gần trước, không hạn theo
/// ngày tạo mới nhất trước. Nhóm rỗng bỏ qua.
List<TaskSection> groupTasksByDue(List<CollaborationTask> tasks, DateTime now) {
  final buckets = <TaskDueBucket, List<CollaborationTask>>{};
  for (final task in tasks) {
    buckets.putIfAbsent(taskDueBucket(task, now), () => []).add(task);
  }
  return [
    for (final bucket in TaskDueBucket.values)
      if (buckets[bucket] case final list? when list.isNotEmpty)
        TaskSection(
          title: taskDueBucketTitle(bucket),
          overdue: bucket == TaskDueBucket.overdue,
          tasks: list
            ..sort((a, b) {
              final ad = a.dueAt;
              final bd = b.dueAt;
              if (ad != null && bd != null) return ad.compareTo(bd);
              return b.createdAt.compareTo(a.createdAt);
            }),
        ),
  ];
}

/// Việc đã xong chia theo ngày hoàn thành: Hôm nay, Hôm qua, Trước đó (mới
/// nhất trước).
List<TaskSection> groupDoneTasks(List<CollaborationTask> tasks, DateTime now) {
  final today = _day(now);
  final yesterday = today.subtract(const Duration(days: 1));
  final sorted = [...tasks]
    ..sort((a, b) {
      final ac = a.completedAt ?? a.updatedAt ?? a.createdAt;
      final bc = b.completedAt ?? b.updatedAt ?? b.createdAt;
      return bc.compareTo(ac);
    });
  final groups = <String, List<CollaborationTask>>{};
  for (final task in sorted) {
    final done = task.completedAt;
    final day = done == null ? null : _day(done);
    final title = day == null
        ? tr('Trước đó', 'Earlier')
        : !day.isBefore(today)
        ? tr('Hôm nay', 'Today')
        : !day.isBefore(yesterday)
        ? tr('Hôm qua', 'Yesterday')
        : tr('Trước đó', 'Earlier');
    groups.putIfAbsent(title, () => []).add(task);
  }
  return [
    for (final entry in groups.entries)
      TaskSection(title: entry.key, tasks: entry.value),
  ];
}

/// Kết quả tìm: chia theo trạng thái Chưa nhận / Đã nhận / Hoàn thành / Đã huỷ.
List<TaskSection> groupTasksByStatus(List<CollaborationTask> tasks) {
  final order = [
    (CollaborationTaskStatus.open, tr('Chưa nhận', 'Unclaimed')),
    (CollaborationTaskStatus.inProgress, tr('Đã nhận', 'Claimed')),
    (CollaborationTaskStatus.done, tr('Hoàn thành', 'Done')),
    (CollaborationTaskStatus.cancelled, tr('Đã huỷ', 'Cancelled')),
  ];
  return [
    for (final (status, title) in order)
      if (tasks.where((task) => task.taskStatus == status).toList()
          case final list when list.isNotEmpty)
        TaskSection(title: title, tasks: list),
  ];
}

String _two(int value) => value.toString().padLeft(2, '0');

/// Kiểu nhãn hạn: quá hạn (đỏ), gấp (hôm nay, vàng), thường (xám), xong (xanh).
enum TaskDueTone { overdue, soon, normal, done }

/// Nhãn hạn trên thẻ việc: "Quá hạn 2 ngày", "Hôm nay 17:00", "Ngày mai",
/// "Hạn 20/11"; việc xong: "Xong 14:20" / "Xong 12/11". Không hạn: null.
({String label, TaskDueTone tone})? taskDueLabel(
  CollaborationTask task,
  DateTime now,
) {
  if (task.taskStatus == CollaborationTaskStatus.done) {
    final done = task.completedAt?.toLocal();
    if (done == null) return null;
    final sameDay = _day(done) == _day(now);
    return (
      label: sameDay
          ? tr(
              'Xong ${_two(done.hour)}:${_two(done.minute)}',
              'Done ${_two(done.hour)}:${_two(done.minute)}',
            )
          : tr(
              'Xong ${_two(done.day)}/${_two(done.month)}',
              'Done ${_two(done.day)}/${_two(done.month)}',
            ),
      tone: TaskDueTone.done,
    );
  }
  final due = task.dueAt?.toLocal();
  if (due == null) return null;
  final time = '${_two(due.hour)}:${_two(due.minute)}';
  final hasTime = !(due.hour == 0 && due.minute == 0);
  switch (taskDueBucket(task, now)) {
    case TaskDueBucket.overdue:
      final days = _day(now).difference(_day(due)).inDays;
      return (
        label: days <= 0
            ? tr('Quá hạn từ $time', 'Overdue since $time')
            : tr('Quá hạn $days ngày', 'Overdue $days d'),
        tone: TaskDueTone.overdue,
      );
    case TaskDueBucket.today:
      return (
        label: hasTime
            ? tr('Hôm nay $time', 'Today $time')
            : tr('Hôm nay', 'Today'),
        tone: TaskDueTone.soon,
      );
    case TaskDueBucket.tomorrow:
      return (
        label: hasTime
            ? tr('Ngày mai $time', 'Tomorrow $time')
            : tr('Ngày mai', 'Tomorrow'),
        tone: TaskDueTone.normal,
      );
    case TaskDueBucket.nextWeek:
    case TaskDueBucket.later:
      return (
        label: tr(
          'Hạn ${_two(due.day)}/${_two(due.month)}',
          'Due ${_two(due.day)}/${_two(due.month)}',
        ),
        tone: TaskDueTone.normal,
      );
    case TaskDueBucket.noDue:
      return null;
  }
}

/// Số việc theo 3 ô lọc (Hoàn thành: xong trong 7 ngày qua, như thẻ ở tab
/// Công việc).
({int open, int inProgress, int done}) countMyTasks(
  List<CollaborationTask> tasks,
  DateTime now,
) {
  var open = 0;
  var inProgress = 0;
  var done = 0;
  for (final task in tasks) {
    switch (task.taskStatus) {
      case CollaborationTaskStatus.open:
        open++;
      case CollaborationTaskStatus.inProgress:
        inProgress++;
      case CollaborationTaskStatus.done:
        if (isRecentlyDone(task, now)) done++;
      case CollaborationTaskStatus.cancelled:
        break;
    }
  }
  return (open: open, inProgress: inProgress, done: done);
}
