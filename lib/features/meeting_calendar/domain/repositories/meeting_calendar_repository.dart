import '../../../../core/result/result.dart';
import '../../../conversations/domain/entities/collaboration_room.dart';
import '../entities/calendar_meeting.dart';

/// API Lịch họp (gốc `/api/v1/workspaces/{ws}`).
abstract interface class MeetingCalendarRepository {
  /// Mọi cuộc họp trong khoảng [from, to) ở các nhóm mình là thành viên.
  Future<Result<List<CalendarMeeting>>> listMeetings({
    required String workspaceId,
    required DateTime from,
    required DateTime to,
  });

  Future<Result<CalendarMeeting>> getMeeting({
    required String workspaceId,
    required String channelId,
    required String meetingId,
  });

  Future<Result<CalendarMeeting>> createMeeting({
    required String workspaceId,
    required String channelId,
    required MeetingDraft draft,
  });

  Future<Result<void>> updateMeeting({
    required String workspaceId,
    required String channelId,
    required String meetingId,
    required MeetingDraft draft,
    required MeetingScope scope,
  });

  Future<Result<void>> cancelMeeting({
    required String workspaceId,
    required String channelId,
    required String meetingId,
    required MeetingScope scope,
  });

  Future<Result<void>> respond({
    required String workspaceId,
    required String channelId,
    required String meetingId,
    required MeetingResponse response,
    MeetingScope? scope,
  });

  Future<Result<void>> saveMinutes({
    required String workspaceId,
    required String channelId,
    required String meetingId,
    required String content,
  });

  /// Gửi biên bản vào nhóm; trả mã tin nhắn.
  Future<Result<String>> publishMinutes({
    required String workspaceId,
    required String channelId,
    required String meetingId,
  });

  Future<Result<List<CollaborationTask>>> listMeetingTasks({
    required String workspaceId,
    required String channelId,
    required String meetingId,
  });

  Future<Result<CollaborationTask>> createMeetingTask({
    required String workspaceId,
    required String channelId,
    required String meetingId,
    required String title,
    String? assigneeUserId,
    DateTime? dueAt,
  });

  Future<Result<List<MeetingConflict>>> findConflicts({
    required String workspaceId,
    required List<String> userIds,
    required DateTime startsAt,
    required DateTime endsAt,
    String? excludeMeetingId,
  });

  Future<Result<MeetingGuestLink>> enableGuestLink({
    required String workspaceId,
    required String channelId,
    required String meetingId,
  });

  Future<Result<void>> disableGuestLink({
    required String workspaceId,
    required String channelId,
    required String meetingId,
  });
}
