import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/providers/foundation_providers.dart';
import '../../../../core/error/error_mapper.dart';
import '../../../../core/result/result.dart';
import '../../../../design_system/icons/webtui_icons.dart';
import '../../../../design_system/tokens/webtui_colors.dart';
import '../../../../design_system/tokens/webtui_typography.dart';
import '../../../../l10n/app_strings.dart';
import '../../../conversations/domain/entities/collaboration_room.dart';
import '../../../meetings/application/meeting_providers.dart';
import '../../../meetings/domain/meeting_models.dart';
import '../../../meetings/presentation/meeting_room_screen.dart';
import '../../../work_hub/presentation/widgets/work_common.dart';
import '../../application/meeting_calendar_providers.dart';
import '../../domain/entities/calendar_meeting.dart';
import '../controllers/meeting_calendar_controllers.dart';
import '../meeting_calendar_routes.dart';
import '../widgets/meeting_dialogs.dart';
import '../widgets/meeting_widgets.dart';
import 'meeting_form_screen.dart';

/// Chi tiết một cuộc họp: thông tin, phản hồi, Vào họp, Nhắn vào nhóm, Sửa /
/// Huỷ, biên bản, việc giao từ cuộc họp, link khách.
class MeetingDetailScreen extends ConsumerStatefulWidget {
  const MeetingDetailScreen({
    required this.workspaceId,
    required this.channelId,
    required this.meetingId,
    this.now,
    this.clock,
    super.key,
  });

  final String workspaceId;
  final String channelId;
  final String meetingId;

  /// Chỉ để test cố định "bây giờ".
  final DateTime? now;

  /// Chỉ để test: đồng hồ giả (đổi được giữa chừng) khi không có [now].
  final DateTime Function()? clock;

  @override
  ConsumerState<MeetingDetailScreen> createState() =>
      _MeetingDetailScreenState();
}

class _MeetingDetailScreenState extends ConsumerState<MeetingDetailScreen>
    with MeetingClockTicker<MeetingDetailScreen> {
  bool _busy = false;

  MeetingKey get _key => (
    workspaceId: widget.workspaceId,
    channelId: widget.channelId,
    meetingId: widget.meetingId,
  );

  DateTime _now() => widget.now ?? (widget.clock ?? DateTime.now)();

  void _notice(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// Chạy một thao tác ghi; lỗi thì báo, xong thì tải lại lịch họp.
  Future<bool> _run(
    Future<Result<Object?>> Function() action, {
    String? done,
  }) async {
    if (_busy) return false;
    setState(() => _busy = true);
    final result = await action();
    if (!mounted) return false;
    setState(() => _busy = false);
    switch (result) {
      case Success():
        bumpMeetingCalendar(ref.read);
        if (done != null) _notice(done);
        return true;
      case FailureResult(failure: final failure):
        _notice(userFacingErrorMessage(failure));
        return false;
    }
  }

  Future<void> _respond(MeetingResponse response) async {
    await _run(
      () => ref
          .read(respondToMeetingUseCaseProvider)
          .execute(
            workspaceId: widget.workspaceId,
            channelId: widget.channelId,
            meetingId: widget.meetingId,
            response: response,
          ),
      done: tr(
        'Đã trả lời: ${response.label}',
        'Response saved: ${response.label}',
      ),
    );
  }

  Future<void> _join(CalendarMeeting meeting) async {
    final external = meeting.externalUrl;
    final launcher = ref.read(externalUrlLauncherProvider);
    if (external != null && external.isNotEmpty) {
      if (!await launcher.open(external)) {
        _notice(
          tr(
            'Không mở được link họp trên thiết bị này.',
            'Couldn\'t open the meeting link on this device.',
          ),
        );
      }
      return;
    }
    if (_busy) return;
    setState(() => _busy = true);
    final api = ref.read(meetingApiProvider);
    final MeetingJoinInfo join;
    try {
      join = await api.fetchJoinToken(
        workspaceId: widget.workspaceId,
        channelId: widget.channelId,
        meetingId: meeting.id,
      );
    } on Object catch (error) {
      if (mounted) setState(() => _busy = false);
      _notice(userFacingErrorMessage(error));
      return;
    }
    if (!mounted) return;
    setState(() => _busy = false);
    if (join.provider == MeetingProviderKind.jitsi) {
      final base = Uri.tryParse(join.serverUrl);
      final opened =
          base != null &&
          join.room.isNotEmpty &&
          await launcher.open(
            MeetingJoinInfo.withJitsiJwt(
              base.resolve(Uri.encodeComponent(join.room)),
              join.token,
            ).toString(),
          );
      if (!opened) {
        _notice(
          tr(
            'Không mở được phòng họp trên thiết bị này.',
            'Couldn\'t open the meeting room on this device.',
          ),
        );
      }
      return;
    }
    await Navigator.of(context, rootNavigator: true).push<void>(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => MeetingRoomScreen(
          title: meeting.title,
          join: join,
          refreshJoin: () => api.fetchJoinToken(
            workspaceId: widget.workspaceId,
            channelId: widget.channelId,
            meetingId: meeting.id,
          ),
        ),
      ),
    );
  }

  void _openGroup(CalendarMeeting meeting) {
    context.push(
      meetingGroupChatLocation(
        workspaceId: widget.workspaceId,
        channelId: meeting.channelId,
        title: meeting.channelName.isEmpty
            ? tr('Nhóm', 'Group')
            : meeting.channelName,
      ),
    );
  }

  Future<void> _edit(CalendarMeeting meeting) async {
    final saved = await Navigator.of(context).push<CalendarMeeting>(
      MaterialPageRoute(
        builder: (_) => MeetingFormScreen(
          workspaceId: widget.workspaceId,
          existing: meeting,
        ),
      ),
    );
    if (saved != null && mounted) {
      _notice(tr('Đã lưu cuộc họp.', 'Meeting saved.'));
    }
  }

  Future<void> _cancel(CalendarMeeting meeting) async {
    MeetingScope scope = MeetingScope.occurrence;
    if (meeting.isRecurring) {
      final picked = await askMeetingScope(
        context,
        title: tr('Huỷ cuộc họp', 'Cancel meeting'),
      );
      if (picked == null) return;
      scope = picked;
    } else {
      final ok = await confirmMeetingAction(
        context,
        title: tr('Huỷ cuộc họp?', 'Cancel this meeting?'),
        message: tr(
          'Nhóm sẽ nhận tin báo và người tham dự nhận thông báo.',
          'The group gets a message and attendees get a notification.',
        ),
        confirmLabel: tr('Huỷ họp', 'Cancel meeting'),
        destructive: true,
      );
      if (!ok) return;
    }
    if (!mounted) return;
    await _run(
      () => ref
          .read(cancelMeetingUseCaseProvider)
          .execute(
            workspaceId: widget.workspaceId,
            channelId: widget.channelId,
            meetingId: widget.meetingId,
            scope: scope,
          ),
      done: tr('Đã huỷ cuộc họp.', 'Meeting canceled.'),
    );
  }

  Future<void> _editMinutes(CalendarMeeting meeting) async {
    final content = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) =>
            _MinutesEditorScreen(initial: meeting.minutes?.content ?? ''),
      ),
    );
    if (content == null || !mounted) return;
    await _run(
      () => ref
          .read(meetingMinutesUseCaseProvider)
          .save(
            workspaceId: widget.workspaceId,
            channelId: widget.channelId,
            meetingId: widget.meetingId,
            content: content,
          ),
      done: tr('Đã lưu biên bản.', 'Minutes saved.'),
    );
  }

  Future<void> _publishMinutes() async {
    final ok = await confirmMeetingAction(
      context,
      title: tr('Gửi biên bản vào nhóm?', 'Send minutes to the group?'),
      message: tr(
        'Biên bản sẽ được gửi thành một tin trong nhóm chat.',
        'The minutes will be posted as a message in the group chat.',
      ),
      confirmLabel: tr('Gửi', 'Send'),
    );
    if (!ok || !mounted) return;
    await _run(
      () => ref
          .read(meetingMinutesUseCaseProvider)
          .publish(
            workspaceId: widget.workspaceId,
            channelId: widget.channelId,
            meetingId: widget.meetingId,
          ),
      done: tr('Đã gửi biên bản vào nhóm.', 'Minutes sent to the group.'),
    );
  }

  Future<void> _addTask(CalendarMeeting meeting) async {
    final draft = await showDialog<_TaskDraft>(
      context: context,
      builder: (_) => _TaskDialog(attendees: meeting.attendees),
    );
    if (draft == null || !mounted) return;
    await _run(
      () => ref
          .read(meetingTasksUseCaseProvider)
          .create(
            workspaceId: widget.workspaceId,
            channelId: widget.channelId,
            meetingId: widget.meetingId,
            title: draft.title,
            assigneeUserId: draft.assigneeUserId,
          ),
      done: tr('Đã giao việc.', 'Task assigned.'),
    );
  }

  Future<void> _setGuestLink(bool enabled) async {
    await _run(
      () => ref
          .read(meetingGuestLinkUseCaseProvider)
          .setEnabled(
            workspaceId: widget.workspaceId,
            channelId: widget.channelId,
            meetingId: widget.meetingId,
            enabled: enabled,
          ),
      done: enabled
          ? tr('Đã bật link cho khách.', 'Guest link turned on.')
          : tr('Đã tắt link cho khách.', 'Guest link turned off.'),
    );
  }

  Future<void> _copy(String url) async {
    await Clipboard.setData(ClipboardData(text: url));
    _notice(tr('Đã sao chép link.', 'Link copied.'));
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(meetingDetailProvider(_key));
    final meeting = async.valueOrNull;
    final now = _now();
    final phase = meeting == null ? null : meetingPhaseAt(meeting, now);
    final editable =
        meeting != null &&
        phase != MeetingPhase.cancelled &&
        phase != MeetingPhase.ended;
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Cuộc họp', 'Meeting')),
        actions: [
          if (editable && meeting.canEdit)
            IconButton(
              key: const Key('meeting_edit'),
              tooltip: tr('Sửa', 'Edit'),
              onPressed: _busy ? null : () => _edit(meeting),
              icon: const Icon(WebTuiIcons.edit),
            ),
          if (editable && meeting.canCancel)
            IconButton(
              key: const Key('meeting_cancel'),
              tooltip: tr('Huỷ họp', 'Cancel meeting'),
              onPressed: _busy ? null : () => _cancel(meeting),
              icon: Icon(WebTuiIcons.block, color: MeetingTones.dangerText),
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: async.when(
          skipLoadingOnReload: true,
          loading: () => const Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              children: [
                WorkSkeleton(height: 120, radius: 18),
                SizedBox(height: 12),
                WorkSkeleton(height: 56, radius: 14),
                SizedBox(height: 12),
                WorkSkeleton(height: 160, radius: 18),
              ],
            ),
          ),
          error: (error, _) => Center(
            child: WorkErrorBox(
              message: meetingErrorText(error),
              onRetry: () => ref.invalidate(meetingDetailProvider(_key)),
            ),
          ),
          data: (meeting) => RefreshIndicator(
            onRefresh: () async {
              bumpMeetingCalendar(ref.read);
              try {
                await ref.read(meetingDetailProvider(_key).future);
              } on Object {
                // Lỗi hiện trong màn kèm nút Thử lại.
              }
            },
            child: _content(meeting, now),
          ),
        ),
      ),
    );
  }

  Widget _content(CalendarMeeting meeting, DateTime now) {
    final phase = meetingPhaseAt(meeting, now);
    final joinable = canJoinMeetingAt(meeting, now);
    final open = phase != MeetingPhase.cancelled && phase != MeetingPhase.ended;
    final recurrence = meeting.recurrence;
    return ListView(
      key: const Key('meeting_detail'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            MeetingStatusBadge(phase: phase),
            if (meeting.isRecurring)
              MeetingPill(
                label: tr('Định kỳ', 'Recurring'),
                background: WebTuiColors.backgroundMuted,
                foreground: WebTuiColors.textSecondary,
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          meeting.title,
          style: WebTuiTypography.titleLarge.copyWith(
            color: WebTuiColors.textPrimary,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        _InfoRow(
          icon: WebTuiIcons.meetings,
          text:
              '${meetingLongDate(meeting.startsAt)} · ${meetingTimeRange(meeting)}',
        ),
        if (recurrence != null)
          _InfoRow(
            icon: WebTuiIcons.refresh,
            text: meetingRecurrenceLabel(recurrence),
          ),
        if (meeting.reminderOffsets.isNotEmpty)
          _InfoRow(
            icon: WebTuiIcons.bell,
            text: tr(
              'Nhắc: ${meeting.reminderOffsets.map(meetingReminderLabel).join(', ')}',
              'Reminders: ${meeting.reminderOffsets.map(meetingReminderLabel).join(', ')}',
            ),
          ),
        if (meeting.channelName.isNotEmpty)
          _InfoRow(icon: WebTuiIcons.group, text: meeting.channelName),
        if (meeting.hasExternalUrl)
          _InfoRow(
            icon: WebTuiIcons.externalLink,
            text: meeting.externalUrl!,
            color: MeetingTones.accentText,
          ),
        const SizedBox(height: 14),
        if (open)
          FilledButton.icon(
            key: const Key('meeting_join'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(meetingMinTapSize),
              backgroundColor: MeetingTones.actionBackground,
              foregroundColor: Colors.white,
              disabledBackgroundColor: WebTuiColors.backgroundMuted,
              disabledForegroundColor: WebTuiColors.textSecondary,
            ),
            onPressed: joinable && !_busy ? () => _join(meeting) : null,
            icon: Icon(
              meeting.hasExternalUrl
                  ? WebTuiIcons.externalLink
                  : WebTuiIcons.video,
            ),
            label: Text(
              joinable
                  ? tr('Vào họp', 'Join meeting')
                  : tr(
                      'Vào họp từ ${meetingClock(meeting.startsAt.subtract(meetingJoinLeadTime))}',
                      'Join from ${meetingClock(meeting.startsAt.subtract(meetingJoinLeadTime))}',
                    ),
            ),
          ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          key: const Key('meeting_message_group'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(meetingMinTapSize),
            foregroundColor: MeetingTones.accentText,
          ),
          onPressed: () => _openGroup(meeting),
          icon: const Icon(WebTuiIcons.messages),
          label: Text(tr('Nhắn vào nhóm', 'Message the group')),
        ),
        if (meeting.canRespond && open) ...[
          MeetingSectionTitle(tr('Bạn sẽ tham dự?', 'Will you attend?')),
          _ResponseButtons(
            current: meeting.myResponse,
            enabled: !_busy,
            onSelected: _respond,
          ),
        ],
        if (meeting.description.trim().isNotEmpty) ...[
          MeetingSectionTitle(tr('Nội dung', 'Description')),
          SelectableText(
            meeting.description,
            style: WebTuiTypography.bodyMedium.copyWith(
              color: WebTuiColors.textPrimary,
            ),
          ),
        ],
        ..._attendeesSection(meeting),
        ..._minutesSection(meeting),
        ..._tasksSection(meeting),
        if (meeting.canEdit && open) ..._guestSection(meeting),
      ],
    );
  }

  List<Widget> _attendeesSection(CalendarMeeting meeting) {
    final summary = meeting.attendeeSummary;
    if (meeting.attendees.isEmpty && summary == null) return const [];
    return [
      MeetingSectionTitle(tr('Người tham dự', 'Attendees')),
      if (summary != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
          child: Text(
            tr(
              '${summary.accepted} tham gia · ${summary.tentative} có thể · '
                  '${summary.declined} từ chối · ${summary.pending} chưa trả lời',
              '${summary.accepted} going · ${summary.tentative} maybe · '
                  '${summary.declined} declined · ${summary.pending} no response',
            ),
            key: const Key('meeting_attendee_summary'),
            style: WebTuiTypography.bodySmall.copyWith(
              color: WebTuiColors.textSecondary,
            ),
          ),
        ),
      for (final attendee in meeting.attendees)
        ListTile(
          key: Key('meeting_attendee_${attendee.userId}'),
          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
          minTileHeight: 52,
          leading: MeetingInitialAvatar(name: attendee.displayName),
          title: Text(
            attendee.displayName,
            style: TextStyle(color: WebTuiColors.textPrimary),
          ),
          subtitle: attendee.isOrganizer
              ? Text(
                  tr('Người tổ chức', 'Organizer'),
                  style: TextStyle(color: WebTuiColors.textSecondary),
                )
              : null,
          trailing: Text(
            attendee.response.label,
            style: WebTuiTypography.bodySmall.copyWith(
              color: MeetingTones.responseText(attendee.response),
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
    ];
  }

  List<Widget> _minutesSection(CalendarMeeting meeting) {
    final minutes = meeting.minutes;
    final content = minutes?.content.trim() ?? '';
    if (content.isEmpty && !meeting.canEditMinutes) return const [];
    final published = minutes?.publishedAt;
    return [
      MeetingSectionTitle(
        tr('Biên bản họp', 'Meeting minutes'),
        trailing: meeting.canEditMinutes
            ? TextButton.icon(
                key: const Key('meeting_minutes_edit'),
                style: TextButton.styleFrom(
                  minimumSize: const Size(meetingMinTapSize, meetingMinTapSize),
                  foregroundColor: MeetingTones.accentText,
                ),
                onPressed: _busy ? null : () => _editMinutes(meeting),
                icon: const Icon(WebTuiIcons.note, size: 18),
                label: Text(
                  content.isEmpty ? tr('Soạn', 'Write') : tr('Sửa', 'Edit'),
                ),
              )
            : null,
      ),
      if (content.isEmpty)
        Text(
          tr('Chưa có biên bản.', 'No minutes yet.'),
          style: WebTuiTypography.bodyMedium.copyWith(
            color: WebTuiColors.textSecondary,
          ),
        )
      else
        WorkCard(
          radius: 14,
          padding: const EdgeInsets.all(12),
          child: SelectableText(
            content,
            key: const Key('meeting_minutes_content'),
            style: WebTuiTypography.bodyMedium.copyWith(
              color: WebTuiColors.textPrimary,
            ),
          ),
        ),
      if (published != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
          child: Text(
            tr(
              'Đã gửi vào nhóm lúc ${meetingClock(published)} ${meetingShortDate(published)}',
              'Sent to the group at ${meetingClock(published)}, ${meetingShortDate(published)}',
            ),
            style: WebTuiTypography.bodySmall.copyWith(
              color: WebTuiColors.textSecondary,
            ),
          ),
        ),
      if (meeting.canEdit && content.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: OutlinedButton.icon(
            key: const Key('meeting_minutes_publish'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(meetingMinTapSize),
              foregroundColor: MeetingTones.accentText,
            ),
            onPressed: _busy ? null : _publishMinutes,
            icon: const Icon(WebTuiIcons.send),
            label: Text(
              published == null
                  ? tr('Gửi biên bản vào nhóm', 'Send minutes to the group')
                  : tr('Gửi lại vào nhóm', 'Send again to the group'),
            ),
          ),
        ),
    ];
  }

  List<Widget> _tasksSection(CalendarMeeting meeting) {
    final async = ref.watch(meetingTasksProvider(_key));
    final canAssign = meeting.canEditMinutes || meeting.canEdit;
    final tasks = async.valueOrNull ?? const <CollaborationTask>[];
    if (!canAssign && tasks.isEmpty) return const [];
    final names = {
      for (final attendee in meeting.attendees)
        attendee.userId: attendee.displayName,
    };
    return [
      MeetingSectionTitle(
        tr('Việc từ cuộc họp', 'Tasks from this meeting'),
        trailing: canAssign
            ? TextButton.icon(
                key: const Key('meeting_task_add'),
                style: TextButton.styleFrom(
                  minimumSize: const Size(meetingMinTapSize, meetingMinTapSize),
                  foregroundColor: MeetingTones.accentText,
                ),
                onPressed: _busy ? null : () => _addTask(meeting),
                icon: const Icon(WebTuiIcons.add, size: 18),
                label: Text(tr('Giao việc', 'Assign task')),
              )
            : null,
      ),
      ...async.when(
        skipLoadingOnReload: true,
        loading: () => const [WorkSkeleton(height: 48, radius: 12)],
        error: (error, _) => [
          WorkErrorBox(
            message: meetingErrorText(error),
            onRetry: () => ref.invalidate(meetingTasksProvider(_key)),
          ),
        ],
        data: (tasks) => tasks.isEmpty
            ? [
                Text(
                  tr('Chưa có việc nào.', 'No tasks yet.'),
                  style: WebTuiTypography.bodyMedium.copyWith(
                    color: WebTuiColors.textSecondary,
                  ),
                ),
              ]
            : [
                for (final task in tasks)
                  ListTile(
                    key: Key('meeting_task_${task.id}'),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                    minTileHeight: 52,
                    leading: Icon(
                      task.taskStatus == CollaborationTaskStatus.done
                          ? WebTuiIcons.selected
                          : WebTuiIcons.unselected,
                      color: WebTuiColors.textSecondary,
                    ),
                    title: Text(
                      task.title,
                      style: TextStyle(color: WebTuiColors.textPrimary),
                    ),
                    subtitle: Text(
                      [
                        task.taskStatus.label,
                        if (task.assigneeUserId != null)
                          names[task.assigneeUserId] ??
                              tr('Đã giao', 'Assigned'),
                      ].join(' · '),
                      style: TextStyle(color: WebTuiColors.textSecondary),
                    ),
                  ),
              ],
      ),
    ];
  }

  List<Widget> _guestSection(CalendarMeeting meeting) {
    final link = meeting.guestLink;
    final enabled = link?.enabled == true;
    final guestUrl = absoluteGuestUrl(
      link?.url ?? '',
      () => ref.read(activeServerUriProvider),
    );
    return [
      MeetingSectionTitle(tr('Link cho khách', 'Guest link')),
      SwitchListTile(
        key: const Key('meeting_guest_switch'),
        contentPadding: const EdgeInsets.symmetric(horizontal: 4),
        value: enabled,
        onChanged: _busy ? null : _setGuestLink,
        title: Text(
          tr('Cho khách ngoài xin vào', 'Let outside guests ask to join'),
          style: TextStyle(color: WebTuiColors.textPrimary),
        ),
        subtitle: Text(
          tr(
            'Khách mở link rồi chờ người tổ chức duyệt.',
            'Guests open the link and wait for the organizer to approve.',
          ),
          style: TextStyle(color: WebTuiColors.textSecondary),
        ),
      ),
      if (enabled && guestUrl.isNotEmpty)
        WorkCard(
          radius: 14,
          padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
          child: Row(
            children: [
              Expanded(
                child: SelectableText(
                  guestUrl,
                  key: const Key('meeting_guest_url'),
                  maxLines: 2,
                  style: WebTuiTypography.bodySmall.copyWith(
                    color: MeetingTones.accentText,
                  ),
                ),
              ),
              IconButton(
                key: const Key('meeting_guest_copy'),
                tooltip: tr('Sao chép link', 'Copy link'),
                onPressed: () => _copy(guestUrl),
                icon: const Icon(WebTuiIcons.copy),
              ),
            ],
          ),
        ),
    ];
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.text, this.color});

  final IconData icon;
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: WebTuiColors.textSecondary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: WebTuiTypography.bodyMedium.copyWith(
                color: color ?? WebTuiColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ResponseButtons extends StatelessWidget {
  const _ResponseButtons({
    required this.current,
    required this.enabled,
    required this.onSelected,
  });

  final MeetingResponse? current;
  final bool enabled;
  final ValueChanged<MeetingResponse> onSelected;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final response in const [
          MeetingResponse.accepted,
          MeetingResponse.tentative,
          MeetingResponse.declined,
        ]) ...[
          Expanded(
            child: _ResponseButton(
              response: response,
              selected: current == response,
              onPressed: enabled ? () => onSelected(response) : null,
            ),
          ),
          if (response != MeetingResponse.declined) const SizedBox(width: 8),
        ],
      ],
    );
  }
}

class _ResponseButton extends StatelessWidget {
  const _ResponseButton({
    required this.response,
    required this.selected,
    required this.onPressed,
  });

  final MeetingResponse response;
  final bool selected;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final color = MeetingTones.responseText(response);
    return Semantics(
      selected: selected,
      child: OutlinedButton(
        key: Key('meeting_response_${response.apiValue}'),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(meetingMinTapSize),
          padding: const EdgeInsets.symmetric(horizontal: 6),
          foregroundColor: selected ? color : WebTuiColors.textPrimary,
          backgroundColor: selected
              ? color.withValues(alpha: 0.12)
              : Colors.transparent,
          side: BorderSide(
            color: selected ? color : WebTuiColors.border,
            width: selected ? 2 : 1,
          ),
        ),
        onPressed: onPressed,
        child: Text(
          response.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

/// Soạn biên bản (toàn màn hình, tối đa 20 000 ký tự). Trả nội dung khi Lưu.
class _MinutesEditorScreen extends StatefulWidget {
  const _MinutesEditorScreen({required this.initial});

  final String initial;

  @override
  State<_MinutesEditorScreen> createState() => _MinutesEditorScreenState();
}

class _MinutesEditorScreenState extends State<_MinutesEditorScreen> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Biên bản họp', 'Meeting minutes')),
        actions: [
          TextButton(
            key: const Key('meeting_minutes_save'),
            style: TextButton.styleFrom(
              minimumSize: const Size(meetingMinTapSize, meetingMinTapSize),
              foregroundColor: MeetingTones.accentText,
            ),
            onPressed: () => Navigator.of(context).pop(_controller.text),
            child: Text(tr('Lưu', 'Save')),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            key: const Key('meeting_minutes_field'),
            controller: _controller,
            autofocus: true,
            expands: true,
            maxLines: null,
            maxLength: 20000,
            textAlignVertical: TextAlignVertical.top,
            decoration: InputDecoration(
              hintText: tr(
                'Nội dung đã bàn, quyết định, việc cần làm…',
                'What was discussed, decisions, next steps…',
              ),
            ),
          ),
        ),
      ),
    );
  }
}

final class _TaskDraft {
  const _TaskDraft({required this.title, this.assigneeUserId});

  final String title;
  final String? assigneeUserId;
}

class _TaskDialog extends StatefulWidget {
  const _TaskDialog({required this.attendees});

  final List<MeetingAttendee> attendees;

  @override
  State<_TaskDialog> createState() => _TaskDialogState();
}

class _TaskDialogState extends State<_TaskDialog> {
  final _title = TextEditingController();
  String? _assignee;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(tr('Giao việc từ cuộc họp', 'Assign a task')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const Key('meeting_task_title'),
            controller: _title,
            autofocus: true,
            decoration: InputDecoration(
              labelText: tr('Tên việc', 'Task'),
              errorText: _error,
            ),
          ),
          if (widget.attendees.isNotEmpty)
            DropdownButtonFormField<String?>(
              key: const Key('meeting_task_assignee'),
              initialValue: _assignee,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: tr('Người làm', 'Assignee'),
              ),
              items: [
                DropdownMenuItem(
                  value: null,
                  child: Text(tr('Chưa giao', 'Unassigned')),
                ),
                for (final attendee in widget.attendees)
                  DropdownMenuItem(
                    value: attendee.userId,
                    child: Text(attendee.displayName),
                  ),
              ],
              onChanged: (value) => setState(() => _assignee = value),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(tr('Thôi', 'Cancel')),
        ),
        TextButton(
          key: const Key('meeting_task_save'),
          onPressed: () {
            final title = _title.text.trim();
            if (title.isEmpty) {
              setState(
                () => _error = tr('Hãy nhập tên việc.', 'Enter a task.'),
              );
              return;
            }
            Navigator.of(
              context,
            ).pop(_TaskDraft(title: title, assigneeUserId: _assignee));
          },
          child: Text(tr('Giao', 'Assign')),
        ),
      ],
    );
  }
}
