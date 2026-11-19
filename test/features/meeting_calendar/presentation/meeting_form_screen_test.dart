import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/features/meeting_calendar/domain/entities/calendar_meeting.dart';
import 'package:webtui_chat/features/meeting_calendar/presentation/screens/meeting_form_screen.dart';

import '../meeting_calendar_fakes.dart';
import 'meeting_harness.dart';

void main() {
  // Thứ Hai 16/11/2026, 8 giờ sáng; họp gợi ý lúc 10 giờ.
  final now = DateTime(2026, 11, 16, 8);
  final start = DateTime(2026, 11, 16, 10);

  Widget form({
    required FakeMeetingCalendarRepository calendar,
    FakeMeetingConversations? conversations,
    CalendarMeeting? existing,
  }) {
    return meetingApp(
      calendar: calendar,
      conversations: conversations,
      now: now,
      home: _Launcher(
        form: MeetingFormScreen(
          workspaceId: 'ws',
          existing: existing,
          initialStart: start,
          now: now,
        ),
      ),
    );
  }

  Future<void> open(WidgetTester tester, Widget app) async {
    await tester.pumpWidget(app);
    await tester.tap(find.text('mở biểu mẫu'));
    await tester.pumpAndSettle();
  }

  Future<void> tapKey(WidgetTester tester, String key) async {
    final finder = find.byKey(Key(key));
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> chooseGroup(WidgetTester tester) async {
    await tapKey(tester, 'meeting_group');
    await tester.tap(find.byKey(const Key('meeting_group_c-a')));
    await tester.pumpAndSettle();
    // Chờ hẹn giờ kiểm trùng lịch.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
  }

  testWidgets('thoát khi chưa sửa gì: không hỏi', (tester) async {
    phoneView(tester, height: 2600);
    await open(tester, form(calendar: FakeMeetingCalendarRepository()));
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Bỏ thay đổi?'), findsNothing);
    expect(find.byKey(const Key('meeting_title')), findsNothing);
  });

  testWidgets('đã sửa mà thoát: hỏi Bỏ thay đổi, Tiếp tục sửa giữ nguyên', (
    tester,
  ) async {
    phoneView(tester, height: 2600);
    await open(tester, form(calendar: FakeMeetingCalendarRepository()));
    await tester.enterText(find.byKey(const Key('meeting_title')), 'Họp dở');
    // Khung hình sau khi gõ: màn biết đã có thay đổi, khoá vuốt lùi.
    await tester.pump();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Bỏ thay đổi?'), findsOneWidget);

    await tester.tap(find.byKey(const Key('webtui_dialog_cancel')));
    await tester.pumpAndSettle();
    expect(find.text('Họp dở'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('webtui_dialog_confirm')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('meeting_title')), findsNothing);
  });

  testWidgets('bắt buộc tiêu đề, link phải https, phải chọn nhóm', (
    tester,
  ) async {
    phoneView(tester, height: 2600);
    final calendar = FakeMeetingCalendarRepository();
    await open(tester, form(calendar: calendar));

    await tapKey(tester, 'meeting_save');
    expect(find.text('Hãy nhập tiêu đề cuộc họp.'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('meeting_title')), 'Họp tuần');
    await tester.enterText(
      find.byKey(const Key('meeting_url')),
      'http://zoom.us/j/1',
    );
    await tapKey(tester, 'meeting_save');
    expect(find.text('Link họp phải bắt đầu bằng https://'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('meeting_url')),
      'https://zoom.us/j/1',
    );
    await tapKey(tester, 'meeting_save');
    expect(find.text('Hãy chọn nhóm.'), findsOneWidget);
    expect(calendar.calls.where((call) => call.startsWith('create')), isEmpty);
  });

  testWidgets('chọn nhóm: mặc định cả nhóm, báo trùng lịch nhưng vẫn lưu', (
    tester,
  ) async {
    phoneView(tester, height: 2600);
    final calendar = FakeMeetingCalendarRepository(
      conflicts: [
        MeetingConflict(
          userId: 'u1',
          meetingId: 'm9',
          startsAt: DateTime(2026, 11, 16, 10, 30),
          endsAt: DateTime(2026, 11, 16, 11),
          title: 'Gặp khách',
        ),
      ],
    );
    await open(tester, form(calendar: calendar));
    await tester.enterText(find.byKey(const Key('meeting_title')), 'Họp tuần');
    await chooseGroup(tester);

    expect(find.text('An toàn'), findsOneWidget);
    expect(find.text('Cả nhóm (1)'), findsOneWidget);
    expect(calendar.lastConflictUsers, ['u1']);
    expect(find.byKey(const Key('meeting_conflicts')), findsOneWidget);
    expect(
      find.textContaining('Người u1: «Gặp khách» 10:30–11:00'),
      findsOneWidget,
    );

    await tapKey(tester, 'meeting_save');
    expect(calendar.calls, contains('create:c-a'));
    final draft = calendar.drafts.single;
    expect(draft.title, 'Họp tuần');
    expect(draft.startsAt, start);
    expect(draft.endsAt, start.add(const Duration(hours: 1)));
    expect(draft.attendeeUserIds, isNull, reason: 'cả nhóm: để máy chủ mời');
    expect(draft.reminderOffsets, [15, 0]);
    expect(draft.recurrence, isNull);
    expect(draft.timezone, 'Asia/Ho_Chi_Minh');
  });

  testWidgets('mốc nhắc: tối đa 3 mốc, mốc thứ 4 bị khoá', (tester) async {
    phoneView(tester, height: 2600);
    final calendar = FakeMeetingCalendarRepository();
    await open(tester, form(calendar: calendar));
    await tester.enterText(find.byKey(const Key('meeting_title')), 'Họp');
    await chooseGroup(tester);

    await tapKey(tester, 'meeting_reminder_5');
    final sixty = tester.widget<FilterChip>(
      find.byKey(const Key('meeting_reminder_60')),
    );
    expect(sixty.onSelected, isNull);
    await tapKey(tester, 'meeting_reminder_15');
    expect(
      tester
          .widget<FilterChip>(find.byKey(const Key('meeting_reminder_60')))
          .onSelected,
      isNotNull,
    );
    await tapKey(tester, 'meeting_reminder_60');

    await tapKey(tester, 'meeting_save');
    expect(calendar.drafts.single.reminderOffsets, [60, 5, 0]);
  });

  testWidgets('lặp hằng tuần theo thứ, kết thúc sau số buổi', (tester) async {
    phoneView(tester, height: 2600);
    final calendar = FakeMeetingCalendarRepository();
    await open(tester, form(calendar: calendar));
    await tester.enterText(find.byKey(const Key('meeting_title')), 'Họp tuần');
    await chooseGroup(tester);

    await tapKey(tester, 'meeting_repeat');
    await tester.tap(find.text('Hằng tuần').last);
    await tester.pumpAndSettle();
    // Mặc định chọn thứ của ngày bắt đầu (Thứ Hai).
    expect(
      tester
          .widget<FilterChip>(find.byKey(const Key('meeting_weekday_1')))
          .selected,
      isTrue,
    );
    await tapKey(tester, 'meeting_weekday_3');
    await tapKey(tester, 'meeting_repeat_end_count');
    await tester.enterText(find.byKey(const Key('meeting_repeat_count')), '0');
    await tapKey(tester, 'meeting_save');
    expect(find.text('Số buổi từ 1 đến 100.'), findsOneWidget);
    expect(calendar.drafts, isEmpty);

    await tester.enterText(find.byKey(const Key('meeting_repeat_count')), '5');
    await tapKey(tester, 'meeting_save');
    final recurrence = calendar.drafts.single.recurrence!;
    expect(recurrence.frequency, MeetingRecurrenceFrequency.weekly);
    expect(recurrence.byWeekday, [1, 3]);
    expect(recurrence.count, 5);
    expect(recurrence.until, isNull);
  });

  testWidgets('chọn người lẻ: tạo nhóm riêng tư mới rồi tạo họp', (
    tester,
  ) async {
    phoneView(tester, height: 2600);
    final calendar = FakeMeetingCalendarRepository();
    final conversations = FakeMeetingConversations();
    await open(tester, form(calendar: calendar, conversations: conversations));
    await tester.enterText(find.byKey(const Key('meeting_title')), 'Phỏng vấn');
    await tester.tap(find.text('Chọn người'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('meeting_group')), findsNothing);

    await tapKey(tester, 'meeting_save');
    expect(find.text('Hãy chọn ít nhất một người.'), findsOneWidget);

    await tapKey(tester, 'meeting_attendees');
    await tester.tap(find.byKey(const Key('meeting_person_u7')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('meeting_people_done')));
    await tester.pumpAndSettle();
    expect(find.text('1 người'), findsOneWidget);

    await tapKey(tester, 'meeting_save');
    expect(conversations.created.single.name, 'Phỏng vấn');
    expect(conversations.added, ['u7']);
    expect(calendar.calls, contains('create:new-group'));
    expect(calendar.drafts.single.attendeeUserIds, ['u7']);
  });

  testWidgets('sửa buổi họp lặp lại: hỏi Chỉ buổi này / Cả chuỗi', (
    tester,
  ) async {
    phoneView(tester, height: 2600);
    final calendar = FakeMeetingCalendarRepository();
    final existing = fakeMeeting(
      'm1',
      channelId: 'c-a',
      channelName: 'An toàn',
      title: 'Họp tuần',
      startsAt: start,
      seriesId: 's1',
      recurrence: const MeetingRecurrence(
        frequency: MeetingRecurrenceFrequency.weekly,
        byWeekday: [1],
      ),
      canEdit: true,
    );
    await open(tester, form(calendar: calendar, existing: existing));
    expect(find.text('Sửa cuộc họp'), findsOneWidget);
    expect(find.text('Hằng tuần: T2'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('meeting_title')),
      'Họp tuần (dời)',
    );
    await tapKey(tester, 'meeting_save');
    expect(find.text('Chỉ buổi này'), findsOneWidget);
    expect(find.text('Buổi đã sửa riêng trước đó giữ nguyên.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('meeting_scope_series')));
    await tester.pumpAndSettle();
    expect(calendar.calls, contains('update:m1'));
    expect(calendar.lastScope, MeetingScope.series);
    expect(calendar.drafts.single.title, 'Họp tuần (dời)');
    // Sửa không gửi quy tắc lặp (máy chủ không đổi quy tắc khi sửa).
    expect(calendar.drafts.single.recurrence, isNull);
  });

  for (final rule in [
    MeetingRecurrence(
      frequency: MeetingRecurrenceFrequency.weekly,
      byWeekday: const [1],
      until: DateTime(2027, 3, 31),
    ),
    const MeetingRecurrence(
      frequency: MeetingRecurrenceFrequency.weekly,
      byWeekday: [1],
      count: 8,
    ),
  ]) {
    testWidgets(
      'sửa cả chuỗi có điều kiện kết thúc (${rule.until != null ? 'đến ngày' : 'số buổi'}): lưu được, không gửi lại quy tắc lặp',
      (tester) async {
        phoneView(tester, height: 2600);
        final calendar = FakeMeetingCalendarRepository();
        final existing = fakeMeeting(
          'm2',
          channelId: 'c-a',
          channelName: 'An toàn',
          title: 'Họp tuần',
          startsAt: start,
          seriesId: 's2',
          recurrence: rule,
          canEdit: true,
        );
        await open(tester, form(calendar: calendar, existing: existing));
        await tester.enterText(
          find.byKey(const Key('meeting_title')),
          'Họp tuần (đổi tên)',
        );
        await tapKey(tester, 'meeting_save');
        await tester.tap(find.byKey(const Key('meeting_scope_series')));
        await tester.pumpAndSettle();
        expect(calendar.calls, contains('update:m2'));
        expect(calendar.drafts.single.title, 'Họp tuần (đổi tên)');
        expect(calendar.drafts.single.recurrence, isNull);
      },
    );
  }
}

/// Trang mở biểu mẫu bằng Navigator (biểu mẫu tự đóng khi lưu xong).
class _Launcher extends StatelessWidget {
  const _Launcher({required this.form});

  final Widget form;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: TextButton(
        onPressed: () => Navigator.of(
          context,
        ).push(MaterialPageRoute<CalendarMeeting>(builder: (_) => form)),
        child: const Text('mở biểu mẫu'),
      ),
    );
  }
}
