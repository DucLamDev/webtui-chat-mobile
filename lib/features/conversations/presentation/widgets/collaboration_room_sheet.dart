import 'dart:async';
import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers/foundation_providers.dart';
import '../../../../design_system/tokens/webtui_colors.dart';
import '../../../../design_system/tokens/webtui_radii.dart';
import '../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../design_system/tokens/webtui_typography.dart';
import '../../domain/entities/collaboration_room.dart';
import '../../domain/entities/conversation_summary.dart';

Future<void> showCollaborationRoomSheet(
  BuildContext context, {
  required String workspaceId,
  required String channelId,
  required String title,
  required ConversationSummary? conversation,
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
    ),
  );
}

class CollaborationRoomSheet extends ConsumerStatefulWidget {
  const CollaborationRoomSheet({
    required this.workspaceId,
    required this.channelId,
    required this.title,
    required this.conversation,
    super.key,
  });

  final String workspaceId;
  final String channelId;
  final String title;
  final ConversationSummary? conversation;

  @override
  ConsumerState<CollaborationRoomSheet> createState() =>
      _CollaborationRoomSheetState();
}

class _CollaborationRoomSheetState
    extends ConsumerState<CollaborationRoomSheet> {
  final _notesController = TextEditingController();
  final _taskController = TextEditingController();
  final _promoteController = TextEditingController();
  final _meetingController = TextEditingController();
  final _breakoutBroadcastController = TextEditingController();
  CollaborationSettings? _settings;
  CollaborationDocument? _notes;
  CollaborationDocument? _whiteboard;
  List<CollaborationTask> _tasks = const [];
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
  List<_MobileStroke> _strokes = const [];
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
    _promoteController.text = widget.title;
    unawaited(_load());
  }

  @override
  void dispose() {
    _notesController.dispose();
    _taskController.dispose();
    _promoteController.dispose();
    _meetingController.dispose();
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
      final profile = await ref.read(loadProfileUseCaseProvider).execute();
      final settings = await remote.getCollaborationSettings(
        workspaceId: widget.workspaceId,
        channelId: widget.channelId,
      );
      final results = await Future.wait<Object>([
        remote.getCollaborationDocument(
          workspaceId: widget.workspaceId,
          channelId: widget.channelId,
          kind: 'notes',
        ),
        remote.getCollaborationDocument(
          workspaceId: widget.workspaceId,
          channelId: widget.channelId,
          kind: 'whiteboard',
        ),
        remote.listCollaborationTasks(
          workspaceId: widget.workspaceId,
          channelId: widget.channelId,
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
      final whiteboard = results[1] as CollaborationDocument;
      setState(() {
        _settings = settings;
        _notes = notes;
        _whiteboard = whiteboard;
        _notesController.text = notes.content['text']?.toString() ?? '';
        _strokes = _parseStrokes(whiteboard.content);
        _tasks = results[2] as List<CollaborationTask>;
        _roles = results[3] as List<CollaborationRole>;
        _breakouts = results[4] as List<BreakoutRoom>;
        _guests = results[5] as List<CollaborationGuest>;
        _userGroups = results[6] as List<CollaborationUserGroup>;
        _currentUserId = profile.valueOrNull?.id;
        _loading = false;
      });
      unawaited(_loadAdvanced());
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
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
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.92,
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
                      const Icon(
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
                        child: const Text('Thử lại'),
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
              gradient: const LinearGradient(
                colors: [Color(0xFF2E8AF7), Color(0xFF1759BC)],
              ),
              borderRadius: BorderRadius.circular(WebTuiRadii.lg),
            ),
            child: const Icon(
              CupertinoIcons.video_camera_solid,
              color: Colors.white,
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
                      ? 'Hội thảo'
                      : mode == CollaborationRoomMode.public
                      ? 'Phòng có khách ngoài'
                      : _settings?.isDirect == true
                      ? 'Hội thoại 1-1 riêng tư'
                      : 'Phòng nhóm nội bộ',
                  style: WebTuiTypography.bodySmall.copyWith(
                    color: WebTuiColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Đóng',
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }

  Widget _buildTabs() {
    const tabs = [
      (Icons.home_outlined, 'Tổng quan'),
      (Icons.video_call_outlined, 'Họp'),
      (Icons.folder_copy_outlined, 'Đã chia sẻ'),
      (Icons.description_outlined, 'Biên bản'),
      (Icons.draw_outlined, 'Bảng trắng'),
      (Icons.task_alt_outlined, 'Task'),
    ];
    return SizedBox(
      height: 52,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: WebTuiSpacing.lg),
        scrollDirection: Axis.horizontal,
        itemCount: tabs.length,
        separatorBuilder: (_, _) => const SizedBox(width: WebTuiSpacing.xs),
        itemBuilder: (context, index) => ChoiceChip(
          selected: _tab == index,
          avatar: Icon(tabs[index].$1, size: 17),
          label: Text(tabs[index].$2),
          onSelected: (_) => setState(() => _tab = index),
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
        padding: const EdgeInsets.all(WebTuiSpacing.lg),
        children: [
          Container(
            padding: const EdgeInsets.all(WebTuiSpacing.lg),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF0D6EFD), Color(0xFF5B4BDB)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(22),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Không gian cộng tác',
                  style: WebTuiTypography.titleMedium.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: WebTuiSpacing.xs),
                Text(
                  'Họp, voice room, task và nội dung quan trọng trong cùng một nơi.',
                  style: WebTuiTypography.bodySmall.copyWith(
                    color: Colors.white.withValues(alpha: 0.86),
                  ),
                ),
                const SizedBox(height: WebTuiSpacing.md),
                Wrap(
                  spacing: WebTuiSpacing.sm,
                  runSpacing: WebTuiSpacing.sm,
                  children: [
                    _HomeMetric(
                      icon: Icons.alternate_email_rounded,
                      value: home?.unreadMentions ?? 0,
                      label: 'nhắc tên',
                    ),
                    _HomeMetric(
                      icon: Icons.notifications_none_rounded,
                      value: home?.pendingReminders ?? 0,
                      label: 'nhắc việc',
                    ),
                    _HomeMetric(
                      icon: Icons.phone_missed_rounded,
                      value: home?.missedCalls ?? 0,
                      label: 'cuộc gọi nhỡ',
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: WebTuiSpacing.md),
          _sectionCard(
            icon: Icons.event_available_outlined,
            title: 'Sắp diễn ra',
            child: home == null
                ? const Center(child: CircularProgressIndicator())
                : home.upcomingMeetings.isEmpty
                ? const Text('Chưa có cuộc họp nào được lên lịch.')
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
              title: 'Năng lực máy chủ',
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
                            : 'AI chưa bật',
                      ),
                      _CapabilityChip(
                        icon: Icons.lock_outline_rounded,
                        label: integration.e2eeCallsEnabled
                            ? 'E2EE call'
                            : 'WebRTC bảo mật',
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
                        label: const Text('Tóm tắt tin nhắn bằng AI nội bộ'),
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
            title: 'Nội dung được chia sẻ',
            child: _sharedItems.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: WebTuiSpacing.lg),
                    child: Center(
                      child: Text('Chưa có file, poll, task hoặc bản ghi.'),
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
            title: 'Hội thoại 1-1 riêng tư',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Chat chữ, voice, file, gọi thoại/video và screen share được giữ riêng tư. Muốn có link khách, hãy Promote thành phòng nhóm.',
                ),
                const SizedBox(height: WebTuiSpacing.md),
                TextField(
                  controller: _promoteController,
                  decoration: const InputDecoration(
                    labelText: 'Tên phòng nhóm',
                  ),
                ),
                const SizedBox(height: WebTuiSpacing.sm),
                FilledButton.icon(
                  onPressed: _saving ? null : _promote,
                  icon: const Icon(Icons.group_add_rounded),
                  label: const Text('Promote thành phòng nhóm'),
                ),
              ],
            ),
          )
        else ...[
          _sectionCard(
            icon: CupertinoIcons.video_camera_solid,
            title: 'Họp video nhóm',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: [
                    _CapabilityChip(
                      icon: Icons.grid_view_rounded,
                      label: 'Grid',
                    ),
                    _CapabilityChip(
                      icon: Icons.back_hand_outlined,
                      label: 'Giơ tay',
                    ),
                    _CapabilityChip(
                      icon: Icons.blur_on_rounded,
                      label: 'Blur nền',
                    ),
                    _CapabilityChip(
                      icon: Icons.screen_share_outlined,
                      label: 'Chia sẻ màn hình',
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
                        ? 'Vào phòng họp'
                        : 'Media server chưa cấu hình',
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
                  ? 'Đang mở · thành viên có thể tham gia ngay.'
                  : 'Mở một không gian nói chuyện nhanh, không cần lên lịch.',
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
            label: Text(active ? 'Kết thúc' : 'Bắt đầu'),
          ),
        ],
      ),
    );
  }

  Widget _meetingLifecycleCard() {
    return _sectionCard(
      icon: Icons.calendar_month_outlined,
      title: 'Lịch họp',
      child: Column(
        children: [
          if (_canManage) ...[
            TextField(
              controller: _meetingController,
              maxLength: 160,
              decoration: const InputDecoration(
                labelText: 'Tên cuộc họp mới',
                hintText: 'Ví dụ: Daily team sản phẩm',
                counterText: '',
              ),
              onSubmitted: (_) => _createMeeting(),
            ),
            const SizedBox(height: WebTuiSpacing.sm),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _saving ? null : _createMeeting,
                icon: const Icon(Icons.add_circle_outline_rounded),
                label: const Text('Lên lịch sau 5 phút'),
              ),
            ),
            const Divider(height: WebTuiSpacing.xl),
          ],
          if (_meetings.isEmpty)
            const Text('Chưa có cuộc họp được lên lịch.')
          else
            for (final meeting in _meetings.take(10))
              _meetingTile(meeting, controls: true),
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
      subtitle: Text(meeting.isLive ? 'Đang diễn ra' : time),
      trailing: controls && _canManage
          ? PopupMenuButton<String>(
              onSelected: (action) => _transitionMeeting(meeting, action),
              itemBuilder: (context) => [
                if (meeting.canStart)
                  const PopupMenuItem(value: 'start', child: Text('Bắt đầu')),
                if (meeting.isLive)
                  const PopupMenuItem(value: 'end', child: Text('Kết thúc')),
                if (meeting.canStart)
                  const PopupMenuItem(value: 'cancel', child: Text('Hủy lịch')),
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
      title: 'Ghi hình & AI meeting notes',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_canManage)
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Cho phép ghi cuộc họp'),
              subtitle: Text(
                policy.consentRequired
                    ? 'Yêu cầu mọi người đồng ý · lưu ${policy.retentionDays} ngày'
                    : 'Lưu ${policy.retentionDays} ngày',
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
                label: '${policy.retentionDays} ngày',
              ),
            ],
          ),
          const SizedBox(height: WebTuiSpacing.md),
          if (active == null && policy.enabled && _canManage)
            FilledButton.icon(
              onPressed: _saving ? null : _startRecording,
              icon: const Icon(Icons.fiber_manual_record_rounded),
              label: const Text('Yêu cầu ghi hình'),
            )
          else if (active != null) ...[
            Text(
              active.status == 'pending'
                  ? 'Đang chờ đồng ý: ${active.consentCount}/${active.participantCount}'
                  : 'Bản ghi đang ở trạng thái ${active.status}.',
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
                    label: const Text('Tôi đồng ý'),
                  ),
                if (_canManage)
                  OutlinedButton.icon(
                    onPressed: _saving ? null : () => _stopRecording(active),
                    icon: const Icon(Icons.stop_circle_outlined),
                    label: const Text('Dừng'),
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
      title: 'Quyền và chế độ phòng',
      child: Column(
        children: [
          DropdownButtonFormField<CollaborationRoomMode>(
            initialValue: settings.roomMode,
            decoration: const InputDecoration(labelText: 'Loại phòng'),
            items: const [
              DropdownMenuItem(
                value: CollaborationRoomMode.internal,
                child: Text('Nhóm nội bộ'),
              ),
              DropdownMenuItem(
                value: CollaborationRoomMode.public,
                child: Text('Khách ngoài'),
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
            title: const Text('Phòng chờ'),
            subtitle: const Text('Host duyệt khách trước khi vào'),
            value: settings.lobbyEnabled,
            onChanged: (value) => _updateSettings(lobbyEnabled: value),
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('Khóa chat khách'),
            value: settings.chatLocked,
            onChanged: (value) => _updateSettings(chatLocked: value),
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('Mic khách mặc định bật'),
            value: settings.guestMicrophoneEnabled,
            onChanged: (value) =>
                _updateSettings(guestMicrophoneEnabled: value),
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('Camera khách mặc định bật'),
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
      title: 'Link khách ngoài',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (settings.publicAccessEnabled)
            Text(
              'Link đang hoạt động · ${settings.publicTokenPrefix ?? ''}…',
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
                    settings.publicAccessEnabled ? 'Tạo link mới' : 'Tạo link',
                  ),
                ),
              ),
              if (settings.publicAccessEnabled) ...[
                const SizedBox(width: WebTuiSpacing.sm),
                IconButton.outlined(
                  tooltip: 'Thu hồi link',
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
      title: 'Thêm theo nhóm người dùng',
      child: Column(
        children: [
          DropdownButtonFormField<String>(
            initialValue: _selectedUserGroupId,
            decoration: const InputDecoration(labelText: 'Phòng ban nội bộ'),
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
              label: const Text('Thêm toàn bộ thành viên'),
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
      title: 'Phòng chờ (${waiting.length})',
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
                    tooltip: 'Duyệt',
                    onPressed: () => _moderateGuest(guest.id, true),
                    icon: const Icon(
                      Icons.check_circle_rounded,
                      color: WebTuiColors.accentGreen,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Từ chối',
                    onPressed: () => _moderateGuest(guest.id, false),
                    icon: const Icon(
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
      title: 'Diễn giả và khán giả',
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
                items: const [
                  DropdownMenuItem(
                    value: CollaborationParticipantRole.moderator,
                    child: Text('Chủ trì'),
                  ),
                  DropdownMenuItem(
                    value: CollaborationParticipantRole.presenter,
                    child: Text('Diễn giả'),
                  ),
                  DropdownMenuItem(
                    value: CollaborationParticipantRole.member,
                    child: Text('Thành viên'),
                  ),
                  DropdownMenuItem(
                    value: CollaborationParticipantRole.listener,
                    child: Text('Khán giả'),
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
                '${room.assignedUserIds.length} thành viên · '
                '${room.status == 'prepared' ? 'đã chuẩn bị' : 'đang mở'}',
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
                  label: const Text('Chia tự động'),
                ),
                OutlinedButton.icon(
                  onPressed: _saving
                      ? null
                      : () => _setupBreakouts('self_select'),
                  icon: const Icon(Icons.how_to_reg_outlined),
                  label: const Text('Tự chọn phòng'),
                ),
                OutlinedButton.icon(
                  onPressed: _saving ? null : _createBreakout,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Tạo thủ công'),
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
                  label: const Text('Mở tất cả phòng nhỏ'),
                ),
              ),
            ],
            if (openRooms.isNotEmpty) ...[
              const Divider(height: WebTuiSpacing.xl),
              TextField(
                controller: _breakoutBroadcastController,
                decoration: const InputDecoration(
                  labelText: 'Thông báo đến mọi phòng',
                  hintText: 'Còn 5 phút thảo luận…',
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
                      label: const Text('Phát thông báo'),
                    ),
                  ),
                  const SizedBox(width: WebTuiSpacing.sm),
                  OutlinedButton(
                    onPressed: _saving ? null : _returnBreakouts,
                    child: const Text('Gọi tất cả về'),
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
                decoration: const InputDecoration(
                  hintText:
                      '# Nội dung cuộc họp\n\n- Quyết định\n- Việc cần làm\n- Người phụ trách',
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
                  label: const Text('Lưu biên bản'),
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
      child: _sectionCard(
        icon: Icons.draw_outlined,
        title: 'Interactive Whiteboard · v${_whiteboard?.version ?? 1}',
        child: Column(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(WebTuiRadii.lg),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return GestureDetector(
                      onPanStart: (details) => _startStroke(
                        details.localPosition,
                        constraints.biggest,
                      ),
                      onPanUpdate: (details) => _appendStroke(
                        details.localPosition,
                        constraints.biggest,
                      ),
                      onPanEnd: (_) => unawaited(_saveWhiteboard()),
                      child: CustomPaint(
                        painter: _WhiteboardPainter(_strokes),
                        size: Size.infinite,
                      ),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: WebTuiSpacing.sm),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Vẽ bằng một ngón tay · tự lưu khi nhấc tay',
                    style: TextStyle(
                      color: WebTuiColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: () {
                    setState(() => _strokes = const []);
                    unawaited(_saveWhiteboard());
                  },
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: const Text('Xóa'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTasksTab() {
    return ListView(
      padding: const EdgeInsets.all(WebTuiSpacing.lg),
      children: [
        _sectionCard(
          icon: Icons.task_alt_rounded,
          title: 'Task công việc',
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _taskController,
                      maxLength: 240,
                      decoration: const InputDecoration(
                        hintText: 'Việc cần làm…',
                        counterText: '',
                      ),
                      onSubmitted: (_) => _createTask(),
                    ),
                  ),
                  const SizedBox(width: WebTuiSpacing.sm),
                  IconButton.filled(
                    tooltip: 'Tạo task',
                    onPressed: _saving ? null : _createTask,
                    icon: const Icon(Icons.add_rounded),
                  ),
                ],
              ),
              const SizedBox(height: WebTuiSpacing.sm),
              if (_tasks.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(WebTuiSpacing.lg),
                  child: Text('Chưa có task trong phòng.'),
                )
              else
                for (final task in _tasks)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: task.status == 'done',
                    title: Text(
                      task.title,
                      style: TextStyle(
                        decoration: task.status == 'done'
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                    ),
                    subtitle: task.sourceMessageId == null
                        ? null
                        : const Text('Được tạo từ tin nhắn'),
                    onChanged: (_) => _toggleTask(task),
                  ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _sectionCard({
    required IconData icon,
    required String title,
    required Widget child,
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
          child,
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
      _notice('Đã chuyển thành phòng nhóm nội bộ.');
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
            ? 'Tất cả thành viên nhóm đã có trong phòng.'
            : 'Đã thêm ${missing.length} thành viên từ nhóm.',
      );
    });
  }

  Future<void> _createPublicLink() async {
    final passwordController = TextEditingController();
    var webinar = _settings!.roomMode == CollaborationRoomMode.webinar;
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Tạo link khách ngoài'),
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
                decoration: const InputDecoration(
                  labelText: 'Mật khẩu tùy chọn',
                  helperText: 'Nếu nhập, tối thiểu 8 ký tự',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Hủy'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Tạo link'),
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
      _notice('Đã tạo và sao chép link khách.');
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
      _notice('Đã thu hồi link khách.');
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
      _notice(active ? 'Voice room đã bắt đầu.' : 'Voice room đã kết thúc.');
    });
  }

  Future<void> _createMeeting() async {
    final title = _meetingController.text.trim();
    if (title.isEmpty) return;
    await _guard(() async {
      await ref
          .read(conversationRemoteDataSourceProvider)
          .createMeeting(
            workspaceId: widget.workspaceId,
            channelId: widget.channelId,
            title: title,
            startsAt: DateTime.now().toUtc().add(const Duration(minutes: 5)),
            endsAt: DateTime.now().toUtc().add(const Duration(minutes: 65)),
          );
      _meetingController.clear();
      final meetings = await ref
          .read(conversationRemoteDataSourceProvider)
          .listMeetings(
            workspaceId: widget.workspaceId,
            channelId: widget.channelId,
          );
      if (mounted) setState(() => _meetings = meetings);
      _notice('Đã lên lịch cuộc họp sau 5 phút.');
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
      _notice('Đã gửi yêu cầu đồng ý ghi hình tới các thành viên.');
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
      _notice('Đã gửi thông báo đến mọi phòng nhỏ.');
    });
  }

  Future<void> _createBreakout() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Tạo phòng nhỏ'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Tên phòng'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Tạo'),
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
      _notice('Đã gọi tất cả thành viên về phòng chính.');
    });
  }

  Future<void> _openMeeting(String roomKey) async {
    final settings = _settings!;
    final baseUrl = settings.meetingBaseUrl?.trim() ?? '';
    final base = Uri.tryParse(baseUrl);
    if (baseUrl.isEmpty || base == null) {
      _notice('Media server chưa được cấu hình.');
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
    final roomUri = base.resolve('${Uri.encodeComponent(roomKey)}#$fragment');
    final opened = await ref
        .read(externalUrlLauncherProvider)
        .open(roomUri.toString());
    if (!opened) _notice('Không mở được phòng họp trên thiết bị này.');
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
      _notice('Đã lưu biên bản.');
    });
  }

  void _startStroke(Offset point, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final normalized = Offset(point.dx / size.width, point.dy / size.height);
    setState(() {
      _strokes = [
        ..._strokes,
        _MobileStroke(points: [normalized]),
      ];
    });
  }

  void _appendStroke(Offset point, Size size) {
    if (_strokes.isEmpty || size.width <= 0 || size.height <= 0) return;
    final normalized = Offset(point.dx / size.width, point.dy / size.height);
    setState(() {
      final last = _strokes.last;
      _strokes = [
        ..._strokes.take(_strokes.length - 1),
        _MobileStroke(points: [...last.points, normalized]),
      ];
    });
  }

  Future<void> _saveWhiteboard() async {
    final document = _whiteboard!;
    await _guard(() async {
      final updated = await ref
          .read(conversationRemoteDataSourceProvider)
          .updateCollaborationDocument(
            workspaceId: widget.workspaceId,
            channelId: widget.channelId,
            kind: 'whiteboard',
            content: {
              'strokes': [
                for (final stroke in _strokes)
                  {
                    'color': '#2563eb',
                    'points': [
                      for (final point in stroke.points)
                        {'x': point.dx, 'y': point.dy},
                    ],
                  },
              ],
            },
            expectedVersion: document.version,
          );
      if (mounted) setState(() => _whiteboard = updated);
    }, quiet: true);
  }

  Future<void> _createTask() async {
    final title = _taskController.text.trim();
    if (title.isEmpty) return;
    await _guard(() async {
      await ref
          .read(conversationRemoteDataSourceProvider)
          .createCollaborationTask(
            workspaceId: widget.workspaceId,
            channelId: widget.channelId,
            title: title,
          );
      _taskController.clear();
      final tasks = await ref
          .read(conversationRemoteDataSourceProvider)
          .listCollaborationTasks(
            workspaceId: widget.workspaceId,
            channelId: widget.channelId,
          );
      if (mounted) setState(() => _tasks = tasks);
    });
  }

  Future<void> _toggleTask(CollaborationTask task) async {
    await _guard(() async {
      await ref
          .read(conversationRemoteDataSourceProvider)
          .updateCollaborationTask(
            workspaceId: widget.workspaceId,
            channelId: widget.channelId,
            taskId: task.id,
            status: task.status == 'done' ? 'open' : 'done',
          );
      final tasks = await ref
          .read(conversationRemoteDataSourceProvider)
          .listCollaborationTasks(
            workspaceId: widget.workspaceId,
            channelId: widget.channelId,
          );
      if (mounted) setState(() => _tasks = tasks);
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
        builder: (context) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.auto_awesome_rounded),
              SizedBox(width: WebTuiSpacing.sm),
              Expanded(child: Text('Tóm tắt AI nội bộ')),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(summary.summary),
                if (summary.decisions.isNotEmpty) ...[
                  const SizedBox(height: WebTuiSpacing.md),
                  const Text(
                    'Quyết định',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  for (final item in summary.decisions) Text('• $item'),
                ],
                if (summary.actionItems.isNotEmpty) ...[
                  const SizedBox(height: WebTuiSpacing.md),
                  const Text(
                    'Việc cần làm',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  for (final item in summary.actionItems) Text('• $item'),
                ],
                const SizedBox(height: WebTuiSpacing.md),
                Text(
                  '${summary.messageCount} tin nhắn · ${summary.model}',
                  style: WebTuiTypography.bodySmall.copyWith(
                    color: WebTuiColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Đóng'),
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
      if (!quiet) _notice(error.toString());
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

class _HomeMetric extends StatelessWidget {
  const _HomeMetric({
    required this.icon,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final int value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: WebTuiSpacing.sm,
        vertical: WebTuiSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.20)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 16),
          const SizedBox(width: 5),
          Text(
            '$value $label',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
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
    'pin' => 'Tin nhắn đã ghim',
    'poll' => 'Bình chọn',
    'task' => 'Task',
    'recording' => 'Bản ghi cuộc họp',
    _ => 'Nội dung chia sẻ',
  };
}

final class _MobileStroke {
  const _MobileStroke({required this.points});

  final List<Offset> points;
}

class _WhiteboardPainter extends CustomPainter {
  const _WhiteboardPainter(this.strokes);

  final List<_MobileStroke> strokes;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
    final grid = Paint()
      ..color = const Color(0xFFE8EDF5)
      ..strokeWidth = 1;
    for (double x = 0; x < size.width; x += 24) {
      for (double y = 0; y < size.height; y += 24) {
        canvas.drawCircle(Offset(x, y), 1, grid);
      }
    }
    final paint = Paint()
      ..color = const Color(0xFF2563EB)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke;
    for (final stroke in strokes) {
      if (stroke.points.isEmpty) continue;
      final path = Path();
      final first = stroke.points.first;
      path.moveTo(first.dx * size.width, first.dy * size.height);
      for (final point in stroke.points.skip(1)) {
        path.lineTo(point.dx * size.width, point.dy * size.height);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _WhiteboardPainter oldDelegate) =>
      oldDelegate.strokes != strokes;
}

List<_MobileStroke> _parseStrokes(Map<String, Object?> content) {
  final raw = content['strokes'];
  if (raw is! List) return const [];
  return raw
      .expand<_MobileStroke>((stroke) {
        if (stroke is! Map) return const [];
        final points = stroke['points'];
        if (points is! List) return const [];
        final parsed = points
            .expand<Offset>((point) {
              if (point is! Map) return const [];
              final x = point['x'];
              final y = point['y'];
              if (x is! num || y is! num) return const [];
              return [Offset(x.toDouble(), y.toDouble())];
            })
            .toList(growable: false);
        return parsed.isEmpty ? const [] : [_MobileStroke(points: parsed)];
      })
      .toList(growable: false);
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
