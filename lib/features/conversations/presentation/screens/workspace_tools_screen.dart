import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../design_system/components/webtui_components.dart';
import '../../../../design_system/icons/webtui_icons.dart';
import '../../../../design_system/tokens/webtui_colors.dart';
import '../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../design_system/tokens/webtui_typography.dart';
import '../../../../l10n/app_strings.dart';
import '../../../meeting_calendar/domain/entities/calendar_meeting.dart';
import '../../../meeting_calendar/presentation/controllers/meeting_calendar_controllers.dart';
import '../../../meeting_calendar/presentation/meeting_calendar_routes.dart';
import '../../../moderation/presentation/controllers/moderation_controller.dart';
import '../../../work_hub/presentation/controllers/work_hub_providers.dart';
import '../../../work_hub/presentation/screens/meetings_screen.dart';
import '../../../work_hub/presentation/widgets/my_tasks_card.dart';
import '../../../work_hub/presentation/widgets/work_apps_grid.dart';
import '../../../work_hub/presentation/widgets/work_common.dart';
import '../../domain/entities/conversation_summary.dart';
import '../widgets/workspace_modules.dart';

/// Công cụ tạo nội dung dùng chung trong phòng chat bị khoá khi người dùng bị
/// chặn / chưa rõ trạng thái chặn (dùng cho các công cụ mở từ phòng chat).
bool workspaceToolsSharedContentBlocked(
  ConversationSummary room,
  ModerationState moderationState,
) {
  if (room.kind != ConversationKind.direct) return false;
  if (moderationState.isLoadingBlockedUsers ||
      moderationState.errorMessage != null) {
    return true;
  }
  final peerUserId = room.directCallTargetUserId();
  if (peerUserId == null || peerUserId.trim().isEmpty) return true;
  return moderationState.isBlocked(peerUserId);
}

/// Số cuộc họp sắp tới hiện ở tab Công việc (đủ danh sách ở màn Lịch họp).
const upcomingMeetingsPreviewLimit = 3;

/// Tab Công việc (giao diện liền mạch, không thẻ): tiêu đề lớn + tìm việc, Việc
/// của tôi, lưới Ứng dụng (Lịch họp, Tệp chia sẻ, tiện ích như Ghi chú, lối
/// tắt), Họp sắp tới. Công cụ cộng tác (họp, bảng trắng...) vẫn mở từ bên trong
/// từng phòng chat.
class WorkspaceToolsScreen extends ConsumerWidget {
  const WorkspaceToolsScreen({required this.workspaceId, this.now, super.key});

  final String workspaceId;

  /// Chỉ để test cố định "bây giờ" (nhãn Hôm nay / Ngày mai của họp).
  final DateTime? now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = workspaceId.trim();
    if (id.isEmpty) {
      return WebTuiEmptyState(
        key: const Key('workspace_tools_empty'),
        title: tr('Chưa có workspace', 'No workspace yet'),
        message: tr(
          'Chọn một workspace để xem công việc của bạn.',
          'Select a workspace to see your work.',
        ),
        icon: WebTuiIcons.work,
      );
    }
    final modules = ref
        .watch(workspaceModulesProvider)
        .where((module) => module.enabled)
        .toList(growable: false);
    final workHub = ref.watch(workHubEnabledProvider);
    return ColoredBox(
      color: WebTuiColors.page,
      child: ListView(
        key: const Key('workspace_tools_list'),
        // Đệm đáy gồm chỗ của thanh tab nổi: nhóm cuối không bị che.
        padding: EdgeInsets.only(
          bottom:
              WebTuiSpacing.lg +
              WebTuiFloatingTabBar.contentBottomPadding(context),
        ),
        children: [
          WebTuiLargeTitleBar(
            title: context.strings.tabWork,
            actions: [
              WebTuiHeaderIconButton(
                key: const Key('work_search'),
                icon: WebTuiIcons.search,
                tooltip: tr('Tìm việc của tôi', 'Search my tasks'),
                onPressed: () => context.push(
                  Uri(
                    path: '/my-tasks',
                    queryParameters: {'workspaceId': id, 'search': '1'},
                  ).toString(),
                ),
              ),
            ],
          ),
          MyTasksCard(workspaceId: id),
          const WebTuiGroupGap(),
          WorkAppsSection(
            workspaceId: id,
            extraApps: [
              for (final module in modules)
                WorkAppItem(
                  key: Key('workspace_module_${module.id}'),
                  glyph: _moduleGlyph(module),
                  color: WebTuiColors.primary,
                  label: _moduleLabel(module),
                  onTap: () => context.push(module.routeFor(id)),
                ),
            ],
          ),
          if (workHub) ...[
            const WebTuiGroupGap(),
            _UpcomingMeetingsSection(workspaceId: id, now: now),
          ],
        ],
      ),
    );
  }
}

PhosphorDuotoneGlyph _moduleGlyph(WorkspaceModule module) =>
    switch (module.id) {
      'my_notes' => WebTuiDuotoneIcons.note,
      _ => webTuiShortcutDuotoneIcon(null),
    };

String _moduleLabel(WorkspaceModule module) => switch (module.id) {
  'my_notes' => tr('Ghi chú', 'Notes'),
  _ => module.title,
};

/// Nhóm "Họp sắp tới": tối đa [upcomingMeetingsPreviewLimit] cuộc họp chưa
/// qua, chưa huỷ, dùng chung danh sách Sắp tới của màn Lịch họp.
class _UpcomingMeetingsSection extends ConsumerWidget {
  const _UpcomingMeetingsSection({required this.workspaceId, this.now});

  final String workspaceId;
  final DateTime? now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = now ?? DateTime.now();
    final today = meetingDayStart(current);
    // Cùng khoá với tab Sắp tới của màn Lịch họp: dùng chung bộ nhớ đệm và
    // tự tải lại khi lịch họp đổi (meetingCalendarRefreshTickProvider).
    final key = (
      workspaceId: workspaceId,
      from: today,
      to: DateTime(today.year, today.month, today.day + meetingListWindowDays),
    );
    final async = ref.watch(meetingRangeProvider(key));
    return Column(
      key: const Key('upcoming_meetings'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        WebTuiGroupHeader(
          title: tr('Họp sắp tới', 'Upcoming meetings'),
          actionLabel: tr('Lịch họp', 'Meetings'),
          actionKey: const Key('upcoming_meetings_all'),
          onAction: () => context.push(
            Uri(
              path: '/meetings',
              queryParameters: {'workspaceId': workspaceId},
            ).toString(),
          ),
        ),
        ...async.when(
          skipLoadingOnReload: true,
          loading: () => [
            WorkSeamlessNote(
              key: const Key('upcoming_meetings_loading'),
              message: tr('Đang tải lịch họp…', 'Loading meetings…'),
            ),
          ],
          error: (error, _) => [
            WorkSeamlessError(
              key: const Key('upcoming_meetings_error'),
              message: meetingErrorText(error),
              onRetry: () => ref.invalidate(meetingRangeProvider(key)),
            ),
          ],
          data: (all) {
            final items = meetingsForTab(
              [
                for (final meeting in all)
                  if (!meeting.isCancelled) meeting,
              ],
              past: false,
              now: current,
            ).take(upcomingMeetingsPreviewLimit).toList();
            if (items.isEmpty) {
              return [
                WorkSeamlessNote(
                  key: const Key('upcoming_meetings_empty'),
                  message: tr(
                    'Chưa có cuộc họp sắp tới',
                    'No upcoming meetings',
                  ),
                ),
              ];
            }
            return [
              for (var i = 0; i < items.length; i++)
                _UpcomingMeetingRow(
                  meeting: items[i],
                  now: current,
                  divider: i < items.length - 1,
                  onTap: () => context.push(
                    meetingDetailLocation(
                      workspaceId: workspaceId,
                      channelId: items[i].channelId,
                      meetingId: items[i].id,
                    ),
                  ),
                ),
            ];
          },
        ),
      ],
    );
  }
}

/// Nhãn ngày ngắn ở cột giờ: Hôm nay / Ngày mai / dd/MM.
String _meetingDayShort(DateTime startsAt, DateTime now) {
  final today = meetingDayStart(now);
  final day = meetingDayStart(startsAt);
  if (day == today) return tr('Hôm nay', 'Today');
  if (day == DateTime(today.year, today.month, today.day + 1)) {
    return tr('Ngày mai', 'Tomorrow');
  }
  return meetingShortDate(day);
}

class _UpcomingMeetingRow extends StatelessWidget {
  const _UpcomingMeetingRow({
    required this.meeting,
    required this.now,
    required this.divider,
    required this.onTap,
  });

  final CalendarMeeting meeting;
  final DateTime now;
  final bool divider;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return WorkSeamlessRow(
      key: Key('upcoming_meeting_${meeting.id}'),
      leadingWidth: 66,
      divider: divider,
      title: meeting.title,
      subtitle: meeting.channelName,
      onTap: onTap,
      leading: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            meetingClock(meeting.startsAt),
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.fade,
            style: WebTuiTypography.bodyMedium.copyWith(
              fontSize: 15,
              height: 1.3,
              fontWeight: FontWeight.w700,
              color: WebTuiColors.textPrimary,
            ),
          ),
          Text(
            _meetingDayShort(meeting.startsAt, now),
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.fade,
            style: WebTuiTypography.bodySmall.copyWith(
              fontSize: 12.5,
              height: 1.3,
              color: WebTuiColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}
