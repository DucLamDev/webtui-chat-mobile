import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:webtui_chat/l10n/app_strings.dart';

import '../../../../design_system/icons/webtui_icons.dart';
import '../../../../design_system/tokens/webtui_colors.dart';
import '../../../../design_system/tokens/webtui_typography.dart';
import '../../../meeting_calendar/domain/entities/calendar_meeting.dart';
import '../../../meeting_calendar/presentation/controllers/meeting_calendar_controllers.dart';
import '../../../meeting_calendar/presentation/meeting_calendar_routes.dart';
import '../../../meeting_calendar/presentation/screens/meeting_form_screen.dart';
import '../../../meeting_calendar/presentation/widgets/meeting_widgets.dart';
import '../widgets/work_common.dart';

/// Số ngày tải cho tab Sắp tới / Đã qua (máy chủ cho tối đa 62 ngày).
const meetingListWindowDays = 60;

/// Nhóm họp theo ngày địa phương, giữ thứ tự của [meetings].
List<(DateTime, List<CalendarMeeting>)> groupCalendarMeetingsByDay(
  List<CalendarMeeting> meetings,
) {
  final groups = <DateTime, List<CalendarMeeting>>{};
  for (final meeting in meetings) {
    groups
        .putIfAbsent(meetingDayStart(meeting.startsAt), () => [])
        .add(meeting);
  }
  return [for (final entry in groups.entries) (entry.key, entry.value)];
}

/// Lọc và sắp danh sách cho một tab: Sắp tới theo giờ tăng dần, Đã qua mới
/// nhất trước.
List<CalendarMeeting> meetingsForTab(
  List<CalendarMeeting> meetings, {
  required bool past,
  required DateTime now,
}) {
  final items = [
    for (final meeting in meetings)
      if (isPastMeetingAt(meeting, now) == past) meeting,
  ];
  items.sort(
    (a, b) => past
        ? b.startsAt.compareTo(a.startsAt)
        : a.startsAt.compareTo(b.startsAt),
  );
  return items;
}

/// Lịch họp: dải tuần có chấm ngày có họp, tab Sắp tới / Đã qua, nút Tạo họp.
class MeetingsScreen extends ConsumerStatefulWidget {
  const MeetingsScreen({
    required this.workspaceId,
    this.now,
    this.clock,
    super.key,
  });

  final String workspaceId;

  /// Chỉ để test cố định "bây giờ".
  final DateTime? now;

  /// Chỉ để test: đồng hồ giả (đổi được giữa chừng) khi không có [now].
  final DateTime Function()? clock;

  @override
  ConsumerState<MeetingsScreen> createState() => _MeetingsScreenState();
}

class _MeetingsScreenState extends ConsumerState<MeetingsScreen>
    with MeetingClockTicker<MeetingsScreen> {
  bool _past = false;
  late DateTime _weekStart = meetingWeekStart(_now());
  DateTime? _selectedDay;

  DateTime _now() => widget.now ?? (widget.clock ?? DateTime.now)();

  MeetingRangeKey _upcomingKey(DateTime today) => (
    workspaceId: widget.workspaceId,
    from: today,
    to: DateTime(today.year, today.month, today.day + meetingListWindowDays),
  );

  MeetingRangeKey _pastKey(DateTime today) => (
    workspaceId: widget.workspaceId,
    from: DateTime(today.year, today.month, today.day - meetingListWindowDays),
    to: DateTime(today.year, today.month, today.day + 1),
  );

  MeetingRangeKey get _weekKey => (
    workspaceId: widget.workspaceId,
    from: _weekStart,
    to: DateTime(_weekStart.year, _weekStart.month, _weekStart.day + 7),
  );

  MeetingRangeKey _listKey(DateTime today) {
    if (_selectedDay != null) return _weekKey;
    return _past ? _pastKey(today) : _upcomingKey(today);
  }

  void _selectDay(DateTime day, DateTime today) {
    setState(() {
      if (_selectedDay == day) {
        _selectedDay = null;
        return;
      }
      _selectedDay = day;
      if (day.isBefore(today)) _past = true;
      if (day.isAfter(today)) _past = false;
    });
  }

  void _moveWeek(int weeks) {
    setState(() {
      _weekStart = DateTime(
        _weekStart.year,
        _weekStart.month,
        _weekStart.day + 7 * weeks,
      );
      _selectedDay = null;
    });
  }

  Future<void> _refresh(DateTime today) async {
    bumpMeetingCalendar(ref.read);
    try {
      await Future.wait([
        ref.read(meetingRangeProvider(_listKey(today)).future),
        ref.read(meetingRangeProvider(_weekKey).future),
      ]);
    } on Object {
      // Lỗi hiện trong danh sách kèm nút Thử lại.
    }
  }

  Future<void> _create() async {
    final created = await Navigator.of(context).push<CalendarMeeting>(
      MaterialPageRoute(
        builder: (_) => MeetingFormScreen(workspaceId: widget.workspaceId),
      ),
    );
    if (!mounted || created == null) return;
    bumpMeetingCalendar(ref.read);
    _openMeeting(created);
  }

  void _openMeeting(CalendarMeeting meeting) {
    context.push(
      meetingDetailLocation(
        workspaceId: widget.workspaceId,
        channelId: meeting.channelId,
        meetingId: meeting.id,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final now = _now();
    final today = meetingDayStart(now);
    final weekAsync = ref.watch(meetingRangeProvider(_weekKey));
    final listKey = _listKey(today);
    final listAsync = ref.watch(meetingRangeProvider(listKey));
    final marked = <DateTime>{
      for (final meeting in weekAsync.valueOrNull ?? const <CalendarMeeting>[])
        if (!meeting.isCancelled) meetingDayStart(meeting.startsAt),
    };
    final selectedDay = _selectedDay;

    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Lịch họp', 'Meetings')),
        actions: [
          IconButton(
            key: const Key('meeting_create'),
            tooltip: tr('Tạo họp', 'New meeting'),
            onPressed: _create,
            icon: const Icon(WebTuiIcons.add),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => _refresh(today),
          child: ListView(
            key: const Key('meetings_list'),
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
            children: [
              MeetingWeekStrip(
                weekStart: _weekStart,
                today: today,
                selectedDay: selectedDay,
                markedDays: marked,
                onSelectDay: (day) => _selectDay(day, today),
                onPreviousWeek: () => _moveWeek(-1),
                onNextWeek: () => _moveWeek(1),
              ),
              const SizedBox(height: 8),
              _TabSwitch(
                past: _past,
                onChanged: (past) => setState(() => _past = past),
              ),
              if (selectedDay != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          tr(
                            'Đang xem ${meetingDayHeading(selectedDay, now)}',
                            'Showing ${meetingDayHeading(selectedDay, now)}',
                          ),
                          style: WebTuiTypography.bodySmall.copyWith(
                            color: WebTuiColors.textSecondary,
                          ),
                        ),
                      ),
                      TextButton(
                        key: const Key('meeting_clear_day'),
                        style: TextButton.styleFrom(
                          minimumSize: const Size(
                            meetingMinTapSize,
                            meetingMinTapSize,
                          ),
                          foregroundColor: MeetingTones.accentText,
                        ),
                        onPressed: () => setState(() => _selectedDay = null),
                        child: Text(tr('Xem tất cả', 'Show all')),
                      ),
                    ],
                  ),
                ),
              ...listAsync.when(
                skipLoadingOnReload: true,
                loading: () => const [
                  SizedBox(height: 12),
                  WorkSkeleton(height: 84, radius: 18),
                  SizedBox(height: 10),
                  WorkSkeleton(height: 84, radius: 18),
                ],
                error: (error, _) => [
                  const SizedBox(height: 24),
                  WorkErrorBox(
                    message: meetingErrorText(error),
                    onRetry: () =>
                        ref.invalidate(meetingRangeProvider(listKey)),
                  ),
                ],
                data: (all) {
                  final inScope = selectedDay == null
                      ? all
                      : [
                          for (final meeting in all)
                            if (meetingSameDay(meeting.startsAt, selectedDay))
                              meeting,
                        ];
                  final items = meetingsForTab(inScope, past: _past, now: now);
                  if (items.isEmpty) {
                    return [
                      WorkEmptyBox(
                        icon: WebTuiIcons.meetings,
                        message: _past
                            ? tr('Chưa có cuộc họp đã qua', 'No past meetings')
                            : tr(
                                'Chưa có cuộc họp sắp tới',
                                'No upcoming meetings',
                              ),
                      ),
                    ];
                  }
                  return [
                    for (final (day, meetings) in groupCalendarMeetingsByDay(
                      items,
                    )) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
                        child: Text(
                          meetingDayHeading(day, now),
                          style: WebTuiTypography.titleMedium.copyWith(
                            fontWeight: FontWeight.w800,
                            color: WebTuiColors.textPrimary,
                          ),
                        ),
                      ),
                      for (final meeting in meetings)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: MeetingCard(
                            meeting: meeting,
                            now: now,
                            onTap: () => _openMeeting(meeting),
                          ),
                        ),
                    ],
                  ];
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TabSwitch extends StatelessWidget {
  const _TabSwitch({required this.past, required this.onChanged});

  final bool past;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget tab(String label, bool value, Key key) {
      final selected = past == value;
      return Expanded(
        child: Semantics(
          selected: selected,
          button: true,
          child: Material(
            color: selected ? WebTuiColors.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              key: key,
              borderRadius: BorderRadius.circular(12),
              onTap: () => onChanged(value),
              child: SizedBox(
                height: meetingMinTapSize,
                child: Center(
                  child: Text(
                    label,
                    style: WebTuiTypography.bodyMedium.copyWith(
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                      color: selected
                          ? WebTuiColors.textPrimary
                          : WebTuiColors.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: WebTuiColors.backgroundMuted,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: WebTuiColors.border.withValues(alpha: 0.55)),
      ),
      child: Row(
        children: [
          tab(
            tr('Sắp tới', 'Upcoming'),
            false,
            const Key('meeting_tab_upcoming'),
          ),
          tab(tr('Đã qua', 'Past'), true, const Key('meeting_tab_past')),
        ],
      ),
    );
  }
}
