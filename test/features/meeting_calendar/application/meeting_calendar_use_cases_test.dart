import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/core/error/failure.dart';
import 'package:webtui_chat/core/result/result.dart';
import 'package:webtui_chat/features/conversations/application/use_cases/create_group_use_case.dart';
import 'package:webtui_chat/features/conversations/domain/entities/conversation_summary.dart';
import 'package:webtui_chat/features/meeting_calendar/application/meeting_calendar_use_cases.dart';
import 'package:webtui_chat/features/meeting_calendar/domain/entities/calendar_meeting.dart';

import '../meeting_calendar_fakes.dart';

final _now = DateTime(2026, 11, 16, 8);

MeetingDraft _draft({
  String title = 'Họp tuần',
  DateTime? startsAt,
  DateTime? endsAt,
  String? externalUrl,
  List<int> reminders = defaultReminderOffsets,
  MeetingRecurrence? recurrence,
  List<String>? attendees,
}) {
  final start = startsAt ?? DateTime(2026, 11, 16, 9);
  return MeetingDraft(
    title: title,
    startsAt: start,
    endsAt: endsAt ?? start.add(const Duration(hours: 1)),
    externalUrl: externalUrl,
    reminderOffsets: reminders,
    recurrence: recurrence,
    attendeeUserIds: attendees,
  );
}

void main() {
  group('kiểm đầu vào', () {
    test('tiêu đề bắt buộc, tối đa 200 ký tự', () {
      expect(validateMeetingTitle('  '), isNotNull);
      expect(validateMeetingTitle('a' * 201), isNotNull);
      expect(validateMeetingTitle(' Họp '), isNull);
    });

    test('link ngoài: trống được, chỉ https, không kèm tài khoản', () {
      expect(validateMeetingExternalUrl(''), isNull);
      expect(validateMeetingExternalUrl('https://meet.google.com/x'), isNull);
      expect(validateMeetingExternalUrl('http://meet.google.com/x'), isNotNull);
      expect(validateMeetingExternalUrl('meet.google.com/x'), isNotNull);
      expect(validateMeetingExternalUrl('https://'), isNotNull);
      expect(validateMeetingExternalUrl('https://u:p@zoom.us/j/1'), isNotNull);
    });

    test('mốc nhắc: tối đa 3, chỉ 0/5/10/15/30/60, không trùng', () {
      expect(validateReminderOffsets(const []), isNull);
      expect(validateReminderOffsets(const [60, 15, 0]), isNull);
      expect(validateReminderOffsets(const [60, 30, 15, 0]), isNotNull);
      expect(validateReminderOffsets(const [20]), isNotNull);
      expect(validateReminderOffsets(const [15, 15]), isNotNull);
    });

    test('giờ: kết thúc sau bắt đầu; tạo mới không ở quá khứ', () {
      final start = DateTime(2026, 11, 16, 9);
      expect(
        validateMeetingTimes(
          startsAt: start,
          endsAt: start,
          now: _now,
          isNew: true,
        ),
        isNotNull,
      );
      expect(
        validateMeetingTimes(
          startsAt: DateTime(2026, 11, 16, 7),
          endsAt: null,
          now: _now,
          isNew: true,
        ),
        isNotNull,
      );
      expect(
        validateMeetingTimes(
          startsAt: DateTime(2026, 11, 16, 7),
          endsAt: null,
          now: _now,
          isNew: false,
        ),
        isNull,
        reason: 'sửa họp đã qua giờ vẫn được',
      );
    });

    test('lặp lại: tuần phải có thứ, số buổi 1–100, ngày kết thúc hợp lệ', () {
      final start = DateTime(2026, 11, 16, 9);
      expect(
        validateMeetingRecurrence(
          const MeetingRecurrence(frequency: MeetingRecurrenceFrequency.weekly),
          startsAt: start,
        ),
        isNotNull,
      );
      expect(
        validateMeetingRecurrence(
          const MeetingRecurrence(
            frequency: MeetingRecurrenceFrequency.daily,
            count: 101,
          ),
          startsAt: start,
        ),
        isNotNull,
      );
      expect(
        validateMeetingRecurrence(
          MeetingRecurrence(
            frequency: MeetingRecurrenceFrequency.monthly,
            until: DateTime(2026, 11, 15),
          ),
          startsAt: start,
        ),
        isNotNull,
      );
      expect(
        validateMeetingRecurrence(
          MeetingRecurrence(
            frequency: MeetingRecurrenceFrequency.weekly,
            byWeekday: const [1, 3],
            until: DateTime(2026, 11, 16),
          ),
          startsAt: start,
        ),
        isNull,
      );
    });
  });

  group('trạng thái', () {
    final start = DateTime(2026, 11, 16, 9);

    test('nhãn theo giờ và status', () {
      final meeting = fakeMeeting('m', startsAt: start);
      expect(
        meetingPhaseAt(meeting, DateTime(2026, 11, 16, 8)),
        MeetingPhase.upcoming,
      );
      expect(
        meetingPhaseAt(meeting, DateTime(2026, 11, 16, 9, 30)),
        MeetingPhase.live,
      );
      expect(
        meetingPhaseAt(meeting, DateTime(2026, 11, 16, 10)),
        MeetingPhase.ended,
      );
      expect(
        meetingPhaseAt(
          fakeMeeting('a', startsAt: start, status: 'active'),
          DateTime(2026, 11, 16, 8),
        ),
        MeetingPhase.live,
      );
      expect(
        meetingPhaseAt(
          fakeMeeting('c', startsAt: start, status: 'cancelled'),
          DateTime(2026, 11, 16, 8),
        ),
        MeetingPhase.cancelled,
      );
    });

    test('Vào họp mở trước 10 phút, đóng khi kết thúc / huỷ', () {
      final meeting = fakeMeeting('m', startsAt: start);
      expect(canJoinMeetingAt(meeting, DateTime(2026, 11, 16, 8, 49)), isFalse);
      expect(canJoinMeetingAt(meeting, DateTime(2026, 11, 16, 8, 50)), isTrue);
      expect(canJoinMeetingAt(meeting, DateTime(2026, 11, 16, 10)), isFalse);
      expect(
        canJoinMeetingAt(
          fakeMeeting('c', startsAt: start, status: 'cancelled'),
          DateTime(2026, 11, 16, 9),
        ),
        isFalse,
      );
    });
  });

  group('use case', () {
    test('danh sách: cắt khoảng tối đa 62 ngày, sắp theo giờ', () async {
      final repository = FakeMeetingCalendarRepository(
        meetings: [
          fakeMeeting('b', startsAt: DateTime(2026, 11, 20)),
          fakeMeeting('a', startsAt: DateTime(2026, 11, 18)),
        ],
      );
      final result = await ListMeetingsInRangeUseCase(repository).execute(
        workspaceId: 'ws',
        from: DateTime(2026, 11, 1),
        to: DateTime(2027, 3, 1),
      );
      expect(result.valueOrNull!.map((m) => m.id), ['a', 'b']);
      expect(repository.ranges.single.$2, DateTime(2027, 1, 2));
    });

    test('tạo trong nhóm có sẵn: chuẩn hoá nội dung, không tạo nhóm', () async {
      final repository = FakeMeetingCalendarRepository();
      final conversations = FakeMeetingConversations();
      final useCase = CreateMeetingUseCase(
        repository,
        CreateGroupUseCase(conversations),
        clock: () => _now,
      );
      final result = await useCase.execute(
        workspaceId: 'ws',
        target: const ExistingGroupTarget('c1'),
        draft: _draft(
          title: '  Họp tuần  ',
          externalUrl: ' ',
          reminders: const [0, 15],
          attendees: const ['u1', 'u1', 'u2'],
        ),
      );
      expect(result, isA<Success<CalendarMeeting>>());
      expect(repository.calls, ['create:c1']);
      final sent = repository.drafts.single;
      expect(sent.title, 'Họp tuần');
      expect(sent.externalUrl, isNull);
      expect(sent.reminderOffsets, [15, 0]);
      expect(sent.attendeeUserIds, ['u1', 'u2']);
      expect(conversations.created, isEmpty);
    });

    test(
      'chọn người lẻ: tạo nhóm riêng tư rồi tạo họp trong nhóm đó',
      () async {
        final repository = FakeMeetingCalendarRepository();
        final conversations = FakeMeetingConversations();
        String? reported;
        final result =
            await CreateMeetingUseCase(
              repository,
              CreateGroupUseCase(conversations),
              clock: () => _now,
            ).execute(
              workspaceId: 'ws',
              target: const NewGroupTarget(memberIds: ['u2', 'u3']),
              draft: _draft(title: 'Phỏng vấn', attendees: const ['u2', 'u3']),
              onGroupCreated: (id) => reported = id,
            );
        expect(result, isA<Success<CalendarMeeting>>());
        expect(conversations.created.single.name, 'Phỏng vấn');
        expect(
          conversations.created.single.visibility,
          ChannelVisibility.private,
        );
        expect(conversations.added, ['u2', 'u3']);
        expect(reported, 'new-group');
        expect(repository.calls, ['create:new-group']);
      },
    );

    test('đầu vào sai: không gọi máy chủ', () async {
      final repository = FakeMeetingCalendarRepository();
      final useCase = CreateMeetingUseCase(
        repository,
        CreateGroupUseCase(FakeMeetingConversations()),
        clock: () => _now,
      );
      final badUrl = await useCase.execute(
        workspaceId: 'ws',
        target: const ExistingGroupTarget('c1'),
        draft: _draft(externalUrl: 'http://zoom.us/j/1'),
      );
      expect(badUrl.failureOrNull!.code, 'MEETING_URL_INVALID');
      final noTarget = await useCase.execute(
        workspaceId: 'ws',
        target: const NewGroupTarget(memberIds: []),
        draft: _draft(),
      );
      expect(noTarget.failureOrNull!.code, 'MEETING_TARGET_REQUIRED');
      final tooMany = await useCase.execute(
        workspaceId: 'ws',
        target: const ExistingGroupTarget('c1'),
        draft: _draft(reminders: const [60, 30, 15, 0]),
      );
      expect(tooMany.failureOrNull!.code, 'MEETING_REMINDERS_INVALID');
      expect(repository.calls, isEmpty);
    });

    test('sửa: gửi đúng scope; lỗi 403 có câu dễ hiểu', () async {
      final repository = FakeMeetingCalendarRepository();
      final useCase = UpdateMeetingUseCase(repository, clock: () => _now);
      await useCase.execute(
        workspaceId: 'ws',
        channelId: 'c1',
        meetingId: 'm1',
        draft: _draft(),
        scope: MeetingScope.series,
      );
      expect(repository.lastScope, MeetingScope.series);
      repository.writeFailure = const Failure(
        kind: FailureKind.forbidden,
        message: 'forbidden',
      );
      final denied = await useCase.execute(
        workspaceId: 'ws',
        channelId: 'c1',
        meetingId: 'm1',
        draft: _draft(),
      );
      expect(denied.failureOrNull!.message, contains('không có quyền'));
    });

    test(
      'kiểm trùng: không có người thì không gọi máy chủ, bỏ trùng id',
      () async {
        final repository = FakeMeetingCalendarRepository();
        final useCase = CheckMeetingConflictsUseCase(repository);
        final start = DateTime(2026, 11, 16, 9);
        final none = await useCase.execute(
          workspaceId: 'ws',
          userIds: const [' '],
          startsAt: start,
          endsAt: start.add(const Duration(hours: 1)),
        );
        expect(none.valueOrNull, isEmpty);
        expect(repository.calls, isEmpty);
        await useCase.execute(
          workspaceId: 'ws',
          userIds: const ['u1', 'u1', 'u2'],
          startsAt: start,
          endsAt: start.add(const Duration(hours: 1)),
        );
        expect(repository.lastConflictUsers, ['u1', 'u2']);
      },
    );

    test('phản hồi, biên bản, việc, link khách', () async {
      final repository = FakeMeetingCalendarRepository();
      final pending = await RespondToMeetingUseCase(repository).execute(
        workspaceId: 'ws',
        channelId: 'c1',
        meetingId: 'm1',
        response: MeetingResponse.pending,
      );
      expect(pending.isFailure, isTrue);
      await RespondToMeetingUseCase(repository).execute(
        workspaceId: 'ws',
        channelId: 'c1',
        meetingId: 'm1',
        response: MeetingResponse.accepted,
      );
      expect(repository.lastResponse, MeetingResponse.accepted);

      final minutesUseCase = MeetingMinutesUseCase(repository);
      final tooLong = await minutesUseCase.save(
        workspaceId: 'ws',
        channelId: 'c1',
        meetingId: 'm1',
        content: 'a' * 20001,
      );
      expect(tooLong.failureOrNull!.code, 'MEETING_MINUTES_TOO_LONG');
      await minutesUseCase.save(
        workspaceId: 'ws',
        channelId: 'c1',
        meetingId: 'm1',
        content: '  Chốt  ',
      );
      expect(repository.lastMinutes, 'Chốt');

      final tasks = MeetingTasksUseCase(repository);
      final empty = await tasks.create(
        workspaceId: 'ws',
        channelId: 'c1',
        meetingId: 'm1',
        title: ' ',
      );
      expect(empty.failureOrNull!.code, 'TASK_TITLE_REQUIRED');
      await tasks.create(
        workspaceId: 'ws',
        channelId: 'c1',
        meetingId: 'm1',
        title: ' Gửi báo giá ',
        assigneeUserId: '',
      );
      expect(repository.lastTask, (title: 'Gửi báo giá', assignee: null));

      final guest = MeetingGuestLinkUseCase(repository);
      final on = await guest.setEnabled(
        workspaceId: 'ws',
        channelId: 'c1',
        meetingId: 'm1',
        enabled: true,
      );
      expect(on.valueOrNull!.url, isNotEmpty);
      final off = await guest.setEnabled(
        workspaceId: 'ws',
        channelId: 'c1',
        meetingId: 'm1',
        enabled: false,
      );
      expect(off.valueOrNull!.enabled, isFalse);
      expect(repository.calls, containsAllInOrder(['guestOn', 'guestOff']));
    });

    test('nhóm chọn được: chỉ nhóm đang là thành viên, bỏ bot', () async {
      final conversations = FakeMeetingConversations();
      final groups = await LoadMeetingPeopleUseCase(
        conversations,
      ).groups(workspaceId: 'ws');
      expect(groups.valueOrNull!.map((g) => g.channelId), ['c-a', 'c-b']);
      final members = await LoadMeetingPeopleUseCase(
        conversations,
      ).groupMembers(workspaceId: 'ws', channelId: 'c-a');
      expect(members.valueOrNull!.map((p) => p.userId), ['u1']);
    });
  });
}
