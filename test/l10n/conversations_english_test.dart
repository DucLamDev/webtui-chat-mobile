import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/features/conversations/presentation/controllers/collaboration_task_controller.dart';
import 'package:webtui_chat/features/conversations/presentation/models/task_due_label.dart';
import 'package:webtui_chat/features/conversations/presentation/widgets/notice_bot_read_only_bar.dart';
import 'package:webtui_chat/l10n/app_strings.dart';

void main() {
  void useEnglish() {
    AppStrings.current = const AppStringsEn();
    addTearDown(() => AppStrings.current = const AppStringsVi());
  }

  test('nhãn hạn việc đổi sang tiếng Anh', () {
    final now = DateTime(2026, 11, 16, 8);
    expect(formatTaskDue(DateTime(2026, 11, 16, 17), now), 'Hôm nay 17:00');
    useEnglish();
    expect(formatTaskDue(DateTime(2026, 11, 16, 17), now), 'Today 17:00');
    expect(formatTaskDue(DateTime(2026, 11, 17, 9), now), 'Tomorrow 09:00');
    expect(formatTaskDue(DateTime(2026, 11, 15, 9), now), 'Yesterday 09:00');
  });

  test('tên bộ lọc việc tính lúc dùng', () {
    expect(TaskListFilter.overdue.label, 'Quá hạn');
    useEnglish();
    expect(TaskListFilter.overdue.label, 'Overdue');
    expect(TaskListFilter.all.label, 'All');
  });

  testWidgets('thanh chỉ đọc của bot thông báo hiện tiếng Anh', (tester) async {
    useEnglish();
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: NoticeBotReadOnlyBar())),
    );
    expect(
      find.text('Notification bot, replies are not allowed'),
      findsOneWidget,
    );
    expect(find.text('Bot thông báo, không trả lời được'), findsNothing);
  });
}
