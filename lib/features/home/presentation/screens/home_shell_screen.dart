import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/providers/foundation_providers.dart';
import '../../../../core/notifications/native_incoming_call_service.dart';
import '../../../../design_system/components/webtui_components.dart';
import '../../../../design_system/tokens/webtui_colors.dart';
import '../../../../design_system/tokens/webtui_radii.dart';
import '../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../design_system/tokens/webtui_typography.dart';
import '../../../business/presentation/screens/business_dashboard_screen.dart';
import '../../../conversations/domain/entities/call_session.dart';
import '../../../conversations/domain/entities/conversation_summary.dart';
import '../../../conversations/presentation/controllers/chat_room_controller.dart';
import '../../../conversations/presentation/controllers/conversation_home_controller.dart';
import '../../../conversations/presentation/screens/webrtc_call_screen.dart';
import '../../../conversations/presentation/widgets/conversation_home_views.dart';
import '../../../notifications/domain/entities/mobile_notification.dart';
import '../../../notifications/presentation/controllers/notification_center_controller.dart';
import '../../../workspace/presentation/controllers/workspace_controller.dart';

class HomeShellScreen extends ConsumerStatefulWidget {
  const HomeShellScreen({this.initialTabIndex = 0, super.key});

  final int initialTabIndex;

  @override
  ConsumerState<HomeShellScreen> createState() => _HomeShellScreenState();
}

class _HomeShellScreenState extends ConsumerState<HomeShellScreen>
    with WidgetsBindingObserver {
  late int _tabIndex;
  String? _pushRegisteredWorkspaceId;
  String? _presenceWorkspaceId;
  String? _syncWorkspaceId;
  bool _syncInFlight = false;
  Timer? _presenceTimer;
  StreamSubscription<NotificationTarget>? _notificationOpenSubscription;
  StreamSubscription<NotificationTarget>? _foregroundNotificationSubscription;
  StreamSubscription<NativeIncomingCallAction>? _nativeCallSubscription;
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
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _presenceTimer?.cancel();
    _notificationOpenSubscription?.cancel();
    _foregroundNotificationSubscription?.cancel();
    _nativeCallSubscription?.cancel();
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
    final presence = switch (state) {
      AppLifecycleState.resumed => ConversationPresence.online,
      AppLifecycleState.detached => ConversationPresence.offline,
      _ => ConversationPresence.away,
    };
    unawaited(_setPresence(workspaceId, presence));
    if (state == AppLifecycleState.resumed) {
      unawaited(_runWorkspaceCatchUp(workspaceId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final workspaceState = ref.watch(workspaceControllerProvider);
    final activeWorkspace = workspaceState.activeWorkspace;

    if (workspaceState.isLoading && activeWorkspace == null) {
      return const Scaffold(
        body: SafeArea(
          child: WebTuiLoadingState(message: 'Đang tải workspace...'),
        ),
      );
    }

    if (activeWorkspace == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('WebTui')),
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

    if (_pushRegisteredWorkspaceId != activeWorkspace.id) {
      _pushRegisteredWorkspaceId = activeWorkspace.id;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        unawaited(
          ref
              .read(pushNotificationServiceProvider)
              .registerForWorkspace(activeWorkspace.id),
        );
        _listenPushTargets();
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
    final notificationState = ref.watch(
      notificationCenterControllerProvider(activeWorkspace.id),
    );

    return KeyedSubtree(
      key: ValueKey('workspace-shell-${workspaceState.generation}'),
      child: WebTuiMobileScaffold(
        title: _titles[_tabIndex],
        selectedTab: _tabIndex,
        onTabSelected: (index) => setState(() => _tabIndex = index),
        leading: IconButton(
          tooltip: 'Hồ sơ cá nhân',
          onPressed: () => context.push('/profile'),
          icon: const Icon(CupertinoIcons.person),
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
              onPressed: () => setState(() => _tabIndex = 1),
              icon: const Icon(CupertinoIcons.square_pencil),
            ),
        ],
        floatingActionButton: switch (_tabIndex) {
          0 => FloatingActionButton(
            tooltip: 'Tạo hội thoại',
            onPressed: () => setState(() => _tabIndex = 1),
            child: const Icon(CupertinoIcons.chat_bubble_2),
          ),
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
              child: switch (_tabIndex) {
                0 => MessagesHomeView(workspaceId: activeWorkspace.id),
                1 => ContactsHomeView(workspaceId: activeWorkspace.id),
                2 => ChannelsHomeView(workspaceId: activeWorkspace.id),
                3 => BusinessDashboardScreen(workspaceId: activeWorkspace.id),
                _ => _SettingsTab(
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
                ),
              },
            ),
          ],
        ),
      ),
    );
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
      final acceptedResult = await ref
          .read(acceptCallUseCaseProvider)
          .execute(workspaceId: target.workspaceId, callId: callId);
      final acceptedCall = acceptedResult.valueOrNull;
      if (!mounted || acceptedCall == null) {
        await NativeIncomingCallService.endCall(callId);
        return;
      }
      await NativeIncomingCallService.markConnected(callId);
      if (!mounted) {
        return;
      }
      await Navigator.of(context, rootNavigator: true).push<void>(
        MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (_) => WebRtcCallScreen(
            workspaceId: acceptedCall.workspaceId,
            channelId: acceptedCall.channelId,
            callId: acceptedCall.id,
            title: target.callerName ?? 'Cuộc gọi đến',
            mode: acceptedCall.mode,
            incoming: true,
            onLeave: () async {
              await NativeIncomingCallService.endCall(acceptedCall.id);
              ref.invalidate(chatRoomControllerProvider);
              ref.invalidate(
                conversationHomeControllerProvider(acceptedCall.workspaceId),
              );
              ref.invalidate(
                notificationCenterControllerProvider(acceptedCall.workspaceId),
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
    switch (action.type) {
      case NativeIncomingCallActionType.accept:
        await _acceptNativeIncomingCall(action.target);
      case NativeIncomingCallActionType.decline:
        await _rejectNativeIncomingCall(action.target, reason: 'declined');
      case NativeIncomingCallActionType.timeout:
        await _rejectNativeIncomingCall(action.target, reason: 'timeout');
      case NativeIncomingCallActionType.ended:
        await _rejectNativeIncomingCall(action.target, reason: 'ended');
    }
  }

  Future<void> _acceptNativeIncomingCall(NotificationTarget target) async {
    final callId = target.callId?.trim();
    if (!mounted || callId == null || callId.isEmpty) {
      return;
    }
    if (_activeIncomingCallId == callId) {
      return;
    }
    _activeIncomingCallId = callId;
    try {
      final currentResult = await ref
          .read(getCallUseCaseProvider)
          .execute(workspaceId: target.workspaceId, callId: callId);
      final currentCall = currentResult.valueOrNull;
      if (!mounted || currentCall == null || currentCall.isTerminal) {
        await NativeIncomingCallService.endCall(callId);
        return;
      }

      final acceptedCall = currentCall.status == CallStatus.accepted
          ? currentCall
          : (await ref
                    .read(acceptCallUseCaseProvider)
                    .execute(workspaceId: target.workspaceId, callId: callId))
                .valueOrNull;
      if (!mounted || acceptedCall == null || acceptedCall.isTerminal) {
        await NativeIncomingCallService.endCall(callId);
        return;
      }

      await NativeIncomingCallService.markConnected(callId);
      if (!mounted) {
        return;
      }
      await Navigator.of(context, rootNavigator: true).push<void>(
        MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (_) => WebRtcCallScreen(
            workspaceId: acceptedCall.workspaceId,
            channelId: acceptedCall.channelId,
            callId: acceptedCall.id,
            title: target.callerName ?? 'Cuộc gọi đến',
            mode: acceptedCall.mode,
            incoming: true,
            onLeave: () async {
              await NativeIncomingCallService.endCall(acceptedCall.id);
              ref.invalidate(chatRoomControllerProvider);
              ref.invalidate(
                conversationHomeControllerProvider(acceptedCall.workspaceId),
              );
              ref.invalidate(
                notificationCenterControllerProvider(acceptedCall.workspaceId),
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

  Future<void> _rejectNativeIncomingCall(
    NotificationTarget target, {
    required String reason,
  }) async {
    final callId = target.callId?.trim();
    if (callId == null || callId.isEmpty) {
      return;
    }
    await NativeIncomingCallService.endCall(callId);
    await ref
        .read(rejectCallUseCaseProvider)
        .execute(
          workspaceId: target.workspaceId,
          callId: callId,
          reason: reason,
        );
  }

  static const _titles = ['Tin nhắn', 'Bạn bè', 'Kênh', 'Nghiệp vụ', 'Cài đặt'];
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
