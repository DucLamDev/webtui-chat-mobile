import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/core/error/failure.dart';
import 'package:webtui_chat/core/network/api_transport.dart';
import 'package:webtui_chat/core/result/result.dart';
import 'package:webtui_chat/features/meeting_calendar/data/datasources/meeting_calendar_remote_data_source.dart';
import 'package:webtui_chat/features/meeting_calendar/data/repositories/meeting_calendar_repository_impl.dart';
import 'package:webtui_chat/features/meeting_calendar/domain/entities/calendar_meeting.dart';

const _fullMeeting = {
  'id': 'm1',
  'workspace_id': 'w1',
  'channel_id': 'c1',
  'channel_name': 'Nhóm dự án',
  'title': 'Họp tuần',
  'description': 'Bàn kế hoạch',
  'starts_at': '2026-11-18T02:00:00Z',
  'ends_at': '2026-11-18T03:00:00Z',
  'status': 'scheduled',
  'room_policy': 'keep',
  'created_by': 'u1',
  'created_at': '2026-11-10T00:00:00Z',
  'updated_at': '2026-11-10T00:00:00Z',
  'external_url': 'https://meet.google.com/abc-defg-hij',
  'reminder_offsets': [30, 5, 0],
  'timezone': 'Asia/Ho_Chi_Minh',
  'series_id': 's1',
  'recurrence': {
    'freq': 'weekly',
    'interval': 1,
    'by_weekday': [1, 3, 5],
    'until': '2027-03-31',
    'count': null,
  },
  'is_exception': true,
  'my_response': 'tentative',
  'attendee_summary': {
    'accepted': 3,
    'tentative': 1,
    'declined': 0,
    'pending': 2,
  },
  'can_edit': true,
  'can_cancel': true,
  'can_respond': true,
  'can_edit_minutes': true,
  'attendees': [
    {
      'user_id': 'u1',
      'display_name': 'Lan',
      'avatar_url': null,
      'role': 'organizer',
      'response': 'accepted',
      'responded_at': '2026-11-10T00:00:00Z',
    },
    {
      'user_id': 'u2',
      'display_name': 'Minh',
      'role': 'attendee',
      'response': 'pending',
    },
  ],
  'minutes': {
    'content': 'Chốt lịch',
    'updated_at': '2026-11-18T04:00:00Z',
    'updated_by': 'u1',
    'published_at': null,
  },
  'guest_link': {'enabled': true, 'url': 'https://chat.example/g/abc'},
};

void main() {
  group('đọc MeetingDTO', () {
    test('đủ trường mới', () {
      final meeting = calendarMeetingFromJson(_fullMeeting);
      expect(meeting.id, 'm1');
      expect(meeting.channelName, 'Nhóm dự án');
      expect(meeting.externalUrl, 'https://meet.google.com/abc-defg-hij');
      expect(meeting.reminderOffsets, [30, 5, 0]);
      expect(meeting.timezone, 'Asia/Ho_Chi_Minh');
      expect(meeting.seriesId, 's1');
      expect(meeting.isRecurring, isTrue);
      expect(meeting.recurrence!.frequency, MeetingRecurrenceFrequency.weekly);
      expect(meeting.recurrence!.byWeekday, [1, 3, 5]);
      expect(meeting.recurrence!.until, DateTime(2027, 3, 31));
      expect(meeting.recurrence!.count, isNull);
      expect(meeting.isException, isTrue);
      expect(meeting.myResponse, MeetingResponse.tentative);
      expect(meeting.attendeeSummary!.total, 6);
      expect(meeting.canEdit && meeting.canCancel, isTrue);
      expect(meeting.canRespond && meeting.canEditMinutes, isTrue);
      expect(meeting.attendees, hasLength(2));
      expect(meeting.attendees.first.isOrganizer, isTrue);
      expect(meeting.attendees.first.response, MeetingResponse.accepted);
      expect(meeting.attendees.last.isOrganizer, isFalse);
      expect(meeting.minutes!.content, 'Chốt lịch');
      expect(meeting.minutes!.isPublished, isFalse);
      expect(meeting.guestLink!.enabled, isTrue);
      expect(meeting.guestLink!.url, 'https://chat.example/g/abc');
    });

    test('máy chủ cũ thiếu trường mới: giá trị an toàn', () {
      final meeting = calendarMeetingFromJson({
        'id': 'm2',
        'channel_id': 'c1',
        'title': 'Cũ',
        'starts_at': '2026-11-18T02:00:00Z',
        'status': 'scheduled',
      }, workspaceId: 'w1');
      expect(meeting.workspaceId, 'w1');
      expect(meeting.channelName, '');
      expect(meeting.externalUrl, isNull);
      expect(meeting.reminderOffsets, defaultReminderOffsets);
      expect(meeting.recurrence, isNull);
      expect(meeting.isRecurring, isFalse);
      expect(meeting.myResponse, isNull);
      expect(meeting.attendeeSummary, isNull);
      expect(meeting.canEdit, isFalse);
      expect(meeting.canCancel, isFalse);
      expect(meeting.canRespond, isFalse);
      expect(meeting.canEditMinutes, isFalse);
      expect(meeting.attendees, isEmpty);
      expect(meeting.minutes, isNull);
      expect(meeting.guestLink, isNull);
      expect(
        meeting.effectiveEnd,
        DateTime.utc(2026, 11, 18, 3),
        reason: 'thiếu ends_at thì tính 60 phút',
      );
    });

    test('bỏ giá trị lạ: link không https, mốc nhắc lạ, phản hồi lạ', () {
      final meeting = calendarMeetingFromJson({
        'id': 'm3',
        'channel_id': 'c1',
        'starts_at': '2026-11-18T02:00:00Z',
        'external_url': 'javascript:alert(1)',
        'reminder_offsets': [15, 7, 15, 0, 5, 60],
        'my_response': 'maybe',
        'recurrence': {'freq': 'yearly'},
        'guest_link': {'enabled': false, 'url': 'https://x.example/g'},
      });
      expect(meeting.title, 'Cuộc họp');
      expect(meeting.externalUrl, isNull);
      expect(meeting.reminderOffsets, [15, 0, 5]);
      expect(meeting.myResponse, isNull);
      expect(meeting.recurrence, isNull);
      expect(meeting.guestLink!.enabled, isFalse);
      expect(meeting.guestLink!.url, '');
    });
  });

  group('đường dẫn và phương thức', () {
    test('danh sách theo khoảng: GET /meetings?from&to (UTC)', () async {
      final transport = _Transport({
        'data': {
          'meetings': [_fullMeeting],
        },
      });
      final list = await MeetingCalendarRemoteDataSource(transport)
          .listMeetings(
            workspaceId: 'w 1',
            from: DateTime.utc(2026, 11, 16),
            to: DateTime.utc(2026, 11, 23),
          );
      final call = transport.calls.single;
      expect(call.line, 'GET /api/v1/workspaces/w%201/meetings');
      expect(call.query, {
        'from': '2026-11-16T00:00:00.000Z',
        'to': '2026-11-23T00:00:00.000Z',
      });
      expect(list.single.id, 'm1');
    });

    test('chi tiết, tạo, sửa, huỷ, phản hồi', () async {
      final transport = _Transport({
        'data': {'meeting': _fullMeeting},
      });
      final remote = MeetingCalendarRemoteDataSource(transport);
      const base = '/api/v1/workspaces/w1/channels/c1/collaboration/meetings';
      await remote.getMeeting(
        workspaceId: 'w1',
        channelId: 'c1',
        meetingId: 'm1',
      );
      final draft = MeetingDraft(
        title: 'Họp',
        startsAt: DateTime.utc(2026, 11, 18, 2),
        endsAt: DateTime.utc(2026, 11, 18, 3),
        externalUrl: 'https://meet.google.com/x',
        reminderOffsets: const [15, 0],
        attendeeUserIds: const ['u1', 'u2'],
        timezone: 'Asia/Ho_Chi_Minh',
        recurrence: MeetingRecurrence(
          frequency: MeetingRecurrenceFrequency.weekly,
          byWeekday: const [1, 3],
          until: DateTime(2027, 3, 31),
        ),
      );
      await remote.createMeeting(
        workspaceId: 'w1',
        channelId: 'c1',
        draft: draft,
      );
      await remote.updateMeeting(
        workspaceId: 'w1',
        channelId: 'c1',
        meetingId: 'm1',
        draft: draft,
        scope: MeetingScope.occurrence,
      );
      await remote.updateMeeting(
        workspaceId: 'w1',
        channelId: 'c1',
        meetingId: 'm1',
        draft: draft,
        scope: MeetingScope.series,
      );
      await remote.cancelMeeting(
        workspaceId: 'w1',
        channelId: 'c1',
        meetingId: 'm1',
        scope: MeetingScope.series,
      );
      await remote.respond(
        workspaceId: 'w1',
        channelId: 'c1',
        meetingId: 'm1',
        response: MeetingResponse.declined,
      );
      expect(transport.calls.map((call) => call.line), [
        'GET $base/m1',
        'POST $base',
        'PATCH $base/m1',
        'PATCH $base/m1',
        'POST $base/m1/cancel',
        'POST $base/m1/response',
      ]);
      final created = transport.calls[1].data! as Map;
      expect(created['title'], 'Họp');
      expect(created['starts_at'], '2026-11-18T02:00:00.000Z');
      expect(created['ends_at'], '2026-11-18T03:00:00.000Z');
      expect(created['external_url'], 'https://meet.google.com/x');
      expect(created['reminder_offsets'], [15, 0]);
      expect(created['attendee_user_ids'], ['u1', 'u2']);
      expect(created['timezone'], 'Asia/Ho_Chi_Minh');
      expect(created['recurrence'], {
        'freq': 'weekly',
        'interval': 1,
        'by_weekday': [1, 3],
        'until': '2027-03-31',
        'count': null,
      });
      final onlyThis = transport.calls[2].data! as Map;
      expect(onlyThis['scope'], 'this');
      expect(onlyThis.containsKey('recurrence'), isFalse);
      final series = transport.calls[3].data! as Map;
      expect(series['scope'], 'series');
      expect(series['recurrence'], isNotNull);
      expect(transport.calls[4].data, {'scope': 'series'});
      expect(transport.calls[5].data, {'response': 'declined'});
    });

    test('biên bản, việc theo meeting_id, kiểm trùng, link khách', () async {
      final transport = _Transport({
        'data': {
          'message_id': 'msg1',
          'url': 'https://chat.example/g/1',
          'tasks': [
            {
              'id': 't1',
              'title': 'Gửi báo giá',
              'status': 'open',
              'created_at': '2026-11-18T04:00:00Z',
            },
          ],
          'task': {
            'id': 't2',
            'title': 'Việc mới',
            'status': 'open',
            'created_at': '2026-11-18T04:00:00Z',
          },
          'conflicts': [
            {
              'user_id': 'u2',
              'meeting_id': 'm9',
              'starts_at': '2026-11-18T02:30:00Z',
              'ends_at': '2026-11-18T03:30:00Z',
            },
          ],
        },
      });
      final remote = MeetingCalendarRemoteDataSource(transport);
      const ws = '/api/v1/workspaces/w1';
      const base = '$ws/channels/c1/collaboration/meetings/m1';
      await remote.saveMinutes(
        workspaceId: 'w1',
        channelId: 'c1',
        meetingId: 'm1',
        content: 'Nội dung',
      );
      final messageId = await remote.publishMinutes(
        workspaceId: 'w1',
        channelId: 'c1',
        meetingId: 'm1',
      );
      final tasks = await remote.listMeetingTasks(
        workspaceId: 'w1',
        channelId: 'c1',
        meetingId: 'm1',
      );
      final task = await remote.createMeetingTask(
        workspaceId: 'w1',
        channelId: 'c1',
        meetingId: 'm1',
        title: 'Việc mới',
        assigneeUserId: 'u2',
      );
      final conflicts = await remote.findConflicts(
        workspaceId: 'w1',
        userIds: const ['u1', 'u2'],
        startsAt: DateTime.utc(2026, 11, 18, 2),
        endsAt: DateTime.utc(2026, 11, 18, 3),
        excludeMeetingId: 'm1',
      );
      final link = await remote.enableGuestLink(
        workspaceId: 'w1',
        channelId: 'c1',
        meetingId: 'm1',
      );
      await remote.disableGuestLink(
        workspaceId: 'w1',
        channelId: 'c1',
        meetingId: 'm1',
      );
      expect(transport.calls.map((call) => call.line), [
        'PUT $base/minutes',
        'POST $base/minutes/publish',
        'GET $ws/channels/c1/collaboration/tasks',
        'POST $ws/channels/c1/collaboration/tasks',
        'GET $ws/meetings/conflicts',
        'POST $base/guest-link',
        'DELETE $base/guest-link',
      ]);
      expect(transport.calls[0].data, {'content': 'Nội dung'});
      expect(messageId, 'msg1');
      expect(transport.calls[2].query, {'meeting_id': 'm1'});
      expect(tasks.single.title, 'Gửi báo giá');
      expect(transport.calls[3].data, {
        'title': 'Việc mới',
        'meeting_id': 'm1',
        'assignee_user_id': 'u2',
      });
      expect(task.id, 't2');
      expect(transport.calls[4].query, {
        'user_ids': 'u1,u2',
        'starts_at': '2026-11-18T02:00:00.000Z',
        'ends_at': '2026-11-18T03:00:00.000Z',
        'exclude_meeting_id': 'm1',
      });
      expect(conflicts.single.userId, 'u2');
      expect(conflicts.single.title, isNull);
      expect(link.enabled, isTrue);
      expect(link.url, 'https://chat.example/g/1');
    });
  });

  group('kho Lịch họp', () {
    test(
      'máy chủ cũ (404 không mã): dùng /meetings/upcoming và lọc khoảng',
      () async {
        final transport = _Transport(
          {
            'data': {
              'meetings': [
                {
                  ..._fullMeeting,
                  'id': 'trong',
                  'starts_at': '2026-11-18T02:00:00Z',
                },
                {
                  ..._fullMeeting,
                  'id': 'ngoai',
                  'starts_at': '2026-12-30T02:00:00Z',
                },
              ],
            },
          },
          failPaths: {'/api/v1/workspaces/w1/meetings'},
        );
        final repository = MeetingCalendarRepositoryImpl(
          MeetingCalendarRemoteDataSource(transport),
          clock: () => DateTime.utc(2026, 11, 16),
        );
        final result = await repository.listMeetings(
          workspaceId: 'w1',
          from: DateTime.utc(2026, 11, 16),
          to: DateTime.utc(2026, 11, 23),
        );
        expect(transport.calls.map((call) => call.line), [
          'GET /api/v1/workspaces/w1/meetings',
          'GET /api/v1/workspaces/w1/meetings/upcoming',
        ]);
        expect(transport.calls.last.query, {'days': 8, 'limit': 100});
        expect(result.valueOrNull!.map((m) => m.id), ['trong']);
      },
    );

    test('máy chủ cũ, khoảng đã qua: trả rỗng, không gọi thêm', () async {
      final transport = _Transport(
        const {},
        failPaths: {'/api/v1/workspaces/w1/meetings'},
      );
      final repository = MeetingCalendarRepositoryImpl(
        MeetingCalendarRemoteDataSource(transport),
        clock: () => DateTime.utc(2026, 11, 16),
      );
      final result = await repository.listMeetings(
        workspaceId: 'w1',
        from: DateTime.utc(2026, 10, 1),
        to: DateTime.utc(2026, 11, 1),
      );
      expect(result, isA<Success<List<CalendarMeeting>>>());
      expect(result.valueOrNull, isEmpty);
      expect(transport.calls, hasLength(1));
    });

    test('lỗi chi tiết 404 có mã MEETING_NOT_FOUND: báo lỗi', () async {
      final transport = _Transport(
        const {},
        failPaths: {
          '/api/v1/workspaces/w1/channels/c1/collaboration/meetings/m1',
        },
        failCode: 'MEETING_NOT_FOUND',
      );
      final result = await MeetingCalendarRepositoryImpl(
        MeetingCalendarRemoteDataSource(transport),
      ).getMeeting(workspaceId: 'w1', channelId: 'c1', meetingId: 'm1');
      expect(result.failureOrNull!.kind, FailureKind.notFound);
      expect(result.failureOrNull!.code, 'MEETING_NOT_FOUND');
    });
  });
}

final class _Call {
  const _Call(this.line, this.data, this.query);

  final String line;
  final Object? data;
  final Map<String, dynamic>? query;
}

final class _Transport implements ApiTransport {
  _Transport(this.body, {this.failPaths = const {}, this.failCode});

  final Object? body;
  final Set<String> failPaths;
  final String? failCode;
  final calls = <_Call>[];

  Future<Response<T>> _reply<T>(
    String method,
    String path,
    Object? data,
    Map<String, dynamic>? query,
  ) async {
    calls.add(_Call('$method $path', data, query));
    if (failPaths.contains(path)) {
      final options = RequestOptions(path: path);
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.badResponse,
        response: Response<Object>(
          requestOptions: options,
          statusCode: 404,
          data: failCode == null
              ? {'error': 'not found'}
              : {
                  'error': {'code': failCode, 'message': 'not found'},
                },
        ),
      );
    }
    return Response<T>(
      requestOptions: RequestOptions(path: path),
      data: body as T,
      statusCode: 200,
    );
  }

  @override
  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) => _reply('GET', path, null, queryParameters);

  @override
  Future<Response<T>> post<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) => _reply('POST', path, data, queryParameters);

  @override
  Future<Response<T>> put<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) => _reply('PUT', path, data, queryParameters);

  @override
  Future<Response<T>> patch<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) => _reply('PATCH', path, data, queryParameters);

  @override
  Future<Response<T>> delete<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) => _reply('DELETE', path, data, queryParameters);
}
