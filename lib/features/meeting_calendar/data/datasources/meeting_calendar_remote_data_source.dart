import '../../../../core/network/api_response.dart';
import '../../../../core/network/api_transport.dart';
import '../../../../l10n/app_strings.dart';
import '../../../conversations/data/datasources/conversation_remote_data_source.dart';
import '../../../conversations/domain/entities/collaboration_room.dart';
import '../../domain/entities/calendar_meeting.dart';

/// Gọi API Lịch họp theo hợp đồng đợt 1 + 2.
final class MeetingCalendarRemoteDataSource {
  const MeetingCalendarRemoteDataSource(this._api);

  final ApiTransport _api;

  String _workspace(String workspaceId) =>
      '/api/v1/workspaces/${_e(workspaceId)}';

  String _meetings(String workspaceId, String channelId) =>
      '${_workspace(workspaceId)}/channels/${_e(channelId)}'
      '/collaboration/meetings';

  String _meeting(String workspaceId, String channelId, String meetingId) =>
      '${_meetings(workspaceId, channelId)}/${_e(meetingId)}';

  Future<List<CalendarMeeting>> listMeetings({
    required String workspaceId,
    required DateTime from,
    required DateTime to,
  }) async {
    final response = await _api.get<Object>(
      '${_workspace(workspaceId)}/meetings',
      queryParameters: {
        'from': from.toUtc().toIso8601String(),
        'to': to.toUtc().toIso8601String(),
      },
    );
    return _meetingList(response.data, workspaceId);
  }

  /// Máy chủ cũ chưa có `GET /meetings?from&to`: dùng danh sách sắp tới.
  Future<List<CalendarMeeting>> listUpcomingMeetings({
    required String workspaceId,
    required int days,
    int limit = 100,
  }) async {
    final response = await _api.get<Object>(
      '${_workspace(workspaceId)}/meetings/upcoming',
      queryParameters: {'days': days, 'limit': limit},
    );
    return _meetingList(response.data, workspaceId);
  }

  Future<CalendarMeeting> getMeeting({
    required String workspaceId,
    required String channelId,
    required String meetingId,
  }) async {
    final response = await _api.get<Object>(
      _meeting(workspaceId, channelId, meetingId),
    );
    return _meetingItem(response.data, workspaceId, channelId);
  }

  Future<CalendarMeeting> createMeeting({
    required String workspaceId,
    required String channelId,
    required MeetingDraft draft,
  }) async {
    final response = await _api.post<Object>(
      _meetings(workspaceId, channelId),
      data: meetingDraftBody(draft),
    );
    return _meetingItem(response.data, workspaceId, channelId);
  }

  Future<void> updateMeeting({
    required String workspaceId,
    required String channelId,
    required String meetingId,
    required MeetingDraft draft,
    required MeetingScope scope,
  }) async {
    await _api.patch<Object>(
      _meeting(workspaceId, channelId, meetingId),
      data: {
        ...meetingDraftBody(draft, includeRecurrence: scope.isSeries),
        'scope': scope.apiValue,
      },
    );
  }

  Future<void> cancelMeeting({
    required String workspaceId,
    required String channelId,
    required String meetingId,
    required MeetingScope scope,
  }) async {
    await _api.post<Object>(
      '${_meeting(workspaceId, channelId, meetingId)}/cancel',
      data: {'scope': scope.apiValue},
    );
  }

  Future<void> respond({
    required String workspaceId,
    required String channelId,
    required String meetingId,
    required MeetingResponse response,
    MeetingScope? scope,
  }) async {
    await _api.post<Object>(
      '${_meeting(workspaceId, channelId, meetingId)}/response',
      data: {'response': response.apiValue, 'scope': ?scope?.apiValue},
    );
  }

  Future<void> saveMinutes({
    required String workspaceId,
    required String channelId,
    required String meetingId,
    required String content,
  }) async {
    await _api.put<Object>(
      '${_meeting(workspaceId, channelId, meetingId)}/minutes',
      data: {'content': content},
    );
  }

  Future<String> publishMinutes({
    required String workspaceId,
    required String channelId,
    required String meetingId,
  }) async {
    final response = await _api.post<Object>(
      '${_meeting(workspaceId, channelId, meetingId)}/minutes/publish',
      data: const <String, Object?>{},
    );
    final map = jsonMap(envelopeData(response.data));
    return stringField(map, const ['message_id', 'messageId']);
  }

  Future<List<CollaborationTask>> listMeetingTasks({
    required String workspaceId,
    required String channelId,
    required String meetingId,
  }) async {
    final response = await _api.get<Object>(
      '${_workspace(workspaceId)}/channels/${_e(channelId)}'
      '/collaboration/tasks',
      queryParameters: {'meeting_id': meetingId},
    );
    return envelopeList(
      response.data,
      'tasks',
    ).map(collaborationTaskFromJson).toList(growable: false);
  }

  Future<CollaborationTask> createMeetingTask({
    required String workspaceId,
    required String channelId,
    required String meetingId,
    required String title,
    String? assigneeUserId,
    DateTime? dueAt,
  }) async {
    final response = await _api.post<Object>(
      '${_workspace(workspaceId)}/channels/${_e(channelId)}'
      '/collaboration/tasks',
      data: compactMap({
        'title': title,
        'meeting_id': meetingId,
        'assignee_user_id': assigneeUserId,
        'due_at': dueAt?.toUtc().toIso8601String(),
      }),
    );
    return collaborationTaskFromJson(envelopeItem(response.data, 'task'));
  }

  Future<List<MeetingConflict>> findConflicts({
    required String workspaceId,
    required List<String> userIds,
    required DateTime startsAt,
    required DateTime endsAt,
    String? excludeMeetingId,
  }) async {
    final response = await _api.get<Object>(
      '${_workspace(workspaceId)}/meetings/conflicts',
      queryParameters: {
        'user_ids': userIds.join(','),
        'starts_at': startsAt.toUtc().toIso8601String(),
        'ends_at': endsAt.toUtc().toIso8601String(),
        if (excludeMeetingId != null && excludeMeetingId.isNotEmpty)
          'exclude_meeting_id': excludeMeetingId,
      },
    );
    return envelopeList(response.data, 'conflicts')
        .map(
          (map) => MeetingConflict(
            userId: stringField(map, const ['user_id']),
            meetingId: stringField(map, const ['meeting_id']),
            startsAt: dateTimeField(map, const ['starts_at']),
            endsAt: nullableDateTimeField(map, const ['ends_at']),
            title: nullableStringField(map, const ['title']),
          ),
        )
        .where((item) => item.userId.isNotEmpty)
        .toList(growable: false);
  }

  Future<MeetingGuestLink> enableGuestLink({
    required String workspaceId,
    required String channelId,
    required String meetingId,
  }) async {
    final response = await _api.post<Object>(
      '${_meeting(workspaceId, channelId, meetingId)}/guest-link',
      data: const <String, Object?>{},
    );
    final map = jsonMap(envelopeData(response.data));
    final url = stringField(map, const ['url']).trim();
    if (url.isEmpty) {
      throw const FormatException('guest-link response has no url');
    }
    return MeetingGuestLink(enabled: true, url: url);
  }

  Future<void> disableGuestLink({
    required String workspaceId,
    required String channelId,
    required String meetingId,
  }) async {
    await _api.delete<Object>(
      '${_meeting(workspaceId, channelId, meetingId)}/guest-link',
    );
  }
}

extension on MeetingScope {
  bool get isSeries => this == MeetingScope.series;
}

String _e(String value) => Uri.encodeComponent(value);

List<CalendarMeeting> _meetingList(Object? data, String workspaceId) {
  return envelopeList(data, 'meetings')
      .map((map) => calendarMeetingFromJson(map, workspaceId: workspaceId))
      .where((item) => item.id.isNotEmpty && item.channelId.isNotEmpty)
      .toList(growable: false);
}

CalendarMeeting _meetingItem(
  Object? data,
  String workspaceId,
  String channelId,
) {
  final map = envelopeItem(data, 'meeting');
  if (stringField(map, const ['id']).isEmpty) {
    throw const FormatException('meeting response has no id');
  }
  return calendarMeetingFromJson(
    map,
    workspaceId: workspaceId,
    channelId: channelId,
  );
}

/// Thân `POST` / `PATCH` cuộc họp. [includeRecurrence] = false khi chỉ sửa một
/// buổi (luật lặp thuộc cả chuỗi).
Map<String, Object?> meetingDraftBody(
  MeetingDraft draft, {
  bool includeRecurrence = true,
}) {
  final recurrence = draft.recurrence;
  final externalUrl = draft.externalUrl?.trim() ?? '';
  return {
    'title': draft.title,
    'description': draft.description,
    'starts_at': draft.startsAt.toUtc().toIso8601String(),
    if (draft.endsAt != null)
      'ends_at': draft.endsAt!.toUtc().toIso8601String(),
    // Chuỗi rỗng = bỏ link ngoài (khi sửa).
    'external_url': externalUrl.isEmpty ? null : externalUrl,
    'reminder_offsets': draft.reminderOffsets,
    'attendee_user_ids': ?draft.attendeeUserIds,
    if (includeRecurrence) 'recurrence': ?_recurrenceBody(recurrence),
    'timezone': ?draft.timezone,
  };
}

Map<String, Object?>? _recurrenceBody(MeetingRecurrence? recurrence) {
  if (recurrence == null) return null;
  final until = recurrence.until;
  return {
    'freq': recurrence.frequency.apiValue,
    'interval': recurrence.interval,
    if (recurrence.frequency == MeetingRecurrenceFrequency.weekly)
      'by_weekday': recurrence.byWeekday,
    'until': until == null ? null : meetingDateOnly(until),
    'count': recurrence.count,
  };
}

/// `YYYY-MM-DD` theo ngày của [value] (không đổi múi giờ).
String meetingDateOnly(DateTime value) {
  String two(int number) => number.toString().padLeft(2, '0');
  return '${value.year.toString().padLeft(4, '0')}-${two(value.month)}'
      '-${two(value.day)}';
}

/// Đọc `MeetingDTO`; thiếu trường mới thì dùng giá trị an toàn.
CalendarMeeting calendarMeetingFromJson(
  JsonMap map, {
  String workspaceId = '',
  String channelId = '',
}) {
  return CalendarMeeting(
    id: stringField(map, const ['id']),
    workspaceId: stringField(map, const [
      'workspace_id',
    ], fallback: workspaceId),
    channelId: stringField(map, const ['channel_id'], fallback: channelId),
    channelName: stringField(map, const ['channel_name']),
    title:
        nullableStringField(map, const ['title']) ?? tr('Cuộc họp', 'Meeting'),
    description: stringField(map, const ['description']),
    startsAt: dateTimeField(map, const ['starts_at']),
    endsAt: nullableDateTimeField(map, const ['ends_at']),
    lobbyOpensAt: nullableDateTimeField(map, const ['lobby_opens_at']),
    status: stringField(map, const [
      'status',
    ], fallback: 'scheduled').trim().toLowerCase(),
    createdBy: nullableStringField(map, const ['created_by']),
    startedAt: nullableDateTimeField(map, const ['started_at']),
    endedAt: nullableDateTimeField(map, const ['ended_at']),
    externalUrl: _httpsOrNull(nullableStringField(map, const ['external_url'])),
    reminderOffsets: _reminderOffsets(map['reminder_offsets']),
    timezone: nullableStringField(map, const ['timezone']),
    seriesId: nullableStringField(map, const ['series_id']),
    recurrence: _recurrenceFromJson(jsonMapOrNull(map['recurrence'])),
    isException: boolField(map, const ['is_exception']),
    myResponse: MeetingResponse.fromApi(map['my_response']),
    attendeeSummary: _summaryFromJson(jsonMapOrNull(map['attendee_summary'])),
    canEdit: boolField(map, const ['can_edit']),
    canCancel: boolField(map, const ['can_cancel']),
    canRespond: boolField(map, const ['can_respond']),
    canEditMinutes: boolField(map, const ['can_edit_minutes']),
    attendees: jsonMapList(map['attendees'])
        .map(
          (item) => MeetingAttendee(
            userId: stringField(item, const ['user_id']),
            displayName:
                nullableStringField(item, const ['display_name']) ??
                tr('Thành viên', 'Member'),
            avatarUrl: nullableStringField(item, const ['avatar_url']),
            isOrganizer:
                stringField(item, const ['role']).trim().toLowerCase() ==
                'organizer',
            response:
                MeetingResponse.fromApi(item['response']) ??
                MeetingResponse.pending,
            respondedAt: nullableDateTimeField(item, const ['responded_at']),
          ),
        )
        .where((item) => item.userId.isNotEmpty)
        .toList(growable: false),
    minutes: _minutesFromJson(jsonMapOrNull(map['minutes'])),
    guestLink: _guestLinkFromJson(jsonMapOrNull(map['guest_link'])),
  );
}

/// Chỉ nhận link https (không mở link lạ máy chủ gửi về).
String? _httpsOrNull(String? value) {
  if (value == null) return null;
  final uri = Uri.tryParse(value);
  if (uri == null || uri.scheme.toLowerCase() != 'https' || uri.host.isEmpty) {
    return null;
  }
  return value;
}

List<int> _reminderOffsets(Object? value) {
  if (value is! List) return defaultReminderOffsets;
  final offsets = <int>[];
  for (final item in value) {
    final number = item is num ? item.toInt() : int.tryParse('$item');
    if (number != null &&
        allowedReminderOffsets.contains(number) &&
        !offsets.contains(number)) {
      offsets.add(number);
    }
  }
  return List.unmodifiable(offsets.take(maxReminderOffsets));
}

MeetingRecurrence? _recurrenceFromJson(JsonMap? map) {
  if (map == null) return null;
  final frequency = MeetingRecurrenceFrequency.fromApi(map['freq']);
  if (frequency == null) return null;
  final weekdays = map['by_weekday'];
  final count = intField(map, const ['count']);
  final until = nullableStringField(map, const ['until']);
  final untilDate = until == null ? null : DateTime.tryParse(until);
  return MeetingRecurrence(
    frequency: frequency,
    interval: intField(map, const ['interval'], fallback: 1).clamp(1, 365),
    byWeekday: weekdays is List
        ? [
            for (final day in weekdays)
              if ((day is num ? day.toInt() : int.tryParse('$day'))
                  case final int number when number >= 1 && number <= 7)
                number,
          ]
        : const [],
    until: untilDate == null
        ? null
        : DateTime(untilDate.year, untilDate.month, untilDate.day),
    count: count > 0 ? count : null,
  );
}

MeetingAttendeeSummary? _summaryFromJson(JsonMap? map) {
  if (map == null) return null;
  return MeetingAttendeeSummary(
    accepted: intField(map, const ['accepted']),
    tentative: intField(map, const ['tentative']),
    declined: intField(map, const ['declined']),
    pending: intField(map, const ['pending']),
  );
}

MeetingMinutes? _minutesFromJson(JsonMap? map) {
  if (map == null) return null;
  return MeetingMinutes(
    content: stringField(map, const ['content']),
    updatedAt: nullableDateTimeField(map, const ['updated_at']),
    updatedBy: nullableStringField(map, const ['updated_by']),
    publishedAt: nullableDateTimeField(map, const ['published_at']),
  );
}

MeetingGuestLink? _guestLinkFromJson(JsonMap? map) {
  if (map == null) return null;
  final url = stringField(map, const ['url']).trim();
  final enabled = boolField(map, const ['enabled']);
  return MeetingGuestLink(
    enabled: enabled && url.isNotEmpty,
    url: enabled ? url : '',
  );
}
