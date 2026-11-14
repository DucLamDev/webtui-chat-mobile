import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../design_system/icons/webtui_icons.dart';
import '../../../../design_system/tokens/webtui_colors.dart';
import '../../../../design_system/tokens/webtui_typography.dart';
import '../../../conversations/presentation/widgets/collaboration_room_sheet.dart';
import '../../domain/entities/work_hub.dart';
import '../controllers/work_hub_providers.dart';
import '../widgets/work_common.dart';

/// Vị trí tab Họp trong bảng cộng tác của kênh.
const _meetingTabIndex = 1;

/// Nhóm họp theo ngày địa phương: "Hôm nay", "Ngày mai", còn lại dd/MM.
List<(String, List<UpcomingMeeting>)> groupMeetingsByDay(
  List<UpcomingMeeting> meetings,
  DateTime now,
) {
  final today = DateTime(now.year, now.month, now.day);
  final sorted = [...meetings]
    ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
  final groups = <DateTime, List<UpcomingMeeting>>{};
  for (final meeting in sorted) {
    final local = meeting.startsAt.toLocal();
    final day = DateTime(local.year, local.month, local.day);
    groups.putIfAbsent(day, () => []).add(meeting);
  }
  return [
    for (final entry in groups.entries)
      (
        switch (entry.key.difference(today).inDays) {
          0 => 'Hôm nay',
          1 => 'Ngày mai',
          _ => workShortDate(entry.key),
        },
        entry.value,
      ),
  ];
}

String _clock(DateTime value) {
  final local = value.toLocal();
  return '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';
}

/// Lịch họp sắp tới của mọi kênh người dùng tham gia.
class MeetingsScreen extends ConsumerWidget {
  const MeetingsScreen({required this.workspaceId, this.now, super.key});

  final String workspaceId;

  /// Chỉ để test cố định "hôm nay".
  final DateTime? now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(upcomingMeetingsProvider(workspaceId));
    return Scaffold(
      appBar: AppBar(title: const Text('Lịch họp')),
      body: SafeArea(
        child: async.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              children: [
                WorkSkeleton(height: 72, radius: 16),
                SizedBox(height: 10),
                WorkSkeleton(height: 72, radius: 16),
              ],
            ),
          ),
          error: (error, _) => Center(
            child: WorkErrorBox(
              message: workHubErrorText(error),
              onRetry: () => ref.invalidate(upcomingMeetingsProvider),
            ),
          ),
          data: (meetings) {
            if (meetings.isEmpty) {
              return const WorkEmptyBox(
                icon: WebTuiIcons.meetings,
                message: 'Chưa có cuộc họp sắp tới',
              );
            }
            final groups = groupMeetingsByDay(meetings, now ?? DateTime.now());
            return RefreshIndicator(
              onRefresh: () async => ref.invalidate(upcomingMeetingsProvider),
              child: ListView(
                key: const Key('meetings_list'),
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                children: [
                  for (final (label, items) in groups) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 14, 4, 8),
                      child: Text(
                        label,
                        style: WebTuiTypography.titleMedium.copyWith(
                          fontWeight: FontWeight.w800,
                          color: WebTuiColors.textPrimary,
                        ),
                      ),
                    ),
                    for (final meeting in items)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _MeetingCard(
                          meeting: meeting,
                          onTap: () => showCollaborationRoomSheet(
                            context,
                            workspaceId: workspaceId,
                            channelId: meeting.channelId,
                            title: meeting.channelName.isEmpty
                                ? 'Hội thoại'
                                : meeting.channelName,
                            conversation: null,
                            initialTab: _meetingTabIndex,
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _MeetingCard extends StatelessWidget {
  const _MeetingCard({required this.meeting, required this.onTap});

  final UpcomingMeeting meeting;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final end = meeting.endsAt;
    final time = end == null
        ? _clock(meeting.startsAt)
        : '${_clock(meeting.startsAt)} – ${_clock(end)}';
    return WorkCard(
      key: Key('meeting_${meeting.id}'),
      radius: 18,
      onTap: onTap,
      child: Row(
        children: [
          WorkIconBox(
            icon: WebTuiIcons.meetings,
            size: 48,
            radius: 15,
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
                  children: [
                    Text(
                      time,
                      style: WebTuiTypography.bodySmall.copyWith(
                        color: WebTuiColors.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (meeting.isActive) const _LiveBadge(),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  meeting.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: WebTuiTypography.bodyMedium.copyWith(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700,
                    color: WebTuiColors.textPrimary,
                  ),
                ),
                if (meeting.channelName.isNotEmpty)
                  Text(
                    meeting.channelName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: WebTuiTypography.bodySmall.copyWith(
                      color: WebTuiColors.textMuted,
                    ),
                  ),
              ],
            ),
          ),
          const Icon(WebTuiIcons.forward, color: WebTuiColors.textMuted),
        ],
      ),
    );
  }
}

class _LiveBadge extends StatelessWidget {
  const _LiveBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFFE7F7EE),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        'Đang diễn ra',
        style: WebTuiTypography.labelSmall.copyWith(
          color: const Color(0xFF1E9E5A),
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
