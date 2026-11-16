import '../../../../core/error/failure.dart';
import '../../../../core/result/result.dart';
import '../../../../core/result/result_guard.dart';
import '../../../conversations/domain/entities/collaboration_room.dart';
import '../../domain/entities/calendar_meeting.dart';
import '../../domain/repositories/meeting_calendar_repository.dart';
import '../datasources/meeting_calendar_remote_data_source.dart';

final class MeetingCalendarRepositoryImpl implements MeetingCalendarRepository {
  MeetingCalendarRepositoryImpl(this._remote, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final MeetingCalendarRemoteDataSource _remote;
  final DateTime Function() _clock;

  @override
  Future<Result<List<CalendarMeeting>>> listMeetings({
    required String workspaceId,
    required DateTime from,
    required DateTime to,
  }) async {
    final result = await guardResult(
      () => _remote.listMeetings(workspaceId: workspaceId, from: from, to: to),
    );
    if (result case FailureResult<List<CalendarMeeting>>(
      failure: final failure,
    ) when _isMissingEndpoint(failure)) {
      return _legacyUpcoming(workspaceId: workspaceId, from: from, to: to);
    }
    return result;
  }

  /// Máy chủ cũ (404 không kèm mã lỗi họp): chỉ có danh sách sắp tới, lọc
  /// theo khoảng. Khoảng đã qua hẳn thì trả rỗng.
  Future<Result<List<CalendarMeeting>>> _legacyUpcoming({
    required String workspaceId,
    required DateTime from,
    required DateTime to,
  }) async {
    final now = _clock();
    if (!to.isAfter(now)) return const Success([]);
    final days = to.difference(now).inDays + 1;
    final result = await guardResult(
      () => _remote.listUpcomingMeetings(
        workspaceId: workspaceId,
        days: days.clamp(1, 62),
      ),
    );
    return switch (result) {
      Success(value: final meetings) => Success([
        for (final meeting in meetings)
          if (!meeting.startsAt.isBefore(from) && meeting.startsAt.isBefore(to))
            meeting,
      ]),
      FailureResult(failure: final failure) => FailureResult(failure),
    };
  }

  @override
  Future<Result<CalendarMeeting>> getMeeting({
    required String workspaceId,
    required String channelId,
    required String meetingId,
  }) => guardResult(
    () => _remote.getMeeting(
      workspaceId: workspaceId,
      channelId: channelId,
      meetingId: meetingId,
    ),
  );

  @override
  Future<Result<CalendarMeeting>> createMeeting({
    required String workspaceId,
    required String channelId,
    required MeetingDraft draft,
  }) => guardResult(
    () => _remote.createMeeting(
      workspaceId: workspaceId,
      channelId: channelId,
      draft: draft,
    ),
  );

  @override
  Future<Result<void>> updateMeeting({
    required String workspaceId,
    required String channelId,
    required String meetingId,
    required MeetingDraft draft,
    required MeetingScope scope,
  }) => guardResult(
    () => _remote.updateMeeting(
      workspaceId: workspaceId,
      channelId: channelId,
      meetingId: meetingId,
      draft: draft,
      scope: scope,
    ),
  );

  @override
  Future<Result<void>> cancelMeeting({
    required String workspaceId,
    required String channelId,
    required String meetingId,
    required MeetingScope scope,
  }) => guardResult(
    () => _remote.cancelMeeting(
      workspaceId: workspaceId,
      channelId: channelId,
      meetingId: meetingId,
      scope: scope,
    ),
  );

  @override
  Future<Result<void>> respond({
    required String workspaceId,
    required String channelId,
    required String meetingId,
    required MeetingResponse response,
    MeetingScope? scope,
  }) => guardResult(
    () => _remote.respond(
      workspaceId: workspaceId,
      channelId: channelId,
      meetingId: meetingId,
      response: response,
      scope: scope,
    ),
  );

  @override
  Future<Result<void>> saveMinutes({
    required String workspaceId,
    required String channelId,
    required String meetingId,
    required String content,
  }) => guardResult(
    () => _remote.saveMinutes(
      workspaceId: workspaceId,
      channelId: channelId,
      meetingId: meetingId,
      content: content,
    ),
  );

  @override
  Future<Result<String>> publishMinutes({
    required String workspaceId,
    required String channelId,
    required String meetingId,
  }) => guardResult(
    () => _remote.publishMinutes(
      workspaceId: workspaceId,
      channelId: channelId,
      meetingId: meetingId,
    ),
  );

  @override
  Future<Result<List<CollaborationTask>>> listMeetingTasks({
    required String workspaceId,
    required String channelId,
    required String meetingId,
  }) => guardResult(
    () => _remote.listMeetingTasks(
      workspaceId: workspaceId,
      channelId: channelId,
      meetingId: meetingId,
    ),
  );

  @override
  Future<Result<CollaborationTask>> createMeetingTask({
    required String workspaceId,
    required String channelId,
    required String meetingId,
    required String title,
    String? assigneeUserId,
    DateTime? dueAt,
  }) => guardResult(
    () => _remote.createMeetingTask(
      workspaceId: workspaceId,
      channelId: channelId,
      meetingId: meetingId,
      title: title,
      assigneeUserId: assigneeUserId,
      dueAt: dueAt,
    ),
  );

  @override
  Future<Result<List<MeetingConflict>>> findConflicts({
    required String workspaceId,
    required List<String> userIds,
    required DateTime startsAt,
    required DateTime endsAt,
    String? excludeMeetingId,
  }) => guardResult(
    () => _remote.findConflicts(
      workspaceId: workspaceId,
      userIds: userIds,
      startsAt: startsAt,
      endsAt: endsAt,
      excludeMeetingId: excludeMeetingId,
    ),
  );

  @override
  Future<Result<MeetingGuestLink>> enableGuestLink({
    required String workspaceId,
    required String channelId,
    required String meetingId,
  }) => guardResult(
    () => _remote.enableGuestLink(
      workspaceId: workspaceId,
      channelId: channelId,
      meetingId: meetingId,
    ),
  );

  @override
  Future<Result<void>> disableGuestLink({
    required String workspaceId,
    required String channelId,
    required String meetingId,
  }) => guardResult(
    () => _remote.disableGuestLink(
      workspaceId: workspaceId,
      channelId: channelId,
      meetingId: meetingId,
    ),
  );
}

/// 404 không kèm mã lỗi: máy chủ chưa có đường này (không phải "không thấy
/// cuộc họp").
bool _isMissingEndpoint(Failure failure) {
  if (failure.kind != FailureKind.notFound) return false;
  final code = failure.code?.trim() ?? '';
  return code.isEmpty || code.toUpperCase() == 'NOT_FOUND';
}
