import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/error/error_mapper.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/result/result.dart';
import '../../../../l10n/app_strings.dart';
import '../../../conversations/domain/entities/collaboration_room.dart';
import '../../../conversations/domain/entities/conversation_realtime_event.dart';
import '../../../profile/presentation/controllers/profile_controller.dart';
import '../../application/meeting_calendar_providers.dart';
import '../../domain/entities/calendar_meeting.dart';

/// Tăng mỗi khi lịch họp đổi (sự kiện `MeetingUpdated`, thông báo họp, vừa
/// tạo / sửa / huỷ): mọi danh sách và chi tiết đang mở tự tải lại.
final meetingCalendarRefreshTickProvider = StateProvider<int>((ref) => 0);

/// Báo lịch họp đã đổi.
void bumpMeetingCalendar(T Function<T>(ProviderListenable<T>) read) {
  final tick = read(meetingCalendarRefreshTickProvider.notifier);
  tick.state = tick.state + 1;
}

/// Xử lý `MeetingUpdated` (room nhóm hoặc room riêng): tải lại lịch họp. Trả
/// `true` nếu đúng là sự kiện họp.
bool handleMeetingRealtimeEvent({
  required T Function<T>(ProviderListenable<T>) read,
  required ConversationRealtimeEvent event,
}) {
  if (event.type != ConversationRealtimeEventType.meetingUpdated) return false;
  bumpMeetingCalendar(read);
  return true;
}

T _unwrap<T>(Result<T> result) => result.when(
  success: (value) => value,
  failure: (failure) => throw FailureException(failure),
);

String meetingErrorText(Object error) {
  if (error is FailureException) return userFacingErrorMessage(error.failure);
  return userFacingErrorMessage(error);
}

typedef MeetingRangeKey = ({String workspaceId, DateTime from, DateTime to});

typedef MeetingKey = ({String workspaceId, String channelId, String meetingId});

final meetingRangeProvider = FutureProvider.autoDispose
    .family<List<CalendarMeeting>, MeetingRangeKey>((ref, key) async {
      ref.watch(meetingCalendarRefreshTickProvider);
      return _unwrap(
        await ref
            .watch(listMeetingsInRangeUseCaseProvider)
            .execute(workspaceId: key.workspaceId, from: key.from, to: key.to),
      );
    });

final meetingDetailProvider = FutureProvider.autoDispose
    .family<CalendarMeeting, MeetingKey>((ref, key) async {
      ref.watch(meetingCalendarRefreshTickProvider);
      return _unwrap(
        await ref
            .watch(getMeetingDetailUseCaseProvider)
            .execute(
              workspaceId: key.workspaceId,
              channelId: key.channelId,
              meetingId: key.meetingId,
            ),
      );
    });

final meetingTasksProvider = FutureProvider.autoDispose
    .family<List<CollaborationTask>, MeetingKey>((ref, key) async {
      ref.watch(meetingCalendarRefreshTickProvider);
      return _unwrap(
        await ref
            .watch(meetingTasksUseCaseProvider)
            .list(
              workspaceId: key.workspaceId,
              channelId: key.channelId,
              meetingId: key.meetingId,
            ),
      );
    });

/// Nhóm chọn được khi tạo họp.
final meetingGroupsProvider = FutureProvider.autoDispose
    .family<List<MeetingGroupOption>, String>((ref, workspaceId) async {
      return _unwrap(
        await ref
            .watch(loadMeetingPeopleUseCaseProvider)
            .groups(workspaceId: workspaceId),
      );
    });

/// Thành viên một nhóm (người tham dự mặc định).
final meetingGroupMembersProvider = FutureProvider.autoDispose
    .family<List<MeetingPerson>, ({String workspaceId, String channelId})>((
      ref,
      key,
    ) async {
      return _unwrap(
        await ref
            .watch(loadMeetingPeopleUseCaseProvider)
            .groupMembers(
              workspaceId: key.workspaceId,
              channelId: key.channelId,
            ),
      );
    });

/// Thành viên workspace (chọn người lẻ).
final meetingWorkspacePeopleProvider = FutureProvider.autoDispose
    .family<List<MeetingPerson>, String>((ref, workspaceId) async {
      return _unwrap(
        await ref
            .watch(loadMeetingPeopleUseCaseProvider)
            .workspacePeople(workspaceId: workspaceId),
      );
    });

/// Múi giờ IANA trong hồ sơ người dùng (để máy chủ lặp đúng thứ / ngày).
final meetingTimezoneProvider = Provider.autoDispose<String?>((ref) {
  final timezone = ref.watch(profileControllerProvider).profile?.timezone;
  return timezone == null || timezone.trim().isEmpty ? null : timezone.trim();
});

// ---------------------------------------------------------------------------
// Định dạng ngày giờ theo ngôn ngữ (giờ theo máy).

String _two(int value) => value.toString().padLeft(2, '0');

/// Giờ: tiếng Việt `09:05`, tiếng Anh `9:05 AM`.
String meetingClock(DateTime value) {
  final local = value.toLocal();
  if (!AppStrings.current.isEnglish) {
    return '${_two(local.hour)}:${_two(local.minute)}';
  }
  final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final suffix = local.hour < 12 ? 'AM' : 'PM';
  return '$hour:${_two(local.minute)} $suffix';
}

String meetingTimeRange(CalendarMeeting meeting) {
  final end = meeting.endsAt;
  return end == null
      ? meetingClock(meeting.startsAt)
      : '${meetingClock(meeting.startsAt)} – ${meetingClock(end)}';
}

const _viWeekdayShort = ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'];
const _enWeekdayShort = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _viWeekdayLong = [
  'Thứ Hai',
  'Thứ Ba',
  'Thứ Tư',
  'Thứ Năm',
  'Thứ Sáu',
  'Thứ Bảy',
  'Chủ nhật',
];
const _enWeekdayLong = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];
const _enMonths = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// Thứ viết tắt, [weekday] 1 = Thứ 2 … 7 = Chủ nhật.
String meetingWeekdayShort(int weekday) => AppStrings.current.isEnglish
    ? _enWeekdayShort[(weekday - 1) % 7]
    : _viWeekdayShort[(weekday - 1) % 7];

String meetingWeekdayLong(int weekday) => AppStrings.current.isEnglish
    ? _enWeekdayLong[(weekday - 1) % 7]
    : _viWeekdayLong[(weekday - 1) % 7];

/// Ngày ngắn: `18/11` hoặc `Nov 18`.
String meetingShortDate(DateTime value) {
  final local = value.toLocal();
  return AppStrings.current.isEnglish
      ? '${_enMonths[local.month - 1]} ${local.day}'
      : '${_two(local.day)}/${_two(local.month)}';
}

/// Ngày đầy đủ: `Thứ Hai, 18/11/2026` hoặc `Monday, Nov 18, 2026`.
String meetingLongDate(DateTime value) {
  final local = value.toLocal();
  return AppStrings.current.isEnglish
      ? '${meetingWeekdayLong(local.weekday)}, ${meetingShortDate(local)}, '
            '${local.year}'
      : '${meetingWeekdayLong(local.weekday)}, ${meetingShortDate(local)}'
            '/${local.year}';
}

/// Tiêu đề nhóm theo ngày: Hôm nay / Ngày mai / Hôm qua / `Thứ Hai, 18/11`.
String meetingDayHeading(DateTime day, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final local = day.toLocal();
  final target = DateTime(local.year, local.month, local.day);
  final diff = _dayDiff(today, target);
  return switch (diff) {
    0 => tr('Hôm nay', 'Today'),
    1 => tr('Ngày mai', 'Tomorrow'),
    -1 => tr('Hôm qua', 'Yesterday'),
    _ =>
      '${meetingWeekdayLong(target.weekday)}, ${meetingShortDate(target)}'
          '${target.year == today.year ? '' : '/${target.year}'}',
  };
}

/// Số ngày lịch giữa hai ngày (không lệch vì đổi giờ mùa hè).
int _dayDiff(DateTime from, DateTime to) => DateTime.utc(
  to.year,
  to.month,
  to.day,
).difference(DateTime.utc(from.year, from.month, from.day)).inDays;

/// Đầu ngày địa phương.
DateTime meetingDayStart(DateTime value) {
  final local = value.toLocal();
  return DateTime(local.year, local.month, local.day);
}

/// Thứ Hai đầu tuần chứa [value].
DateTime meetingWeekStart(DateTime value) {
  final day = meetingDayStart(value);
  return DateTime(day.year, day.month, day.day - (day.weekday - 1));
}

bool meetingSameDay(DateTime a, DateTime b) {
  final left = a.toLocal();
  final right = b.toLocal();
  return left.year == right.year &&
      left.month == right.month &&
      left.day == right.day;
}

/// Nhãn mốc nhắc: 0 → "Lúc bắt đầu", 60 → "1 giờ trước", còn lại "N phút trước".
String meetingReminderLabel(int minutes) {
  if (minutes == 0) return tr('Lúc bắt đầu', 'At start time');
  if (minutes == 60) return tr('1 giờ trước', '1 hour before');
  return tr('$minutes phút trước', '$minutes minutes before');
}

/// Mô tả luật lặp, ví dụ "Hằng tuần: T2, T4 · đến 31/03/2027".
String meetingRecurrenceLabel(MeetingRecurrence recurrence) {
  final base = switch (recurrence.frequency) {
    MeetingRecurrenceFrequency.daily => tr('Hằng ngày', 'Daily'),
    MeetingRecurrenceFrequency.weekly => tr('Hằng tuần', 'Weekly'),
    MeetingRecurrenceFrequency.monthly => tr('Hằng tháng', 'Monthly'),
  };
  final days =
      recurrence.frequency == MeetingRecurrenceFrequency.weekly &&
          recurrence.byWeekday.isNotEmpty
      ? ': ${recurrence.byWeekday.map(meetingWeekdayShort).join(', ')}'
      : '';
  final until = recurrence.until;
  final count = recurrence.count;
  final end = count != null
      ? tr(' · $count buổi', ' · $count times')
      : until != null
      ? tr(
          ' · đến ${meetingShortDate(until)}/${until.year}',
          ' · until ${meetingShortDate(until)}, ${until.year}',
        )
      : '';
  return '$base$days$end';
}
