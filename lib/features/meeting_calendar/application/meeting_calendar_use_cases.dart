import '../../../core/error/failure.dart';
import '../../../core/result/result.dart';
import '../../../l10n/app_strings.dart';
import '../../conversations/application/use_cases/create_group_use_case.dart';
import '../../conversations/domain/entities/collaboration_room.dart';
import '../../conversations/domain/entities/conversation_summary.dart';
import '../../conversations/domain/repositories/conversation_repository.dart';
import '../domain/entities/calendar_meeting.dart';
import '../domain/repositories/meeting_calendar_repository.dart';

const maxMeetingTitleLength = 200;
const maxMeetingDescriptionLength = 5000;
const maxMeetingMinutesLength = 20000;
const maxMeetingUrlLength = 2048;
const maxMeetingRangeDays = 62;
const maxMeetingOccurrences = 100;
const maxMeetingTaskTitleLength = 200;

Failure _validation(String message, String code) =>
    Failure(kind: FailureKind.validation, message: message, code: code);

/// Tiêu đề: bắt buộc, tối đa [maxMeetingTitleLength] ký tự.
String? validateMeetingTitle(String raw) {
  final title = raw.trim();
  if (title.isEmpty) {
    return tr('Hãy nhập tiêu đề cuộc họp.', 'Enter a meeting title.');
  }
  if (title.runes.length > maxMeetingTitleLength) {
    return tr(
      'Tiêu đề tối đa $maxMeetingTitleLength ký tự.',
      'Titles can be up to $maxMeetingTitleLength characters.',
    );
  }
  return null;
}

/// Link họp ngoài: để trống được; có thì phải là https, có tên máy chủ, không
/// kèm tài khoản.
String? validateMeetingExternalUrl(String raw) {
  final url = raw.trim();
  if (url.isEmpty) return null;
  final needHttps = tr(
    'Link họp phải bắt đầu bằng https://',
    'The meeting link must start with https://',
  );
  if (url.length > maxMeetingUrlLength) {
    return tr(
      'Link họp tối đa $maxMeetingUrlLength ký tự.',
      'Meeting links can be up to $maxMeetingUrlLength characters.',
    );
  }
  final uri = Uri.tryParse(url);
  if (uri == null ||
      !url.toLowerCase().startsWith('https://') ||
      uri.host.isEmpty) {
    return needHttps;
  }
  if (uri.userInfo.isNotEmpty) {
    return tr(
      'Link họp không được chứa tên đăng nhập hoặc mật khẩu.',
      'The meeting link can\'t contain a username or password.',
    );
  }
  return null;
}

/// Giờ: kết thúc sau bắt đầu; tạo mới thì không bắt đầu trong quá khứ (cho
/// lệch 5 phút vì người dùng chọn theo phút).
String? validateMeetingTimes({
  required DateTime startsAt,
  required DateTime? endsAt,
  required DateTime now,
  required bool isNew,
}) {
  if (endsAt != null && !endsAt.isAfter(startsAt)) {
    return tr(
      'Giờ kết thúc phải sau giờ bắt đầu.',
      'The end time must be after the start time.',
    );
  }
  if (isNew && startsAt.isBefore(now.subtract(const Duration(minutes: 5)))) {
    return tr(
      'Giờ bắt đầu đã qua. Hãy chọn giờ khác.',
      'The start time has passed. Choose another time.',
    );
  }
  return null;
}

/// Mốc nhắc: chỉ giá trị cho phép, không trùng, tối đa [maxReminderOffsets].
String? validateReminderOffsets(List<int> offsets) {
  if (offsets.length > maxReminderOffsets) {
    return tr(
      'Chọn tối đa $maxReminderOffsets mốc nhắc.',
      'Choose up to $maxReminderOffsets reminders.',
    );
  }
  if (offsets.toSet().length != offsets.length ||
      offsets.any((item) => !allowedReminderOffsets.contains(item))) {
    return tr('Mốc nhắc không hợp lệ.', 'Invalid reminder.');
  }
  return null;
}

/// Luật lặp: theo tuần phải chọn thứ; số buổi 1–100; ngày kết thúc không trước
/// ngày bắt đầu.
String? validateMeetingRecurrence(
  MeetingRecurrence? recurrence, {
  required DateTime startsAt,
}) {
  if (recurrence == null) return null;
  if (recurrence.frequency == MeetingRecurrenceFrequency.weekly &&
      recurrence.byWeekday.isEmpty) {
    return tr(
      'Hãy chọn ít nhất một thứ trong tuần.',
      'Choose at least one day of the week.',
    );
  }
  final count = recurrence.count;
  if (count != null && (count < 1 || count > maxMeetingOccurrences)) {
    return tr(
      'Số buổi từ 1 đến $maxMeetingOccurrences.',
      'Occurrences must be between 1 and $maxMeetingOccurrences.',
    );
  }
  final until = recurrence.until;
  if (until != null) {
    final startDay = DateTime(startsAt.year, startsAt.month, startsAt.day);
    final untilDay = DateTime(until.year, until.month, until.day);
    if (untilDay.isBefore(startDay)) {
      return tr(
        'Ngày kết thúc lặp phải từ ngày bắt đầu trở đi.',
        'The repeat end date must be on or after the start date.',
      );
    }
  }
  return null;
}

/// Kiểm toàn bộ nội dung trước khi gửi; trả lỗi đầu tiên.
Failure? validateMeetingDraft(
  MeetingDraft draft, {
  required DateTime now,
  required bool isNew,
}) {
  final title = validateMeetingTitle(draft.title);
  if (title != null) return _validation(title, 'MEETING_TITLE_INVALID');
  if (draft.description.runes.length > maxMeetingDescriptionLength) {
    return _validation(
      tr(
        'Nội dung tối đa $maxMeetingDescriptionLength ký tự.',
        'The description can be up to $maxMeetingDescriptionLength characters.',
      ),
      'MEETING_DESCRIPTION_TOO_LONG',
    );
  }
  final times = validateMeetingTimes(
    startsAt: draft.startsAt,
    endsAt: draft.endsAt,
    now: now,
    isNew: isNew,
  );
  if (times != null) return _validation(times, 'MEETING_TIME_INVALID');
  final url = validateMeetingExternalUrl(draft.externalUrl ?? '');
  if (url != null) return _validation(url, 'MEETING_URL_INVALID');
  final reminders = validateReminderOffsets(draft.reminderOffsets);
  if (reminders != null) {
    return _validation(reminders, 'MEETING_REMINDERS_INVALID');
  }
  final recurrence = validateMeetingRecurrence(
    draft.recurrence,
    startsAt: draft.startsAt,
  );
  if (recurrence != null) {
    return _validation(recurrence, 'MEETING_RECURRENCE_INVALID');
  }
  return null;
}

/// Đổi lỗi máy chủ sang câu dễ hiểu cho các thao tác họp.
Failure friendlyMeetingFailure(Failure failure) {
  if (failure.kind == FailureKind.forbidden) {
    return failure.copyWith(
      message: tr(
        'Bạn không có quyền làm việc này với cuộc họp.',
        'You don\'t have permission to do this for the meeting.',
      ),
    );
  }
  if (failure.hasCode('MEETING_NOT_FOUND')) {
    return failure.copyWith(
      message: tr(
        'Cuộc họp không còn nữa hoặc bạn không còn ở nhóm.',
        'The meeting no longer exists or you\'re no longer in the group.',
      ),
    );
  }
  return failure;
}

Result<T> _friendly<T>(Result<T> result) => switch (result) {
  FailureResult<T>(failure: final failure) => FailureResult(
    friendlyMeetingFailure(failure),
  ),
  _ => result,
};

/// Danh sách họp trong khoảng, sắp theo giờ bắt đầu. Khoảng quá
/// [maxMeetingRangeDays] ngày thì cắt bớt (giới hạn của máy chủ).
final class ListMeetingsInRangeUseCase {
  const ListMeetingsInRangeUseCase(this._repository);

  final MeetingCalendarRepository _repository;

  Future<Result<List<CalendarMeeting>>> execute({
    required String workspaceId,
    required DateTime from,
    required DateTime to,
  }) async {
    final limit = from.add(const Duration(days: maxMeetingRangeDays));
    final end = to.isAfter(limit) ? limit : to;
    if (!end.isAfter(from)) return const Success([]);
    final result = await _repository.listMeetings(
      workspaceId: workspaceId,
      from: from,
      to: end,
    );
    return switch (result) {
      Success(value: final meetings) => Success(
        [...meetings]..sort((a, b) => a.startsAt.compareTo(b.startsAt)),
      ),
      FailureResult(failure: final failure) => FailureResult(
        friendlyMeetingFailure(failure),
      ),
    };
  }
}

final class GetMeetingDetailUseCase {
  const GetMeetingDetailUseCase(this._repository);

  final MeetingCalendarRepository _repository;

  Future<Result<CalendarMeeting>> execute({
    required String workspaceId,
    required String channelId,
    required String meetingId,
  }) async {
    if (channelId.trim().isEmpty || meetingId.trim().isEmpty) {
      return FailureResult(
        Failure(
          kind: FailureKind.notFound,
          message: tr('Không tìm thấy cuộc họp.', 'Meeting not found.'),
          code: 'MEETING_NOT_FOUND',
        ),
      );
    }
    return _friendly(
      await _repository.getMeeting(
        workspaceId: workspaceId,
        channelId: channelId,
        meetingId: meetingId,
      ),
    );
  }
}

/// Nơi gắn cuộc họp: nhóm có sẵn, hoặc người lẻ (tạo nhóm riêng tư mới).
sealed class MeetingTarget {
  const MeetingTarget();
}

final class ExistingGroupTarget extends MeetingTarget {
  const ExistingGroupTarget(this.channelId);

  final String channelId;
}

final class NewGroupTarget extends MeetingTarget {
  const NewGroupTarget({required this.memberIds, this.groupName = ''});

  final List<String> memberIds;

  /// Trống: dùng tiêu đề cuộc họp làm tên nhóm.
  final String groupName;
}

/// Tạo cuộc họp. Chọn người lẻ thì tạo nhóm riêng tư mới rồi tạo họp trong
/// nhóm đó; [onGroupCreated] báo mã nhóm ngay khi có để lần thử lại không tạo
/// thêm nhóm.
final class CreateMeetingUseCase {
  CreateMeetingUseCase(
    this._repository,
    this._createGroup, {
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final MeetingCalendarRepository _repository;
  final CreateGroupUseCase _createGroup;
  final DateTime Function() _clock;

  Future<Result<CalendarMeeting>> execute({
    required String workspaceId,
    required MeetingTarget target,
    required MeetingDraft draft,
    void Function(String channelId)? onGroupCreated,
    DateTime? now,
  }) async {
    final invalid = validateMeetingDraft(
      draft,
      now: now ?? _clock(),
      isNew: true,
    );
    if (invalid != null) return FailureResult(invalid);
    final clean = _cleanDraft(draft);
    final String channelId;
    switch (target) {
      case ExistingGroupTarget(channelId: final id):
        if (id.trim().isEmpty) {
          return FailureResult(
            _validation(
              tr('Hãy chọn nhóm hoặc người.', 'Choose a group or people.'),
              'MEETING_TARGET_REQUIRED',
            ),
          );
        }
        channelId = id;
      case NewGroupTarget(memberIds: final ids, groupName: final name):
        final members = ids.map((id) => id.trim()).where((id) => id.isNotEmpty);
        if (members.isEmpty) {
          return FailureResult(
            _validation(
              tr('Hãy chọn nhóm hoặc người.', 'Choose a group or people.'),
              'MEETING_TARGET_REQUIRED',
            ),
          );
        }
        final groupName = (name.trim().isEmpty ? clean.title : name.trim());
        final created = await _createGroup.execute(
          workspaceId: workspaceId,
          name: groupName.length > groupNameMaxLength
              ? groupName.substring(0, groupNameMaxLength)
              : groupName,
          memberIds: members.toList(),
        );
        if (created case FailureResult<CreateGroupResult>(
          failure: final failure,
        )) {
          return FailureResult(failure);
        }
        channelId = created.valueOrNull!.channel.channelId;
        onGroupCreated?.call(channelId);
    }
    return _friendly(
      await _repository.createMeeting(
        workspaceId: workspaceId,
        channelId: channelId,
        draft: clean,
      ),
    );
  }
}

final class UpdateMeetingUseCase {
  UpdateMeetingUseCase(this._repository, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final MeetingCalendarRepository _repository;
  final DateTime Function() _clock;

  Future<Result<void>> execute({
    required String workspaceId,
    required String channelId,
    required String meetingId,
    required MeetingDraft draft,
    MeetingScope scope = MeetingScope.occurrence,
    DateTime? now,
  }) async {
    final invalid = validateMeetingDraft(
      draft,
      now: now ?? _clock(),
      isNew: false,
    );
    if (invalid != null) return FailureResult(invalid);
    return _friendly(
      await _repository.updateMeeting(
        workspaceId: workspaceId,
        channelId: channelId,
        meetingId: meetingId,
        draft: _cleanDraft(draft),
        scope: scope,
      ),
    );
  }
}

MeetingDraft _cleanDraft(MeetingDraft draft) {
  final url = draft.externalUrl?.trim() ?? '';
  final recurrence = draft.recurrence;
  return MeetingDraft(
    title: draft.title.trim(),
    description: draft.description.trim(),
    startsAt: draft.startsAt,
    endsAt: draft.endsAt,
    externalUrl: url.isEmpty ? null : url,
    reminderOffsets: [...draft.reminderOffsets]..sort((a, b) => b.compareTo(a)),
    attendeeUserIds: draft.attendeeUserIds?.toSet().toList(),
    recurrence: recurrence == null
        ? null
        : MeetingRecurrence(
            frequency: recurrence.frequency,
            interval: recurrence.interval < 1 ? 1 : recurrence.interval,
            byWeekday: (recurrence.byWeekday.toSet().toList()..sort()),
            until: recurrence.count == null ? recurrence.until : null,
            count: recurrence.count,
          ),
    timezone: draft.timezone?.trim().isEmpty == true ? null : draft.timezone,
  );
}

final class CancelMeetingUseCase {
  const CancelMeetingUseCase(this._repository);

  final MeetingCalendarRepository _repository;

  Future<Result<void>> execute({
    required String workspaceId,
    required String channelId,
    required String meetingId,
    MeetingScope scope = MeetingScope.occurrence,
  }) async {
    return _friendly(
      await _repository.cancelMeeting(
        workspaceId: workspaceId,
        channelId: channelId,
        meetingId: meetingId,
        scope: scope,
      ),
    );
  }
}

final class RespondToMeetingUseCase {
  const RespondToMeetingUseCase(this._repository);

  final MeetingCalendarRepository _repository;

  Future<Result<void>> execute({
    required String workspaceId,
    required String channelId,
    required String meetingId,
    required MeetingResponse response,
    MeetingScope? scope,
  }) async {
    if (response == MeetingResponse.pending) {
      return FailureResult(
        _validation(
          tr('Hãy chọn một phản hồi.', 'Choose a response.'),
          'MEETING_RESPONSE_INVALID',
        ),
      );
    }
    return _friendly(
      await _repository.respond(
        workspaceId: workspaceId,
        channelId: channelId,
        meetingId: meetingId,
        response: response,
        scope: scope,
      ),
    );
  }
}

/// Biên bản họp: lưu (≤ 20 000 ký tự) và gửi vào nhóm.
final class MeetingMinutesUseCase {
  const MeetingMinutesUseCase(this._repository);

  final MeetingCalendarRepository _repository;

  Future<Result<void>> save({
    required String workspaceId,
    required String channelId,
    required String meetingId,
    required String content,
  }) async {
    final text = content.trim();
    if (text.length > maxMeetingMinutesLength) {
      return FailureResult(
        _validation(
          tr(
            'Biên bản tối đa $maxMeetingMinutesLength ký tự.',
            'Minutes can be up to $maxMeetingMinutesLength characters.',
          ),
          'MEETING_MINUTES_TOO_LONG',
        ),
      );
    }
    return _friendly(
      await _repository.saveMinutes(
        workspaceId: workspaceId,
        channelId: channelId,
        meetingId: meetingId,
        content: text,
      ),
    );
  }

  Future<Result<String>> publish({
    required String workspaceId,
    required String channelId,
    required String meetingId,
  }) async {
    return _friendly(
      await _repository.publishMinutes(
        workspaceId: workspaceId,
        channelId: channelId,
        meetingId: meetingId,
      ),
    );
  }
}

/// Việc nhóm giao từ cuộc họp (`meeting_id`).
final class MeetingTasksUseCase {
  const MeetingTasksUseCase(this._repository);

  final MeetingCalendarRepository _repository;

  Future<Result<List<CollaborationTask>>> list({
    required String workspaceId,
    required String channelId,
    required String meetingId,
  }) async {
    return _friendly(
      await _repository.listMeetingTasks(
        workspaceId: workspaceId,
        channelId: channelId,
        meetingId: meetingId,
      ),
    );
  }

  Future<Result<CollaborationTask>> create({
    required String workspaceId,
    required String channelId,
    required String meetingId,
    required String title,
    String? assigneeUserId,
    DateTime? dueAt,
  }) async {
    final clean = title.trim();
    if (clean.isEmpty) {
      return FailureResult(
        _validation(
          tr('Hãy nhập tên việc.', 'Enter a task title.'),
          'TASK_TITLE_REQUIRED',
        ),
      );
    }
    if (clean.runes.length > maxMeetingTaskTitleLength) {
      return FailureResult(
        _validation(
          tr(
            'Tên việc tối đa $maxMeetingTaskTitleLength ký tự.',
            'Task titles can be up to $maxMeetingTaskTitleLength characters.',
          ),
          'TASK_TITLE_TOO_LONG',
        ),
      );
    }
    final assignee = assigneeUserId?.trim();
    return _friendly(
      await _repository.createMeetingTask(
        workspaceId: workspaceId,
        channelId: channelId,
        meetingId: meetingId,
        title: clean,
        assigneeUserId: assignee == null || assignee.isEmpty ? null : assignee,
        dueAt: dueAt,
      ),
    );
  }
}

/// Kiểm trùng lịch; không có người hoặc giờ sai thì không gọi máy chủ.
final class CheckMeetingConflictsUseCase {
  const CheckMeetingConflictsUseCase(this._repository);

  final MeetingCalendarRepository _repository;

  Future<Result<List<MeetingConflict>>> execute({
    required String workspaceId,
    required List<String> userIds,
    required DateTime startsAt,
    required DateTime endsAt,
    String? excludeMeetingId,
  }) async {
    final ids = userIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
    if (ids.isEmpty || !endsAt.isAfter(startsAt)) return const Success([]);
    return _repository.findConflicts(
      workspaceId: workspaceId,
      userIds: ids,
      startsAt: startsAt,
      endsAt: endsAt,
      excludeMeetingId: excludeMeetingId,
    );
  }
}

/// Bật / tắt link cho khách ngoài.
final class MeetingGuestLinkUseCase {
  const MeetingGuestLinkUseCase(this._repository);

  final MeetingCalendarRepository _repository;

  Future<Result<MeetingGuestLink>> setEnabled({
    required String workspaceId,
    required String channelId,
    required String meetingId,
    required bool enabled,
  }) async {
    if (enabled) {
      return _friendly(
        await _repository.enableGuestLink(
          workspaceId: workspaceId,
          channelId: channelId,
          meetingId: meetingId,
        ),
      );
    }
    final result = await _repository.disableGuestLink(
      workspaceId: workspaceId,
      channelId: channelId,
      meetingId: meetingId,
    );
    return switch (result) {
      Success() => const Success(MeetingGuestLink(enabled: false)),
      FailureResult(failure: final failure) => FailureResult(
        friendlyMeetingFailure(failure),
      ),
    };
  }
}

/// Nhóm và người chọn được khi tạo họp (dùng API hội thoại có sẵn).
final class LoadMeetingPeopleUseCase {
  const LoadMeetingPeopleUseCase(this._conversations);

  final ConversationRepository _conversations;

  /// Nhóm mình đang là thành viên (bỏ kênh bot / tự động).
  Future<Result<List<MeetingGroupOption>>> groups({
    required String workspaceId,
  }) async {
    final result = await _conversations.listChannels(workspaceId: workspaceId);
    return switch (result) {
      Success(value: final channels) => Success(
        [
          for (final channel in channels)
            if (channel.kind == ConversationKind.channel &&
                (channel.membershipStatus == MembershipStatus.active ||
                    channel.membershipStatus == MembershipStatus.muted) &&
                !channel.noticeBot &&
                !channel.isAutomation)
              MeetingGroupOption(
                channelId: channel.channelId,
                name: channel.title,
                memberCount: channel.memberCount,
              ),
        ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase())),
      ),
      FailureResult(failure: final failure) => FailureResult(failure),
    };
  }

  /// Thành viên đang hoạt động của nhóm.
  Future<Result<List<MeetingPerson>>> groupMembers({
    required String workspaceId,
    required String channelId,
  }) async {
    final result = await _conversations.listMembers(
      workspaceId: workspaceId,
      channelId: channelId,
    );
    return switch (result) {
      Success(value: final members) => Success([
        for (final member in members)
          if (const {
            '',
            'active',
            'muted',
          }.contains(member.status.trim().toLowerCase()))
            MeetingPerson(
              userId: member.userId,
              displayName: member.displayName.trim().isNotEmpty
                  ? member.displayName
                  : member.username,
              avatarUrl: member.avatarUrl,
            ),
      ]),
      FailureResult(failure: final failure) => FailureResult(failure),
    };
  }

  /// Mọi thành viên workspace (chọn người lẻ).
  Future<Result<List<MeetingPerson>>> workspacePeople({
    required String workspaceId,
  }) async {
    final result = await _conversations.listWorkspaceMembers(
      workspaceId: workspaceId,
    );
    return switch (result) {
      Success(value: final people) => Success(
        [
          for (final person in people)
            if (person.userId.trim().isNotEmpty)
              MeetingPerson(
                userId: person.userId,
                displayName: person.displayName.trim().isNotEmpty
                    ? person.displayName
                    : person.username,
                avatarUrl: person.avatarUrl,
              ),
        ]..sort(
          (a, b) => a.displayName.toLowerCase().compareTo(
            b.displayName.toLowerCase(),
          ),
        ),
      ),
      FailureResult(failure: final failure) => FailureResult(failure),
    };
  }
}
