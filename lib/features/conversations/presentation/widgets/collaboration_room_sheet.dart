import 'dart:async';
import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers/foundation_providers.dart';
import '../../../../core/error/error_mapper.dart';
import '../../../../design_system/components/webtui_components.dart';
import '../../../../design_system/icons/webtui_icons.dart';
import '../../../../design_system/tokens/webtui_colors.dart';
import '../../../../design_system/tokens/webtui_radii.dart';
import '../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../design_system/tokens/webtui_typography.dart';
import '../../../../l10n/app_strings.dart';
import '../../../meetings/application/meeting_join_flow.dart';
import '../../../meetings/application/meeting_providers.dart';
import '../../../meetings/domain/meeting_models.dart';
import '../../../meetings/presentation/group_call_button.dart';
import '../../../meetings/presentation/meeting_room_screen.dart';
import '../../domain/entities/collaboration_room.dart';
import '../../domain/entities/conversation_summary.dart';
import '../controllers/collaboration_task_controller.dart';
import 'collaboration_tasks_panel.dart';
import 'collaboration_whiteboard.dart';
import 'meeting_scheduler_sheet.dart';

/// Vị trí tab Task trong bảng (Tổng quan, Họp, Đã chia sẻ, Biên bản, Bảng trắng, Task).
const collaborationTasksTabIndex = 5;

Future<void> showCollaborationRoomSheet(
  BuildContext context, {
  required String workspaceId,
  required String channelId,
  required String title,
  required ConversationSummary? conversation,
  int initialTab = 0,
  String? focusTaskId,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: WebTuiColors.surface,
    builder: (_) => CollaborationRoomSheet(
      workspaceId: workspaceId,
      channelId: channelId,
      title: title,
      conversation: conversation,
      initialTab: initialTab,
      focusTaskId: focusTaskId,
    ),
  );
}

class CollaborationRoomSheet extends ConsumerStatefulWidget {
  const CollaborationRoomSheet({
    required this.workspaceId,
    required this.channelId,
    required this.title,
    required this.conversation,
    this.initialTab = 0,
    this.focusTaskId,
    super.key,
  });

  final String workspaceId;
  final String channelId;
  final String title;
  final ConversationSummary? conversation;
  final int initialTab;

  /// Mở sẵn việc này ở tab Task (bấm từ thông báo / "Việc của tôi").
  final String? focusTaskId;

  @override
  ConsumerState<CollaborationRoomSheet> createState() =>
      _CollaborationRoomSheetState();
}

class _CollaborationRoomSheetState
    extends ConsumerState<CollaborationRoomSheet> {
  final _notesController = TextEditingController();
  final _promoteController = TextEditingController();
  final _breakoutBroadcastController = TextEditingController();
  CollaborationSettings? _settings;
  CollaborationDocument? _notes;
  List<CollaborationGuest> _guests = const [];
  List<CollaborationRole> _roles = const [];
  List<BreakoutRoom> _breakouts = const [];
  List<CollaborationUserGroup> _userGroups = const [];
  TalkHome? _talkHome;
  List<ChannelMeeting> _meetings = const [];
  VoiceRoom? _voiceRoom;
  List<SharedConversationItem> _sharedItems = const [];
  RecordingPolicy? _recordingPolicy;
  List<ChannelRecording> _recordings = const [];
  TalkIntegration? _talkIntegration;
  String? _selectedUserGroupId;
  int _tab = 0;
  bool _loading = true;
  bool _saving = false;
  String? _error;
  String? _currentUserId;

  bool get _canManage =>
      widget.conversation?.canManage == true || _settings?.isDirect == true;

  @override
  void initState() {
    super.initState();
    _tab = widget.initialTab.clamp(0, 5).toInt();
    _promoteController.text = widget.title;
    unawaited(_load());
  }

  @override
  void dispose() {
    _notesController.dispose();
    _promoteController.dispose();
    _breakoutBroadcastController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final remote = ref.read(conversationRemoteDataSourceProvider);
    try {
      final profileFuture = ref.read(loadProfileUseCaseProvider).execute();
      final settingsFuture = remote.getCollaborationSettings(
        workspaceId: widget.workspaceId,
        channelId: widget.channelId,
      );
      final profile = await profileFuture;
      final settings = await settingsFuture;
      // Meeting/shared-content APIs do not depend on the notes and task APIs.
      // Warm them in the same round trip so a direct tool shortcut opens fast.
      unawaited(_loadAdvanced());
      final results = await Future.wait<Object>([
        remote.getCollaborationDocument(
          workspaceId: widget.workspaceId,
          channelId: widget.channelId,
          kind: 'notes',
        ),
        if (!settings.isDirect)
          remote.listCollaborationRoles(
            workspaceId: widget.workspaceId,
            channelId: widget.channelId,
          )
        else
          Future<List<CollaborationRole>>.value(const []),
        if (!settings.isDirect)
          remote.listBreakoutRooms(
            workspaceId: widget.workspaceId,
            channelId: widget.channelId,
          )
        else
          Future<List<BreakoutRoom>>.value(const []),
        if (settings.publicAccessEnabled &&
            (widget.conversation?.canManage == true || settings.isDirect))
          remote.listCollaborationGuests(
            workspaceId: widget.workspaceId,
            channelId: widget.channelId,
          )
        else
          Future<List<CollaborationGuest>>.value(const []),
        if (!settings.isDirect && widget.conversation?.canManage == true)
          remote.listCollaborationUserGroups(workspaceId: widget.workspaceId)
        else
          Future<List<CollaborationUserGroup>>.value(const []),
      ]);
      if (!mounted) return;
      final notes = results[0] as CollaborationDocument;
      setState(() {
        _settings = settings;
        _notes = notes;
        _notesController.text = notes.content['text']?.toString() ?? '';
        _roles = results[1] as List<CollaborationRole>;
        _breakouts = results[2] as List<BreakoutRoom>;
        _guests = results[3] as List<CollaborationGuest>;
        _userGroups = results[4] as List<CollaborationUserGroup>;
        _currentUserId = profile.valueOrNull?.id;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = userFacingErrorMessage(error);
        _loading = false;
      });
    }
  }

  Future<void> _loadAdvanced() async {
    final remote = ref.read(conversationRemoteDataSourceProvider);
    try {
      final results = await Future.wait<Object>([
        remote.getTalkHome(workspaceId: widget.workspaceId),
        remote.listMeetings(
          workspaceId: widget.workspaceId,
          channelId: widget.channelId,
        ),
        remote.getVoiceRoom(
          workspaceId: widget.workspaceId,
          channelId: widget.channelId,
        ),
        remote.listSharedItems(
          workspaceId: widget.workspaceId,
          channelId: widget.channelId,
        ),
        remote.getRecordingPolicy(
          workspaceId: widget.workspaceId,
          channelId: widget.channelId,
        ),
        remote.listRecordings(
          workspaceId: widget.workspaceId,
          channelId: widget.channelId,
        ),
        remote.getTalkIntegration(workspaceId: widget.workspaceId),
      ]);
      if (!mounted) return;
      setState(() {
        _talkHome = results[0] as TalkHome;
        _meetings = results[1] as List<ChannelMeeting>;
        _voiceRoom = results[2] as VoiceRoom;
        _sharedItems = results[3] as List<SharedConversationItem>;
        _recordingPolicy = results[4] as RecordingPolicy;
        _recordings = results[5] as List<ChannelRecording>;
        _talkIntegration = results[6] as TalkIntegration;
      });
    } catch (_) {
      // Advanced modules are feature-gated. The core collaboration room remains
      // usable while an older self-hosted server is being upgraded.
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final safeHeight = media.size.height - media.padding.top;
    final sheetHeight = (safeHeight - WebTuiSpacing.sm).clamp(
      media.size.height * 0.78,
      media.size.height * 0.9,
    );
    return SafeArea(
      top: false,
      child: SizedBox(
        height: sheetHeight,
        child: Column(
          children: [
            _buildHeader(),
            if (_loading)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else if (_error != null)
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(WebTuiSpacing.xl),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.cloud_off_rounded,
                          color: WebTuiColors.textMuted,
                          size: 38,
                        ),
                        const SizedBox(height: WebTuiSpacing.md),
                        Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: WebTuiTypography.bodySmall,
                        ),
                        const SizedBox(height: WebTuiSpacing.md),
                        FilledButton(
                          onPressed: _load,
                          child: Text(tr('Thử lại', 'Try again')),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else ...[
              _buildTabs(),
              Expanded(
                child: IndexedStack(
                  index: _tab,
                  children: [
                    _buildTalkHomeTab(),
                    _buildMeetingTab(),
                    _buildSharedItemsTab(),
                    _buildNotesTab(),
                    _buildWhiteboardTab(),
                    _buildTasksTab(),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final mode = _settings?.roomMode;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        WebTuiSpacing.lg,
        WebTuiSpacing.xs,
        WebTuiSpacing.sm,
        WebTuiSpacing.md,
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: WebTuiColors.primarySoft,
              borderRadius: BorderRadius.circular(WebTuiRadii.lg),
            ),
            child: Icon(
              CupertinoIcons.video_camera_solid,
              color: WebTuiColors.primary,
            ),
          ),
          const SizedBox(width: WebTuiSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: WebTuiTypography.titleMedium.copyWith(
                    color: WebTuiColors.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  mode == CollaborationRoomMode.webinar
                      ? tr('Hội thảo', 'Webinar')
                      : mode == CollaborationRoomMode.public
                      ? tr('Phòng có khách ngoài', 'Room with external guests')
                      : _settings?.isDirect == true
                      ? tr('Hội thoại 1-1 riêng tư', 'Private 1-1 conversation')
                      : tr('Phòng nhóm nội bộ', 'Internal group room'),
                  style: WebTuiTypography.bodySmall.copyWith(
                    color: WebTuiColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: tr('Đóng', 'Close'),
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }

  Widget _buildTabs() {
    final tabs = [
      (Icons.home_outlined, tr('Tổng quan', 'Overview')),
      (Icons.video_call_outlined, tr('Họp', 'Meeting')),
      (Icons.folder_copy_outlined, tr('Đã chia sẻ', 'Shared')),
      (Icons.description_outlined, tr('Biên bản', 'Minutes')),
      (Icons.draw_outlined, tr('Bảng trắng', 'Whiteboard')),
      (Icons.task_alt_outlined, 'Task'),
    ];
    return DecoratedBox(
      decoration: BoxDecoration(
        color: WebTuiColors.surface,
        border: Border(bottom: BorderSide(color: WebTuiColors.border)),
      ),
      child: SizedBox(
        height: 60,
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(
            WebTuiSpacing.lg,
            WebTuiSpacing.sm,
            WebTuiSpacing.lg,
            WebTuiSpacing.sm,
          ),
          scrollDirection: Axis.horizontal,
          itemCount: tabs.length,
          separatorBuilder: (_, _) => const SizedBox(width: WebTuiSpacing.xs),
          itemBuilder: (context, index) => ChoiceChip(
            selected: _tab == index,
            avatar: Icon(tabs[index].$1, size: 17),
            // Có biểu tượng mà để dấu tích thì lúc chọn Flutter phủ vòng tối
            // lên biểu tượng (trông như lỗi hover). Màu nền đã đủ báo đang chọn.
            showCheckmark: false,
            label: Text(tabs[index].$2),
            onSelected: (_) => setState(() => _tab = index),
          ),
        ),
      ),
    );
  }

  Widget _buildTalkHomeTab() {
    final home = _talkHome;
    final integration = _talkIntegration;
    return RefreshIndicator(
      onRefresh: _loadAdvanced,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          WebTuiSpacing.lg,
          WebTuiSpacing.md,
          WebTuiSpacing.lg,
          WebTuiSpacing.lg,
        ),
        children: [
          _sectionCard(
            icon: Icons.event_available_outlined,
            title: tr('Sắp diễn ra', 'Upcoming'),
            child: home == null
                ? const Center(child: CircularProgressIndicator())
                : home.upcomingMeetings.isEmpty
                ? Text(
                    tr(
                      'Chưa có cuộc họp nào được lên lịch.',
                      'No meetings scheduled.',
                    ),
                  )
                : Column(
                    children: [
                      for (final meeting in home.upcomingMeetings.take(4))
                        _meetingTile(meeting),
                    ],
                  ),
          ),
          if (integration != null) ...[
            const SizedBox(height: WebTuiSpacing.md),
            _sectionCard(
              icon: Icons.hub_outlined,
              title: tr('Năng lực máy chủ', 'Server capabilities'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 7,
                    runSpacing: 7,
                    children: [
                      _CapabilityChip(
                        icon: Icons.auto_awesome_outlined,
                        label: integration.aiEnabled
                            ? 'AI ${integration.aiProvider}'
                            : tr('AI chưa bật', 'AI is off'),
                      ),
                      _CapabilityChip(
                        icon: Icons.lock_outline_rounded,
                        label: integration.e2eeCallsEnabled
                            ? 'E2EE call'
                            : tr('WebRTC bảo mật', 'Secure WebRTC'),
                      ),
                      if (integration.federationEnabled)
                        const _CapabilityChip(
                          icon: Icons.language_rounded,
                          label: 'Federation',
                        ),
                      if (integration.sipEnabled)
                        const _CapabilityChip(
                          icon: Icons.dialpad_rounded,
                          label: 'SIP',
                        ),
                    ],
                  ),
                  if (integration.aiEnabled) ...[
                    const SizedBox(height: WebTuiSpacing.md),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.tonalIcon(
                        onPressed: _saving ? null : _summarizeChannel,
                        icon: const Icon(Icons.auto_awesome_rounded),
                        label: Text(
                          tr(
                            'Tóm tắt tin nhắn bằng AI nội bộ',
                            'Summarize messages with internal AI',
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSharedItemsTab() {
    return RefreshIndicator(
      onRefresh: _loadAdvanced,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(WebTuiSpacing.lg),
        children: [
          _sectionCard(
            icon: Icons.folder_copy_outlined,
            title: tr('Nội dung được chia sẻ', 'Shared content'),
            child: _sharedItems.isEmpty
                ? Padding(
                    padding: EdgeInsets.symmetric(vertical: WebTuiSpacing.lg),
                    child: Center(
                      child: Text(
                        tr(
                          'Chưa có file, poll, task hoặc bản ghi.',
                          'No files, polls, tasks or recordings yet.',
                        ),
                      ),
                    ),
                  )
                : Column(
                    children: [
                      for (final item in _sharedItems)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: CircleAvatar(
                            backgroundColor: WebTuiColors.primary.withValues(
                              alpha: 0.10,
                            ),
                            child: Icon(
                              _sharedItemIcon(item.kind),
                              color: WebTuiColors.primary,
                            ),
                          ),
                          title: Text(
                            item.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: item.subtitle.isEmpty
                              ? Text(_sharedItemLabel(item.kind))
                              : Text(
                                  item.subtitle,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                          onTap: item.url.isEmpty
                              ? null
                              : () => ref
                                    .read(externalUrlLauncherProvider)
                                    .open(item.url),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildMeetingTab() {
    final settings = _settings!;
    return ListView(
      padding: const EdgeInsets.all(WebTuiSpacing.lg),
      children: [
        _voiceRoomCard(),
        const SizedBox(height: WebTuiSpacing.md),
        _meetingLifecycleCard(),
        if (_recordingPolicy != null) ...[
          const SizedBox(height: WebTuiSpacing.md),
          _recordingCard(),
        ],
        const SizedBox(height: WebTuiSpacing.md),
        if (settings.isDirect)
          _sectionCard(
            icon: Icons.lock_person_outlined,
            title: tr('Hội thoại 1-1 riêng tư', 'Private 1-1 conversation'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr(
                    'Chat chữ, voice, file và gọi thoại/video được giữ riêng tư. Muốn có link khách, hãy Promote thành phòng nhóm.',
                    'Text chat, voice, files and voice/video calls stay private. To get a guest link, promote this to a group room.',
                  ),
                ),
                const SizedBox(height: WebTuiSpacing.md),
                TextField(
                  controller: _promoteController,
                  decoration: InputDecoration(
                    labelText: tr('Tên phòng nhóm', 'Group room name'),
                  ),
                ),
                const SizedBox(height: WebTuiSpacing.sm),
                FilledButton.icon(
                  onPressed: _saving ? null : _promote,
                  icon: const Icon(Icons.group_add_rounded),
                  label: Text(
                    tr('Promote thành phòng nhóm', 'Promote to group room'),
                  ),
                ),
              ],
            ),
          )
        else ...[
          _sectionCard(
            icon: CupertinoIcons.video_camera_solid,
            title: tr('Họp video nhóm', 'Group video meeting'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: [
                    _CapabilityChip(
                      icon: Icons.grid_view_rounded,
                      label: 'Grid',
                    ),
                    _CapabilityChip(
                      icon: Icons.back_hand_outlined,
                      label: tr('Giơ tay', 'Raise hand'),
                    ),
                    _CapabilityChip(
                      icon: Icons.blur_on_rounded,
                      label: tr('Blur nền', 'Blur background'),
                    ),
                    _CapabilityChip(
                      icon: Icons.privacy_tip_outlined,
                      label: tr(
                        'Quyền media theo ngữ cảnh',
                        'Context-aware media permissions',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: WebTuiSpacing.md),
                FilledButton.icon(
                  onPressed: settings.canOpenMeeting
                      ? () => _openMeeting(settings.meetingRoomKey!)
                      : null,
                  icon: const Icon(CupertinoIcons.video_camera_solid),
                  label: Text(
                    settings.canOpenMeeting
                        ? tr('Vào phòng họp', 'Join meeting room')
                        : tr(
                            'Media server chưa cấu hình',
                            'Media server not configured',
                          ),
                  ),
                ),
                if (settings.canOpenMeeting && !settings.isDirect && _canManage)
                  Padding(
                    padding: const EdgeInsets.only(top: WebTuiSpacing.sm),
                    child: GroupCallButton(
                      busy: _saving,
                      onStart: (kind) => unawaited(_startGroupCall(kind)),
                    ),
                  ),
              ],
            ),
          ),
          if (_canManage) ...[
            const SizedBox(height: WebTuiSpacing.md),
            _meetingPolicies(settings),
            const SizedBox(height: WebTuiSpacing.md),
            if (_userGroups.isNotEmpty) ...[
              _userGroupCard(),
              const SizedBox(height: WebTuiSpacing.md),
            ],
            _publicLinkCard(settings),
          ],
          if (_guests.any((guest) => guest.status == 'waiting')) ...[
            const SizedBox(height: WebTuiSpacing.md),
            _lobbyCard(),
          ],
          if (settings.roomMode == CollaborationRoomMode.webinar) ...[
            const SizedBox(height: WebTuiSpacing.md),
            _rolesCard(),
          ],
          const SizedBox(height: WebTuiSpacing.md),
          _breakoutCard(),
        ],
      ],
    );
  }

  Widget _voiceRoomCard() {
    final active = _voiceRoom?.isActive == true;
    return _sectionCard(
      icon: active ? Icons.graphic_eq_rounded : Icons.headset_mic_outlined,
      title: 'Voice room',
      child: Row(
        children: [
          Expanded(
            child: Text(
              active
                  ? tr(
                      'Đang mở · thành viên có thể tham gia ngay.',
                      'Open · members can join right away.',
                    )
                  : tr(
                      'Mở một không gian nói chuyện nhanh, không cần lên lịch.',
                      'Open a quick space to talk, no scheduling needed.',
                    ),
              style: WebTuiTypography.bodySmall.copyWith(
                color: active
                    ? WebTuiColors.accentGreen
                    : WebTuiColors.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: WebTuiSpacing.sm),
          FilledButton.icon(
            onPressed: _saving ? null : () => _setVoiceRoom(!active),
            icon: Icon(active ? Icons.stop_circle_outlined : Icons.mic_rounded),
            label: Text(
              active ? tr('Kết thúc', 'End') : tr('Bắt đầu', 'Start'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _meetingLifecycleCard() {
    final upcoming =
        _meetings
            .where((meeting) => meeting.canStart || meeting.isLive)
            .toList(growable: false)
          ..sort((left, right) {
            if (left.isLive && !right.isLive) return -1;
            if (right.isLive && !left.isLive) return 1;
            return left.startsAt.compareTo(right.startsAt);
          });
    final history = _meetings
        .where((meeting) => !meeting.canStart && !meeting.isLive)
        .take(5)
        .toList(growable: false);
    return _sectionCard(
      icon: Icons.calendar_month_outlined,
      title: tr('Lịch họp', 'Meeting schedule'),
      child: Column(
        children: [
          if (_canManage) ...[
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _saving ? null : _createMeeting,
                icon: const Icon(Icons.event_available_rounded),
                label: Text(tr('Tạo lịch họp', 'Schedule a meeting')),
              ),
            ),
            const Divider(height: WebTuiSpacing.xl),
          ],
          if (upcoming.isEmpty)
            Padding(
              padding: EdgeInsets.symmetric(vertical: WebTuiSpacing.sm),
              child: Text(
                tr('Chưa có cuộc họp sắp diễn ra.', 'No upcoming meetings.'),
              ),
            )
          else
            for (final meeting in upcoming.take(10))
              _meetingTile(meeting, controls: true),
          if (history.isNotEmpty)
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: EdgeInsets.zero,
              title: Text(
                tr(
                  'Lịch sử gần đây (${history.length})',
                  'Recent history (${history.length})',
                ),
                style: WebTuiTypography.bodySmall.copyWith(
                  color: WebTuiColors.textSecondary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              children: [for (final meeting in history) _meetingTile(meeting)],
            ),
        ],
      ),
    );
  }

  Widget _meetingTile(ChannelMeeting meeting, {bool controls = false}) {
    final local = meeting.startsAt.toLocal();
    final time =
        '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')} '
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: meeting.isLive
            ? WebTuiColors.danger.withValues(alpha: 0.12)
            : WebTuiColors.primary.withValues(alpha: 0.10),
        child: Icon(
          meeting.isLive ? Icons.podcasts_rounded : Icons.event_outlined,
          color: meeting.isLive ? WebTuiColors.danger : WebTuiColors.primary,
        ),
      ),
      title: Text(meeting.title),
      subtitle: Text(
        meeting.isLive
            ? tr('Đang diễn ra · Chạm để vào họp', 'In progress · Tap to join')
            : meeting.status == 'cancelled'
            ? tr('Đã hủy · $time', 'Cancelled · $time')
            : meeting.status == 'ended'
            ? tr('Đã kết thúc · $time', 'Ended · $time')
            : meeting.description.isEmpty
            ? time
            : '$time · ${meeting.description}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      onTap:
          meeting.isLive &&
              _settings?.canOpenMeeting == true &&
              _settings?.meetingRoomKey != null
          ? () => _openMeeting(_settings!.meetingRoomKey!)
          : null,
      trailing: controls && _canManage
          ? PopupMenuButton<String>(
              onSelected: (action) => _transitionMeeting(meeting, action),
              itemBuilder: (context) => [
                if (meeting.canStart)
                  PopupMenuItem(
                    value: 'start',
                    child: Text(tr('Bắt đầu', 'Start')),
                  ),
                if (meeting.isLive)
                  PopupMenuItem(
                    value: 'end',
                    child: Text(tr('Kết thúc', 'End')),
                  ),
                if (meeting.canStart)
                  PopupMenuItem(
                    value: 'cancel',
                    child: Text(tr('Hủy lịch', 'Cancel meeting')),
                  ),
              ],
            )
          : null,
    );
  }

  Widget _recordingCard() {
    final policy = _recordingPolicy!;
    final active = _recordings.where((item) => item.isActive).firstOrNull;
    return _sectionCard(
      icon: Icons.fiber_manual_record_rounded,
      title: tr('Ghi hình & AI meeting notes', 'Recording & AI meeting notes'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_canManage)
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: Text(
                tr('Cho phép ghi cuộc họp', 'Allow meeting recording'),
              ),
              subtitle: Text(
                policy.consentRequired
                    ? tr(
                        'Yêu cầu mọi người đồng ý · lưu ${policy.retentionDays} ngày',
                        'Everyone must consent · kept for ${policy.retentionDays} days',
                      )
                    : tr(
                        'Lưu ${policy.retentionDays} ngày',
                        'Kept for ${policy.retentionDays} days',
                      ),
              ),
              value: policy.enabled,
              onChanged: _saving ? null : _toggleRecordingPolicy,
            ),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              if (policy.transcriptionEnabled)
                const _CapabilityChip(
                  icon: Icons.subtitles_outlined,
                  label: 'Transcript',
                ),
              if (policy.summaryEnabled)
                const _CapabilityChip(
                  icon: Icons.auto_awesome_outlined,
                  label: 'AI summary',
                ),
              _CapabilityChip(
                icon: Icons.storage_outlined,
                label: tr(
                  '${policy.retentionDays} ngày',
                  '${policy.retentionDays} days',
                ),
              ),
            ],
          ),
          const SizedBox(height: WebTuiSpacing.md),
          if (active == null && policy.enabled && _canManage)
            FilledButton.icon(
              onPressed: _saving ? null : _startRecording,
              icon: const Icon(Icons.fiber_manual_record_rounded),
              label: Text(tr('Yêu cầu ghi hình', 'Request recording')),
            )
          else if (active != null) ...[
            Text(
              active.status == 'pending'
                  ? tr(
                      'Đang chờ đồng ý: ${active.consentCount}/${active.participantCount}',
                      'Waiting for consent: ${active.consentCount}/${active.participantCount}',
                    )
                  : tr(
                      'Bản ghi đang ở trạng thái ${active.status}.',
                      'Recording status: ${active.status}.',
                    ),
            ),
            const SizedBox(height: WebTuiSpacing.sm),
            Wrap(
              spacing: WebTuiSpacing.sm,
              children: [
                if (active.status == 'pending')
                  OutlinedButton.icon(
                    onPressed: _saving
                        ? null
                        : () => _setRecordingConsent(active, true),
                    icon: const Icon(Icons.check_circle_outline_rounded),
                    label: Text(tr('Tôi đồng ý', 'I agree')),
                  ),
                if (_canManage)
                  OutlinedButton.icon(
                    onPressed: _saving ? null : () => _stopRecording(active),
                    icon: const Icon(Icons.stop_circle_outlined),
                    label: Text(tr('Dừng', 'Stop')),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _meetingPolicies(CollaborationSettings settings) {
    return _sectionCard(
      icon: Icons.admin_panel_settings_outlined,
      title: tr('Quyền và chế độ phòng', 'Room permissions and mode'),
      child: Column(
        children: [
          DropdownButtonFormField<CollaborationRoomMode>(
            initialValue: settings.roomMode,
            decoration: InputDecoration(
              labelText: tr('Loại phòng', 'Room type'),
            ),
            items: [
              DropdownMenuItem(
                value: CollaborationRoomMode.internal,
                child: Text(tr('Nhóm nội bộ', 'Internal group')),
              ),
              DropdownMenuItem(
                value: CollaborationRoomMode.public,
                child: Text(tr('Khách ngoài', 'External guests')),
              ),
              DropdownMenuItem(
                value: CollaborationRoomMode.webinar,
                child: Text('Webinar'),
              ),
            ],
            onChanged: (value) {
              if (value != null) unawaited(_updateSettings(roomMode: value));
            },
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: Text(tr('Phòng chờ', 'Waiting room')),
            subtitle: Text(
              tr(
                'Host duyệt khách trước khi vào',
                'Host approves guests before they join',
              ),
            ),
            value: settings.lobbyEnabled,
            onChanged: (value) => _updateSettings(lobbyEnabled: value),
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: Text(tr('Khóa chat khách', 'Lock guest chat')),
            value: settings.chatLocked,
            onChanged: (value) => _updateSettings(chatLocked: value),
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: Text(
              tr('Mic khách mặc định bật', 'Guest mic on by default'),
            ),
            value: settings.guestMicrophoneEnabled,
            onChanged: (value) =>
                _updateSettings(guestMicrophoneEnabled: value),
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: Text(
              tr('Camera khách mặc định bật', 'Guest camera on by default'),
            ),
            value: settings.guestCameraEnabled,
            onChanged: (value) => _updateSettings(guestCameraEnabled: value),
          ),
        ],
      ),
    );
  }

  Widget _publicLinkCard(CollaborationSettings settings) {
    return _sectionCard(
      icon: Icons.public_rounded,
      title: tr('Link khách ngoài', 'External guest link'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (settings.publicAccessEnabled)
            Text(
              tr(
                'Link đang hoạt động · ${settings.publicTokenPrefix ?? ''}…',
                'Link active · ${settings.publicTokenPrefix ?? ''}…',
              ),
              style: WebTuiTypography.bodySmall.copyWith(
                color: WebTuiColors.accentGreen,
              ),
            ),
          const SizedBox(height: WebTuiSpacing.sm),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _saving ? null : _createPublicLink,
                  icon: const Icon(Icons.link_rounded),
                  label: Text(
                    settings.publicAccessEnabled
                        ? tr('Tạo link mới', 'Create new link')
                        : tr('Tạo link', 'Create link'),
                  ),
                ),
              ),
              if (settings.publicAccessEnabled) ...[
                const SizedBox(width: WebTuiSpacing.sm),
                IconButton.outlined(
                  tooltip: tr('Thu hồi link', 'Revoke link'),
                  onPressed: _saving ? null : _disablePublicLink,
                  icon: const Icon(Icons.link_off_rounded),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _userGroupCard() {
    return _sectionCard(
      icon: Icons.groups_2_outlined,
      title: tr('Thêm theo nhóm người dùng', 'Add by user group'),
      child: Column(
        children: [
          DropdownButtonFormField<String>(
            initialValue: _selectedUserGroupId,
            decoration: InputDecoration(
              labelText: tr('Phòng ban nội bộ', 'Internal department'),
            ),
            items: [
              for (final group in _userGroups)
                DropdownMenuItem(
                  value: group.id,
                  child: Text('${group.name} (${group.memberCount})'),
                ),
            ],
            onChanged: (value) => setState(() => _selectedUserGroupId = value),
          ),
          const SizedBox(height: WebTuiSpacing.sm),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _saving || (_selectedUserGroupId?.isEmpty ?? true)
                  ? null
                  : _importUserGroup,
              icon: const Icon(Icons.group_add_outlined),
              label: Text(tr('Thêm toàn bộ thành viên', 'Add all members')),
            ),
          ),
        ],
      ),
    );
  }

  Widget _lobbyCard() {
    final waiting = _guests
        .where((guest) => guest.status == 'waiting')
        .toList(growable: false);
    return _sectionCard(
      icon: Icons.meeting_room_outlined,
      title: tr(
        'Phòng chờ (${waiting.length})',
        'Waiting room (${waiting.length})',
      ),
      child: Column(
        children: [
          for (final guest in waiting)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(child: Text(_initials(guest.displayName))),
              title: Text(guest.displayName),
              trailing: Wrap(
                children: [
                  IconButton(
                    tooltip: tr('Duyệt', 'Approve'),
                    onPressed: () => _moderateGuest(guest.id, true),
                    icon: Icon(
                      Icons.check_circle_rounded,
                      color: WebTuiColors.accentGreen,
                    ),
                  ),
                  IconButton(
                    tooltip: tr('Từ chối', 'Decline'),
                    onPressed: () => _moderateGuest(guest.id, false),
                    icon: Icon(
                      Icons.cancel_outlined,
                      color: WebTuiColors.danger,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _rolesCard() {
    return _sectionCard(
      icon: Icons.campaign_outlined,
      title: tr('Diễn giả và khán giả', 'Speakers and audience'),
      child: Column(
        children: [
          for (final role in _roles)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(child: Text(_initials(role.displayName))),
              title: Text(role.displayName),
              subtitle: Text('@${role.username}'),
              trailing: DropdownButton<CollaborationParticipantRole>(
                value: role.role,
                items: [
                  DropdownMenuItem(
                    value: CollaborationParticipantRole.moderator,
                    child: Text(tr('Chủ trì', 'Host')),
                  ),
                  DropdownMenuItem(
                    value: CollaborationParticipantRole.presenter,
                    child: Text(tr('Diễn giả', 'Speaker')),
                  ),
                  DropdownMenuItem(
                    value: CollaborationParticipantRole.member,
                    child: Text(tr('Thành viên', 'Member')),
                  ),
                  DropdownMenuItem(
                    value: CollaborationParticipantRole.listener,
                    child: Text(tr('Khán giả', 'Audience')),
                  ),
                ],
                onChanged: _canManage
                    ? (value) {
                        if (value != null) {
                          unawaited(_updateRole(role.userId, value));
                        }
                      }
                    : null,
              ),
            ),
        ],
      ),
    );
  }

  Widget _breakoutCard() {
    final openRooms = _breakouts
        .where((room) => room.isActive)
        .toList(growable: false);
    final preparedRooms = _breakouts
        .where((room) => room.status == 'prepared')
        .toList(growable: false);
    return _sectionCard(
      icon: Icons.account_tree_outlined,
      title: 'Breakout rooms',
      child: Column(
        children: [
          for (final room in [...preparedRooms, ...openRooms])
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.groups_2_outlined),
              title: Text(room.name),
              subtitle: Text(
                tr(
                  '${room.assignedUserIds.length} thành viên · '
                      '${room.status == 'prepared' ? 'đã chuẩn bị' : 'đang mở'}',
                  '${room.assignedUserIds.length} members · '
                      '${room.status == 'prepared' ? 'prepared' : 'open'}',
                ),
              ),
              trailing: room.isActive
                  ? TextButton(
                      onPressed: room.canSelfJoin
                          ? () => _joinBreakout(room)
                          : () => _openMeeting(room.roomKey),
                      child: const Text('Tham gia'),
                    )
                  : null,
            ),
          if (_canManage) ...[
            Wrap(
              spacing: WebTuiSpacing.sm,
              runSpacing: WebTuiSpacing.sm,
              children: [
                OutlinedButton.icon(
                  onPressed: _saving
                      ? null
                      : () => _setupBreakouts('automatic'),
                  icon: const Icon(Icons.shuffle_rounded),
                  label: Text(tr('Chia tự động', 'Auto-assign')),
                ),
                OutlinedButton.icon(
                  onPressed: _saving
                      ? null
                      : () => _setupBreakouts('self_select'),
                  icon: const Icon(Icons.how_to_reg_outlined),
                  label: Text(tr('Tự chọn phòng', 'Choose own room')),
                ),
                OutlinedButton.icon(
                  onPressed: _saving ? null : _createBreakout,
                  icon: const Icon(Icons.add_rounded),
                  label: Text(tr('Tạo thủ công', 'Create manually')),
                ),
              ],
            ),
            if (preparedRooms.isNotEmpty) ...[
              const SizedBox(height: WebTuiSpacing.sm),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _saving ? null : _startBreakouts,
                  icon: const Icon(Icons.play_circle_outline_rounded),
                  label: Text(
                    tr('Mở tất cả phòng nhỏ', 'Open all breakout rooms'),
                  ),
                ),
              ),
            ],
            if (openRooms.isNotEmpty) ...[
              const Divider(height: WebTuiSpacing.xl),
              TextField(
                controller: _breakoutBroadcastController,
                decoration: InputDecoration(
                  labelText: tr(
                    'Thông báo đến mọi phòng',
                    'Announcement to all rooms',
                  ),
                  hintText: tr(
                    'Còn 5 phút thảo luận…',
                    '5 minutes left to discuss…',
                  ),
                ),
                onSubmitted: (_) => _broadcastBreakouts(),
              ),
              const SizedBox(height: WebTuiSpacing.sm),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _saving ? null : _broadcastBreakouts,
                      icon: const Icon(Icons.campaign_outlined),
                      label: Text(
                        tr('Phát thông báo', 'Broadcast announcement'),
                      ),
                    ),
                  ),
                  const SizedBox(width: WebTuiSpacing.sm),
                  OutlinedButton(
                    onPressed: _saving ? null : _returnBreakouts,
                    child: Text(tr('Gọi tất cả về', 'Call everyone back')),
                  ),
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildNotesTab() {
    return ListView(
      padding: const EdgeInsets.all(WebTuiSpacing.lg),
      children: [
        _sectionCard(
          icon: Icons.description_outlined,
          title: 'Collaborative Notes · v${_notes?.version ?? 1}',
          child: Column(
            children: [
              TextField(
                controller: _notesController,
                minLines: 12,
                maxLines: 24,
                decoration: InputDecoration(
                  hintText: tr(
                    '# Nội dung cuộc họp\n\n- Quyết định\n- Việc cần làm\n- Người phụ trách',
                    '# Meeting content\n\n- Decisions\n- Tasks\n- Owner',
                  ),
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: WebTuiSpacing.md),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _saving ? null : _saveNotes,
                  icon: const Icon(Icons.cloud_upload_outlined),
                  label: Text(tr('Lưu biên bản', 'Save minutes')),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildWhiteboardTab() {
    return Padding(
      padding: const EdgeInsets.all(WebTuiSpacing.lg),
      child: CollaborationWhiteboard(
        workspaceId: widget.workspaceId,
        channelId: widget.channelId,
        active: _tab == 4,
      ),
    );
  }

  Widget _buildTasksTab() {
    return CollaborationTasksPanel(
      scope: CollaborationTaskScope(
        workspaceId: widget.workspaceId,
        channelId: widget.channelId,
        canManageRoom:
            widget.conversation?.canManage == true ||
            ref.watch(canManageWorkspaceChannelsProvider),
      ),
      focusTaskId: widget.focusTaskId,
    );
  }

  Widget _sectionCard({
    required IconData icon,
    required String title,
    required Widget child,
    bool fillHeight = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(WebTuiSpacing.lg),
      decoration: BoxDecoration(
        color: WebTuiColors.surface,
        border: Border.all(color: WebTuiColors.border),
        borderRadius: BorderRadius.circular(WebTuiRadii.lg),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: WebTuiColors.primary, size: 20),
              const SizedBox(width: WebTuiSpacing.sm),
              Expanded(
                child: Text(
                  title,
                  style: WebTuiTypography.titleMedium.copyWith(
                    color: WebTuiColors.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: WebTuiSpacing.md),
          if (fillHeight) Expanded(child: child) else child,
        ],
      ),
    );
  }

  Future<void> _promote() async {
    final name = _promoteController.text.trim();
    if (name.length < 2) return;
    await _guard(() async {
      await ref
          .read(conversationRemoteDataSourceProvider)
          .promoteConversation(
            workspaceId: widget.workspaceId,
            channelId: widget.channelId,
            name: name,
          );
      await _load();
      _notice(
        tr(
          'Đã chuyển thành phòng nhóm nội bộ.',
          'Converted to an internal group room.',
        ),
      );
    });
  }

  Future<void> _updateSettings({
    CollaborationRoomMode? roomMode,
    bool? lobbyEnabled,
    bool? chatLocked,
    bool? guestMicrophoneEnabled,
    bool? guestCameraEnabled,
  }) async {
    final current = _settings!;
    await _guard(() async {
      final updated = await ref
          .read(conversationRemoteDataSourceProvider)
          .updateCollaborationSettings(
            workspaceId: widget.workspaceId,
            channelId: widget.channelId,
            roomMode: roomMode ?? current.roomMode,
            lobbyEnabled: lobbyEnabled ?? current.lobbyEnabled,
            chatLocked: chatLocked ?? current.chatLocked,
            guestMicrophoneEnabled:
                guestMicrophoneEnabled ?? current.guestMicrophoneEnabled,
            guestCameraEnabled:
                guestCameraEnabled ?? current.guestCameraEnabled,
            defaultParticipantRole:
                (roomMode ?? current.roomMode) == CollaborationRoomMode.webinar
                ? CollaborationParticipantRole.listener
                : current.defaultParticipantRole,
          );
      if (mounted) setState(() => _settings = updated);
    });
  }

  Future<void> _importUserGroup() async {
    final groupId = _selectedUserGroupId;
    if (groupId == null || groupId.isEmpty) return;
    await _guard(() async {
      final remote = ref.read(conversationRemoteDataSourceProvider);
      final userIds = await remote.listCollaborationUserGroupMemberIds(
        workspaceId: widget.workspaceId,
        groupId: groupId,
      );
      final existing = _roles.map((role) => role.userId).toSet();
      final missing = userIds
          .where((userId) => !existing.contains(userId))
          .toList(growable: false);
      await Future.wait([
        for (final userId in missing)
          remote.addMember(
            workspaceId: widget.workspaceId,
            channelId: widget.channelId,
            userId: userId,
          ),
      ]);
      await _load();
      _notice(
        missing.isEmpty
            ? tr(
                'Tất cả thành viên nhóm đã có trong phòng.',
                'All group members are already in the room.',
              )
            : tr(
                'Đã thêm ${missing.length} thành viên từ nhóm.',
                missing.length == 1
                    ? 'Added 1 member from the group.'
                    : 'Added ${missing.length} members from the group.',
              ),
      );
    });
  }

  Future<void> _createPublicLink() async {
    final passwordController = TextEditingController();
    var webinar = _settings!.roomMode == CollaborationRoomMode.webinar;
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => WebTuiDialog(
          title: tr('Tạo link khách ngoài', 'Create external guest link'),
          icon: WebTuiIcons.share,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Webinar mode'),
                value: webinar,
                onChanged: (value) => setDialogState(() => webinar = value),
              ),
              TextField(
                controller: passwordController,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: tr('Mật khẩu tùy chọn', 'Optional password'),
                  helperText: tr(
                    'Nếu nhập, tối thiểu 8 ký tự',
                    'If entered, at least 8 characters',
                  ),
                ),
              ),
            ],
          ),
          actions: [
            WebTuiDialogAction(
              label: tr('Hủy', 'Cancel'),
              onPressed: () => Navigator.of(context).pop(false),
            ),
            WebTuiDialogAction(
              label: tr('Tạo link', 'Create link'),
              primary: true,
              onPressed: () => Navigator.of(context).pop(true),
            ),
          ],
        ),
      ),
    );
    final password = passwordController.text;
    passwordController.dispose();
    if (approved != true || (password.isNotEmpty && password.length < 8)) {
      return;
    }
    await _guard(() async {
      final link = await ref
          .read(conversationRemoteDataSourceProvider)
          .createPublicConversationLink(
            workspaceId: widget.workspaceId,
            channelId: widget.channelId,
            roomMode: webinar
                ? CollaborationRoomMode.webinar
                : CollaborationRoomMode.public,
            password: password,
            lobbyEnabled: _settings!.lobbyEnabled,
            chatLocked: _settings!.chatLocked,
            guestMicrophoneEnabled: _settings!.guestMicrophoneEnabled,
            guestCameraEnabled: _settings!.guestCameraEnabled,
          );
      final server = ref.read(activeServerUriProvider);
      final url = Uri(
        scheme: server.scheme,
        host: server.host,
        port: server.hasPort ? server.port : null,
        path: '/join/${link.token}',
      ).toString();
      await Clipboard.setData(ClipboardData(text: url));
      if (mounted) setState(() => _settings = link.settings);
      _notice(
        tr('Đã tạo và sao chép link khách.', 'Guest link created and copied.'),
      );
    });
  }

  Future<void> _disablePublicLink() async {
    await _guard(() async {
      final updated = await ref
          .read(conversationRemoteDataSourceProvider)
          .disablePublicConversationLink(
            workspaceId: widget.workspaceId,
            channelId: widget.channelId,
          );
      if (mounted) setState(() => _settings = updated);
      _notice(tr('Đã thu hồi link khách.', 'Guest link revoked.'));
    });
  }

  Future<void> _moderateGuest(String requestId, bool approve) async {
    await _guard(() async {
      await ref
          .read(conversationRemoteDataSourceProvider)
          .moderateCollaborationGuest(
            workspaceId: widget.workspaceId,
            channelId: widget.channelId,
            requestId: requestId,
            approve: approve,
          );
      final guests = await ref
          .read(conversationRemoteDataSourceProvider)
          .listCollaborationGuests(
            workspaceId: widget.workspaceId,
            channelId: widget.channelId,
          );
      if (mounted) setState(() => _guests = guests);
    });
  }

  Future<void> _updateRole(
    String userId,
    CollaborationParticipantRole role,
  ) async {
    await _guard(() async {
      await ref
          .read(conversationRemoteDataSourceProvider)
          .updateCollaborationRole(
            workspaceId: widget.workspaceId,
            channelId: widget.channelId,
            userId: userId,
            role: role,
          );
      final roles = await ref
          .read(conversationRemoteDataSourceProvider)
          .listCollaborationRoles(
            workspaceId: widget.workspaceId,
            channelId: widget.channelId,
          );
      if (mounted) setState(() => _roles = roles);
    });
  }

  Future<void> _setVoiceRoom(bool active) async {
    await _guard(() async {
      final room = await ref
          .read(conversationRemoteDataSourceProvider)
          .setVoiceRoom(
            workspaceId: widget.workspaceId,
            channelId: widget.channelId,
            active: active,
          );
      if (mounted) setState(() => _voiceRoom = room);
      _notice(
        active
            ? tr('Voice room đã bắt đầu.', 'Voice room started.')
            : tr('Voice room đã kết thúc.', 'Voice room ended.'),
      );
    });
  }

  Future<void> _createMeeting() async {
    final draft = await showMeetingSchedulerSheet(
      context,
      conversationTitle: widget.title,
    );
    if (draft == null || !mounted) return;
    await _guard(() async {
      await ref
          .read(conversationRemoteDataSourceProvider)
          .createMeeting(
            workspaceId: widget.workspaceId,
            channelId: widget.channelId,
            title: draft.title,
            description: draft.description,
            startsAt: draft.startsAt,
            endsAt: draft.endsAt,
            lobbyOpensAt: draft.lobbyOpensAt,
            roomPolicy: draft.roomPolicy,
            cleanupAfter: draft.cleanupAfter,
          );
      final meetings = await ref
          .read(conversationRemoteDataSourceProvider)
          .listMeetings(
            workspaceId: widget.workspaceId,
            channelId: widget.channelId,
          );
      if (mounted) setState(() => _meetings = meetings);
      _notice(tr('Đã lên lịch cuộc họp.', 'Meeting scheduled.'));
    });
  }

  Future<void> _transitionMeeting(ChannelMeeting meeting, String action) async {
    await _guard(() async {
      await ref
          .read(conversationRemoteDataSourceProvider)
          .transitionMeeting(
            workspaceId: widget.workspaceId,
            channelId: widget.channelId,
            meetingId: meeting.id,
            action: action,
          );
      final meetings = await ref
          .read(conversationRemoteDataSourceProvider)
          .listMeetings(
            workspaceId: widget.workspaceId,
            channelId: widget.channelId,
          );
      if (mounted) setState(() => _meetings = meetings);
    });
  }

  Future<void> _toggleRecordingPolicy(bool enabled) async {
    final current = _recordingPolicy!;
    await _guard(() async {
      final policy = await ref
          .read(conversationRemoteDataSourceProvider)
          .updateRecordingPolicy(
            workspaceId: widget.workspaceId,
            channelId: widget.channelId,
            policy: RecordingPolicy(
              enabled: enabled,
              consentRequired: true,
              retentionDays: current.retentionDays,
              transcriptionEnabled: current.transcriptionEnabled,
              summaryEnabled: current.summaryEnabled,
              provider: current.provider,
            ),
          );
      if (mounted) setState(() => _recordingPolicy = policy);
    });
  }

  Future<void> _startRecording() async {
    await _guard(() async {
      final activeMeeting = _meetings.where((item) => item.isLive).firstOrNull;
      await ref
          .read(conversationRemoteDataSourceProvider)
          .startRecording(
            workspaceId: widget.workspaceId,
            channelId: widget.channelId,
            meetingId: activeMeeting?.id,
          );
      await _refreshRecordings();
      _notice(
        tr(
          'Đã gửi yêu cầu đồng ý ghi hình tới các thành viên.',
          'Recording consent request sent to members.',
        ),
      );
    });
  }

  Future<void> _setRecordingConsent(
    ChannelRecording recording,
    bool consented,
  ) async {
    await _guard(() async {
      await ref
          .read(conversationRemoteDataSourceProvider)
          .setRecordingConsent(
            workspaceId: widget.workspaceId,
            channelId: widget.channelId,
            recordingId: recording.id,
            consented: consented,
          );
      await _refreshRecordings();
    });
  }

  Future<void> _stopRecording(ChannelRecording recording) async {
    await _guard(() async {
      await ref
          .read(conversationRemoteDataSourceProvider)
          .stopRecording(
            workspaceId: widget.workspaceId,
            channelId: widget.channelId,
            recordingId: recording.id,
          );
      await _refreshRecordings();
    });
  }

  Future<void> _refreshRecordings() async {
    final recordings = await ref
        .read(conversationRemoteDataSourceProvider)
        .listRecordings(
          workspaceId: widget.workspaceId,
          channelId: widget.channelId,
        );
    if (mounted) setState(() => _recordings = recordings);
  }

  Future<void> _setupBreakouts(String mode) async {
    await _guard(() async {
      final rooms = await ref
          .read(conversationRemoteDataSourceProvider)
          .setupBreakoutRooms(
            workspaceId: widget.workspaceId,
            channelId: widget.channelId,
            assignmentMode: mode,
            roomCount: 3,
            allowSelfSelect: mode == 'self_select',
          );
      if (mounted) setState(() => _breakouts = rooms);
    });
  }

  Future<void> _startBreakouts() async {
    await _guard(() async {
      final rooms = await ref
          .read(conversationRemoteDataSourceProvider)
          .startBreakoutRooms(
            workspaceId: widget.workspaceId,
            channelId: widget.channelId,
          );
      if (mounted) setState(() => _breakouts = rooms);
    });
  }

  Future<void> _joinBreakout(BreakoutRoom room) async {
    await _guard(() async {
      final rooms = await ref
          .read(conversationRemoteDataSourceProvider)
          .joinBreakoutRoom(
            workspaceId: widget.workspaceId,
            channelId: widget.channelId,
            roomId: room.id,
          );
      if (mounted) setState(() => _breakouts = rooms);
      await _openMeeting(room.roomKey);
    });
  }

  Future<void> _broadcastBreakouts() async {
    final body = _breakoutBroadcastController.text.trim();
    if (body.isEmpty) return;
    await _guard(() async {
      await ref
          .read(conversationRemoteDataSourceProvider)
          .broadcastToBreakouts(
            workspaceId: widget.workspaceId,
            channelId: widget.channelId,
            body: body,
          );
      _breakoutBroadcastController.clear();
      _notice(
        tr(
          'Đã gửi thông báo đến mọi phòng nhỏ.',
          'Announcement sent to all breakout rooms.',
        ),
      );
    });
  }

  Future<void> _createBreakout() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => WebTuiDialog(
        title: tr('Tạo phòng nhỏ', 'Create breakout room'),
        icon: WebTuiIcons.group,
        content: WebTuiDialogTextField(
          controller: controller,
          autofocus: true,
          label: tr('Tên phòng', 'Room name'),
        ),
        actions: [
          WebTuiDialogAction(
            label: tr('Hủy', 'Cancel'),
            onPressed: () => Navigator.of(context).pop(),
          ),
          WebTuiDialogAction(
            label: tr('Tạo', 'Create'),
            primary: true,
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.length < 2) return;
    await _guard(() async {
      await ref
          .read(conversationRemoteDataSourceProvider)
          .createBreakoutRoom(
            workspaceId: widget.workspaceId,
            channelId: widget.channelId,
            name: name,
            assignedUserIds: const [],
          );
      final rooms = await ref
          .read(conversationRemoteDataSourceProvider)
          .listBreakoutRooms(
            workspaceId: widget.workspaceId,
            channelId: widget.channelId,
          );
      if (mounted) setState(() => _breakouts = rooms);
    });
  }

  Future<void> _returnBreakouts() async {
    await _guard(() async {
      final rooms = await ref
          .read(conversationRemoteDataSourceProvider)
          .returnBreakoutRooms(
            workspaceId: widget.workspaceId,
            channelId: widget.channelId,
          );
      if (mounted) setState(() => _breakouts = rooms);
      _notice(
        tr(
          'Đã gọi tất cả thành viên về phòng chính.',
          'Called all members back to the main room.',
        ),
      );
    });
  }

  ChannelMeeting? get _liveMeeting =>
      _meetings.where((item) => item.isLive).firstOrNull;

  Future<void> _openMeeting(String roomKey) async {
    try {
      await _openMeetingUnsafe(roomKey);
    } on Object catch (error) {
      _notice(userFacingErrorMessage(error));
    }
  }

  Future<void> _openMeetingUnsafe(String roomKey) async {
    final settings = _settings!;
    if (settings.meetingProvider == 'livekit') {
      final inApp = opensMeetingInApp(
        meetingProvider: settings.meetingProvider,
        livekitCapability:
            ref.read(activeServerDiscoveryProvider)?.capabilities.livekit ==
            true,
      );
      final live = _liveMeeting;
      if (!inApp) {
        _notice(
          tr(
            'Máy chủ chưa bật họp trực tuyến trong ứng dụng.',
            'The server has not enabled in-app online meetings.',
          ),
        );
      } else if (live == null) {
        _notice(
          tr('Chưa có cuộc họp nào đang diễn ra.', 'No meeting in progress.'),
        );
      } else {
        await _openLiveKitMeeting(live.id, live.title);
      }
      return;
    }
    final baseUrl = settings.meetingBaseUrl?.trim() ?? '';
    final base = Uri.tryParse(baseUrl);
    if (baseUrl.isEmpty || base == null) {
      _notice(
        tr(
          'Media server chưa được cấu hình.',
          'Media server is not configured.',
        ),
      );
      return;
    }
    final role = _roles
        .where((item) => item.userId == _currentUserId)
        .map((item) => item.role)
        .firstOrNull;
    final canPresent =
        settings.roomMode != CollaborationRoomMode.webinar ||
        role == CollaborationParticipantRole.moderator ||
        role == CollaborationParticipantRole.presenter;
    final chatEnabled =
        !settings.chatLocked ||
        role == CollaborationParticipantRole.moderator ||
        role == CollaborationParticipantRole.presenter;
    final toolbarButtons = [
      if (canPresent) ...[
        'microphone',
        'camera',
        'desktop',
        'select-background',
      ],
      if (chatEnabled) 'chat',
      'raisehand',
      'tileview',
      'fullscreen',
      'settings',
      'security',
      'hangup',
    ];
    final fragment = Uri(
      queryParameters: {
        'config.prejoinConfig.enabled': 'false',
        'config.startWithAudioMuted': '${!canPresent}',
        'config.startWithVideoMuted': '${!canPresent}',
        'config.toolbarButtons': jsonEncode(toolbarButtons),
        'interfaceConfig.TILE_VIEW_MAX_COLUMNS': '4',
      },
    ).query;
    // Máy chủ bật JWT cho Jitsi thì kèm token; máy chủ cũ (404) mở như trước.
    final jwt = await fetchJitsiJwtOrEmpty(
      ref.read(meetingApiProvider),
      workspaceId: widget.workspaceId,
      channelId: widget.channelId,
      meetingId: _liveMeeting?.id,
    );
    final jwtQuery = jwt.isEmpty ? '' : '?jwt=${Uri.encodeQueryComponent(jwt)}';
    final roomUri = base.resolve(
      '${Uri.encodeComponent(roomKey)}$jwtQuery#$fragment',
    );
    final opened = await ref
        .read(externalUrlLauncherProvider)
        .open(roomUri.toString());
    if (!opened) {
      _notice(
        tr(
          'Không mở được phòng họp trên thiết bị này.',
          'Could not open the meeting room on this device.',
        ),
      );
    }
  }

  Future<void> _openLiveKitMeeting(
    String meetingId,
    String title, {
    MeetingJoinInfo? prefetched,
    bool startWithVideo = false,
  }) async {
    final api = ref.read(meetingApiProvider);
    final join =
        prefetched ??
        await api.fetchJoinToken(
          workspaceId: widget.workspaceId,
          channelId: widget.channelId,
          meetingId: meetingId,
        );
    if (!mounted) return;
    await Navigator.of(context, rootNavigator: true).push<void>(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => MeetingRoomScreen(
          title: title.isEmpty ? widget.title : title,
          join: join,
          startWithVideo: startWithVideo,
          refreshJoin: () => api.fetchJoinToken(
            workspaceId: widget.workspaceId,
            channelId: widget.channelId,
            meetingId: meetingId,
          ),
        ),
      ),
    );
  }

  /// Đổ chuông cả nhóm rồi vào họp; máy chủ kiểm quyền gọi và giới hạn 1 cuộc
  /// đổ chuông mỗi kênh.
  Future<void> _startGroupCall(String kind) async {
    final live = _liveMeeting;
    if (live == null) {
      _notice(
        tr(
          'Hãy bắt đầu cuộc họp trước khi gọi cả nhóm.',
          'Start the meeting before calling the whole group.',
        ),
      );
      return;
    }
    await _guard(() async {
      final api = ref.read(meetingApiProvider);
      final call = await api.startGroupCall(
        workspaceId: widget.workspaceId,
        channelId: widget.channelId,
        meetingId: live.id,
        kind: kind,
      );
      _notice(
        call.ringTruncated
            ? tr(
                'Đang đổ chuông 50 thành viên hoạt động gần nhất.',
                'Ringing the 50 most recently active members.',
              )
            : tr('Đang đổ chuông cả nhóm.', 'Ringing the whole group.'),
      );
      await _openMeeting(_settings!.meetingRoomKey ?? '');
    });
  }

  Future<void> _saveNotes() async {
    final notes = _notes!;
    await _guard(() async {
      final updated = await ref
          .read(conversationRemoteDataSourceProvider)
          .updateCollaborationDocument(
            workspaceId: widget.workspaceId,
            channelId: widget.channelId,
            kind: 'notes',
            content: {'text': _notesController.text},
            expectedVersion: notes.version,
          );
      if (mounted) setState(() => _notes = updated);
      _notice(tr('Đã lưu biên bản.', 'Minutes saved.'));
    });
  }

  Future<void> _summarizeChannel() async {
    await _guard(() async {
      final summary = await ref
          .read(conversationRemoteDataSourceProvider)
          .summarizeChannel(
            workspaceId: widget.workspaceId,
            channelId: widget.channelId,
            since: DateTime.now().subtract(const Duration(days: 7)),
          );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => WebTuiDialog(
          title: tr('Tóm tắt AI nội bộ', 'Internal AI summary'),
          icon: WebTuiIcons.bot,
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(summary.summary),
              if (summary.decisions.isNotEmpty) ...[
                const SizedBox(height: WebTuiSpacing.md),
                Text(
                  tr('Quyết định', 'Decisions'),
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                for (final item in summary.decisions) Text('• $item'),
              ],
              if (summary.actionItems.isNotEmpty) ...[
                const SizedBox(height: WebTuiSpacing.md),
                Text(
                  tr('Việc cần làm', 'Tasks'),
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                for (final item in summary.actionItems) Text('• $item'),
              ],
              const SizedBox(height: WebTuiSpacing.md),
              Text(
                tr(
                  '${summary.messageCount} tin nhắn · ${summary.model}',
                  summary.messageCount == 1
                      ? '1 message · ${summary.model}'
                      : '${summary.messageCount} messages · ${summary.model}',
                ),
                style: WebTuiTypography.bodySmall.copyWith(
                  color: WebTuiColors.textSecondary,
                ),
              ),
            ],
          ),
          actions: [
            WebTuiDialogAction(
              label: tr('Đóng', 'Close'),
              primary: true,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      );
    });
  }

  Future<void> _guard(
    Future<void> Function() operation, {
    bool quiet = false,
  }) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await operation();
    } catch (error) {
      if (!quiet) _notice(userFacingErrorMessage(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _notice(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _CapabilityChip extends StatelessWidget {
  const _CapabilityChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(icon, size: 16, color: WebTuiColors.primary),
      label: Text(label),
      visualDensity: VisualDensity.compact,
    );
  }
}

IconData _sharedItemIcon(String kind) {
  return switch (kind) {
    'file' => Icons.insert_drive_file_outlined,
    'pin' => Icons.push_pin_outlined,
    'poll' => Icons.poll_outlined,
    'task' => Icons.task_alt_outlined,
    'recording' => Icons.fiber_manual_record_outlined,
    _ => Icons.link_rounded,
  };
}

String _sharedItemLabel(String kind) {
  return switch (kind) {
    'file' => 'File',
    'pin' => tr('Tin nhắn đã ghim', 'Pinned messages'),
    'poll' => tr('Bình chọn', 'Poll'),
    'task' => 'Task',
    'recording' => tr('Bản ghi cuộc họp', 'Meeting recording'),
    _ => tr('Nội dung chia sẻ', 'Shared content'),
  };
}

String _initials(String value) {
  final words = value
      .trim()
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .toList(growable: false);
  if (words.isEmpty) return '?';
  if (words.length == 1) return words.first.substring(0, 1).toUpperCase();
  return '${words.first.substring(0, 1)}${words.last.substring(0, 1)}'
      .toUpperCase();
}
