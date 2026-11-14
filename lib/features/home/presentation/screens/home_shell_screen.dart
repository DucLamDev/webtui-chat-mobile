import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/providers/foundation_providers.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/notifications/call_tone_player.dart';
import '../../../../core/notifications/native_incoming_call_service.dart';
import '../../../../core/notifications/scoped_local_notification_service.dart';
import '../../../../core/platform/chat_share_intent_service.dart';
import '../../../../core/security/instance_scope.dart';
import '../../../../design_system/components/webtui_components.dart';
import '../../../../design_system/tokens/webtui_colors.dart';
import '../../../../design_system/tokens/webtui_radii.dart';
import '../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../design_system/tokens/webtui_typography.dart';
import '../../../approvals/application/approval_notification_actions.dart';
import '../../../approvals/presentation/controllers/approval_list_controller.dart';
import '../../../auth/application/session_termination.dart';
import '../../../auth/presentation/controllers/device_approval_controllers.dart';
import '../../../auth/presentation/controllers/legal_acceptance_controller.dart';
import '../../../auth/presentation/screens/device_approval_review_screen.dart';
import '../../../conversations/domain/entities/call_device_routing.dart';
import '../../../conversations/domain/entities/call_session.dart';
import '../../../conversations/domain/entities/conversation_realtime_event.dart';
import '../../../conversations/domain/entities/conversation_summary.dart';
import '../../../conversations/presentation/controllers/chat_room_controller.dart';
import '../../../conversations/presentation/controllers/conversation_home_controller.dart';
import '../../../conversations/presentation/controllers/pending_chat_share_controller.dart';
import '../../../conversations/presentation/screens/webrtc_call_screen.dart';
import '../../../conversations/presentation/screens/workspace_tools_screen.dart';
import '../../../conversations/presentation/widgets/conversation_home_views.dart';
import '../../../inbox/presentation/screens/inbox_list_screen.dart'
    show inboxConversationLocation;
import '../../../meetings/application/group_call_coordinator.dart';
import '../../../meetings/application/meeting_providers.dart';
import '../../../meetings/domain/meeting_models.dart';
import '../../../meetings/presentation/group_call_presenter.dart';
import '../../../notifications/domain/entities/mobile_notification.dart';
import '../../../notifications/presentation/controllers/notification_center_controller.dart';
import '../../../workspace/presentation/controllers/workspace_controller.dart';

bool nativeRejectActionIsStaleAfterAcceptance({
  required String reason,
  required CallStatus currentStatus,
}) {
  return (reason == 'timeout' || reason == 'declined') &&
      currentStatus != CallStatus.ringing;
}

/// Hành động gốc (decline / ended / timeout) của máy này với cuộc gọi đã được
/// nhận ở máy khác của chính người dùng: không gửi reject / hangup (sẽ cắt cuộc
/// gọi đang nói ở máy kia), chỉ xác nhận.
bool nativeCallActionIsStaleForOtherDevice({
  required CallSession current,
  required String? localDeviceId,
}) {
  return current.status == CallStatus.accepted &&
      callAnsweredOnAnotherDevice(
        answeredDeviceId: current.answeredDeviceId,
        localDeviceId: localDeviceId,
      );
}

bool nativeCallActionMatchesInstance({
  required NativeIncomingCallAction action,
  required InstanceScope activeInstance,
}) {
  if (!action.target.isBoundToInstance(activeInstance.instanceId)) {
    return false;
  }
  try {
    final actionOrigin = canonicalServerOrigin(
      Uri.parse(action.serverBaseUrl?.trim() ?? ''),
    );
    return actionOrigin == activeInstance.origin;
  } on FormatException {
    return false;
  }
}

class HomeShellScreen extends ConsumerStatefulWidget {
  const HomeShellScreen({this.initialTabIndex = 0, super.key});

  final int initialTabIndex;

  @override
  ConsumerState<HomeShellScreen> createState() => _HomeShellScreenState();
}

class _HomeShellScreenState extends ConsumerState<HomeShellScreen>
    with WidgetsBindingObserver {
  late int _tabIndex;
  late Set<int> _visitedTabs;
  String? _visitedWorkspaceId;
  int? _visitedWorkspaceGeneration;
  String? _pushRegisteredWorkspaceId;
  String? _presenceWorkspaceId;
  String? _syncWorkspaceId;
  String? _shareIntentWorkspaceId;
  String? _quickReplyWorkspaceId;
  String? _approvalActionWorkspaceId;
  bool _syncInFlight = false;
  bool _incomingCallPollInFlight = false;
  Timer? _pushRegistrationRetryTimer;
  Timer? _presenceTimer;
  Timer? _incomingCallPollTimer;
  StreamSubscription<NotificationTarget>? _notificationOpenSubscription;
  StreamSubscription<NotificationTarget>? _foregroundNotificationSubscription;
  StreamSubscription<NativeIncomingCallAction>? _nativeCallSubscription;
  StreamSubscription<ChatSharePayload>? _shareIntentSubscription;
  StreamSubscription<ScopedNotificationQuickReply>? _quickReplySubscription;
  StreamSubscription<ScopedNotificationApprovalAction>?
  _approvalActionSubscription;
  Future<void>? _approvalDrain;
  final Set<String> _nativeCallActionsInFlight = <String>{};
  final Set<String> _openedDeviceApprovals = <String>{};
  StreamSubscription<ConversationRealtimeEvent>?
  _incomingCallRealtimeSubscription;
  bool _notificationEnabled = true;
  bool _compactMode = false;
  bool _networkDegraded = false;
  String? _activeIncomingCallId;
  GroupCallCoordinator? _groupCallCoordinator;
  String? _ringingDialogCallId;
  ValueNotifier<bool>? _ringingDialogDismiss;
  ({String scopeId, String deviceId})? _callDeviceId;
  double _soundLevel = 0.64;
  double _textScalePreview = 0.42;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tabIndex = widget.initialTabIndex.clamp(0, _titles.length - 1).toInt();
    _visitedTabs = {_tabIndex};
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pushRegistrationRetryTimer?.cancel();
    _presenceTimer?.cancel();
    _incomingCallPollTimer?.cancel();
    _notificationOpenSubscription?.cancel();
    _foregroundNotificationSubscription?.cancel();
    _nativeCallSubscription?.cancel();
    _shareIntentSubscription?.cancel();
    _quickReplySubscription?.cancel();
    _approvalActionSubscription?.cancel();
    _incomingCallRealtimeSubscription?.cancel();
    final workspaceId = _presenceWorkspaceId;
    if (workspaceId != null) {
      unawaited(_setPresence(workspaceId, ConversationPresence.offline));
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final workspaceId = _presenceWorkspaceId;
    if (workspaceId == null) {
      return;
    }
    if (state == AppLifecycleState.resumed) {
      _activatePresence(workspaceId);
      _startIncomingCallPolling(workspaceId);
      unawaited(_groupCalls.restoreRinging(workspaceId));
      unawaited(_runWorkspaceCatchUp(workspaceId));
      unawaited(_drainBackgroundQuickReplies(workspaceId));
      // Nút Duyệt / Từ chối bấm lúc app chạy nền được isolate nền lưu lại;
      // quay lại app thì gửi ngay, không đợi khởi động lại.
      if (_approvalActionSubscription != null) {
        unawaited(_drainBackgroundApprovalActions());
      }
      _drainMessageOutbox(workspaceId);
      return;
    }

    // Push notifications remain the background delivery path. Keeping these
    // timers alive wastes battery and previously changed an away user back to
    // online on the next presence heartbeat.
    _presenceTimer?.cancel();
    _incomingCallPollTimer?.cancel();
    _pauseMessageOutboxRetry();
    final presence = switch (state) {
      AppLifecycleState.detached => ConversationPresence.offline,
      _ => ConversationPresence.away,
    };
    unawaited(_setPresence(workspaceId, presence));
  }

  @override
  Widget build(BuildContext context) {
    final workspaceState = ref.watch(workspaceControllerProvider);
    final activeWorkspace = workspaceState.activeWorkspace;
    final organization = ref.watch(activeServerDiscoveryProvider);

    if (workspaceState.isLoading && activeWorkspace == null) {
      return const Scaffold(
        body: SafeArea(
          child: WebTuiLoadingState(message: 'Đang tải workspace...'),
        ),
      );
    }

    if (activeWorkspace == null) {
      return Scaffold(
        appBar: AppBar(title: Text(organization?.name ?? 'Tổ chức')),
        body: const SafeArea(
          child: WebTuiEmptyState(
            title: 'Chưa có workspace',
            message:
                'Tài khoản này chưa được gắn workspace. Hãy liên hệ quản trị viên.',
            icon: Icons.business_rounded,
          ),
        ),
        bottomNavigationBar: Padding(
          padding: const EdgeInsets.all(WebTuiSpacing.lg),
          child: FilledButton.icon(
            onPressed: () =>
                ref.read(workspaceControllerProvider.notifier).load(),
            icon: const Icon(Icons.business_rounded),
            label: const Text('Tải lại workspace'),
          ),
        ),
      );
    }

    if (ref.read(legalAcceptanceWorkspaceScopeProvider) != activeWorkspace.id) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ref.read(legalAcceptanceWorkspaceScopeProvider.notifier).state =
              activeWorkspace.id;
        }
      });
    }

    if (_visitedWorkspaceId != activeWorkspace.id ||
        _visitedWorkspaceGeneration != workspaceState.generation) {
      _visitedWorkspaceId = activeWorkspace.id;
      _visitedWorkspaceGeneration = workspaceState.generation;
      _visitedTabs = {_tabIndex};
    }

    if (_pushRegisteredWorkspaceId != activeWorkspace.id) {
      _pushRegistrationRetryTimer?.cancel();
      _pushRegisteredWorkspaceId = activeWorkspace.id;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        unawaited(_registerPushWorkspace(activeWorkspace.id));
        _listenPushTargets();
        _listenIncomingCalls(activeWorkspace.id);
      });
    }

    if (_presenceWorkspaceId != activeWorkspace.id) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _activatePresence(activeWorkspace.id);
        }
      });
    }
    if (_syncWorkspaceId != activeWorkspace.id) {
      _syncWorkspaceId = activeWorkspace.id;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          unawaited(_runWorkspaceCatchUp(activeWorkspace.id));
          // Mở app: gửi lại tin chờ của mọi hội thoại, không đợi mở đúng phòng.
          _drainMessageOutbox(activeWorkspace.id);
        }
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _ensureShareIntentListener(activeWorkspace.id);
        _ensureQuickReplyListener(activeWorkspace.id);
        _ensureApprovalActionListener(activeWorkspace.id);
      }
    });
    final notificationState = ref.watch(
      notificationCenterControllerProvider(activeWorkspace.id),
    );

    return KeyedSubtree(
      key: ValueKey('workspace-shell-${workspaceState.generation}'),
      child: WebTuiMobileScaffold(
        title: organization == null
            ? _titles[_tabIndex]
            : '${organization.name} · ${_titles[_tabIndex]}',
        selectedTab: _tabIndex,
        onTabSelected: (index) {
          if (index == _tabIndex) return;
          setState(() {
            _tabIndex = index;
            _visitedTabs.add(index);
          });
        },
        leading: IconButton(
          tooltip: 'Hồ sơ cá nhân',
          onPressed: () => context.push('/profile'),
          icon: _OrganizationMark(
            imageUrl: organization?.logoUrl,
            name: organization?.name ?? activeWorkspace.name,
          ),
        ),
        actions: [
          _NotificationBellButton(
            unreadCount: notificationState.unreadCount,
            onPressed: () => context.push(
              '/notifications?workspaceId=${activeWorkspace.id}',
            ),
          ),
          if (_tabIndex == 0)
            IconButton(
              tooltip: 'Tin nhắn mới hoặc tạo nhóm',
              onPressed: _showComposeOptions,
              icon: const Icon(CupertinoIcons.square_pencil),
            ),
        ],
        body: Column(
          children: [
            if (_networkDegraded)
              _NetworkQualityBanner(
                onRetry: () => unawaited(
                  _runWorkspaceCatchUp(activeWorkspace.id, force: true),
                ),
              ),
            Expanded(
              // Keep a tab mounted after its first visit. Switching tabs now
              // paints immediately and no longer disposes its controller/cache.
              child: IndexedStack(
                index: _tabIndex,
                children: [
                  if (_visitedTabs.contains(0))
                    MessagesHomeView(workspaceId: activeWorkspace.id)
                  else
                    const SizedBox.shrink(),
                  if (_visitedTabs.contains(1))
                    ContactsHomeView(workspaceId: activeWorkspace.id)
                  else
                    const SizedBox.shrink(),
                  if (_visitedTabs.contains(2))
                    WorkspaceToolsScreen(workspaceId: activeWorkspace.id)
                  else
                    const SizedBox.shrink(),
                  if (_visitedTabs.contains(3))
                    SettingsTab(
                      workspaceName: activeWorkspace.name,
                      organizationLogoUrl: organization?.logoUrl,
                      notificationEnabled: _notificationEnabled,
                      compactMode: _compactMode,
                      soundLevel: _soundLevel,
                      textScalePreview: _textScalePreview,
                      onProfileTap: () => context.push('/profile'),
                      onAdvancedTap: () => context.push('/settings'),
                      onPrivacyTap: () => context.push('/privacy'),
                      // Luôn mở được danh sách workspace (kể cả khi chỉ có 1:
                      // xem workspace đang dùng, bấm Tải lại khi vừa được mời
                      // thêm); chữ "Chuyển workspace" chỉ khi có từ 2 (2.4).
                      canSwitchWorkspace: workspaceState.canSwitchWorkspace,
                      onWorkspaceTap: () => context.push('/workspaces'),
                      // Máy chủ cũ không trả capability → ẩn (2.2).
                      onQrLoginTap: organization?.capabilities.qrLogin == true
                          ? () => context.push('/qr-login')
                          : null,
                      onLogoutTap: () async {
                        try {
                          await ref
                              .read(pushNotificationServiceProvider)
                              .unregister();
                        } on Object {
                          // Logout must still clear the local session when push cleanup fails.
                        }
                        await ref.read(logoutUseCaseProvider).execute();
                        ref.invalidate(authAccessTokenProvider);
                        if (context.mounted) {
                          context.go('/login');
                        }
                      },
                      onNotificationChanged: (value) {
                        setState(() => _notificationEnabled = value);
                      },
                      onCompactChanged: (value) =>
                          setState(() => _compactMode = value),
                      onSoundChanged: (value) =>
                          setState(() => _soundLevel = value),
                      onTextScaleChanged: (value) {
                        setState(() => _textScalePreview = value);
                      },
                    )
                  else
                    const SizedBox.shrink(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _ensureShareIntentListener(String workspaceId) {
    if (_shareIntentWorkspaceId == workspaceId &&
        _shareIntentSubscription != null) {
      return;
    }
    _shareIntentWorkspaceId = workspaceId;
    unawaited(_shareIntentSubscription?.cancel());
    final service = ref.read(chatShareIntentServiceProvider);
    unawaited(service.start());
    _shareIntentSubscription = service.payloads.listen((payload) {
      if (!mounted || _shareIntentWorkspaceId != workspaceId) {
        return;
      }
      unawaited(_handleChatSharePayload(workspaceId, payload));
    });
  }

  Future<void> _handleChatSharePayload(
    String workspaceId,
    ChatSharePayload payload,
  ) async {
    if (payload.isEmpty) {
      return;
    }
    final result = await ref
        .read(loadConversationHomeUseCaseProvider)
        .execute(workspaceId: workspaceId);
    if (!mounted || _shareIntentWorkspaceId != workspaceId) {
      return;
    }
    final data = result.valueOrNull;
    if (data == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.failureOrNull?.message ??
                'Chưa thể tải danh sách cuộc trò chuyện.',
          ),
        ),
      );
      return;
    }
    final targets = _shareTargets(data);
    if (targets.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chưa có cuộc trò chuyện để gửi vào.')),
      );
      return;
    }

    final selected = await showModalBottomSheet<ConversationSummary>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) =>
          _ShareTargetPickerSheet(payload: payload, targets: targets),
    );
    if (!mounted || selected == null) {
      return;
    }
    ref
        .read(pendingChatShareProvider.notifier)
        .put(
          workspaceId: workspaceId,
          channelId: selected.channelId,
          payload: payload,
        );
    context.push(_conversationLocation(selected), extra: selected);
  }

  List<ConversationSummary> _shareTargets(ConversationHomeData data) {
    final byChannelId = <String, ConversationSummary>{};
    for (final item in data.conversations) {
      final channelId = item.channelId.trim();
      if (channelId.isNotEmpty) {
        byChannelId[channelId] = item;
      }
    }
    for (final item in data.channels) {
      final channelId = item.channelId.trim();
      if (channelId.isNotEmpty && item.isMember) {
        byChannelId[channelId] = item;
      }
    }
    final targets = byChannelId.values.toList(growable: false);
    targets.sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
    return targets;
  }

  String _conversationLocation(ConversationSummary conversation) {
    return Uri(
      path: '/conversations/${conversation.channelId}',
      queryParameters: {
        'workspaceId': conversation.workspaceId,
        'title': conversation.title,
        if (conversation.avatarUrl?.trim().isNotEmpty == true)
          'avatarUrl': conversation.avatarUrl!.trim(),
        if (conversation.peerUserId?.trim().isNotEmpty == true)
          'peerUserId': conversation.peerUserId!.trim(),
        if (conversation.participantIds.isNotEmpty)
          'participantIds': conversation.participantIds.join(','),
      },
    ).toString();
  }

  void _ensureQuickReplyListener(String workspaceId) {
    if (_quickReplyWorkspaceId == workspaceId &&
        _quickReplySubscription != null) {
      return;
    }
    _quickReplyWorkspaceId = workspaceId;
    unawaited(_quickReplySubscription?.cancel());
    _quickReplySubscription = ScopedLocalNotificationService
        .instance
        .quickReplies
        .listen((reply) {
          if (!mounted || _quickReplyWorkspaceId != workspaceId) {
            return;
          }
          unawaited(_sendQuickReply(workspaceId, reply));
        });
    unawaited(_drainBackgroundQuickReplies(workspaceId));
  }

  void _ensureApprovalActionListener(String workspaceId) {
    if (_approvalActionWorkspaceId == workspaceId &&
        _approvalActionSubscription != null) {
      return;
    }
    _approvalActionWorkspaceId = workspaceId;
    unawaited(_approvalActionSubscription?.cancel());
    _approvalActionSubscription = ScopedLocalNotificationService
        .instance
        .approvalActions
        .listen((action) {
          if (!mounted) return;
          unawaited(_decideFromNotification([action]));
        });
    unawaited(_drainBackgroundApprovalActions());
  }

  /// Lấy quyết định isolate nền đã lưu rồi gửi. Lượt đang chạy thì dùng lại,
  /// tránh hai lượt cùng đọc kho và gửi trùng. Bộ gửi tạo trước khi lấy ra
  /// khỏi kho nên màn hình đóng giữa chừng cũng không làm mất quyết định.
  Future<void> _drainBackgroundApprovalActions() {
    if (!mounted) return Future.value();
    final send = _approvalSender();
    return _approvalDrain ??= () async {
      try {
        final actions = await ScopedLocalNotificationService.instance
            .drainBackgroundApprovalActions();
        if (actions.isNotEmpty) await send(actions);
      } finally {
        _approvalDrain = null;
      }
    }();
  }

  Future<void> _decideFromNotification(
    List<ScopedNotificationApprovalAction> actions,
  ) {
    if (!mounted) return Future.value();
    return _approvalSender()(actions);
  }

  /// Bộ gửi quyết định, đọc provider ngay lúc gọi (khi màn còn mở).
  Future<void> Function(List<ScopedNotificationApprovalAction>)
  _approvalSender() {
    final handler = ApprovalNotificationActionHandler(
      decide: ref.read(decideApprovalRequestUseCaseProvider),
      report: ({required approvalId, required title, required body}) {
        return ScopedLocalNotificationService.instance.showApprovalResult(
          approvalId: approvalId,
          title: title,
          body: body,
        );
      },
    );
    final activeInstanceId = ref.read(activeInstanceScopeProvider).instanceId;
    return (actions) async {
      await handler.handleAll([
        for (final action in actions)
          (
            instanceId: action.instanceId,
            decidedAt: action.decidedAt,
            workspaceId: action.workspaceId,
            approvalId: action.approvalId,
            approve: action.approve,
          ),
      ], activeInstanceId: activeInstanceId);
      if (mounted) ref.invalidate(approvalListControllerProvider);
    };
  }

  Future<void> _drainBackgroundQuickReplies(String workspaceId) async {
    final replies = await ScopedLocalNotificationService.instance
        .drainBackgroundQuickReplies();
    if (!mounted || _quickReplyWorkspaceId != workspaceId) {
      return;
    }
    for (final reply in replies) {
      await _sendQuickReply(workspaceId, reply);
    }
  }

  Future<void> _sendQuickReply(
    String activeWorkspaceId,
    ScopedNotificationQuickReply reply,
  ) async {
    if (reply.workspaceId != activeWorkspaceId) {
      return;
    }
    final result = await ref
        .read(sendMessageUseCaseProvider)
        .execute(
          workspaceId: reply.workspaceId,
          channelId: reply.channelId,
          body: reply.body,
        );
    if (!mounted || _quickReplyWorkspaceId != activeWorkspaceId) {
      return;
    }
    if (result.isSuccess) {
      ref.invalidate(conversationHomeControllerProvider(activeWorkspaceId));
      ref.invalidate(notificationCenterControllerProvider(activeWorkspaceId));
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result.failureOrNull?.message ?? 'Chưa gửi được trả lời nhanh.',
        ),
      ),
    );
  }

  Future<void> _registerPushWorkspace(String workspaceId) async {
    try {
      await ref
          .read(pushNotificationServiceProvider)
          .registerForWorkspace(workspaceId);
    } on Object {
      if (!mounted || _pushRegisteredWorkspaceId != workspaceId) return;
      _pushRegistrationRetryTimer?.cancel();
      _pushRegistrationRetryTimer = Timer(const Duration(seconds: 5), () {
        if (!mounted || _pushRegisteredWorkspaceId != workspaceId) return;
        setState(() => _pushRegisteredWorkspaceId = null);
      });
    }
  }

  void _activatePresence(String workspaceId) {
    _presenceWorkspaceId = workspaceId;
    _presenceTimer?.cancel();
    unawaited(_setPresence(workspaceId, ConversationPresence.online));
    _presenceTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      unawaited(_setPresence(workspaceId, ConversationPresence.online));
    });
  }

  Future<void> _setPresence(
    String workspaceId,
    ConversationPresence status,
  ) async {
    try {
      await ref
          .read(updatePresenceUseCaseProvider)
          .execute(workspaceId: workspaceId, status: status);
    } on Object {
      // Presence must never block navigation or messaging.
    }
  }

  /// Nút soạn ở hộp thư gộp: nhắn riêng (chọn người ở tab Bạn bè) hoặc tạo
  /// nhóm / kênh mới.
  Future<void> _showComposeOptions() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(CupertinoIcons.person),
              title: const Text('Tin nhắn mới'),
              subtitle: const Text('Chọn một người trong workspace'),
              onTap: () => Navigator.of(sheetContext).pop('direct'),
            ),
            ListTile(
              leading: const Icon(CupertinoIcons.person_3),
              title: const Text('Tạo nhóm / kênh'),
              subtitle: const Text('Trò chuyện cùng nhiều người'),
              onTap: () => Navigator.of(sheetContext).pop('group'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;
    if (choice == 'group') {
      unawaited(context.push('/channels/new'));
      return;
    }
    setState(() {
      _tabIndex = 1;
      _visitedTabs.add(1);
    });
  }

  Future<void> _runWorkspaceCatchUp(
    String workspaceId, {
    bool force = false,
  }) async {
    if (_syncInFlight && !force) {
      return;
    }
    _syncInFlight = true;
    try {
      final result = await ref
          .read(catchUpWorkspaceSyncUseCaseProvider)
          .execute(
            workspaceId: workspaceId,
            onResetRequired: (_) => _reloadAfterSyncReset(workspaceId),
          );
      final page = result.valueOrNull;
      if (!mounted) {
        return;
      }
      if (page == null) {
        setState(() => _networkDegraded = true);
        return;
      }
      if (_networkDegraded) {
        setState(() => _networkDegraded = false);
        // Có mạng lại: gửi tin còn nằm trong hàng chờ.
        _drainMessageOutbox(workspaceId);
      }
      if (page.events.isEmpty) {
        return;
      }
      ref.invalidate(notificationCenterControllerProvider(workspaceId));
      ref.invalidate(conversationHomeControllerProvider(workspaceId));
    } on Object {
      if (mounted) {
        setState(() => _networkDegraded = true);
      }
      return;
    } finally {
      _syncInFlight = false;
    }
  }

  /// Máy chủ báo con trỏ đồng bộ đã bị dọn (`reset_required`): tải lại danh
  /// sách hội thoại, báo phòng đang mở tải lại tin mới nhất. Tải lại lỗi thì
  /// ném lỗi để use case giữ con trỏ cũ (lần sau đặt lại tiếp).
  Future<void> _reloadAfterSyncReset(String workspaceId) async {
    if (!mounted) {
      throw StateError('Màn hình đã đóng trước khi tải lại.');
    }
    final reloaded = await ref
        .read(conversationHomeControllerProvider(workspaceId).notifier)
        .syncSilently();
    if (!mounted) {
      throw StateError('Màn hình đã đóng trước khi tải lại.');
    }
    ref.invalidate(notificationCenterControllerProvider(workspaceId));
    ref.read(workspaceRefreshSignalProvider).notifyReset(workspaceId);
    if (!reloaded) {
      throw StateError('Không tải lại được danh sách hội thoại.');
    }
  }

  void _drainMessageOutbox(String workspaceId) {
    try {
      unawaited(
        ref.read(messageOutboxDispatcherProvider).drainWorkspace(workspaceId),
      );
    } on Object {
      // Hàng chờ vẫn được gửi lại ở lần kích hoạt sau.
    }
  }

  void _pauseMessageOutboxRetry() {
    try {
      ref.read(messageOutboxDispatcherProvider).pauseAutoRetry();
    } on Object {
      // Provider có thể đã bị huỷ khi đổi máy chủ.
    }
  }

  /// Mã máy đã đăng ký push (theo instance đang dùng), nhớ tạm trong màn.
  Future<String?> _localCallDeviceId() async {
    final String scopeId;
    try {
      scopeId = ref.read(activeInstanceScopeProvider).storageId;
    } on Object {
      return null;
    }
    final cached = _callDeviceId;
    if (cached != null && cached.scopeId == scopeId) return cached.deviceId;
    final resolved = await ref
        .read(resolveCallDeviceIdUseCaseProvider)
        .execute();
    if (resolved != null) {
      _callDeviceId = (scopeId: scopeId, deviceId: resolved);
    }
    return resolved;
  }

  void _listenPushTargets() {
    final service = ref.read(pushNotificationServiceProvider);
    _nativeCallSubscription ??= NativeIncomingCallService.actions.listen((
      action,
    ) {
      if (!mounted) {
        return;
      }
      unawaited(_handleNativeIncomingCallAction(action));
    });
    _notificationOpenSubscription ??= service.openedTargets.listen((target) {
      if (!mounted) {
        return;
      }
      if (target.isDeviceApprovalRequest) {
        _openDeviceApprovalReview(target.sessionId);
      } else if (_handleGroupCallTarget(target)) {
        // Gọi nhóm: chuông / tắt chuông do bộ điều phối xử lý; mở từ thông
        // báo thì hỏi lại máy chủ các cuộc còn đổ chuông.
        unawaited(_groupCalls.restoreRinging(target.workspaceId));
      } else if (target.isIncomingCall) {
        unawaited(_showIncomingCall(target));
      } else {
        _openNotificationTarget(target);
      }
    });
    _foregroundNotificationSubscription ??= service.foregroundTargets.listen((
      target,
    ) {
      if (!mounted) {
        return;
      }
      ref.invalidate(notificationCenterControllerProvider(target.workspaceId));
      if (target.isApprovalUpdate) {
        // Trạng thái yêu cầu của mình đã đổi: tải lại danh sách, không làm phiền.
        ref.invalidate(approvalListControllerProvider);
        return;
      }
      if (target.isDeviceApprovalRequest) {
        _openDeviceApprovalReview(target.sessionId);
        return;
      }
      if (_handleGroupCallTarget(target)) return;
      if (target.isIncomingCall) {
        unawaited(_showIncomingCall(target));
        return;
      }
      final location = _locationForNotificationTarget(target);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Có thông báo mới'),
          action: location == null
              ? null
              : SnackBarAction(
                  label: 'Mở',
                  onPressed: () => context.push(location),
                ),
        ),
      );
    });
  }

  void _openNotificationTarget(NotificationTarget target) {
    final location = _locationForNotificationTarget(target);
    if (location != null) {
      context.push(location);
    }
  }

  Future<void> _showIncomingCall(NotificationTarget target) async {
    final callId = target.callId?.trim();
    if (!mounted || callId == null || callId.isEmpty) {
      return;
    }
    if (_activeIncomingCallId == callId) {
      return;
    }
    _activeIncomingCallId = callId;
    try {
      final initialResult = await ref
          .read(getCallUseCaseProvider)
          .execute(workspaceId: target.workspaceId, callId: callId);
      final initialCall = initialResult.valueOrNull;
      if (!mounted ||
          initialCall == null ||
          initialCall.status != CallStatus.ringing) {
        await NativeIncomingCallService.endCall(callId, remoteEnded: true);
        return;
      }
      final dismiss = ValueNotifier<bool>(false);
      _ringingDialogCallId = callId;
      _ringingDialogDismiss = dismiss;
      final _IncomingCallDialogResult? choice;
      try {
        choice = await showDialog<_IncomingCallDialogResult>(
          context: context,
          useRootNavigator: true,
          barrierDismissible: false,
          builder: (dialogContext) => _IncomingCallDialog(
            callerName: target.callerName ?? 'Cuộc gọi đến',
            mode: initialCall.mode,
            dismissSignal: dismiss,
            checkStatus: () async {
              final result = await ref
                  .read(getCallUseCaseProvider)
                  .execute(workspaceId: target.workspaceId, callId: callId);
              return result.valueOrNull?.status;
            },
          ),
        );
      } finally {
        // Không dispose `dismiss`: hộp thoại còn gỡ listener khi hiệu ứng đóng
        // chạy xong (sau khi future trả về).
        if (identical(_ringingDialogDismiss, dismiss)) {
          _ringingDialogCallId = null;
          _ringingDialogDismiss = null;
        }
      }
      switch (choice) {
        case _IncomingCallDialogResult.accepted:
          break;
        case _IncomingCallDialogResult.declined:
          await NativeIncomingCallService.endCall(callId);
          await ref
              .read(rejectCallUseCaseProvider)
              .execute(
                workspaceId: target.workspaceId,
                callId: callId,
                reason: 'declined',
              );
          return;
        case _IncomingCallDialogResult.timedOut:
          // Hết giờ đổ chuông trong app: tắt cả chuông gốc, báo máy chủ "nhỡ
          // máy" nếu cuộc gọi vẫn đang đổ chuông (như hết giờ ở CallKit).
          await NativeIncomingCallService.endCall(callId, remoteEnded: true);
          if (!mounted) return;
          final current =
              (await ref
                      .read(getCallUseCaseProvider)
                      .execute(workspaceId: target.workspaceId, callId: callId))
                  .valueOrNull;
          if (mounted && current?.status == CallStatus.ringing) {
            await ref
                .read(rejectCallUseCaseProvider)
                .execute(
                  workspaceId: target.workspaceId,
                  callId: callId,
                  reason: 'timeout',
                );
          }
          return;
        case _IncomingCallDialogResult.closedRemotely:
        case null:
          // Đã nhận ở máy khác / người gọi huỷ / máy chủ đổi trạng thái: hộp
          // thoại tự đóng thì vẫn tắt chuông gốc, không gửi gì thêm.
          await NativeIncomingCallService.endCall(callId, remoteEnded: true);
          return;
      }
      if (!mounted) {
        return;
      }
      await Navigator.of(context, rootNavigator: true).push<void>(
        MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (_) => WebRtcCallScreen(
            workspaceId: initialCall.workspaceId,
            channelId: initialCall.channelId,
            callId: initialCall.id,
            title: target.callerName ?? 'Cuộc gọi đến',
            mode: initialCall.mode,
            incoming: true,
            onConnected: () =>
                NativeIncomingCallService.markConnected(initialCall.id),
            onLeave: () async {
              await NativeIncomingCallService.endCall(initialCall.id);
              ref.invalidate(chatRoomControllerProvider);
              ref.invalidate(
                conversationHomeControllerProvider(initialCall.workspaceId),
              );
              ref.invalidate(
                notificationCenterControllerProvider(initialCall.workspaceId),
              );
            },
          ),
        ),
      );
    } finally {
      if (_activeIncomingCallId == callId) {
        _activeIncomingCallId = null;
      }
    }
  }

  Future<void> _handleNativeIncomingCallAction(
    NativeIncomingCallAction action,
  ) async {
    if (!_nativeCallActionsInFlight.add(action.actionId)) return;
    try {
      final activeInstance = ref
          .read(activeServerDiscoveryProvider)
          ?.instanceScope;
      if (activeInstance == null ||
          !nativeCallActionMatchesInstance(
            action: action,
            activeInstance: activeInstance,
          )) {
        final callId = action.target.callId?.trim();
        if (callId != null && callId.isNotEmpty) {
          await NativeIncomingCallService.endCall(callId);
        }
        await NativeIncomingCallService.acknowledge(action);
        return;
      }
      if (action.target.isGroupCall) {
        if (await _handleNativeGroupCallAction(action)) {
          await NativeIncomingCallService.acknowledge(action);
        } else {
          NativeIncomingCallService.retryLater(action);
        }
        return;
      }
      final handled = switch (action.type) {
        NativeIncomingCallActionType.accept => _acceptNativeIncomingCall(
          action.target,
        ),
        NativeIncomingCallActionType.decline => _rejectNativeIncomingCall(
          action.target,
          reason: 'declined',
        ),
        NativeIncomingCallActionType.timeout => _rejectNativeIncomingCall(
          action.target,
          reason: 'timeout',
        ),
        NativeIncomingCallActionType.ended => _endNativeIncomingCall(
          action.target,
        ),
      };
      if (await handled) {
        await NativeIncomingCallService.acknowledge(action);
      } else {
        NativeIncomingCallService.retryLater(action);
      }
    } on Object {
      // Keep the native action durable. It will replay after connectivity,
      // authentication, or the selected workspace becomes ready again.
      NativeIncomingCallService.retryLater(action);
    } finally {
      _nativeCallActionsInFlight.remove(action.actionId);
    }
  }

  Future<bool> _acceptNativeIncomingCall(NotificationTarget target) async {
    final callId = target.callId?.trim();
    if (!mounted || callId == null || callId.isEmpty) {
      return false;
    }
    if (_activeIncomingCallId == callId) {
      return false;
    }
    _activeIncomingCallId = callId;
    try {
      final currentResult = await ref
          .read(getCallUseCaseProvider)
          .execute(workspaceId: target.workspaceId, callId: callId);
      final currentCall = currentResult.valueOrNull;
      if (currentCall == null) {
        if (currentResult.failureOrNull?.kind == FailureKind.notFound) {
          await NativeIncomingCallService.endCall(callId);
          return true;
        }
        return false;
      }
      if (currentCall.isTerminal) {
        await NativeIncomingCallService.endCall(callId);
        return true;
      }
      if (nativeCallActionIsStaleForOtherDevice(
        current: currentCall,
        localDeviceId: await _localCallDeviceId(),
      )) {
        // Đã nhận ở máy khác: chỉ tắt giao diện gốc, không mở màn gọi.
        await NativeIncomingCallService.endCall(callId, remoteEnded: true);
        return true;
      }

      if (!mounted) {
        return false;
      }
      await Navigator.of(context, rootNavigator: true).push<void>(
        MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (_) => WebRtcCallScreen(
            workspaceId: currentCall.workspaceId,
            channelId: currentCall.channelId,
            callId: currentCall.id,
            title: target.callerName ?? 'Cuộc gọi đến',
            mode: currentCall.mode,
            incoming: true,
            onConnected: () =>
                NativeIncomingCallService.markConnected(currentCall.id),
            onLeave: () async {
              await NativeIncomingCallService.endCall(currentCall.id);
              ref.invalidate(chatRoomControllerProvider);
              ref.invalidate(
                conversationHomeControllerProvider(currentCall.workspaceId),
              );
              ref.invalidate(
                notificationCenterControllerProvider(currentCall.workspaceId),
              );
            },
          ),
        ),
      );
      return true;
    } finally {
      if (_activeIncomingCallId == callId) {
        _activeIncomingCallId = null;
      }
    }
  }

  Future<bool> _rejectNativeIncomingCall(
    NotificationTarget target, {
    required String reason,
  }) async {
    final callId = target.callId?.trim();
    if (callId == null || callId.isEmpty) {
      return false;
    }
    await NativeIncomingCallService.endCall(callId);
    final currentResult = await ref
        .read(getCallUseCaseProvider)
        .execute(workspaceId: target.workspaceId, callId: callId);
    final current = currentResult.valueOrNull;
    if (current == null) {
      return currentResult.failureOrNull?.kind == FailureKind.notFound;
    }
    if (current.isTerminal) return true;
    if (nativeCallActionIsStaleForOtherDevice(
      current: current,
      localDeviceId: await _localCallDeviceId(),
    )) {
      return true;
    }
    if (nativeRejectActionIsStaleAfterAcceptance(
      reason: reason,
      currentStatus: current.status,
    )) {
      return true;
    }
    final result = current.status == CallStatus.ringing
        ? await ref
              .read(rejectCallUseCaseProvider)
              .execute(
                workspaceId: target.workspaceId,
                callId: callId,
                reason: reason,
              )
        : await ref
              .read(endCallUseCaseProvider)
              .execute(
                workspaceId: target.workspaceId,
                callId: callId,
                currentStatus: current.status,
                reason: reason,
              );
    if (result.isSuccess) return true;
    return _isCallConfirmedTerminal(target.workspaceId, callId);
  }

  /// Mở màn duyệt thiết bị (từ WS `DeviceApprovalRequested` hoặc push
  /// `device_approval_requested`). Màn tự tải dữ liệu từ máy chủ, không tin
  /// payload; mỗi phiên chỉ mở một lần.
  void _openDeviceApprovalReview(String? sessionId) {
    final id = sessionId?.trim() ?? '';
    if (!mounted ||
        !RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(id) ||
        !_openedDeviceApprovals.add(id)) {
      return;
    }
    ref.invalidate(pendingDeviceApprovalsProvider);
    unawaited(context.push(deviceApprovalReviewLocation(id)));
  }

  void _listenIncomingCalls(String workspaceId) {
    unawaited(_incomingCallRealtimeSubscription?.cancel());
    _incomingCallRealtimeSubscription = ref
        .read(incomingCallRealtimeRepositoryProvider)
        .subscribeToUser(workspaceId: workspaceId)
        .listen((event) {
          if (!mounted) {
            return;
          }
          if (event.type == ConversationRealtimeEventType.sessionRevoked) {
            // Máy chủ chỉ gửi tới kết nối của đúng phiên bị thu hồi: xoá dữ
            // liệu cục bộ rồi về đăng nhập (app lắng nghe bộ điều phối phiên).
            unawaited(
              ref
                  .read(sessionTerminationCoordinatorProvider)
                  .endSession(
                    SessionEndedNotice.revokedByServer(
                      event.payload['reason']?.toString(),
                    ),
                    revokedSessionId: event.payload['session_id']?.toString(),
                  ),
            );
            return;
          }
          if (event.type ==
              ConversationRealtimeEventType.deviceApprovalRequested) {
            _openDeviceApprovalReview(event.payload['session_id']?.toString());
            return;
          }
          if (event.workspaceId != workspaceId) {
            return;
          }
          if (event.type == ConversationRealtimeEventType.reconnected) {
            // Mỗi phòng đang mở cũng nhận sự kiện này; danh sách chỉ tải 1 lần.
            if (event.channelId.isNotEmpty) return;
            final home = conversationHomeControllerProvider(workspaceId);
            unawaited(ref.read(home.notifier).syncSilently());
            // WebSocket nối lại = có mạng lại: gửi tin chờ của mọi hội thoại.
            try {
              ref
                  .read(messageOutboxDispatcherProvider)
                  .handleRealtimeEvent(event);
            } on Object {
              // Hàng chờ vẫn được gửi lại ở lần kích hoạt sau.
            }
            return;
          }
          if (event.type == ConversationRealtimeEventType.resyncRequired) {
            if (event.channelId.isNotEmpty) return;
            // Máy chủ sắp ngắt vì máy này nhận chậm: đồng bộ bù ngay; kho
            // realtime tự nối lại và các phòng tải lại khi nhận `reconnected`.
            unawaited(_runWorkspaceCatchUp(workspaceId, force: true));
            return;
          }
          if (event.isContactEvent) {
            ref.invalidate(conversationHomeControllerProvider(workspaceId));
            ref.invalidate(notificationCenterControllerProvider(workspaceId));
            return;
          }
          if (_handleGroupCallEvent(event)) {
            return;
          }
          if (_handleRemoteCallChange(event)) {
            return;
          }
          if (event.type != ConversationRealtimeEventType.callInvited ||
              event.callId?.trim().isNotEmpty != true) {
            return;
          }
          final target = NotificationTarget.fromPayload(
            workspaceId: event.workspaceId,
            channelId: event.channelId,
            data: {
              'workspace_id': event.workspaceId,
              'channel_id': event.channelId,
              'call_id': event.callId,
              'mode': event.callMode?.name ?? 'audio',
              'status': 'ringing',
              'target_type': 'call',
              'event_type': 'call_invite',
            },
          );
          unawaited(_showIncomingCall(target));
        });
    _startIncomingCallPolling(workspaceId);
    unawaited(_groupCalls.restoreRinging(workspaceId));
  }

  GroupCallCoordinator get _groupCalls {
    return _groupCallCoordinator ??= GroupCallCoordinator(
      api: ref.read(meetingApiProvider),
      localDeviceId: _localCallDeviceId,
      presenter: ShellGroupCallPresenter(
        context: () => mounted ? context : null,
        api: ref.read(meetingApiProvider),
        launcher: ref.read(externalUrlLauncherProvider),
        endNativeRinging: (id) => NativeIncomingCallService.endCallIfActive(
          id,
          remoteEnded: true,
          incomingOnly: true,
        ),
        endNativeCall: NativeIncomingCallService.endCall,
      ),
    );
  }

  GroupCall _groupCallFromTarget(NotificationTarget target) {
    return GroupCall(
      id: target.groupCallId?.trim() ?? '',
      workspaceId: target.workspaceId,
      channelId: target.channelId?.trim() ?? '',
      meetingId: target.meetingId?.trim() ?? '',
      kind: target.callMode?.trim().toLowerCase() == 'video'
          ? 'video'
          : 'audio',
      status: GroupCallStatus.ringing,
      startedByName: target.callerName?.trim() ?? '',
      channelName: target.channelName?.trim() ?? '',
    );
  }

  /// Push `group_call_invite` / `group_call_cancel`. Trả `true` khi là gọi nhóm.
  bool _handleGroupCallTarget(NotificationTarget target) {
    if (target.isGroupCallInvite) {
      unawaited(_groupCalls.handleStarted(_groupCallFromTarget(target)));
      return true;
    }
    if (target.isGroupCallCancel) {
      unawaited(_groupCalls.handleStopped(target.groupCallId!));
      return true;
    }
    return false;
  }

  /// WS `GroupCallStarted` / `GroupCallRingStopped` / `GroupCallEnded`.
  bool _handleGroupCallEvent(ConversationRealtimeEvent event) {
    switch (event.type) {
      case ConversationRealtimeEventType.groupCallStarted:
        unawaited(_groupCalls.handleStarted(GroupCall.fromMap(event.payload)));
        return true;
      case ConversationRealtimeEventType.groupCallRingStopped:
        unawaited(
          _groupCalls.handleStopped(
            event.payload['group_call_id']?.toString() ?? '',
          ),
        );
        return true;
      case ConversationRealtimeEventType.groupCallEnded:
        unawaited(
          _groupCalls.handleStopped(GroupCall.fromMap(event.payload).id),
        );
        return true;
      default:
        return false;
    }
  }

  /// Hành động từ chuông gốc (CallKit / thông báo Android) của gọi nhóm. Trả
  /// `true` khi đã xử lý xong để xác nhận hành động; `false` để thử lại.
  Future<bool> _handleNativeGroupCallAction(
    NativeIncomingCallAction action,
  ) async {
    final target = action.target;
    if (!mounted || !target.isGroupCallInvite) return true;
    final call = _groupCallFromTarget(target);
    return switch (action.type) {
      NativeIncomingCallActionType.accept => _groupCalls.accept(call),
      NativeIncomingCallActionType.decline => _groupCalls.decline(call),
      // Hết giờ / kết thúc giao diện gốc: máy chủ tự dừng chuông, không báo gì.
      NativeIncomingCallActionType.timeout ||
      NativeIncomingCallActionType.ended => Future.value(true),
    };
  }

  /// Cuộc gọi đang đổ chuông trên máy này kết thúc vì lý do phía máy chủ:
  /// đã nhận ở máy khác (CallAccepted / CallAnsweredElsewhere mang mã máy khác
  /// máy này) hoặc người gọi huỷ / cuộc gọi kết thúc.
  bool _handleRemoteCallChange(ConversationRealtimeEvent event) {
    final callId = event.callId?.trim();
    if (callId == null || callId.isEmpty) return false;
    switch (event.type) {
      case ConversationRealtimeEventType.callAccepted ||
          ConversationRealtimeEventType.callAnsweredElsewhere:
        unawaited(_dismissIfAnsweredElsewhere(callId, event.answeredDeviceId));
        return true;
      case ConversationRealtimeEventType.callCancelled ||
          ConversationRealtimeEventType.callRejected ||
          ConversationRealtimeEventType.callEnded ||
          ConversationRealtimeEventType.callMissed:
        unawaited(_dismissRingingCall(callId));
        return true;
      default:
        return false;
    }
  }

  Future<void> _dismissIfAnsweredElsewhere(
    String callId,
    String? answeredDeviceId,
  ) async {
    final localDeviceId = await _localCallDeviceId();
    if (!mounted ||
        !callAnsweredOnAnotherDevice(
          answeredDeviceId: answeredDeviceId,
          localDeviceId: localDeviceId,
        )) {
      return;
    }
    await _dismissRingingCall(callId);
  }

  /// Tắt chuông (hộp thoại trong app + giao diện gốc) của [callId] mà không gửi
  /// reject / hangup. Chỉ đụng tới cuộc gọi đang thật sự đổ chuông trên máy.
  Future<void> _dismissRingingCall(String callId) async {
    if (_ringingDialogCallId == callId) {
      _ringingDialogDismiss?.value = true;
    }
    await NativeIncomingCallService.endCallIfActive(
      callId,
      remoteEnded: true,
      incomingOnly: true,
    );
  }

  void _startIncomingCallPolling(String workspaceId) {
    _incomingCallPollTimer?.cancel();
    _incomingCallPollTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      unawaited(_pollIncomingCall(workspaceId));
    });
    unawaited(_pollIncomingCall(workspaceId));
  }

  Future<void> _pollIncomingCall(String workspaceId) async {
    if (!mounted ||
        _incomingCallPollInFlight ||
        _presenceWorkspaceId != workspaceId) {
      return;
    }
    _incomingCallPollInFlight = true;
    try {
      final result = await ref
          .read(findIncomingCallUseCaseProvider)
          .execute(workspaceId: workspaceId);
      final call = result.valueOrNull;
      if (!mounted || call == null || call.status != CallStatus.ringing) {
        return;
      }
      final home = ref.read(conversationHomeControllerProvider(workspaceId));
      final caller = [
        ...home.contacts,
        ...home.workspaceMembers,
      ].where((item) => item.userId == call.initiatorUserId).firstOrNull;
      final target = NotificationTarget.fromPayload(
        workspaceId: call.workspaceId,
        channelId: call.channelId,
        data: {
          'workspace_id': call.workspaceId,
          'channel_id': call.channelId,
          'call_id': call.id,
          'mode': call.mode.name,
          'status': 'ringing',
          'target_type': 'call',
          'event_type': 'call_invite',
          if (caller != null) 'caller_name': caller.displayName,
        },
      );
      await _showIncomingCall(target);
    } on Object {
      // Push and WebSocket are still the primary paths. Polling keeps incoming
      // calls usable on emulators and devices without a working push runtime.
    } finally {
      _incomingCallPollInFlight = false;
    }
  }

  Future<bool> _endNativeIncomingCall(NotificationTarget target) async {
    final callId = target.callId?.trim();
    if (callId == null || callId.isEmpty) {
      return false;
    }
    await NativeIncomingCallService.endCall(callId);
    final currentResult = await ref
        .read(getCallUseCaseProvider)
        .execute(workspaceId: target.workspaceId, callId: callId);
    final current = currentResult.valueOrNull;
    if (current == null) {
      return currentResult.failureOrNull?.kind == FailureKind.notFound;
    }
    if (current.isTerminal) {
      return true;
    }
    // Đã nhận ở máy khác của chính người dùng: không gác máy hộ máy kia.
    if (nativeCallActionIsStaleForOtherDevice(
      current: current,
      localDeviceId: await _localCallDeviceId(),
    )) {
      return true;
    }
    if (current.status == CallStatus.ringing) {
      final result = await ref
          .read(rejectCallUseCaseProvider)
          .execute(
            workspaceId: target.workspaceId,
            callId: callId,
            reason: 'ended',
          );
      if (result.isSuccess) return true;
      return _isCallConfirmedTerminal(target.workspaceId, callId);
    }
    final result = await ref
        .read(endCallUseCaseProvider)
        .execute(
          workspaceId: target.workspaceId,
          callId: callId,
          currentStatus: current.status,
          reason: 'ended',
        );
    if (result.isSuccess) return true;
    return _isCallConfirmedTerminal(target.workspaceId, callId);
  }

  Future<bool> _isCallConfirmedTerminal(
    String workspaceId,
    String callId,
  ) async {
    final result = await ref
        .read(getCallUseCaseProvider)
        .execute(workspaceId: workspaceId, callId: callId);
    final call = result.valueOrNull;
    if (call != null) return call.isTerminal;
    return result.failureOrNull?.kind == FailureKind.notFound;
  }

  static const _titles = ['Tin nhắn', 'Bạn bè', 'Công việc', 'Cài đặt'];
}

class _ShareTargetPickerSheet extends StatefulWidget {
  const _ShareTargetPickerSheet({required this.payload, required this.targets});

  final ChatSharePayload payload;
  final List<ConversationSummary> targets;

  @override
  State<_ShareTargetPickerSheet> createState() =>
      _ShareTargetPickerSheetState();
}

class _ShareTargetPickerSheetState extends State<_ShareTargetPickerSheet> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final targets = _filteredTargets;
    return SafeArea(
      child: FractionallySizedBox(
        heightFactor: 0.86,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            WebTuiSpacing.lg,
            WebTuiSpacing.xs,
            WebTuiSpacing.lg,
            WebTuiSpacing.lg + media.viewInsets.bottom,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Gửi vào chat',
                style: WebTuiTypography.titleMedium.copyWith(
                  color: WebTuiColors.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: WebTuiSpacing.xs),
              Text(
                widget.payload.summary,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: WebTuiTypography.bodySmall.copyWith(
                  color: WebTuiColors.textSecondary,
                ),
              ),
              const SizedBox(height: WebTuiSpacing.md),
              TextField(
                controller: _searchController,
                onChanged: (value) => setState(() => _query = value),
                decoration: const InputDecoration(
                  prefixIcon: Icon(CupertinoIcons.search),
                  hintText: 'Tìm cuộc trò chuyện hoặc kênh',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: WebTuiSpacing.md),
              Expanded(
                child: targets.isEmpty
                    ? const WebTuiEmptyState(
                        title: 'Không tìm thấy',
                        message: 'Thử tìm bằng tên khác.',
                        icon: CupertinoIcons.chat_bubble_2,
                      )
                    : ListView.separated(
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        itemCount: targets.length,
                        separatorBuilder: (_, _) =>
                            const Divider(height: 1, indent: 56),
                        itemBuilder: (context, index) {
                          final target = targets[index];
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: WebTuiAvatar(
                              label: target.avatarLabel ?? target.title,
                              imageUrl: target.avatarUrl,
                              icon: target.kind == ConversationKind.channel
                                  ? CupertinoIcons.number
                                  : CupertinoIcons.person,
                            ),
                            title: Text(
                              target.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: WebTuiTypography.bodyMedium.copyWith(
                                color: WebTuiColors.textPrimary,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            subtitle: Text(
                              target.kind == ConversationKind.channel
                                  ? 'Kênh'
                                  : 'Tin nhắn',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: () => Navigator.of(context).pop(target),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<ConversationSummary> get _filteredTargets {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) {
      return widget.targets;
    }
    return widget.targets
        .where(
          (target) =>
              '${target.title} ${target.preview}'.toLowerCase().contains(query),
        )
        .toList(growable: false);
  }
}

class _OrganizationMark extends StatelessWidget {
  const _OrganizationMark({required this.name, this.imageUrl, this.size = 30});

  final String name;
  final String? imageUrl;
  final double size;

  double get _radius => size * 8 / 30;

  @override
  Widget build(BuildContext context) {
    final url = imageUrl?.trim();
    if (url != null && url.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(_radius),
        child: WebTuiBoundedNetworkImage(
          imageUrl: url,
          width: size,
          height: size,
          fit: BoxFit.contain,
          maxBytes: webTuiMaxBrandImageBytes,
          allowPublicRequest: true,
          semanticLabel: name,
          fallback: _fallback(),
        ),
      );
    }
    return _fallback();
  }

  Widget _fallback() {
    final normalized = name.trim();
    final initial = normalized.isEmpty ? 'O' : normalized.characters.first;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: WebTuiColors.primary,
        borderRadius: BorderRadius.circular(_radius),
      ),
      child: SizedBox.square(
        dimension: size,
        child: Center(
          child: Text(
            initial.toUpperCase(),
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: size * 0.47,
            ),
          ),
        ),
      ),
    );
  }
}

/// Lý do hộp thoại cuộc gọi đến đóng.
enum _IncomingCallDialogResult {
  accepted,
  declined,

  /// Hết 30 giây đổ chuông trong app.
  timedOut,

  /// Máy chủ đổi trạng thái (đã nhận ở máy khác, người gọi huỷ...).
  closedRemotely,
}

class _IncomingCallDialog extends StatefulWidget {
  const _IncomingCallDialog({
    required this.callerName,
    required this.mode,
    required this.checkStatus,
    required this.dismissSignal,
  });

  final String callerName;
  final CallMode mode;
  final Future<CallStatus?> Function() checkStatus;

  /// Bật `true` khi máy chủ báo cuộc gọi đã được nhận ở máy khác / đã huỷ.
  final ValueListenable<bool> dismissSignal;

  @override
  State<_IncomingCallDialog> createState() => _IncomingCallDialogState();
}

class _IncomingCallDialogState extends State<_IncomingCallDialog> {
  // Nhạc chuông lặp (kêu cả khi gạt im lặng) thay cho âm báo hệ thống nhỏ.
  final CallTonePlayer _ringtone = CallTonePlayer.ringtone();
  Timer? _timer;
  int _remainingSeconds = 30;
  bool _checking = false;

  bool _closed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_ringtone.start());
    unawaited(HapticFeedback.vibrate());
    widget.dismissSignal.addListener(_onDismissSignal);
    if (widget.dismissSignal.value) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _onDismissSignal());
    }
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _closed) {
        return;
      }
      setState(() => _remainingSeconds -= 1);
      if (_remainingSeconds % 2 == 0 && _remainingSeconds > 0) {
        unawaited(HapticFeedback.vibrate());
      }
      unawaited(_checkCall());
      if (_remainingSeconds <= 0) {
        _close(_IncomingCallDialogResult.timedOut);
      }
    });
  }

  @override
  void dispose() {
    widget.dismissSignal.removeListener(_onDismissSignal);
    _timer?.cancel();
    // Dừng chuông trước khi màn gọi bật micro / WebRTC.
    unawaited(_ringtone.stop());
    super.dispose();
  }

  void _onDismissSignal() {
    if (widget.dismissSignal.value) {
      _close(_IncomingCallDialogResult.closedRemotely);
    }
  }

  void _close(_IncomingCallDialogResult result) {
    if (!mounted || _closed) return;
    _closed = true;
    _timer?.cancel();
    unawaited(_ringtone.stop());
    Navigator.of(context).pop(result);
  }

  Future<void> _checkCall() async {
    if (_checking) {
      return;
    }
    _checking = true;
    try {
      final status = await widget.checkStatus();
      if (mounted && status != null && status != CallStatus.ringing) {
        _close(_IncomingCallDialogResult.closedRemotely);
      }
    } finally {
      _checking = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final video = widget.mode == CallMode.video;
    return PopScope(
      canPop: false,
      child: Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 28),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 34,
                backgroundColor: WebTuiColors.primary.withValues(alpha: 0.12),
                child: Icon(
                  video ? Icons.videocam_rounded : Icons.call_rounded,
                  size: 32,
                  color: WebTuiColors.primary,
                ),
              ),
              const SizedBox(height: WebTuiSpacing.md),
              Text(
                widget.callerName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: WebTuiTypography.titleMedium.copyWith(
                  color: WebTuiColors.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: WebTuiSpacing.xs),
              Text(
                video ? 'Cuộc gọi video đến' : 'Cuộc gọi thoại đến',
                style: WebTuiTypography.bodySmall.copyWith(
                  color: WebTuiColors.textSecondary,
                ),
              ),
              const SizedBox(height: 28),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _IncomingCallAction(
                    label: 'Từ chối',
                    icon: Icons.call_end_rounded,
                    color: WebTuiColors.danger,
                    onPressed: () => _close(_IncomingCallDialogResult.declined),
                  ),
                  _IncomingCallAction(
                    label: 'Nghe',
                    icon: video ? Icons.videocam_rounded : Icons.call_rounded,
                    color: const Color(0xFF16A34A),
                    onPressed: () => _close(_IncomingCallDialogResult.accepted),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _IncomingCallAction extends StatelessWidget {
  const _IncomingCallAction({
    required this.label,
    required this.icon,
    required this.color,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton.filled(
          onPressed: onPressed,
          style: IconButton.styleFrom(
            backgroundColor: color,
            foregroundColor: Colors.white,
            minimumSize: const Size.square(58),
          ),
          icon: Icon(icon, size: 27),
        ),
        const SizedBox(height: WebTuiSpacing.xs),
        Text(
          label,
          style: WebTuiTypography.labelSmall.copyWith(
            color: WebTuiColors.textSecondary,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

String? _locationForNotificationTarget(NotificationTarget target) {
  if (target.isInboxConversation) {
    return inboxConversationLocation(
      conversationId: target.inboxConversationId!,
      workspaceId: target.workspaceId,
    );
  }
  if (target.isApproval) {
    return Uri(
      path: '/approvals/${Uri.encodeComponent(target.approvalId!.trim())}',
      queryParameters: <String, String>{'workspaceId': target.workspaceId},
    ).toString();
  }
  if (target.canOpenContacts) {
    return Uri(
      path: '/',
      queryParameters: <String, String>{
        'tab': 'contacts',
        'workspaceId': target.workspaceId,
      },
    ).toString();
  }
  final channelId = target.channelId?.trim();
  if (channelId == null || channelId.isEmpty) {
    return null;
  }
  final params = <String, String>{
    'workspaceId': target.workspaceId,
    'title': 'Hội thoại',
    if (target.messageId?.trim().isNotEmpty == true)
      'messageId': target.messageId!.trim(),
    if (target.opensTasks) 'tool': 'tasks',
    if (target.opensTasks && target.taskId?.trim().isNotEmpty == true)
      'taskId': target.taskId!.trim(),
  };
  return Uri(
    path: '/conversations/$channelId',
    queryParameters: params,
  ).toString();
}

class _NotificationBellButton extends StatelessWidget {
  const _NotificationBellButton({
    required this.unreadCount,
    required this.onPressed,
  });

  final int unreadCount;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          tooltip: 'Thông báo',
          onPressed: onPressed,
          icon: const Icon(CupertinoIcons.bell),
        ),
        if (unreadCount > 0)
          Positioned(
            right: 6,
            top: 6,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: WebTuiColors.danger,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                child: Text(
                  unreadCount > 99 ? '99+' : unreadCount.toString(),
                  style: WebTuiTypography.labelSmall.copyWith(
                    color: WebTuiColors.textOnPrimary,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _NetworkQualityBanner extends StatelessWidget {
  const _NetworkQualityBanner({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: WebTuiColors.accentAmber.withValues(alpha: 0.12),
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: WebTuiColors.accentAmber.withValues(alpha: 0.35),
            ),
          ),
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: WebTuiSpacing.md,
          vertical: WebTuiSpacing.xs,
        ),
        child: Row(
          children: [
            const Icon(
              Icons.wifi_off_rounded,
              size: 18,
              color: WebTuiColors.accentAmber,
            ),
            const SizedBox(width: WebTuiSpacing.sm),
            Expanded(
              child: Text(
                'Mạng yếu, đang dùng dữ liệu gần nhất',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: WebTuiTypography.labelSmall.copyWith(
                  color: WebTuiColors.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('Thử lại'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tab Cài đặt. Công khai để test dựng riêng, không cần cả màn chính.
@visibleForTesting
class SettingsTab extends StatelessWidget {
  const SettingsTab({
    required this.workspaceName,
    required this.onWorkspaceTap,
    required this.notificationEnabled,
    required this.compactMode,
    required this.soundLevel,
    required this.textScalePreview,
    required this.onProfileTap,
    required this.onAdvancedTap,
    required this.onPrivacyTap,
    required this.onLogoutTap,
    required this.onNotificationChanged,
    required this.onCompactChanged,
    required this.onSoundChanged,
    required this.onTextScaleChanged,
    this.canSwitchWorkspace = false,
    this.organizationLogoUrl,
    this.onQrLoginTap,
    super.key,
  });

  /// Mở danh sách workspace.
  final VoidCallback onWorkspaceTap;

  /// Tài khoản có từ 2 workspace: dòng ghi "Chuyển workspace".
  final bool canSwitchWorkspace;

  /// Logo tổ chức (discovery); trống thì thẻ đầu trang hiện chữ viết tắt.
  final String? organizationLogoUrl;

  /// null khi máy chủ không bật đăng nhập QR.
  final VoidCallback? onQrLoginTap;
  final String workspaceName;
  final bool notificationEnabled;
  final bool compactMode;
  final double soundLevel;
  final double textScalePreview;
  final VoidCallback onProfileTap;
  final VoidCallback onAdvancedTap;
  final VoidCallback onPrivacyTap;
  final VoidCallback onLogoutTap;
  final ValueChanged<bool> onNotificationChanged;
  final ValueChanged<bool> onCompactChanged;
  final ValueChanged<double> onSoundChanged;
  final ValueChanged<double> onTextScaleChanged;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.only(bottom: WebTuiSpacing.lg),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            WebTuiSpacing.lg,
            WebTuiSpacing.md,
            WebTuiSpacing.lg,
            WebTuiSpacing.lg,
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: WebTuiColors.primarySoft,
              borderRadius: BorderRadius.circular(WebTuiRadii.lg),
              border: Border.all(
                color: WebTuiColors.primary.withValues(alpha: 0.12),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(WebTuiSpacing.lg),
              child: Row(
                children: [
                  _WorkspaceBadge(
                    name: workspaceName,
                    logoUrl: organizationLogoUrl,
                  ),
                  const SizedBox(width: WebTuiSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          workspaceName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: WebTuiTypography.titleMedium.copyWith(
                            color: WebTuiColors.textPrimary,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: WebTuiSpacing.xs),
                        Text(
                          'Đang hoạt động trong workspace',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: WebTuiTypography.bodySmall.copyWith(
                            color: WebTuiColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton.filledTonal(
                    tooltip: 'Hồ sơ cá nhân',
                    onPressed: onProfileTap,
                    icon: const Icon(Icons.person_outline_rounded),
                  ),
                ],
              ),
            ),
          ),
        ),
        WebTuiListSurface(
          children: [
            WebTuiSettingRow(
              key: const Key('settings_workspace_row'),
              title: canSwitchWorkspace ? 'Chuyển workspace' : 'Workspace',
              subtitle: workspaceName,
              icon: Icons.business_rounded,
              onTap: onWorkspaceTap,
              trailing: canSwitchWorkspace
                  ? const Icon(Icons.swap_horiz_rounded)
                  : null,
            ),
            if (onQrLoginTap != null)
              WebTuiSettingRow(
                key: const Key('settings_qr_login_row'),
                title: 'Đăng nhập máy tính bằng QR',
                subtitle: 'Quét mã trên trang đăng nhập của máy tính',
                icon: Icons.qr_code_scanner_rounded,
                onTap: onQrLoginTap,
              ),
            WebTuiSettingRow(
              title: 'Hồ sơ cá nhân',
              subtitle: 'Cập nhật tên, ảnh đại diện và trạng thái',
              icon: Icons.person_outline_rounded,
              onTap: onProfileTap,
            ),
            WebTuiSettingRow(
              title: 'Thiết lập nâng cao',
              subtitle: 'Quyền riêng tư, bảo mật và thiết bị',
              icon: Icons.tune_rounded,
              onTap: onAdvancedTap,
            ),
            WebTuiSettingRow(
              title: 'Thông báo',
              subtitle: 'Nhận tin nhắn và cảnh báo kênh',
              icon: Icons.notifications_none_rounded,
              trailing: WebTuiToggle(
                value: notificationEnabled,
                onChanged: onNotificationChanged,
              ),
            ),
            WebTuiSettingRow(
              title: 'Danh sách dày',
              subtitle: 'Tăng mật độ thông tin như ảnh reference',
              icon: Icons.format_line_spacing_rounded,
              trailing: WebTuiToggle(
                value: compactMode,
                onChanged: onCompactChanged,
              ),
            ),
          ],
        ),
        const WebTuiSectionLabel('Thiết lập chuông'),
        WebTuiListSurface(
          children: [
            WebTuiSliderRow(
              icon: Icons.volume_up_outlined,
              value: soundLevel,
              onChanged: onSoundChanged,
            ),
            WebTuiSliderRow(
              icon: Icons.text_fields_rounded,
              value: textScalePreview,
              onChanged: onTextScaleChanged,
            ),
          ],
        ),
        const SizedBox(height: WebTuiSpacing.md),
        WebTuiListSurface(
          children: [
            WebTuiSettingRow(
              title: 'Tài khoản',
              icon: Icons.account_circle_outlined,
              onTap: onPrivacyTap,
            ),
            WebTuiSettingRow(
              title: 'Đăng xuất',
              icon: Icons.logout_rounded,
              destructive: true,
              onTap: onLogoutTap,
            ),
          ],
        ),
      ],
    );
  }
}

/// Ô tròn ở thẻ đầu tab Cài đặt: logo tổ chức (giống góc trên trái) trên nền
/// trắng, không có logo thì chữ viết tắt tên workspace; chấm xanh = đang hoạt
/// động.
class _WorkspaceBadge extends StatelessWidget {
  const _WorkspaceBadge({required this.name, this.logoUrl});

  static const double _size = 68;

  final String name;
  final String? logoUrl;

  @override
  Widget build(BuildContext context) {
    final url = logoUrl?.trim();
    if (url == null || url.isEmpty) {
      return WebTuiAvatar(
        label: name,
        size: _size,
        status: WebTuiPresenceStatus.online,
        color: WebTuiColors.surface,
      );
    }
    return SizedBox.square(
      key: const Key('settings_workspace_logo'),
      dimension: _size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: const BoxDecoration(
                color: WebTuiColors.surface,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: _OrganizationMark(name: name, imageUrl: url, size: 42),
              ),
            ),
          ),
          Positioned(
            right: -1,
            bottom: -1,
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: WebTuiPresenceStatus.online.color,
                shape: BoxShape.circle,
                border: Border.all(color: WebTuiColors.surface, width: 2),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
