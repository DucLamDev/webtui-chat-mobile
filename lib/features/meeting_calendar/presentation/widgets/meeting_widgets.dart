import 'package:flutter/material.dart';

import '../../../../design_system/icons/webtui_icons.dart';
import '../../../../design_system/tokens/webtui_colors.dart';
import '../../../../design_system/tokens/webtui_typography.dart';
import '../../../../l10n/app_strings.dart';
import '../../../work_hub/presentation/widgets/work_common.dart';
import '../../domain/entities/calendar_meeting.dart';
import '../controllers/meeting_calendar_controllers.dart';

/// Vùng bấm tối thiểu.
const meetingMinTapSize = 48.0;

/// Màu chữ / nền của Lịch họp, đã kiểm tương phản ≥ 4.5:1 ở cả nền sáng và
/// tối (chữ nhỏ trên nền thẻ / nền nhãn).
final class MeetingTones {
  const MeetingTones._();

  static bool get _dark => WebTuiColors.brightness == Brightness.dark;

  /// Chữ nhấn (link, giờ): sáng #0561C7 (5.9:1), tối #3D96FF (5.4:1).
  static Color get accentText =>
      _dark ? WebTuiColors.primary : WebTuiColors.primaryPressed;

  /// Nền nút chính có chữ trắng: sáng 5.9:1, tối 6.2:1.
  static Color get actionBackground =>
      _dark ? const Color(0xFF1D5FB8) : WebTuiColors.primaryPressed;

  static Color get dangerText =>
      _dark ? const Color(0xFFFFA8A8) : const Color(0xFFB42318);

  static Color get warningText =>
      _dark ? const Color(0xFFF5C46B) : const Color(0xFF7A4A00);

  static Color get warningBackground =>
      _dark ? const Color(0xFF3A2C10) : const Color(0xFFFFF4DC);

  static (Color background, Color foreground) phase(MeetingPhase phase) {
    return switch (phase) {
      MeetingPhase.upcoming =>
        _dark
            ? (const Color(0xFF14304F), const Color(0xFF9CC8FF))
            : (const Color(0xFFE8F2FF), const Color(0xFF0561C7)),
      MeetingPhase.live =>
        _dark
            ? (const Color(0xFF153826), const Color(0xFF7FE0B0))
            : (const Color(0xFFE7F7EE), const Color(0xFF13774A)),
      MeetingPhase.ended =>
        _dark
            ? (const Color(0xFF2A3850), const Color(0xFFA7B3C6))
            : (const Color(0xFFEEF3F8), const Color(0xFF536074)),
      MeetingPhase.cancelled =>
        _dark
            ? (const Color(0xFF3A1A1A), const Color(0xFFFFA8A8))
            : (const Color(0xFFFDECEC), const Color(0xFFB42318)),
    };
  }

  static Color responseText(MeetingResponse response) => switch (response) {
    MeetingResponse.accepted =>
      _dark ? const Color(0xFF7FE0B0) : const Color(0xFF13774A),
    MeetingResponse.tentative => warningText,
    MeetingResponse.declined => dangerText,
    MeetingResponse.pending => WebTuiColors.textSecondary,
  };
}

class MeetingPill extends StatelessWidget {
  const MeetingPill({
    required this.label,
    required this.background,
    required this.foreground,
    super.key,
  });

  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: WebTuiTypography.labelSmall.copyWith(
          color: foreground,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class MeetingStatusBadge extends StatelessWidget {
  const MeetingStatusBadge({required this.phase, super.key});

  final MeetingPhase phase;

  @override
  Widget build(BuildContext context) {
    final (background, foreground) = MeetingTones.phase(phase);
    return MeetingPill(
      key: Key('meeting_phase_${phase.name}'),
      label: phase.label,
      background: background,
      foreground: foreground,
    );
  }
}

/// Phản hồi của mình trên thẻ: "Bạn: Tham gia".
String myResponseLabel(MeetingResponse response) =>
    tr('Bạn: ${response.label}', 'You: ${response.label}');

/// Thẻ cuộc họp trong danh sách.
class MeetingCard extends StatelessWidget {
  const MeetingCard({
    required this.meeting,
    required this.now,
    required this.onTap,
    super.key,
  });

  final CalendarMeeting meeting;
  final DateTime now;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final phase = meetingPhaseAt(meeting, now);
    final response = meeting.myResponse;
    final muted = phase == MeetingPhase.cancelled;
    return Semantics(
      button: true,
      child: WorkCard(
        key: Key('meeting_${meeting.id}'),
        radius: 18,
        onTap: onTap,
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: meetingMinTapSize),
          child: Row(
            children: [
              WorkIconBox(
                icon: meeting.hasExternalUrl
                    ? WebTuiIcons.externalLink
                    : WebTuiIcons.video,
                size: 44,
                radius: 14,
                background: webTuiShortcutColors('orange').background,
                foreground: webTuiShortcutColors('orange').foreground,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        Text(
                          meetingTimeRange(meeting),
                          style: WebTuiTypography.bodySmall.copyWith(
                            color: MeetingTones.accentText,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        MeetingStatusBadge(phase: phase),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      meeting.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: WebTuiTypography.bodyMedium.copyWith(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700,
                        color: WebTuiColors.textPrimary,
                        decoration: muted ? TextDecoration.lineThrough : null,
                      ),
                    ),
                    if (meeting.channelName.isNotEmpty)
                      Text(
                        meeting.channelName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: WebTuiTypography.bodySmall.copyWith(
                          color: WebTuiColors.textSecondary,
                        ),
                      ),
                    if (response != null && !muted)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          myResponseLabel(response),
                          key: Key('meeting_${meeting.id}_response'),
                          style: WebTuiTypography.bodySmall.copyWith(
                            color: MeetingTones.responseText(response),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Icon(WebTuiIcons.forward, color: WebTuiColors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

/// Dải 7 ngày (Thứ 2 → Chủ nhật) có nút tuần trước / sau và chấm ngày có họp.
class MeetingWeekStrip extends StatelessWidget {
  const MeetingWeekStrip({
    required this.weekStart,
    required this.today,
    required this.selectedDay,
    required this.markedDays,
    required this.onSelectDay,
    required this.onPreviousWeek,
    required this.onNextWeek,
    super.key,
  });

  final DateTime weekStart;
  final DateTime today;
  final DateTime? selectedDay;

  /// Ngày (đầu ngày địa phương) có ít nhất một cuộc họp chưa huỷ.
  final Set<DateTime> markedDays;
  final ValueChanged<DateTime> onSelectDay;
  final VoidCallback onPreviousWeek;
  final VoidCallback onNextWeek;

  @override
  Widget build(BuildContext context) {
    final days = [
      for (var i = 0; i < 7; i++)
        DateTime(weekStart.year, weekStart.month, weekStart.day + i),
    ];
    final last = days.last;
    final range = '${meetingShortDate(days.first)} – ${meetingShortDate(last)}';
    return Column(
      children: [
        Row(
          children: [
            IconButton(
              key: const Key('meeting_week_prev'),
              tooltip: tr('Tuần trước', 'Previous week'),
              onPressed: onPreviousWeek,
              icon: Icon(WebTuiIcons.back, color: WebTuiColors.textPrimary),
            ),
            Expanded(
              child: Text(
                range,
                key: const Key('meeting_week_label'),
                textAlign: TextAlign.center,
                style: WebTuiTypography.bodyMedium.copyWith(
                  fontWeight: FontWeight.w700,
                  color: WebTuiColors.textPrimary,
                ),
              ),
            ),
            IconButton(
              key: const Key('meeting_week_next'),
              tooltip: tr('Tuần sau', 'Next week'),
              onPressed: onNextWeek,
              icon: Icon(WebTuiIcons.forward, color: WebTuiColors.textPrimary),
            ),
          ],
        ),
        Row(
          children: [
            for (final day in days)
              Expanded(
                child: _DayCell(
                  day: day,
                  isToday: day == today,
                  selected: selectedDay == day,
                  marked: markedDays.contains(day),
                  onTap: () => onSelectDay(day),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.isToday,
    required this.selected,
    required this.marked,
    required this.onTap,
  });

  final DateTime day;
  final bool isToday;
  final bool selected;
  final bool marked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final foreground = selected
        ? Colors.white
        : isToday
        ? MeetingTones.accentText
        : WebTuiColors.textPrimary;
    final label =
        '${meetingWeekdayLong(day.weekday)} ${meetingShortDate(day)}'
        '${marked ? tr(', có họp', ', has meetings') : ''}';
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Material(
          color: selected ? MeetingTones.actionBackground : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            key: Key('meeting_day_${day.year}-${day.month}-${day.day}'),
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 64),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    meetingWeekdayShort(day.weekday),
                    style: WebTuiTypography.labelSmall.copyWith(
                      color: selected
                          ? Colors.white
                          : WebTuiColors.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${day.day}',
                    style: WebTuiTypography.bodyMedium.copyWith(
                      color: foreground,
                      fontWeight: isToday || selected
                          ? FontWeight.w800
                          : FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    key: marked
                        ? Key('meeting_dot_${day.year}-${day.month}-${day.day}')
                        : null,
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: marked
                          ? (selected ? Colors.white : MeetingTones.accentText)
                          : Colors.transparent,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Tiêu đề mục trong màn chi tiết / biểu mẫu.
class MeetingSectionTitle extends StatelessWidget {
  const MeetingSectionTitle(this.text, {this.trailing, super.key});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              style: WebTuiTypography.titleMedium.copyWith(
                fontWeight: FontWeight.w800,
                color: WebTuiColors.textPrimary,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// Ảnh đại diện chữ cái đầu (không tải ảnh mạng trong danh sách người họp).
class MeetingInitialAvatar extends StatelessWidget {
  const MeetingInitialAvatar({required this.name, super.key});

  final String name;

  @override
  Widget build(BuildContext context) {
    final trimmed = name.trim();
    final initial = trimmed.isEmpty
        ? '?'
        : String.fromCharCode(trimmed.runes.first).toUpperCase();
    return CircleAvatar(
      radius: 18,
      backgroundColor: WebTuiColors.primarySoft,
      child: Text(
        initial,
        style: WebTuiTypography.bodyMedium.copyWith(
          color: MeetingTones.accentText,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
