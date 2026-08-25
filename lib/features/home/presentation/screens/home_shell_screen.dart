import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/providers/foundation_providers.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/notifications/native_incoming_call_service.dart';
import '../../../../core/notifications/scoped_local_notification_service.dart';
import '../../../../core/platform/chat_share_intent_service.dart';
import '../../../../core/security/instance_scope.dart';
import '../../../../design_system/components/webtui_components.dart';
import '../../../../design_system/tokens/webtui_colors.dart';
import '../../../../design_system/tokens/webtui_radii.dart';
import '../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../design_system/tokens/webtui_typography.dart';
import '../../../auth/presentation/controllers/legal_acceptance_controller.dart';
import '../../../conversations/domain/entities/call_session.dart';
import '../../../conversations/domain/entities/conversation_realtime_event.dart';
import '../../../conversations/domain/entities/conversation_summary.dart';
import '../../../conversations/presentation/controllers/chat_room_controller.dart';
import '../../../conversations/presentation/controllers/conversation_home_controller.dart';
import '../../../conversations/presentation/controllers/pending_chat_share_controller.dart';
import '../../../conversations/presentation/screens/webrtc_call_screen.dart';
import '../../../conversations/presentation/screens/workspace_tools_screen.dart';
import '../../../conversations/presentation/widgets/conversation_home_views.dart';
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
  final Set<String> _nativeCallActionsInFlight = <String>{};
  StreamSubscription<ConversationRealtimeEvent>?
  _incomingCallRealtimeSubscription;
  bool _notificationEnabled = true;
  bool _compactMode = false;
  bool _networkDegraded = false;
  String? _activeIncomingCallId;
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
      unawaited(_runWorkspaceCatchUp(workspaceId));
      unawaited(_drainBackgroundQuickReplies(workspaceId));
      return;
    }

    // Push notifications remain the background delivery path. Keeping these
    // timers alive wastes battery and previously changed an away user back to
    // online on the next presence heartbeat.
    _presenceTimer?.cancel();
    _incomingCallPollTimer?.cancel();
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
        }
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _ensureShareIntentListener(activeWorkspace.id);
        _ensureQuickReplyListener(activeWorkspace.id);
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
          if (_tabIndex == 2)
            IconButton(
              tooltip: 'Tạo kênh',
              onPressed: () => context.push('/channels/new'),
              icon: const Icon(CupertinoIcons.square_pencil),
            )
          else if (_tabIndex == 0)
            IconButton(
              tooltip: 'Tạo hội thoại',
              onPressed: () {
                setState(() {
                  _tabIndex = 1;
                  _visitedTabs.add(1);
                });
              },
              icon: const Icon(CupertinoIcons.square_pencil),
            ),
        ],
        floatingActionButton: switch (_tabIndex) {
          2 => FloatingActionButton(
            tooltip: 'Tạo kênh',
            onPressed: () => context.push('/channels/new'),
            child: const Icon(CupertinoIcons.plus),
          ),
          _ => null,
        },
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
                    ChannelsHomeView(workspaceId: activeWorkspace.id)
                  else
                    const SizedBox.shrink(),
                  if (_visitedTabs.contains(3))
                    WorkspaceToolsScreen(workspaceId: activeWorkspace.id)
                  else
                    const SizedBox.shrink(),
                  if (_visitedTabs.contains(4))
                    _SettingsTab(
                      workspaceName: activeWorkspace.name,
                      notificationEnabled: _notificationEnabled,
                      compactMode: _compactMode,
                      soundLevel: _soundLevel,
                      textScalePreview: _textScalePreview,
                      onProfileTap: () => context.push('/profile'),
                      onAdvancedTap: () => context.push('/settings'),
                      onPrivacyTap: () => context.push('/privacy'),
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
          .execute(workspaceId: workspaceId);
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
      if (target.isIncomingCall) {
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
        await NativeIncomingCallService.endCall(callId);
        return;
      }
      final accepted = await showDialog<bool>(
        context: context,
        useRootNavigator: true,
        barrierDismissible: false,
        builder: (dialogContext) => _IncomingCallDialog(
          callerName: target.callerName ?? 'Cuộc gọi đến',
          mode: initialCall.mode,
          checkStatus: () async {
            final result = await ref
                .read(getCallUseCaseProvider)
                .execute(workspaceId: target.workspaceId, callId: callId);
            return result.valueOrNull?.status;
          },
        ),
      );
      if (!mounted || accepted == null) {
        return;
      }
      if (!accepted) {
        await NativeIncomingCallService.endCall(callId);
        await ref
            .read(rejectCallUseCaseProvider)
            .execute(
              workspaceId: target.workspaceId,
              callId: callId,
              reason: 'declined',
            );
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

  void _listenIncomingCalls(String workspaceId) {
    unawaited(_incomingCallRealtimeSubscription?.cancel());
    _incomingCallRealtimeSubscription = ref
        .read(incomingCallRealtimeRepositoryProvider)
        .subscribeToUser(workspaceId: workspaceId)
        .where(
          (event) =>
              event.workspaceId == workspaceId &&
              event.type == ConversationRealtimeEventType.callInvited,
        )
        .listen((event) {
          if (!mounted || event.callId?.trim().isNotEmpty != true) {
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

  static const _titles = ['Tin nhắn', 'Bạn bè', 'Kênh', 'Công việc', 'Cài đặt'];
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
  const _OrganizationMark({required this.name, this.imageUrl});

  final String name;
  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    final url = imageUrl?.trim();
    if (url != null && url.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: WebTuiBoundedNetworkImage(
          imageUrl: url,
          width: 30,
          height: 30,
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
        borderRadius: BorderRadius.circular(8),
      ),
      child: SizedBox.square(
        dimension: 30,
        child: Center(
          child: Text(
            initial.toUpperCase(),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ),
    );
  }
}

class _IncomingCallDialog extends StatefulWidget {
  const _IncomingCallDialog({
    required this.callerName,
    required this.mode,
    required this.checkStatus,
  });

  final String callerName;
  final CallMode mode;
  final Future<CallStatus?> Function() checkStatus;

  @override
  State<_IncomingCallDialog> createState() => _IncomingCallDialogState();
}

class _IncomingCallDialogState extends State<_IncomingCallDialog> {
  Timer? _timer;
  int _remainingSeconds = 30;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    SystemSound.play(SystemSoundType.alert);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) {
        return;
      }
      setState(() => _remainingSeconds -= 1);
      if (_remainingSeconds % 3 == 0 && _remainingSeconds > 0) {
        SystemSound.play(SystemSoundType.alert);
      }
      unawaited(_checkCall());
      if (_remainingSeconds <= 0) {
        Navigator.of(context).pop();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _checkCall() async {
    if (_checking) {
      return;
    }
    _checking = true;
    try {
      final status = await widget.checkStatus();
      if (mounted && status != null && status != CallStatus.ringing) {
        Navigator.of(context).pop();
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
                    onPressed: () => Navigator.of(context).pop(false),
                  ),
                  _IncomingCallAction(
                    label: 'Nghe',
                    icon: video ? Icons.videocam_rounded : Icons.call_rounded,
                    color: const Color(0xFF16A34A),
                    onPressed: () => Navigator.of(context).pop(true),
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

class _SettingsTab extends StatelessWidget {
  const _SettingsTab({
    required this.workspaceName,
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
  });

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
                  WebTuiAvatar(
                    label: workspaceName,
                    size: 68,
                    status: WebTuiPresenceStatus.online,
                    color: WebTuiColors.surface,
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
              title: 'Workspace',
              subtitle: workspaceName,
              icon: Icons.business_rounded,
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
