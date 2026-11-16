import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/core/error/failure.dart';
import 'package:webtui_chat/features/conversations/domain/entities/collaboration_room.dart';
import 'package:webtui_chat/features/meeting_calendar/domain/entities/calendar_meeting.dart';
import 'package:webtui_chat/features/meeting_calendar/presentation/screens/meeting_detail_screen.dart';
import 'package:webtui_chat/features/meeting_calendar/presentation/widgets/meeting_widgets.dart';

import '../meeting_calendar_fakes.dart';
import 'meeting_harness.dart';

void main() {
  final start = DateTime(2026, 11, 16, 9);

  CalendarMeeting organizerMeeting({
    String? externalUrl,
    String? seriesId,
    MeetingMinutes? minutes,
    MeetingGuestLink? guestLink,
  }) {
    return fakeMeeting(
      'm1',
      title: 'Họp tuần',
      startsAt: start,
      canEdit: true,
      canCancel: true,
      canRespond: true,
      canEditMinutes: true,
      myResponse: MeetingResponse.pending,
      externalUrl: externalUrl,
      seriesId: seriesId,
      minutes: minutes,
      guestLink: guestLink ?? const MeetingGuestLink(enabled: false),
      attendeeSummary: const MeetingAttendeeSummary(accepted: 1, pending: 1),
      attendees: const [
        MeetingAttendee(
          userId: 'u1',
          displayName: 'Lan',
          isOrganizer: true,
          response: MeetingResponse.accepted,
        ),
        MeetingAttendee(userId: 'u2', displayName: 'Minh'),
      ],
    );
  }

  Future<void> open(
    WidgetTester tester, {
    required FakeMeetingCalendarRepository calendar,
    required DateTime now,
    FakeMeetingApi? meetingApi,
    FakeUrlLauncher? launcher,
    Brightness brightness = Brightness.light,
  }) async {
    phoneView(tester, height: 2600);
    await tester.pumpWidget(
      meetingApp(
        calendar: calendar,
        meetingApi: meetingApi,
        launcher: launcher,
        now: now,
        brightness: brightness,
        home: MeetingDetailScreen(
          workspaceId: 'ws',
          channelId: 'c1',
          meetingId: 'm1',
          now: now,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tapKey(WidgetTester tester, String key) async {
    final finder = find.byKey(Key(key));
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'người tham dự thường: không có Sửa / Huỷ / biên bản / link khách',
    (tester) async {
      final calendar = FakeMeetingCalendarRepository(
        detail: fakeMeeting(
          'm1',
          title: 'Họp tuần',
          startsAt: start,
          canRespond: true,
          myResponse: MeetingResponse.accepted,
        ),
      );
      await open(tester, calendar: calendar, now: DateTime(2026, 11, 16, 8));
      expect(find.text('Họp tuần'), findsOneWidget);
      expect(find.text('Sắp bắt đầu'), findsOneWidget);
      expect(find.byKey(const Key('meeting_edit')), findsNothing);
      expect(find.byKey(const Key('meeting_cancel')), findsNothing);
      expect(find.byKey(const Key('meeting_guest_switch')), findsNothing);
      expect(find.byKey(const Key('meeting_minutes_edit')), findsNothing);
      expect(find.byKey(const Key('meeting_task_add')), findsNothing);
      expect(
        find.byKey(const Key('meeting_response_accepted')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('meeting_message_group')), findsOneWidget);
      expect(calendar.calls, contains('get:c1/m1'));
    },
  );

  testWidgets('người tổ chức: đủ nút; phản hồi gửi lên máy chủ', (
    tester,
  ) async {
    final calendar = FakeMeetingCalendarRepository(detail: organizerMeeting());
    await open(tester, calendar: calendar, now: DateTime(2026, 11, 16, 8));
    expect(find.byKey(const Key('meeting_edit')), findsOneWidget);
    expect(find.byKey(const Key('meeting_cancel')), findsOneWidget);
    expect(find.byKey(const Key('meeting_guest_switch')), findsOneWidget);
    expect(find.byKey(const Key('meeting_minutes_edit')), findsOneWidget);
    expect(find.byKey(const Key('meeting_task_add')), findsOneWidget);
    expect(
      find.text('1 tham gia · 0 có thể · 0 từ chối · 1 chưa trả lời'),
      findsOneWidget,
    );
    expect(find.text('Người tổ chức'), findsOneWidget);

    await tapKey(tester, 'meeting_response_tentative');
    expect(calendar.calls, contains('respond:tentative'));
    expect(find.text('Đã trả lời: Có thể'), findsOneWidget);
  });

  testWidgets('Vào họp: khoá tới trước giờ 10 phút, rồi mở phòng video', (
    tester,
  ) async {
    final launcher = FakeUrlLauncher();
    final api = FakeMeetingApi();
    final calendar = FakeMeetingCalendarRepository(detail: organizerMeeting());
    await open(
      tester,
      calendar: calendar,
      now: DateTime(2026, 11, 16, 8, 40),
      launcher: launcher,
      meetingApi: api,
    );
    final early = tester.widget<ButtonStyleButton>(
      find.byKey(const Key('meeting_join')),
    );
    expect(early.onPressed, isNull);
    expect(find.text('Vào họp từ 08:50'), findsOneWidget);

    await open(
      tester,
      calendar: calendar,
      now: DateTime(2026, 11, 16, 8, 50),
      launcher: launcher,
      meetingApi: api,
    );
    await tapKey(tester, 'meeting_join');
    expect(api.tokenRequests, ['c1/m1']);
    expect(launcher.opened, ['https://meet.example.com/phong-1?jwt=jwt-1']);
  });

  testWidgets('màn đang mở: tới giờ mở phòng thì nút Vào họp tự bật', (
    tester,
  ) async {
    var current = DateTime(2026, 11, 16, 8, 45);
    phoneView(tester, height: 2600);
    await tester.pumpWidget(
      meetingApp(
        calendar: FakeMeetingCalendarRepository(detail: organizerMeeting()),
        home: MeetingDetailScreen(
          workspaceId: 'ws',
          channelId: 'c1',
          meetingId: 'm1',
          clock: () => current,
        ),
      ),
    );
    await tester.pumpAndSettle();
    ButtonStyleButton join() =>
        tester.widget<ButtonStyleButton>(find.byKey(const Key('meeting_join')));
    expect(join().onPressed, isNull);
    expect(find.text('Vào họp từ 08:50'), findsOneWidget);

    current = DateTime(2026, 11, 16, 8, 51);
    await tester.pump(meetingClockTick);
    expect(join().onPressed, isNotNull);
    expect(find.text('Vào họp'), findsOneWidget);
  });

  testWidgets('Vào họp có link ngoài: mở link, không xin token', (
    tester,
  ) async {
    final launcher = FakeUrlLauncher();
    final api = FakeMeetingApi();
    await open(
      tester,
      calendar: FakeMeetingCalendarRepository(
        detail: organizerMeeting(externalUrl: 'https://meet.google.com/abc'),
      ),
      now: DateTime(2026, 11, 16, 9, 5),
      launcher: launcher,
      meetingApi: api,
    );
    expect(find.text('Đang diễn ra'), findsOneWidget);
    await tapKey(tester, 'meeting_join');
    expect(launcher.opened, ['https://meet.google.com/abc']);
    expect(api.tokenRequests, isEmpty);
  });

  testWidgets('Nhắn vào nhóm mở phòng chat của nhóm', (tester) async {
    await open(
      tester,
      calendar: FakeMeetingCalendarRepository(detail: organizerMeeting()),
      now: DateTime(2026, 11, 16, 8),
    );
    await tapKey(tester, 'meeting_message_group');
    expect(find.text('phòng c1 Nhóm Kỹ thuật'), findsOneWidget);
  });

  testWidgets('đã kết thúc / đã huỷ: không có Vào họp, Sửa, Huỷ', (
    tester,
  ) async {
    await open(
      tester,
      calendar: FakeMeetingCalendarRepository(
        detail: fakeMeeting(
          'm1',
          startsAt: start,
          status: 'cancelled',
          canEdit: true,
          canCancel: true,
          canRespond: true,
        ),
      ),
      now: DateTime(2026, 11, 16, 8),
    );
    expect(find.text('Đã huỷ'), findsOneWidget);
    expect(find.byKey(const Key('meeting_join')), findsNothing);
    expect(find.byKey(const Key('meeting_edit')), findsNothing);
    expect(find.byKey(const Key('meeting_cancel')), findsNothing);
    expect(find.byKey(const Key('meeting_response_accepted')), findsNothing);
  });

  testWidgets('huỷ buổi họp lặp lại: hỏi phạm vi rồi gửi', (tester) async {
    final calendar = FakeMeetingCalendarRepository(
      detail: organizerMeeting(seriesId: 's1'),
    );
    await open(tester, calendar: calendar, now: DateTime(2026, 11, 16, 8));
    expect(find.text('Định kỳ'), findsOneWidget);
    await tapKey(tester, 'meeting_cancel');
    await tester.tap(find.byKey(const Key('meeting_scope_this')));
    await tester.pumpAndSettle();
    expect(calendar.calls, contains('cancel:m1'));
    expect(calendar.lastScope, MeetingScope.occurrence);
  });

  testWidgets('biên bản: soạn, lưu, gửi vào nhóm', (tester) async {
    final calendar = FakeMeetingCalendarRepository(detail: organizerMeeting());
    await open(tester, calendar: calendar, now: DateTime(2026, 11, 16, 10));
    expect(find.text('Chưa có biên bản.'), findsOneWidget);
    expect(find.byKey(const Key('meeting_minutes_publish')), findsNothing);

    await tapKey(tester, 'meeting_minutes_edit');
    await tester.enterText(
      find.byKey(const Key('meeting_minutes_field')),
      'Chốt lịch giao hàng',
    );
    await tester.tap(find.byKey(const Key('meeting_minutes_save')));
    await tester.pumpAndSettle();
    expect(calendar.lastMinutes, 'Chốt lịch giao hàng');

    calendar.detail = organizerMeeting(
      minutes: const MeetingMinutes(content: 'Chốt lịch giao hàng'),
    );
    calendar.calls.clear();
    final refresh = find.byType(RefreshIndicator);
    await tester.fling(refresh, const Offset(0, 1200), 1000);
    await tester.pumpAndSettle();
    expect(find.text('Chốt lịch giao hàng'), findsOneWidget);

    await tapKey(tester, 'meeting_minutes_publish');
    await tester.tap(find.byKey(const Key('meeting_confirm')));
    await tester.pumpAndSettle();
    expect(calendar.calls, contains('publishMinutes'));
    expect(find.text('Đã gửi biên bản vào nhóm.'), findsOneWidget);
  });

  testWidgets('việc từ cuộc họp: xem danh sách, giao việc cho người dự', (
    tester,
  ) async {
    final calendar = FakeMeetingCalendarRepository(
      detail: organizerMeeting(),
      tasks: [
        CollaborationTask(
          id: 't1',
          title: 'Gửi báo giá',
          status: 'open',
          assigneeUserId: 'u2',
          createdAt: DateTime.utc(2026, 11, 16),
        ),
      ],
    );
    await open(tester, calendar: calendar, now: DateTime(2026, 11, 16, 10));
    expect(calendar.calls, contains('tasks:m1'));
    expect(find.text('Gửi báo giá'), findsOneWidget);
    expect(find.text('Cần làm · Minh'), findsOneWidget);

    await tapKey(tester, 'meeting_task_add');
    await tester.enterText(
      find.byKey(const Key('meeting_task_title')),
      'Làm hợp đồng',
    );
    await tester.tap(find.byKey(const Key('meeting_task_assignee')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lan').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('meeting_task_save')));
    await tester.pumpAndSettle();
    expect(calendar.lastTask, (title: 'Làm hợp đồng', assignee: 'u1'));
  });

  testWidgets('link khách: bật thì hiện link và nút sao chép', (tester) async {
    final calendar = FakeMeetingCalendarRepository(detail: organizerMeeting());
    await open(tester, calendar: calendar, now: DateTime(2026, 11, 16, 8));
    expect(find.byKey(const Key('meeting_guest_url')), findsNothing);
    await tapKey(tester, 'meeting_guest_switch');
    expect(calendar.calls, contains('guestOn'));

    calendar.detail = organizerMeeting(
      guestLink: const MeetingGuestLink(
        enabled: true,
        url: 'https://h.example/g/1',
      ),
    );
    await tester.fling(
      find.byType(RefreshIndicator),
      const Offset(0, 1200),
      1000,
    );
    await tester.pumpAndSettle();
    expect(find.text('https://h.example/g/1'), findsOneWidget);
    expect(find.byKey(const Key('meeting_guest_copy')), findsOneWidget);
  });

  testWidgets('link khách tương đối: ghép tên miền máy chủ đang dùng', (
    tester,
  ) async {
    final calendar = FakeMeetingCalendarRepository(
      detail: organizerMeeting(
        guestLink: const MeetingGuestLink(enabled: true, url: '/join?token=t1'),
      ),
    );
    await open(tester, calendar: calendar, now: DateTime(2026, 11, 16, 8));
    expect(find.text('https://chat.example.com/join?token=t1'), findsOneWidget);
  });

  testWidgets('lỗi tải chi tiết: báo lỗi và Thử lại', (tester) async {
    final calendar = FakeMeetingCalendarRepository(
      detail: organizerMeeting(),
      detailFailure: const Failure(
        kind: FailureKind.network,
        message: 'Mất kết nối',
      ),
    );
    await open(tester, calendar: calendar, now: DateTime(2026, 11, 16, 8));
    expect(find.text('Thử lại'), findsOneWidget);
    calendar.detailFailure = null;
    await tester.tap(find.text('Thử lại'));
    await tester.pumpAndSettle();
    expect(find.text('Họp tuần'), findsOneWidget);
  });

  testWidgets('nền tối: dựng được, nút đủ 48dp', (tester) async {
    await open(
      tester,
      calendar: FakeMeetingCalendarRepository(detail: organizerMeeting()),
      now: DateTime(2026, 11, 16, 8, 55),
      brightness: Brightness.dark,
    );
    for (final key in const [
      'meeting_join',
      'meeting_message_group',
      'meeting_response_accepted',
      'meeting_edit',
    ]) {
      final size = tester.getSize(find.byKey(Key(key)));
      expect(size.height, greaterThanOrEqualTo(48), reason: key);
    }
  });
}
