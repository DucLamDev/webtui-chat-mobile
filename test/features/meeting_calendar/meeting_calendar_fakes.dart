import 'package:webtui_chat/core/error/failure.dart';
import 'package:webtui_chat/core/result/result.dart';
import 'package:webtui_chat/features/conversations/domain/entities/chat_message.dart';
import 'package:webtui_chat/features/conversations/domain/entities/collaboration_room.dart';
import 'package:webtui_chat/features/conversations/domain/entities/conversation_summary.dart';
import 'package:webtui_chat/features/conversations/domain/repositories/conversation_repository.dart';
import 'package:webtui_chat/features/meeting_calendar/domain/entities/calendar_meeting.dart';
import 'package:webtui_chat/features/meeting_calendar/domain/repositories/meeting_calendar_repository.dart';

CalendarMeeting fakeMeeting(
  String id, {
  required DateTime startsAt,
  DateTime? endsAt,
  String title = 'Họp',
  String channelId = 'c1',
  String channelName = 'Nhóm Kỹ thuật',
  String status = 'scheduled',
  MeetingResponse? myResponse,
  bool canEdit = false,
  bool canCancel = false,
  bool canRespond = false,
  bool canEditMinutes = false,
  String? externalUrl,
  String? seriesId,
  MeetingRecurrence? recurrence,
  List<MeetingAttendee> attendees = const [],
  MeetingAttendeeSummary? attendeeSummary,
  MeetingMinutes? minutes,
  MeetingGuestLink? guestLink,
}) {
  return CalendarMeeting(
    id: id,
    workspaceId: 'ws',
    channelId: channelId,
    channelName: channelName,
    title: title,
    startsAt: startsAt,
    endsAt: endsAt ?? startsAt.add(const Duration(hours: 1)),
    status: status,
    myResponse: myResponse,
    canEdit: canEdit,
    canCancel: canCancel,
    canRespond: canRespond,
    canEditMinutes: canEditMinutes,
    externalUrl: externalUrl,
    seriesId: seriesId,
    recurrence: recurrence,
    attendees: attendees,
    attendeeSummary: attendeeSummary,
    minutes: minutes,
    guestLink: guestLink,
  );
}

/// Kho Lịch họp giả: ghi lại lời gọi, trả dữ liệu đặt sẵn.
final class FakeMeetingCalendarRepository implements MeetingCalendarRepository {
  FakeMeetingCalendarRepository({
    this.meetings = const [],
    this.detail,
    this.tasks = const [],
    this.conflicts = const [],
    this.listFailure,
    this.detailFailure,
    this.writeFailure,
  });

  List<CalendarMeeting> meetings;
  CalendarMeeting? detail;
  List<CollaborationTask> tasks;
  List<MeetingConflict> conflicts;
  Failure? listFailure;
  Failure? detailFailure;
  Failure? writeFailure;

  final calls = <String>[];
  final ranges = <(DateTime, DateTime)>[];
  final drafts = <MeetingDraft>[];
  final createdChannels = <String>[];
  MeetingScope? lastScope;
  MeetingResponse? lastResponse;
  String? lastMinutes;
  ({String title, String? assignee})? lastTask;
  List<String>? lastConflictUsers;

  Result<T> _write<T>(T value) {
    final failure = writeFailure;
    return failure == null ? Success(value) : FailureResult(failure);
  }

  @override
  Future<Result<List<CalendarMeeting>>> listMeetings({
    required String workspaceId,
    required DateTime from,
    required DateTime to,
  }) async {
    calls.add('list');
    ranges.add((from, to));
    final failure = listFailure;
    if (failure != null) return FailureResult(failure);
    return Success([
      for (final meeting in meetings)
        if (!meeting.startsAt.isBefore(from) && meeting.startsAt.isBefore(to))
          meeting,
    ]);
  }

  @override
  Future<Result<CalendarMeeting>> getMeeting({
    required String workspaceId,
    required String channelId,
    required String meetingId,
  }) async {
    calls.add('get:$channelId/$meetingId');
    final failure = detailFailure;
    if (failure != null) return FailureResult(failure);
    final found =
        detail ?? meetings.where((item) => item.id == meetingId).firstOrNull;
    if (found == null) {
      return const FailureResult(
        Failure(kind: FailureKind.notFound, message: 'không thấy'),
      );
    }
    return Success(found);
  }

  @override
  Future<Result<CalendarMeeting>> createMeeting({
    required String workspaceId,
    required String channelId,
    required MeetingDraft draft,
  }) async {
    calls.add('create:$channelId');
    drafts.add(draft);
    createdChannels.add(channelId);
    return _write(
      CalendarMeeting(
        id: 'new',
        workspaceId: workspaceId,
        channelId: channelId,
        title: draft.title,
        startsAt: draft.startsAt,
        endsAt: draft.endsAt,
      ),
    );
  }

  @override
  Future<Result<void>> updateMeeting({
    required String workspaceId,
    required String channelId,
    required String meetingId,
    required MeetingDraft draft,
    required MeetingScope scope,
  }) async {
    calls.add('update:$meetingId');
    drafts.add(draft);
    lastScope = scope;
    return _write(null);
  }

  @override
  Future<Result<void>> cancelMeeting({
    required String workspaceId,
    required String channelId,
    required String meetingId,
    required MeetingScope scope,
  }) async {
    calls.add('cancel:$meetingId');
    lastScope = scope;
    return _write(null);
  }

  @override
  Future<Result<void>> respond({
    required String workspaceId,
    required String channelId,
    required String meetingId,
    required MeetingResponse response,
    MeetingScope? scope,
  }) async {
    calls.add('respond:${response.apiValue}');
    lastResponse = response;
    return _write(null);
  }

  @override
  Future<Result<void>> saveMinutes({
    required String workspaceId,
    required String channelId,
    required String meetingId,
    required String content,
  }) async {
    calls.add('saveMinutes');
    lastMinutes = content;
    return _write(null);
  }

  @override
  Future<Result<String>> publishMinutes({
    required String workspaceId,
    required String channelId,
    required String meetingId,
  }) async {
    calls.add('publishMinutes');
    return _write('msg-1');
  }

  @override
  Future<Result<List<CollaborationTask>>> listMeetingTasks({
    required String workspaceId,
    required String channelId,
    required String meetingId,
  }) async {
    calls.add('tasks:$meetingId');
    return Success(tasks);
  }

  @override
  Future<Result<CollaborationTask>> createMeetingTask({
    required String workspaceId,
    required String channelId,
    required String meetingId,
    required String title,
    String? assigneeUserId,
    DateTime? dueAt,
  }) async {
    calls.add('createTask');
    lastTask = (title: title, assignee: assigneeUserId);
    return _write(
      CollaborationTask(
        id: 't-new',
        title: title,
        status: 'open',
        createdAt: DateTime.utc(2026, 11, 16),
      ),
    );
  }

  @override
  Future<Result<List<MeetingConflict>>> findConflicts({
    required String workspaceId,
    required List<String> userIds,
    required DateTime startsAt,
    required DateTime endsAt,
    String? excludeMeetingId,
  }) async {
    calls.add('conflicts');
    lastConflictUsers = userIds;
    return Success(conflicts);
  }

  @override
  Future<Result<MeetingGuestLink>> enableGuestLink({
    required String workspaceId,
    required String channelId,
    required String meetingId,
  }) async {
    calls.add('guestOn');
    return _write(
      const MeetingGuestLink(enabled: true, url: 'https://h.example/g/1'),
    );
  }

  @override
  Future<Result<void>> disableGuestLink({
    required String workspaceId,
    required String channelId,
    required String meetingId,
  }) async {
    calls.add('guestOff');
    return _write(null);
  }
}

/// Kho hội thoại giả cho biểu mẫu họp: nhóm, thành viên, tạo nhóm.
ConversationSummary fakeChannel(
  String id,
  String title, {
  MembershipStatus status = MembershipStatus.active,
  bool noticeBot = false,
}) {
  return ConversationSummary(
    id: id,
    workspaceId: 'ws',
    channelId: id,
    kind: ConversationKind.channel,
    title: title,
    preview: '',
    updatedAt: DateTime.utc(2026, 11, 1),
    membershipStatus: status,
    noticeBot: noticeBot,
    channelVisibility: ChannelVisibility.private,
  );
}

final class FakeMeetingConversations implements ConversationRepository {
  final created = <({String name, ChannelVisibility visibility})>[];
  final added = <String>[];

  @override
  Future<Result<ConversationSummary>> createChannel({
    required String workspaceId,
    required String slug,
    required String name,
    required String description,
    required ChannelVisibility visibility,
  }) async {
    created.add((name: name, visibility: visibility));
    return Success(fakeChannel('new-group', name));
  }

  @override
  Future<Result<ChannelMember>> addMember({
    required String workspaceId,
    required String channelId,
    required String userId,
  }) async {
    added.add(userId);
    return Success(fakeMember(userId, 'active'));
  }

  @override
  Future<Result<List<ConversationSummary>>> listChannels({
    required String workspaceId,
  }) async {
    return Success([
      fakeChannel('c-b', 'Bán hàng'),
      fakeChannel('c-a', 'An toàn', status: MembershipStatus.muted),
      fakeChannel('c-left', 'Đã rời', status: MembershipStatus.left),
      fakeChannel('c-bot', 'Bot', noticeBot: true),
    ]);
  }

  @override
  Future<Result<List<ChannelMember>>> listMembers({
    required String workspaceId,
    required String channelId,
  }) async {
    return Success([fakeMember('u1', 'active'), fakeMember('u9', 'left')]);
  }

  @override
  Future<Result<List<ContactSummary>>> listWorkspaceMembers({
    required String workspaceId,
  }) async {
    return const Success([
      ContactSummary(
        userId: 'u7',
        displayName: 'Hà',
        username: 'ha',
        email: 'ha@example.com',
        status: 'active',
      ),
      ContactSummary(
        userId: 'u8',
        displayName: 'Bình',
        username: 'binh',
        email: 'binh@example.com',
        status: 'active',
      ),
    ]);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

ChannelMember fakeMember(String userId, String status) => ChannelMember(
  channelId: 'c',
  userId: userId,
  email: '$userId@example.com',
  username: userId,
  displayName: 'Người $userId',
  status: status,
  joinedAt: DateTime.utc(2026, 11, 1),
);
