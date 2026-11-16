import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/features/conversations/domain/entities/collaboration_room.dart';
import 'package:webtui_chat/features/work_hub/presentation/controllers/my_task_display.dart';

import '../work_hub_fakes.dart';

void main() {
  final now = DateTime(2026, 11, 16, 10, 30);

  CollaborationTask open(String id, {DateTime? due}) =>
      fakeTask(id, id, CollaborationTaskStatus.open, dueAt: due);

  test(
    'hạn: quá hạn / hôm nay / ngày mai / 7 ngày tới / sau này / không hạn',
    () {
      expect(
        taskDueBucket(open('a', due: DateTime(2026, 11, 16, 9)), now),
        TaskDueBucket.overdue,
      );
      expect(
        taskDueBucket(open('b', due: DateTime(2026, 11, 14)), now),
        TaskDueBucket.overdue,
      );
      expect(
        taskDueBucket(open('c', due: DateTime(2026, 11, 16, 17)), now),
        TaskDueBucket.today,
      );
      expect(
        taskDueBucket(open('d', due: DateTime(2026, 11, 17, 8)), now),
        TaskDueBucket.tomorrow,
      );
      expect(
        taskDueBucket(open('e', due: DateTime(2026, 11, 23, 8)), now),
        TaskDueBucket.nextWeek,
      );
      expect(
        taskDueBucket(open('f', due: DateTime(2026, 11, 24, 8)), now),
        TaskDueBucket.later,
      );
      expect(taskDueBucket(open('g'), now), TaskDueBucket.noDue);
    },
  );

  test(
    'chia nhóm theo hạn: đúng thứ tự, hạn gần trước, Quá hạn được đánh dấu',
    () {
      final sections = groupTasksByDue([
        open('sau', due: DateTime(2026, 12, 1)),
        open('khong-han'),
        open('qua-han-2', due: DateTime(2026, 11, 15, 8)),
        open('hom-nay', due: DateTime(2026, 11, 16, 17)),
        open('qua-han-1', due: DateTime(2026, 11, 10)),
      ], now);
      expect(sections.map((s) => s.title), [
        'Quá hạn',
        'Hôm nay',
        'Sau này',
        'Không có hạn',
      ]);
      expect(sections.first.overdue, isTrue);
      expect(sections.first.tasks.map((t) => t.id), ['qua-han-1', 'qua-han-2']);
      expect(sections[1].overdue, isFalse);
      expect(groupTasksByDue(const [], now), isEmpty);
    },
  );

  test('việc xong chia Hôm nay / Hôm qua / Trước đó, mới nhất trước', () {
    final sections = groupDoneTasks([
      fakeTask(
        'cu',
        'cu',
        CollaborationTaskStatus.done,
        completedAt: DateTime(2026, 11, 12),
      ),
      fakeTask(
        'nay',
        'nay',
        CollaborationTaskStatus.done,
        completedAt: DateTime(2026, 11, 16, 9),
      ),
      fakeTask(
        'qua',
        'qua',
        CollaborationTaskStatus.done,
        completedAt: DateTime(2026, 11, 15, 20),
      ),
    ], now);
    expect(sections.map((s) => s.title), ['Hôm nay', 'Hôm qua', 'Trước đó']);
  });

  test('nhãn hạn trên thẻ việc', () {
    String? label(CollaborationTask task) => taskDueLabel(task, now)?.label;
    TaskDueTone? tone(CollaborationTask task) => taskDueLabel(task, now)?.tone;

    final overdueDays = open('a', due: DateTime(2026, 11, 14, 9));
    expect(label(overdueDays), 'Quá hạn 2 ngày');
    expect(tone(overdueDays), TaskDueTone.overdue);
    expect(
      label(open('b', due: DateTime(2026, 11, 16, 9))),
      'Quá hạn từ 09:00',
    );
    final today = open('c', due: DateTime(2026, 11, 16, 17));
    expect(label(today), 'Hôm nay 17:00');
    expect(tone(today), TaskDueTone.soon);
    expect(label(open('d', due: DateTime(2026, 11, 17))), 'Ngày mai');
    expect(label(open('e', due: DateTime(2026, 11, 20, 8))), 'Hạn 20/11');
    expect(taskDueLabel(open('f'), now), isNull);
    expect(
      label(
        fakeTask(
          'g',
          'g',
          CollaborationTaskStatus.done,
          completedAt: DateTime(2026, 11, 16, 9, 5),
        ),
      ),
      'Xong 09:05',
    );
    expect(
      label(
        fakeTask(
          'h',
          'h',
          CollaborationTaskStatus.done,
          completedAt: DateTime(2026, 11, 12, 9),
        ),
      ),
      'Xong 12/11',
    );
  });

  test('đếm 3 ô lọc: Hoàn thành chỉ tính 7 ngày qua, bỏ việc huỷ', () {
    final counts = countMyTasks([
      open('a'),
      open('b'),
      fakeTask('c', 'c', CollaborationTaskStatus.inProgress),
      fakeTask(
        'd',
        'd',
        CollaborationTaskStatus.done,
        completedAt: DateTime(2026, 11, 15),
      ),
      fakeTask(
        'e',
        'e',
        CollaborationTaskStatus.done,
        completedAt: DateTime(2026, 10, 1),
      ),
      fakeTask('f', 'f', CollaborationTaskStatus.cancelled),
    ], now);
    expect(counts.open, 2);
    expect(counts.inProgress, 1);
    expect(counts.done, 1);
  });

  test('kết quả tìm chia theo trạng thái', () {
    final sections = groupTasksByStatus([
      fakeTask('a', 'a', CollaborationTaskStatus.done),
      fakeTask('b', 'b', CollaborationTaskStatus.open),
    ]);
    expect(sections.map((s) => s.title), ['Chưa nhận', 'Hoàn thành']);
  });
}
