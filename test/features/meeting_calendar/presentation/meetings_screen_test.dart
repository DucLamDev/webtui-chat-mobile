import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/core/error/failure.dart';
import 'package:webtui_chat/features/meeting_calendar/domain/entities/calendar_meeting.dart';
import 'package:webtui_chat/features/work_hub/presentation/screens/meetings_screen.dart';

import '../meeting_calendar_fakes.dart';
import 'meeting_harness.dart';

void main() {
  // Thứ Hai 16/11/2026, 8 giờ sáng.
  final now = DateTime(2026, 11, 16, 8);

  FakeMeetingCalendarRepository calendar() => FakeMeetingCalendarRepository(
    meetings: [
      fakeMeeting(
        'today',
        title: 'Họp sáng',
        startsAt: DateTime(2026, 11, 16, 9),
        myResponse: MeetingResponse.accepted,
      ),
      fakeMeeting(
        'thu',
        title: 'Họp thứ năm',
        startsAt: DateTime(2026, 11, 19, 10),
        myResponse: MeetingResponse.pending,
      ),
      fakeMeeting(
        'cancel',
        title: 'Họp đã huỷ',
        startsAt: DateTime(2026, 11, 20, 10),
        status: 'cancelled',
      ),
      fakeMeeting(
        'past',
        title: 'Họp tuần trước',
        startsAt: DateTime(2026, 11, 13, 14),
        status: 'ended',
      ),
    ],
  );

  testWidgets(
    'dải tuần có chấm ngày có họp, chọn ngày thì lọc, Xem tất cả bỏ lọc',
    (tester) async {
      phoneView(tester);
      final repository = calendar();
      await tester.pumpWidget(
        meetingApp(
          calendar: repository,
          now: now,
          home: MeetingsScreen(workspaceId: 'ws', now: now),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('16/11 – 22/11'), findsOneWidget);
      expect(find.byKey(const Key('meeting_dot_2026-11-16')), findsOneWidget);
      expect(find.byKey(const Key('meeting_dot_2026-11-19')), findsOneWidget);
      expect(
        find.byKey(const Key('meeting_dot_2026-11-20')),
        findsNothing,
        reason: 'họp đã huỷ không tính chấm',
      );
      // Tab Sắp tới: có cả họp đã huỷ (nhãn Đã huỷ) nhưng không có họp đã qua.
      expect(find.text('Họp sáng'), findsOneWidget);
      expect(find.text('Họp thứ năm'), findsOneWidget);
      expect(find.text('Đã huỷ'), findsOneWidget);
      expect(find.text('Họp tuần trước'), findsNothing);
      expect(find.text('Bạn: Tham gia'), findsOneWidget);
      expect(find.text('Bạn: Chưa trả lời'), findsOneWidget);

      await tester.tap(find.byKey(const Key('meeting_day_2026-11-19')));
      await tester.pumpAndSettle();
      expect(find.text('Họp thứ năm'), findsOneWidget);
      expect(find.text('Họp sáng'), findsNothing);
      expect(find.text('Đang xem Thứ Năm, 19/11'), findsOneWidget);

      await tester.tap(find.byKey(const Key('meeting_clear_day')));
      await tester.pumpAndSettle();
      expect(find.text('Họp sáng'), findsOneWidget);
    },
  );

  testWidgets('tab Đã qua và tuần trước', (tester) async {
    phoneView(tester);
    await tester.pumpWidget(
      meetingApp(
        calendar: calendar(),
        now: now,
        home: MeetingsScreen(workspaceId: 'ws', now: now),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('meeting_tab_past')));
    await tester.pumpAndSettle();
    expect(find.text('Họp tuần trước'), findsOneWidget);
    expect(find.text('Đã kết thúc'), findsOneWidget);
    expect(find.text('Họp sáng'), findsNothing);

    await tester.tap(find.byKey(const Key('meeting_week_prev')));
    await tester.pumpAndSettle();
    expect(find.text('09/11 – 15/11'), findsOneWidget);
    expect(find.byKey(const Key('meeting_dot_2026-11-13')), findsOneWidget);
    // Chọn ngày đã qua tự sang tab Đã qua.
    await tester.tap(find.byKey(const Key('meeting_tab_upcoming')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('meeting_day_2026-11-13')));
    await tester.pumpAndSettle();
    expect(find.text('Họp tuần trước'), findsOneWidget);
  });

  testWidgets('lỗi tải: báo lỗi và Thử lại', (tester) async {
    phoneView(tester);
    final repository = calendar()
      ..listFailure = const Failure(
        kind: FailureKind.network,
        message: 'Mất kết nối',
      );
    await tester.pumpWidget(
      meetingApp(
        calendar: repository,
        now: now,
        home: MeetingsScreen(workspaceId: 'ws', now: now),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Thử lại'), findsOneWidget);

    repository.listFailure = null;
    await tester.tap(find.text('Thử lại'));
    await tester.pumpAndSettle();
    expect(find.text('Họp sáng'), findsOneWidget);
  });

  testWidgets('kéo để tải lại gọi lại máy chủ', (tester) async {
    phoneView(tester, height: 800);
    final repository = calendar();
    await tester.pumpWidget(
      meetingApp(
        calendar: repository,
        now: now,
        home: MeetingsScreen(workspaceId: 'ws', now: now),
      ),
    );
    await tester.pumpAndSettle();
    final before = repository.calls.length;
    await tester.fling(find.text('Họp sáng'), const Offset(0, 400), 1000);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(repository.calls.length, greaterThan(before));
  });

  testWidgets('bấm thẻ mở chi tiết; nút + mở biểu mẫu Tạo họp', (tester) async {
    phoneView(tester);
    final repository = calendar();
    await tester.pumpWidget(
      meetingApp(
        calendar: repository,
        now: now,
        home: MeetingsScreen(workspaceId: 'ws', now: now),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Họp sáng'));
    await tester.pumpAndSettle();
    expect(repository.calls, contains('get:c1/today'));
    expect(find.byKey(const Key('meeting_detail')), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('meeting_create')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('meeting_title')), findsOneWidget);
    // Nút tạo đủ vùng bấm 48dp.
    final size = tester.getSize(find.byKey(const Key('meeting_save')));
    expect(size.height, greaterThanOrEqualTo(48));
  });

  testWidgets('ô ngày và tab đủ vùng bấm 48dp', (tester) async {
    phoneView(tester);
    await tester.pumpWidget(
      meetingApp(
        calendar: calendar(),
        now: now,
        home: MeetingsScreen(workspaceId: 'ws', now: now),
      ),
    );
    await tester.pumpAndSettle();
    for (final key in const [
      Key('meeting_day_2026-11-16'),
      Key('meeting_tab_past'),
      Key('meeting_week_next'),
    ]) {
      final size = tester.getSize(find.byKey(key));
      expect(size.height, greaterThanOrEqualTo(48), reason: '$key');
      expect(size.width, greaterThanOrEqualTo(48), reason: '$key');
    }
  });
}
