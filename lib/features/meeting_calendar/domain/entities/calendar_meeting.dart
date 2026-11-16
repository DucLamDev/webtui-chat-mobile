import '../../../../l10n/app_strings.dart';

/// Phản hồi tham dự của một người (`pending` = chưa trả lời).
enum MeetingResponse {
  pending('pending'),
  accepted('accepted'),
  tentative('tentative'),
  declined('declined');

  const MeetingResponse(this.apiValue);

  final String apiValue;

  String get label => switch (this) {
    pending => tr('Chưa trả lời', 'No response'),
    accepted => tr('Tham gia', 'Going'),
    tentative => tr('Có thể', 'Maybe'),
    declined => tr('Từ chối', 'Declined'),
  };

  /// Giá trị lạ / thiếu: `null`.
  static MeetingResponse? fromApi(Object? value) {
    final text = value?.toString().trim().toLowerCase();
    for (final item in values) {
      if (item.apiValue == text) return item;
    }
    return null;
  }
}

/// Phạm vi sửa / huỷ / phản hồi một buổi họp lặp lại.
enum MeetingScope {
  /// Chỉ buổi này.
  occurrence('this'),

  /// Cả chuỗi, từ buổi này trở đi.
  series('series');

  const MeetingScope(this.apiValue);

  final String apiValue;
}

enum MeetingRecurrenceFrequency {
  daily('daily'),
  weekly('weekly'),
  monthly('monthly');

  const MeetingRecurrenceFrequency(this.apiValue);

  final String apiValue;

  static MeetingRecurrenceFrequency? fromApi(Object? value) {
    final text = value?.toString().trim().toLowerCase();
    for (final item in values) {
      if (item.apiValue == text) return item;
    }
    return null;
  }
}

/// Luật lặp lại. [byWeekday]: 1 = Thứ 2 … 7 = Chủ nhật (chỉ dùng khi lặp theo
/// tuần). [until] (ngày, không giờ) và [count] dùng một trong hai.
final class MeetingRecurrence {
  const MeetingRecurrence({
    required this.frequency,
    this.interval = 1,
    this.byWeekday = const [],
    this.until,
    this.count,
  });

  final MeetingRecurrenceFrequency frequency;
  final int interval;
  final List<int> byWeekday;
  final DateTime? until;
  final int? count;
}

/// Số người theo từng phản hồi.
final class MeetingAttendeeSummary {
  const MeetingAttendeeSummary({
    this.accepted = 0,
    this.tentative = 0,
    this.declined = 0,
    this.pending = 0,
  });

  final int accepted;
  final int tentative;
  final int declined;
  final int pending;

  int get total => accepted + tentative + declined + pending;
}

final class MeetingAttendee {
  const MeetingAttendee({
    required this.userId,
    required this.displayName,
    this.avatarUrl,
    this.isOrganizer = false,
    this.response = MeetingResponse.pending,
    this.respondedAt,
  });

  final String userId;
  final String displayName;
  final String? avatarUrl;
  final bool isOrganizer;
  final MeetingResponse response;
  final DateTime? respondedAt;
}

final class MeetingMinutes {
  const MeetingMinutes({
    required this.content,
    this.updatedAt,
    this.updatedBy,
    this.publishedAt,
  });

  final String content;
  final DateTime? updatedAt;
  final String? updatedBy;
  final DateTime? publishedAt;

  bool get isPublished => publishedAt != null;
}

/// Link cho khách ngoài (chỉ người được sửa họp thấy).
final class MeetingGuestLink {
  const MeetingGuestLink({required this.enabled, this.url = ''});

  final bool enabled;
  final String url;
}

/// Link khách đầy đủ để hiện / sao chép. Máy chủ chưa đặt `APP_URL` thì trả
/// đường tương đối (`/join?token=…`): ghép với gốc của máy chủ đang dùng (web
/// và trang `/join` cùng tên miền). Đường đã đầy đủ thì giữ nguyên. Chỉ hỏi
/// địa chỉ máy chủ khi thật sự cần ghép.
String absoluteGuestUrl(String url, Uri Function() server) {
  final value = url.trim();
  if (!value.startsWith('/') || value.startsWith('//')) return value;
  final base = server();
  return base.hasScheme ? '${base.origin}$value' : value;
}

/// Một cuộc họp (buổi họp) theo `MeetingDTO` mở rộng. Máy chủ cũ thiếu trường
/// mới thì dùng giá trị an toàn: không có quyền sửa / huỷ / phản hồi.
final class CalendarMeeting {
  const CalendarMeeting({
    required this.id,
    required this.workspaceId,
    required this.channelId,
    required this.title,
    required this.startsAt,
    this.channelName = '',
    this.description = '',
    this.endsAt,
    this.lobbyOpensAt,
    this.status = 'scheduled',
    this.createdBy,
    this.startedAt,
    this.endedAt,
    this.externalUrl,
    this.reminderOffsets = defaultReminderOffsets,
    this.timezone,
    this.seriesId,
    this.recurrence,
    this.isException = false,
    this.myResponse,
    this.attendeeSummary,
    this.canEdit = false,
    this.canCancel = false,
    this.canRespond = false,
    this.canEditMinutes = false,
    this.attendees = const [],
    this.minutes,
    this.guestLink,
  });

  final String id;
  final String workspaceId;
  final String channelId;
  final String channelName;
  final String title;
  final String description;
  final DateTime startsAt;
  final DateTime? endsAt;
  final DateTime? lobbyOpensAt;

  /// `scheduled` | `active` | `ended` | `cancelled`.
  final String status;
  final String? createdBy;
  final DateTime? startedAt;
  final DateTime? endedAt;

  /// Link họp ngoài (chỉ https), `null` khi dùng phòng video sẵn có.
  final String? externalUrl;

  /// Phút trước giờ bắt đầu sẽ nhắc.
  final List<int> reminderOffsets;
  final String? timezone;
  final String? seriesId;
  final MeetingRecurrence? recurrence;
  final bool isException;

  /// `null`: mình không được mời.
  final MeetingResponse? myResponse;
  final MeetingAttendeeSummary? attendeeSummary;
  final bool canEdit;
  final bool canCancel;
  final bool canRespond;
  final bool canEditMinutes;

  /// Chỉ có ở API chi tiết.
  final List<MeetingAttendee> attendees;
  final MeetingMinutes? minutes;
  final MeetingGuestLink? guestLink;

  bool get isCancelled => status == 'cancelled';
  bool get isRecurring => seriesId != null || recurrence != null;

  /// Giờ kết thúc dùng để tính trạng thái (thiếu thì bắt đầu + 60 phút, như
  /// mặc định của máy chủ).
  DateTime get effectiveEnd => endsAt ?? startsAt.add(defaultMeetingDuration);

  bool get hasExternalUrl => externalUrl?.trim().isNotEmpty == true;
}

/// Mốc nhắc mặc định: 15 phút trước và lúc bắt đầu.
const defaultReminderOffsets = <int>[15, 0];

/// Các mốc nhắc cho phép (phút trước giờ bắt đầu).
const allowedReminderOffsets = <int>[0, 5, 10, 15, 30, 60];

const maxReminderOffsets = 3;

const defaultMeetingDuration = Duration(minutes: 60);

/// Mở nút "Vào họp" trước giờ bắt đầu bao lâu.
const meetingJoinLeadTime = Duration(minutes: 10);

/// Nhãn trạng thái hiển thị.
enum MeetingPhase {
  upcoming,
  live,
  ended,
  cancelled;

  String get label => switch (this) {
    upcoming => tr('Sắp bắt đầu', 'Upcoming'),
    live => tr('Đang diễn ra', 'In progress'),
    ended => tr('Đã kết thúc', 'Ended'),
    cancelled => tr('Đã huỷ', 'Canceled'),
  };
}

/// Trạng thái của [meeting] lúc [now]: theo `status` của máy chủ, cuộc họp
/// `scheduled` đã tới giờ thì tính "Đang diễn ra", quá giờ kết thúc thì "Đã kết
/// thúc" (máy chủ không tự chuyển khi họp bằng link ngoài).
MeetingPhase meetingPhaseAt(CalendarMeeting meeting, DateTime now) {
  switch (meeting.status) {
    case 'cancelled':
      return MeetingPhase.cancelled;
    case 'ended':
      return MeetingPhase.ended;
    case 'active':
      return MeetingPhase.live;
  }
  if (!now.isBefore(meeting.effectiveEnd)) return MeetingPhase.ended;
  if (!now.isBefore(meeting.startsAt)) return MeetingPhase.live;
  return MeetingPhase.upcoming;
}

/// Nút "Vào họp" bấm được: chưa huỷ / kết thúc và đã tới trước giờ bắt đầu
/// [meetingJoinLeadTime].
bool canJoinMeetingAt(CalendarMeeting meeting, DateTime now) {
  final phase = meetingPhaseAt(meeting, now);
  if (phase == MeetingPhase.cancelled || phase == MeetingPhase.ended) {
    return false;
  }
  return !now.isBefore(meeting.startsAt.subtract(meetingJoinLeadTime));
}

/// Cuộc họp thuộc tab "Đã qua" (ngược lại là "Sắp tới").
bool isPastMeetingAt(CalendarMeeting meeting, DateTime now) {
  return switch (meetingPhaseAt(meeting, now)) {
    MeetingPhase.ended => true,
    MeetingPhase.cancelled => meeting.startsAt.isBefore(now),
    _ => false,
  };
}

/// Nội dung tạo / sửa họp (các trường tuỳ chọn để máy chủ dùng mặc định).
final class MeetingDraft {
  const MeetingDraft({
    required this.title,
    required this.startsAt,
    this.endsAt,
    this.description = '',
    this.externalUrl,
    this.reminderOffsets = defaultReminderOffsets,
    this.attendeeUserIds,
    this.recurrence,
    this.timezone,
  });

  final String title;
  final String description;
  final DateTime startsAt;
  final DateTime? endsAt;
  final String? externalUrl;
  final List<int> reminderOffsets;

  /// `null`: để máy chủ mời cả nhóm.
  final List<String>? attendeeUserIds;
  final MeetingRecurrence? recurrence;
  final String? timezone;
}

/// Một người bị trùng lịch.
final class MeetingConflict {
  const MeetingConflict({
    required this.userId,
    required this.meetingId,
    required this.startsAt,
    this.endsAt,
    this.title,
  });

  final String userId;
  final String meetingId;
  final DateTime startsAt;
  final DateTime? endsAt;

  /// Chỉ có khi người hỏi xem được cuộc họp đó.
  final String? title;
}

/// Người chọn được khi mời họp.
final class MeetingPerson {
  const MeetingPerson({
    required this.userId,
    required this.displayName,
    this.avatarUrl,
  });

  final String userId;
  final String displayName;
  final String? avatarUrl;
}

/// Nhóm chat có thể gắn cuộc họp.
final class MeetingGroupOption {
  const MeetingGroupOption({
    required this.channelId,
    required this.name,
    this.memberCount = 0,
  });

  final String channelId;
  final String name;
  final int memberCount;
}
