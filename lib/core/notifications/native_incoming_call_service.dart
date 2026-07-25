import 'dart:async';
import 'dart:io';

import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';

import '../../features/notifications/domain/entities/mobile_notification.dart';

enum NativeIncomingCallActionType { accept, decline, ended, timeout }

final class NativeIncomingCallAction {
  const NativeIncomingCallAction({required this.type, required this.target});

  final NativeIncomingCallActionType type;
  final NotificationTarget target;
}

final class NativeIncomingCallService {
  NativeIncomingCallService._();

  static final _actions =
      StreamController<NativeIncomingCallAction>.broadcast();
  static final _pendingActions = <NativeIncomingCallAction>[];
  static StreamSubscription<CallEvent?>? _subscription;
  static bool _permissionsRequested = false;

  static Stream<NativeIncomingCallAction> get actions {
    ensureStarted();
    return Stream.multi((controller) {
      for (final action in _pendingActions) {
        controller.add(action);
      }
      _pendingActions.clear();
      final subscription = _actions.stream.listen(
        controller.add,
        onError: controller.addError,
        onDone: controller.close,
      );
      controller.onCancel = subscription.cancel;
    });
  }

  static void ensureStarted() {
    _subscription ??= FlutterCallkitIncoming.onEvent.listen(
      _handleCallkitEvent,
      onError: (_) {},
    );
  }

  static Future<void> prepareDevicePermissions() async {
    if (_permissionsRequested || !Platform.isAndroid) {
      return;
    }
    _permissionsRequested = true;
    try {
      await FlutterCallkitIncoming.requestNotificationPermission({
        'title': 'Cho phép thông báo cuộc gọi',
        'rationaleMessagePermission':
            'Ứng dụng cần quyền thông báo để hiển thị cuộc gọi đến.',
        'postNotificationMessageRequired':
            'Hãy bật thông báo để nhận cuộc gọi đến khi ứng dụng ở nền.',
      });
      final canUseFullScreenIntent =
          await FlutterCallkitIncoming.canUseFullScreenIntent();
      if (canUseFullScreenIntent != true) {
        await FlutterCallkitIncoming.requestFullIntentPermission();
      }
    } on Object {
      // Permission helpers are best-effort because older Android versions may
      // not expose the full-screen intent settings activity.
    }
  }

  static Future<void> syncRemoteMessagePayload({
    required String fallbackWorkspaceId,
    required Map<String, Object?> data,
  }) async {
    final target = NotificationTarget.fromPayload(
      workspaceId: fallbackWorkspaceId,
      data: data,
    );
    if (target.isIncomingCall) {
      await showIncomingCall(target);
      return;
    }
    if (_isTerminalCall(target)) {
      await endCall(target.callId!);
    }
  }

  static Future<void> showIncomingCall(NotificationTarget target) async {
    final callId = target.callId?.trim();
    if (callId == null || callId.isEmpty || !target.isIncomingCall) {
      return;
    }

    final normalizedMode = _normalizedCallMode(target.callMode);
    final isVideo = normalizedMode == 'video';
    final callerName = _callerName(target);
    final extra = <String, dynamic>{
      'call_id': callId,
      'workspace_id': target.workspaceId,
      'channel_id': target.channelId ?? '',
      'mode': normalizedMode,
      'status': 'ringing',
      'target_type': 'call',
      'event_type': 'call_invite',
      'caller_name': callerName,
      if (target.deepLink != null) 'deep_link': target.deepLink,
    };

    final params = CallKitParams(
      id: callId,
      nameCaller: callerName,
      appName: 'WebTui Chat',
      handle: isVideo ? 'Cuộc gọi video' : 'Cuộc gọi thoại',
      type: isVideo ? 1 : 0,
      duration: 30000,
      textAccept: 'Chấp nhận',
      textDecline: 'Từ chối',
      missedCallNotification: const NotificationParams(
        showNotification: true,
        isShowCallback: false,
        subtitle: 'Cuộc gọi nhỡ',
      ),
      callingNotification: const NotificationParams(
        showNotification: true,
        isShowCallback: false,
        subtitle: 'Đang gọi...',
      ),
      extra: extra,
      android: const AndroidParams(
        isCustomNotification: true,
        isCustomSmallExNotification: true,
        isShowCallID: false,
        isShowFullLockedScreen: true,
        isShowLogo: true,
        isImportant: true,
        ringtonePath: 'system_ringtone_default',
        backgroundColor: '#0EA5E9',
        actionColor: '#0068FF',
        textColor: '#FFFFFF',
        incomingCallNotificationChannelName: 'Cuộc gọi đến',
        missedCallNotificationChannelName: 'Cuộc gọi nhỡ',
      ),
      ios: IOSParams(
        handleType: 'generic',
        supportsVideo: isVideo,
        maximumCallGroups: 1,
        maximumCallsPerCallGroup: 1,
        audioSessionMode: 'default',
        audioSessionActive: true,
        configureAudioSession: true,
        supportsDTMF: false,
        supportsHolding: false,
        supportsGrouping: false,
        supportsUngrouping: false,
        ringtonePath: 'system_ringtone_default',
      ),
    );
    await FlutterCallkitIncoming.showCallkitIncoming(params);
  }

  static Future<void> endCall(String callId) async {
    final normalizedCallId = callId.trim();
    if (normalizedCallId.isEmpty) {
      return;
    }
    try {
      await FlutterCallkitIncoming.endCall(normalizedCallId);
    } on Object {
      // The call may already be gone from native UI.
    }
  }

  static Future<void> markConnected(String callId) async {
    final normalizedCallId = callId.trim();
    if (normalizedCallId.isEmpty) {
      return;
    }
    try {
      await FlutterCallkitIncoming.setCallConnected(normalizedCallId);
    } on Object {
      // Android does not need a connected marker; iOS uses it for CallKit.
    }
  }

  static void _handleCallkitEvent(CallEvent? event) {
    if (event == null) {
      return;
    }
    final target = _targetFromCallkitBody(event.body);
    if (target == null || target.callId?.trim().isNotEmpty != true) {
      return;
    }

    final actionType = switch (event.event) {
      Event.actionCallAccept => NativeIncomingCallActionType.accept,
      Event.actionCallDecline => NativeIncomingCallActionType.decline,
      Event.actionCallEnded => NativeIncomingCallActionType.ended,
      Event.actionCallTimeout => NativeIncomingCallActionType.timeout,
      _ => null,
    };
    if (actionType == null) {
      return;
    }
    _emit(NativeIncomingCallAction(type: actionType, target: target));
  }

  static void _emit(NativeIncomingCallAction action) {
    if (!_actions.hasListener) {
      _pendingActions.add(action);
      return;
    }
    _actions.add(action);
  }

  static NotificationTarget? _targetFromCallkitBody(Object? body) {
    final raw = _stringObjectMap(body);
    if (raw.isEmpty) {
      return null;
    }
    final extra = _stringObjectMap(raw['extra']);
    final data = <String, Object?>{
      ...raw,
      ...extra,
      'call_id':
          _firstStringValue(extra['call_id'], raw['call_id'], raw['id']) ?? '',
      'workspace_id':
          _firstStringValue(extra['workspace_id'], raw['workspace_id']) ?? '',
      'channel_id':
          _firstStringValue(extra['channel_id'], raw['channel_id']) ?? '',
      'mode': _firstStringValue(extra['mode'], raw['mode']) ?? 'audio',
      'status': _firstStringValue(extra['status'], raw['status']) ?? 'ringing',
      'target_type':
          _firstStringValue(extra['target_type'], raw['target_type']) ?? 'call',
      'event_type':
          _firstStringValue(extra['event_type'], raw['event_type']) ??
          'call_invite',
      'caller_name':
          _firstStringValue(
            extra['caller_name'],
            raw['caller_name'],
            raw['nameCaller'],
          ) ??
          'Cuộc gọi đến',
    };
    return NotificationTarget.fromPayload(
      workspaceId: data['workspace_id']?.toString() ?? '',
      data: data,
    );
  }

  static Map<String, Object?> _stringObjectMap(Object? value) {
    if (value is Map) {
      return value.map((key, value) => MapEntry(key.toString(), value));
    }
    return const {};
  }

  static bool _isTerminalCall(NotificationTarget target) {
    final callId = target.callId?.trim();
    if (target.targetType != 'call' || callId == null || callId.isEmpty) {
      return false;
    }
    final status = target.callStatus?.trim().toLowerCase();
    return target.eventType == 'call_ended' ||
        status == 'rejected' ||
        status == 'cancelled' ||
        status == 'canceled' ||
        status == 'ended' ||
        status == 'missed';
  }

  static String _callerName(NotificationTarget target) {
    final callerName = target.callerName?.trim();
    if (callerName != null && callerName.isNotEmpty) {
      return callerName;
    }
    return 'Cuộc gọi đến';
  }

  static String _normalizedCallMode(String? value) {
    return value?.trim().toLowerCase() == 'video' ? 'video' : 'audio';
  }

  static String? _firstStringValue(
    Object? first,
    Object? second, [
    Object? third,
  ]) {
    for (final value in [first, second, third]) {
      final string = value?.toString().trim();
      if (string != null && string.isNotEmpty) {
        return string;
      }
    }
    return null;
  }
}
