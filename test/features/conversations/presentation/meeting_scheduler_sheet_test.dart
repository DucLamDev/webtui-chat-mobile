import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/features/conversations/presentation/widgets/meeting_scheduler_sheet.dart';

void main() {
  testWidgets('creates a complete meeting schedule draft', (tester) async {
    MeetingScheduleDraft? result;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () async {
                result = await showMeetingSchedulerSheet(
                  context,
                  conversationTitle: 'Nhóm sản phẩm',
                );
              },
              child: const Text('Mở lịch họp'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Mở lịch họp'));
    await tester.pumpAndSettle();
    expect(find.text('Lên lịch cuộc họp'), findsOneWidget);
    expect(find.text('Nhóm sản phẩm'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'Họp sprint tuần');
    await tester.tap(find.text('Tạo lịch họp'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.title, 'Họp sprint tuần');
    expect(
      result!.endsAt.difference(result!.startsAt),
      const Duration(hours: 1),
    );
    expect(
      result!.startsAt.difference(result!.lobbyOpensAt!),
      const Duration(minutes: 10),
    );
    expect(result!.roomPolicy, 'keep');
    expect(result!.cleanupAfter, isNull);
  });
}
