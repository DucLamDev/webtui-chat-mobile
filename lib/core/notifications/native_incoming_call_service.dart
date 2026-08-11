import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../features/notifications/domain/entities/mobile_notification.dart';
import '../security/instance_scope.dart';
import '../security/secure_key_value_store.dart';
import '../security/server_account_registry.dart';

enum NativeIncomingCallActionType { accept, decline, ended, timeout }

final class NativeIncomingCallAction {
  const NativeIncomingCallAction({
    required this.actionId,
    required this.type,
    required this.target,
    this.serverBaseUrl,
  });

  static NativeIncomingCallAction? tryFromPendingPayload(
    Map<String, Object?> payload,
  ) {
    final event = payload['event']?.toString().trim();
    final type = switch (event) {
      CallEventConstants.actionCallAccept =>
        NativeIncomingCallActionType.accept,
      CallEventConstants.actionCallDecline =>
        NativeIncomingCallActionType.decline,
      CallEventConstants.actionCallEnded => NativeIncomingCallActionType.ended,
      CallEventConstants.actionCallTimeout =>
        NativeIncomingCallActionType.timeout,
      _ => null,
    };
    final callId = payload['call_id']?.toString().trim() ?? '';
    final workspaceId = payload['workspace_id']?.toString().trim() ?? '';
    final instanceId = _normalizedInstanceId(payload['instance_id']);
    final serverBaseUrl = _validatedCallServerBaseUrl(
      instanceId: instanceId,
      value: payload['server_base_url'],
    );
    if (type == null ||
        callId.isEmpty ||
        workspaceId.isEmpty ||
        instanceId == null ||
        serverBaseUrl == null) {
      return null;
    }
    final target = NotificationTarget.fromPayload(
      workspaceId: workspaceId,
      channelId: payload['channel_id']?.toString(),
      data: <String, Object?>{
        ...payload,
        'call_id': callId,
        'workspace_id': workspaceId,
        'instance_id': instanceId,
        'target_type': payload['target_type'] ?? 'call',
        'event_type': payload['event_type'] ?? 'call_invite',
        'status': payload['status'] ?? 'ringing',
        'app_name': payload['organization_name'],
      },
    );
    final expectedActionId = actionIdFor(type, callId, instanceId: instanceId);
    final persistedId = payload['action_id']?.toString().trim() ?? '';
    if (persistedId.isNotEmpty && persistedId != expectedActionId) {
      return null;
    }
    return NativeIncomingCallAction(
      actionId: expectedActionId,
      type: type,
      target: target,
      serverBaseUrl: serverBaseUrl,
    );
  }

  static String actionIdFor(
    NativeIncomingCallActionType type,
    String callId, {
    required String instanceId,
  }) {
    final normalizedCallId = callId.trim();
    final normalizedInstanceId = _normalizedInstanceId(instanceId);
    if (normalizedCallId.isEmpty) {
      throw ArgumentError.value(callId, 'callId', 'must not be empty');
    }
    if (normalizedInstanceId == null) {
      throw ArgumentError.value(instanceId, 'instanceId', 'must be a UUID');
    }
    final event = switch (type) {
      NativeIncomingCallActionType.accept =>
        CallEventConstants.actionCallAccept,
      NativeIncomingCallActionType.decline =>
        CallEventConstants.actionCallDecline,
      NativeIncomingCallActionType.ended => CallEventConstants.actionCallEnded,
      NativeIncomingCallActionType.timeout =>
        CallEventConstants.actionCallTimeout,
    };
    return '$event:$normalizedInstanceId:$normalizedCallId';
  }

  final String actionId;
  final NativeIncomingCallActionType type;
  final NotificationTarget target;
  final String? serverBaseUrl;
}

final class NativeIncomingCallService {
  NativeIncomingCallService._();

  static final _actions =
      StreamController<NativeIncomingCallAction>.broadcast();
  static final _voipTokens = StreamController<String>.broadcast();
  static final _pendingActions = <String, NativeIncomingCallAction>{};
  static final _retryAttempts = <String, int>{};
  static final _retryTimers = <String, Timer>{};
  static final _targetsByCallId = <String, NotificationTarget>{};
  static final _invalidatedInstanceIds = <String>{};
  static StreamSubscription<CallEvent?>? _subscription;
  static bool _permissionsRequested = false;
  static bool _pendingRestoreStarted = false;
  static bool _backgroundHandlerRegistered = false;

  static Stream<NativeIncomingCallAction> get actions {
    ensureStarted();
    return Stream.multi((controller) {
      for (final action in _pendingActions.values) {
        controller.add(action);
      }
      final subscription = _actions.stream.listen(
        controller.add,
        onError: controller.addError,
        onDone: controller.close,
      );
      controller.onCancel = subscription.cancel;
    });
  }

  static Stream<String> get voipTokens {
    ensureStarted();
    return _voipTokens.stream;
  }

  static Future<String?> readVoipPushToken() async {
    if (!Platform.isIOS) return null;
    ensureStarted();
    try {
      final token = (await FlutterCallkitIncoming.getDevicePushTokenVoIP())
          .toString()
          .trim();
      return token.isEmpty ? null : token;
    } on Object {
      return null;
    }
  }

  static void ensureStarted() {
    _subscription ??= FlutterCallkitIncoming.onEvent.listen(
      _handleCallkitEvent,
      onError: (_) {},
    );
    if (Platform.isAndroid && !_pendingRestoreStarted) {
      _pendingRestoreStarted = true;
      unawaited(_restorePendingActions());
    }
  }

  static Future<void> registerBackgroundActionHandler() async {
    if (!Platform.isAndroid || _backgroundHandlerRegistered) return;
    await FlutterCallkitIncoming.onBackgroundMessage(
      webTuiCallkitBackgroundHandler,
    );
    _backgroundHandlerRegistered = true;
  }

  /// Acknowledge only after the authenticated backend action has succeeded (or
  /// a fresh read proves the call is already terminal). Until then it remains
  /// replayable across widget, engine, and process restarts.
  static Future<void> acknowledge(NativeIncomingCallAction action) async {
    _pendingActions.remove(action.actionId);
    _retryAttempts.remove(action.actionId);
    _retryTimers.remove(action.actionId)?.cancel();
    if (!Platform.isAndroid) return;
    try {
      await FlutterCallkitIncoming.ackPendingCallAction(action.actionId);
    } on Object {
      // Native persistence intentionally remains; the next process start will
      // replay it if the acknowledgement could not cross the platform channel.
    }
  }

  /// Ends only native calls that carry the invalidated instance identity and
  /// retires that instance's durable actions. Binding is cleared before this
  /// runs, so terminal callbacks cannot be routed into a new server session.
  static Future<void> terminateCallsForSessionInvalidation(
    InstanceScope? instanceScope,
  ) async {
    final instanceId = instanceScope?.instanceId;
    if (instanceId == null) return;
    _invalidatedInstanceIds.add(instanceId);

    try {
      final calls = await FlutterCallkitIncoming.activeCalls();
      for (final call in calls) {
        final target = _targetFromCallkitBody(call.toJson());
        if (target?.isBoundToInstance(instanceId) == true) {
          await FlutterCallkitIncoming.endCall(call.id);
        }
      }
    } on Object {
      // Continue with durable action cleanup if native UI was already gone.
    }

    final retiredActions = <NativeIncomingCallAction>[];
    try {
      final payloads = await FlutterCallkitIncoming.getPendingCallActions();
      for (final payload in payloads) {
        final action = NativeIncomingCallAction.tryFromPendingPayload(payload);
        if (action?.target.isBoundToInstance(instanceId) == true) {
          retiredActions.add(action!);
        }
      }
    } on Object {
      // In-memory actions are still retired below. Native entries remain
      // fail-closed because the active binding was invalidated first.
    }

    retiredActions.addAll(
      _pendingActions.values.where(
        (action) => action.target.isBoundToInstance(instanceId),
      ),
    );
    for (final action in {
      for (final action in retiredActions) action.actionId: action,
    }.values) {
      await acknowledge(action);
    }
    _targetsByCallId.removeWhere(
      (_, target) => target.isBoundToInstance(instanceId),
    );
  }

  static void retryLater(NativeIncomingCallAction action) {
    if (!_pendingActions.containsKey(action.actionId) ||
        _retryTimers.containsKey(action.actionId)) {
      return;
    }
    const delays = <Duration>[
      Duration(seconds: 2),
      Duration(seconds: 8),
      Duration(seconds: 20),
      Duration(seconds: 45),
    ];
    final attempt = _retryAttempts[action.actionId] ?? 0;
    if (attempt >= delays.length) return;
    _retryAttempts[action.actionId] = attempt + 1;
    _retryTimers[action.actionId] = Timer(delays[attempt], () {
      _retryTimers.remove(action.actionId);
      final pending = _pendingActions[action.actionId];
      if (pending != null && _actions.hasListener) {
        _actions.add(pending);
      }
    });
  }

  static Future<void> _restorePendingActions() async {
    try {
      final payloads = await FlutterCallkitIncoming.getPendingCallActions();
      for (final payload in payloads) {
        final action = NativeIncomingCallAction.tryFromPendingPayload(payload);
        if (action == null) continue;
        final callId = action.target.callId?.trim();
        if (callId != null && callId.isNotEmpty) {
          _targetsByCallId[callId] = action.target;
        }
        _emit(action);
      }
    } on Object {
      // The queue remains native and will be retried on the next process start.
    }
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
    if (await targetMatchesPersistedActiveInstance(target) != true) {
      return;
    }
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
    if (callId == null ||
        callId.isEmpty ||
        !target.isIncomingCall ||
        await targetMatchesPersistedActiveInstance(target) != true) {
      return;
    }

    final normalizedMode = _normalizedCallMode(target.callMode);
    final instanceId = _normalizedInstanceId(target.instanceId);
    if (instanceId == null) return;
    _invalidatedInstanceIds.remove(instanceId);
    final isVideo = normalizedMode == 'video';
    final callerName = _callerName(target);
    final activeServerBaseUrl = await _readActiveServerBaseUrl();
    final extra = <String, dynamic>{
      'call_id': callId,
      'workspace_id': target.workspaceId,
      'channel_id': target.channelId ?? '',
      'mode': normalizedMode,
      'status': 'ringing',
      'target_type': 'call',
      'event_type': 'call_invite',
      'caller_name': callerName,
      'instance_id': target.instanceId,
      'server_base_url': ?activeServerBaseUrl,
      if (target.organizationName != null) 'app_name': target.organizationName,
      if (target.organizationLogoUrl != null)
        'logo_url': target.organizationLogoUrl,
      if (target.deepLink != null) 'deep_link': target.deepLink,
    };
    _targetsByCallId[callId] = target;

    final params = _callKitParams(
      callId: callId,
      callerName: callerName,
      appName: target.organizationName,
      isVideo: isVideo,
      extra: extra,
      includeMissedCallNotification: true,
    );
    await FlutterCallkitIncoming.showCallkitIncoming(params);
  }

  /// Starts the native outgoing-call lifecycle only after WebRTC's visible
  /// runtime permission flow has returned a usable media stream.
  ///
  /// The vendored Android plugin verifies visibility and permissions again,
  /// starts a phoneCall-only FGS, then promotes that same service to the
  /// microphone/camera type(s). iOS records the outgoing call through CallKit.
  static Future<void> startOutgoingCall({
    required InstanceScope instanceScope,
    required String callId,
    required String workspaceId,
    required String channelId,
    required String title,
    required bool isVideo,
  }) async {
    final normalizedCallId = callId.trim();
    final normalizedWorkspaceId = workspaceId.trim();
    final normalizedChannelId = channelId.trim();
    if (normalizedCallId.isEmpty) {
      throw ArgumentError.value(callId, 'callId', 'must not be empty');
    }
    if (normalizedWorkspaceId.isEmpty) {
      throw ArgumentError.value(
        workspaceId,
        'workspaceId',
        'must not be empty',
      );
    }
    final binding = await _readValidatedActiveCallBinding(
      expectedInstanceScope: instanceScope,
      expectedWorkspaceId: normalizedWorkspaceId,
    );
    if (binding == null) {
      throw StateError('Active call instance binding is unavailable.');
    }
    _invalidatedInstanceIds.remove(binding.instanceId);
    final callerName = title.trim().isEmpty
        ? 'Cuộc gọi WebTUI Chat'
        : title.trim();
    final target = NotificationTarget(
      workspaceId: normalizedWorkspaceId,
      instanceId: binding.instanceId,
      channelId: normalizedChannelId,
      targetType: 'call',
      eventType: 'call_started',
      callId: normalizedCallId,
      callMode: isVideo ? 'video' : 'audio',
      callStatus: 'connecting',
      callerName: callerName,
    );
    _targetsByCallId[normalizedCallId] = target;
    try {
      await FlutterCallkitIncoming.startCall(
        _callKitParams(
          callId: normalizedCallId,
          callerName: callerName,
          isVideo: isVideo,
          extra: <String, dynamic>{
            'call_id': normalizedCallId,
            'workspace_id': normalizedWorkspaceId,
            'channel_id': normalizedChannelId,
            'mode': isVideo ? 'video' : 'audio',
            'status': 'connecting',
            'target_type': 'call',
            'event_type': 'call_started',
            'caller_name': callerName,
            'instance_id': binding.instanceId,
            'server_base_url': binding.serverBaseUrl,
          },
          includeMissedCallNotification: false,
        ),
      );
    } on Object {
      if (identical(_targetsByCallId[normalizedCallId], target)) {
        _targetsByCallId.remove(normalizedCallId);
      }
      rethrow;
    }
  }

  /// Promotes an accepted Android incoming call after getUserMedia succeeds.
  /// On iOS the CallKit audio-session lifecycle remains authoritative.
  static Future<void> activateMediaCapture({
    required InstanceScope instanceScope,
    required String callId,
    required String workspaceId,
    required String channelId,
    required String title,
    required bool isVideo,
  }) async {
    if (!Platform.isAndroid) return;
    final normalizedCallId = callId.trim();
    final normalizedWorkspaceId = workspaceId.trim();
    if (normalizedCallId.isEmpty) {
      throw ArgumentError.value(callId, 'callId', 'must not be empty');
    }
    final binding = await _readValidatedActiveCallBinding(
      expectedInstanceScope: instanceScope,
      expectedWorkspaceId: normalizedWorkspaceId,
    );
    if (binding == null) {
      throw StateError('Active call instance binding is unavailable.');
    }
    final target = _targetsByCallId[normalizedCallId];
    if (target != null && !target.isBoundToInstance(binding.instanceId)) {
      throw StateError('Call target no longer matches the active instance.');
    }
    final callerName = target == null ? title.trim() : _callerName(target);
    await FlutterCallkitIncoming.activateCallMedia(
      _callKitParams(
        callId: normalizedCallId,
        callerName: callerName.isEmpty ? 'Cuộc gọi WebTUI Chat' : callerName,
        appName: target?.organizationName,
        isVideo: isVideo,
        extra: <String, dynamic>{
          'call_id': normalizedCallId,
          'workspace_id': normalizedWorkspaceId,
          'channel_id': channelId.trim(),
          'mode': isVideo ? 'video' : 'audio',
          'status': 'accepted',
          'target_type': 'call',
          'event_type': 'call_accepted',
          'caller_name': callerName,
          'instance_id': binding.instanceId,
          'server_base_url': binding.serverBaseUrl,
        },
        includeMissedCallNotification: false,
      ),
    );
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
    } finally {
      _targetsByCallId.remove(normalizedCallId);
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
    final action = actionFromCallkitEvent(event);
    if (action == null) return;
    final callId = action.target.callId?.trim();
    if (action.type != NativeIncomingCallActionType.accept &&
        callId != null &&
        callId.isNotEmpty) {
      _targetsByCallId.remove(callId);
    }
    _emit(action);
  }

  static NativeIncomingCallAction? actionFromCallkitEvent(CallEvent? event) {
    if (event == null) {
      return null;
    }
    if (event is CallEventActionDidUpdateDevicePushTokenVoip) {
      unawaited(_publishCurrentVoipToken());
      return null;
    }

    final (actionType, body, fallbackCallId) = switch (event) {
      CallEventActionCallAccept(callKitParams: final params) => (
        NativeIncomingCallActionType.accept,
        params.toJson(),
        params.id,
      ),
      CallEventActionCallDecline(callKitParams: final params) => (
        NativeIncomingCallActionType.decline,
        params.toJson(),
        params.id,
      ),
      CallEventActionCallEnded(callKitParams: final params) => (
        NativeIncomingCallActionType.ended,
        params.toJson(),
        params.id,
      ),
      CallEventActionCallTimeout(callKitParams: final params) => (
        NativeIncomingCallActionType.timeout,
        params.toJson(),
        params.id,
      ),
      _ => (null, null, null),
    };
    if (actionType == null || fallbackCallId == null) {
      return null;
    }
    final target = _targetFromCallkitBody(body);
    final instanceId = _normalizedInstanceId(target?.instanceId);
    final raw = _stringObjectMap(body);
    final extra = _stringObjectMap(raw['extra']);
    final serverBaseUrl = _validatedCallServerBaseUrl(
      instanceId: instanceId,
      value: _firstStringValue(
        extra['server_base_url'],
        raw['server_base_url'],
      ),
    );
    if (target == null ||
        target.callId?.trim().isNotEmpty != true ||
        instanceId == null ||
        serverBaseUrl == null) {
      return null;
    }
    return NativeIncomingCallAction(
      actionId: NativeIncomingCallAction.actionIdFor(
        actionType,
        fallbackCallId,
        instanceId: instanceId,
      ),
      type: actionType,
      target: target,
      serverBaseUrl: serverBaseUrl,
    );
  }

  static Future<void> _publishCurrentVoipToken() async {
    final token = await readVoipPushToken();
    _voipTokens.add(token ?? '');
  }

  static void _emit(NativeIncomingCallAction action) {
    final instanceId = _normalizedInstanceId(action.target.instanceId);
    if (instanceId == null || _invalidatedInstanceIds.contains(instanceId)) {
      unawaited(acknowledge(action));
      return;
    }
    if (_pendingActions.containsKey(action.actionId)) return;
    _pendingActions[action.actionId] = action;
    if (_actions.hasListener) _actions.add(action);
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

  static CallKitParams _callKitParams({
    required String callId,
    required String callerName,
    required bool isVideo,
    required Map<String, dynamic> extra,
    required bool includeMissedCallNotification,
    String? appName,
  }) {
    final normalizedAppName = appName?.trim();
    return CallKitParams(
      id: callId,
      nameCaller: callerName,
      appName: normalizedAppName?.isNotEmpty == true
          ? normalizedAppName
          : 'WebTUI Chat',
      handle: isVideo ? 'Cuộc gọi video' : 'Cuộc gọi thoại',
      type: isVideo ? 1 : 0,
      duration: 30000,
      missedCallNotification: includeMissedCallNotification
          ? const NotificationParams(
              showNotification: true,
              isShowCallback: false,
              subtitle: 'Cuộc gọi nhỡ',
            )
          : const NotificationParams(showNotification: false),
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
        textAccept: 'Chấp nhận',
        textDecline: 'Từ chối',
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

  static Future<String?> _readActiveServerBaseUrl() async {
    try {
      const storage = FlutterSecureStorage();
      final raw = await storage.read(key: SecureStoreKey.instanceBaseUrl.value);
      return validatedBackgroundCallHttpsOrigin(raw)?.toString();
    } on Object {
      return null;
    }
  }

  static Future<_ActiveCallInstanceBinding?> _readValidatedActiveCallBinding({
    required InstanceScope expectedInstanceScope,
    required String expectedWorkspaceId,
  }) async {
    final workspaceId = expectedWorkspaceId.trim();
    if (workspaceId.isEmpty) return null;
    try {
      const storage = FlutterSecureStorage();
      final values = await Future.wait<String?>([
        storage.read(key: SecureStoreKey.instanceBaseUrl.value),
        storage.read(key: SecureStoreKey.instanceId.value),
        storage.read(key: SecureStoreKey.activeInstanceScopeId.value),
        storage.read(key: SecureStoreKey.liveDiscoveryValidatedScopeId.value),
        storage.read(key: SecureStoreKey.sessionInstanceScopeId.value),
        storage.read(key: SecureStoreKey.activeWorkspaceId.value),
        storage.read(key: SecureStoreKey.activeWorkspaceInstanceScopeId.value),
        storage.read(key: SecureStoreKey.activeInstanceGeneration.value),
      ]);
      final origin = Uri.tryParse(values[0]?.trim() ?? '');
      if (origin == null) return null;
      final activeScope = InstanceScope(
        instanceId: values[1] ?? '',
        serverOrigin: origin,
      );
      final scopeId = activeScope.storageId;
      if (activeScope != expectedInstanceScope ||
          scopeId != values[2]?.trim() ||
          scopeId != values[3]?.trim() ||
          scopeId != values[4]?.trim() ||
          workspaceId != values[5]?.trim() ||
          scopeId != values[6]?.trim() ||
          values[7]?.trim().isEmpty != false) {
        return null;
      }
      return _ActiveCallInstanceBinding(
        instanceId: activeScope.instanceId,
        serverBaseUrl: activeScope.origin.toString(),
      );
    } on Object {
      return null;
    }
  }

  static Future<bool?> targetMatchesPersistedActiveInstance(
    NotificationTarget target,
  ) async {
    try {
      const storage = FlutterSecureStorage();
      final values = await Future.wait<String?>([
        storage.read(key: SecureStoreKey.instanceId.value),
        storage.read(key: SecureStoreKey.activeInstanceScopeId.value),
        storage.read(key: SecureStoreKey.liveDiscoveryValidatedScopeId.value),
        storage.read(key: SecureStoreKey.sessionInstanceScopeId.value),
        storage.read(key: SecureStoreKey.activeInstanceGeneration.value),
      ]);
      final activeInstanceId = values[0]?.trim().toLowerCase() ?? '';
      final activeScopeId = values[1]?.trim() ?? '';
      if (activeInstanceId.isEmpty ||
          activeScopeId.isEmpty ||
          values[2] != activeScopeId ||
          values[3] != activeScopeId ||
          values[4]?.trim().isEmpty != false) {
        return null;
      }
      return target.isBoundToInstance(activeInstanceId);
    } on Object {
      return null;
    }
  }
}

final class _ActiveCallInstanceBinding {
  const _ActiveCallInstanceBinding({
    required this.instanceId,
    required this.serverBaseUrl,
  });

  final String instanceId;
  final String serverBaseUrl;
}

String? _normalizedInstanceId(Object? value) {
  final normalized = value?.toString().trim().toLowerCase() ?? '';
  return _instanceUuidPattern.hasMatch(normalized) ? normalized : null;
}

final _instanceUuidPattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);

String? _validatedCallServerBaseUrl({
  required String? instanceId,
  required Object? value,
}) {
  if (instanceId == null) return null;
  final uri = Uri.tryParse(value?.toString().trim() ?? '');
  if (uri == null) return null;
  try {
    return InstanceScope(
      instanceId: instanceId,
      serverOrigin: uri,
    ).origin.toString();
  } on FormatException {
    return null;
  }
}

@pragma('vm:entry-point')
Future<void> webTuiCallkitBackgroundHandler(CallEvent event) async {
  DartPluginRegistrant.ensureInitialized();
  final action = NativeIncomingCallService.actionFromCallkitEvent(event);
  if (action == null) return;
  // Accept is a visible media/signaling transition. Never complete or ack it
  // headlessly: native accept foregrounds the app, then the WebRTC screen asks
  // for media permission before accepting the server call.
  if (action.type == NativeIncomingCallActionType.accept) return;
  final instanceMatches =
      await NativeIncomingCallService.targetMatchesPersistedActiveInstance(
        action.target,
      );
  if (instanceMatches == false) {
    await NativeIncomingCallService.acknowledge(action);
    return;
  }
  if (instanceMatches != true) return;
  if (await const _BackgroundCallActionClient().apply(action)) {
    await NativeIncomingCallService.acknowledge(action);
  }
}

/// Minimal authenticated client used only by the cold CallKit isolate.
///
/// It deliberately does not accept an arbitrary origin from notification
/// payloads. The persisted origin is only a selector and must exact-match the
/// secure active server plus the secure active workspace before a bearer token
/// is attached. Redirects are disabled to prevent cross-origin credential
/// forwarding.
final class _BackgroundCallActionClient {
  const _BackgroundCallActionClient();

  static const _storage = FlutterSecureStorage();

  Future<bool> apply(NativeIncomingCallAction action) async {
    final binding = await _bindingFor(action);
    if (binding == null) return false;
    final callId = action.target.callId?.trim() ?? '';
    if (callId.isEmpty) return false;

    var lookup = await _lookup(binding, callId);
    if (lookup == _CallLookup.notFound || lookup.isTerminal) return true;
    if (lookup == _CallLookup.failed) return false;

    final (endpoint, reason) = switch (action.type) {
      NativeIncomingCallActionType.accept => ('accept', null),
      NativeIncomingCallActionType.timeout when lookup.isActive => (null, null),
      NativeIncomingCallActionType.decline when lookup.isActive => (null, null),
      NativeIncomingCallActionType.decline => ('reject', 'declined'),
      NativeIncomingCallActionType.timeout => ('reject', 'timeout'),
      NativeIncomingCallActionType.ended when lookup.isRinging => (
        'reject',
        'ended',
      ),
      NativeIncomingCallActionType.ended => ('hangup', 'ended'),
    };
    // A timeout racing an already accepted call is stale; never hang up an
    // active call on behalf of a notification timer.
    if (endpoint == null) return true;

    final response = await _authorizedRequest(
      binding,
      method: 'POST',
      path:
          '/api/v1/workspaces/${Uri.encodeComponent(binding.workspaceId)}/'
          'calls/${Uri.encodeComponent(callId)}/$endpoint',
      data: reason == null ? const {} : <String, Object?>{'reason': reason},
    );
    if (response?.isSuccess == true || response?.statusCode == 404) {
      return true;
    }

    // Invalid-transition conflicts are common when another device or the
    // server timeout won the race. Ack only after a fresh read proves the
    // requested action is no longer applicable.
    lookup = await _lookup(binding, callId);
    return lookup == _CallLookup.notFound ||
        lookup.isTerminal ||
        (action.type == NativeIncomingCallActionType.accept && lookup.isActive);
  }

  Future<_BackgroundServerBinding?> _bindingFor(
    NativeIncomingCallAction action,
  ) async {
    try {
      final values = await Future.wait<String?>([
        _storage.read(key: SecureStoreKey.instanceBaseUrl.value),
        _storage.read(key: SecureStoreKey.activeWorkspaceId.value),
        _storage.read(key: SecureStoreKey.accessToken.value),
        _storage.read(key: SecureStoreKey.instanceId.value),
        _storage.read(key: SecureStoreKey.activeInstanceScopeId.value),
        _storage.read(key: SecureStoreKey.liveDiscoveryValidatedScopeId.value),
        _storage.read(key: SecureStoreKey.sessionInstanceScopeId.value),
        _storage.read(key: SecureStoreKey.activeWorkspaceInstanceScopeId.value),
        _storage.read(key: SecureStoreKey.activeInstanceGeneration.value),
        _storage.read(key: SecureStoreKey.sessionPersistence.value),
      ]);
      final activeOrigin = validatedBackgroundCallHttpsOrigin(values[0]);
      final actionOrigin = validatedBackgroundCallHttpsOrigin(
        action.serverBaseUrl,
      );
      final activeWorkspace = values[1]?.trim() ?? '';
      final actionWorkspace = action.target.workspaceId.trim();
      final activeScopeId = values[4]?.trim() ?? '';
      final generation = values[8]?.trim() ?? '';
      final durableAccountRecord = await SecureServerAccountRegistry(
        FlutterSecureKeyValueStore(_storage),
      ).hasDurableSessionForScopeId(activeScopeId);
      if (activeOrigin == null ||
          actionOrigin == null ||
          !action.target.isBoundToInstance(values[3] ?? '') ||
          activeScopeId.isEmpty ||
          generation.isEmpty ||
          activeScopeId != values[5] ||
          activeScopeId != values[6] ||
          activeScopeId != values[7] ||
          values[9] != durableSessionPersistenceValue ||
          !durableAccountRecord ||
          !backgroundCallBindingMatches(
            activeOrigin: activeOrigin,
            actionOrigin: actionOrigin,
            activeWorkspaceId: activeWorkspace,
            actionWorkspaceId: actionWorkspace,
          )) {
        return null;
      }
      final binding = _BackgroundServerBinding(
        origin: activeOrigin,
        workspaceId: activeWorkspace,
        instanceId: values[3]!.trim().toLowerCase(),
        instanceScopeId: activeScopeId,
        generation: generation,
        accessToken: values[2]?.trim() ?? '',
      );
      if (binding.accessToken.isEmpty ||
          !await _bindingIsStillCurrent(binding)) {
        return null;
      }
      return binding;
    } on Object {
      return null;
    }
  }

  Future<_CallLookup> _lookup(
    _BackgroundServerBinding binding,
    String callId,
  ) async {
    if (!await _bindingIsStillCurrent(binding)) {
      return _CallLookup.failed;
    }
    final response = await _authorizedRequest(
      binding,
      method: 'GET',
      path:
          '/api/v1/workspaces/${Uri.encodeComponent(binding.workspaceId)}/'
          'calls/${Uri.encodeComponent(callId)}',
    );
    if (!await _bindingIsStillCurrent(binding)) {
      return _CallLookup.failed;
    }
    if (response == null) return _CallLookup.failed;
    if (response.statusCode == 404) return _CallLookup.notFound;
    if (!response.isSuccess) return _CallLookup.failed;
    final status = _findStringField(response.jsonBody, 'status')?.toLowerCase();
    return switch (status) {
      'ringing' => _CallLookup.ringing,
      'accepted' || 'connecting' || 'active' => _CallLookup.active,
      'rejected' ||
      'cancelled' ||
      'canceled' ||
      'ended' ||
      'missed' => _CallLookup.terminal,
      _ => _CallLookup.failed,
    };
  }

  Future<_BackgroundHttpResponse?> _authorizedRequest(
    _BackgroundServerBinding binding, {
    required String method,
    required String path,
    Object? data,
  }) async {
    if (!await _bindingIsStillCurrent(binding)) return null;
    final response = await _request(
      binding.origin,
      method: method,
      path: path,
      bearerToken: binding.accessToken,
      data: data,
    );
    if (!await _bindingIsStillCurrent(binding)) return null;
    // Refresh tokens rotate on the backend. A headless isolate cannot safely
    // persist that rotation atomically with the foreground isolate, so a 401
    // remains durable for foreground handling instead of refreshing here.
    return response;
  }

  Future<bool> _bindingIsStillCurrent(_BackgroundServerBinding binding) async {
    try {
      final values = await Future.wait<String?>([
        _storage.read(key: SecureStoreKey.instanceBaseUrl.value),
        _storage.read(key: SecureStoreKey.activeWorkspaceId.value),
        _storage.read(key: SecureStoreKey.instanceId.value),
        _storage.read(key: SecureStoreKey.activeInstanceScopeId.value),
        _storage.read(key: SecureStoreKey.liveDiscoveryValidatedScopeId.value),
        _storage.read(key: SecureStoreKey.sessionInstanceScopeId.value),
        _storage.read(key: SecureStoreKey.activeWorkspaceInstanceScopeId.value),
        _storage.read(key: SecureStoreKey.activeInstanceGeneration.value),
        _storage.read(key: SecureStoreKey.sessionPersistence.value),
      ]);
      final origin = validatedBackgroundCallHttpsOrigin(values[0]);
      final durableAccountRecord = await SecureServerAccountRegistry(
        FlutterSecureKeyValueStore(_storage),
      ).hasDurableSessionForScopeId(values[3] ?? '');
      return origin != null &&
          backgroundCallCredentialBindingMatches(
            expectedOrigin: binding.origin,
            currentOrigin: origin,
            expectedWorkspaceId: binding.workspaceId,
            currentWorkspaceId: values[1] ?? '',
            expectedInstanceId: binding.instanceId,
            currentInstanceId: values[2] ?? '',
            expectedInstanceScopeId: binding.instanceScopeId,
            activeInstanceScopeId: values[3] ?? '',
            liveInstanceScopeId: values[4] ?? '',
            sessionInstanceScopeId: values[5] ?? '',
            workspaceInstanceScopeId: values[6] ?? '',
            expectedGeneration: binding.generation,
            currentGeneration: values[7] ?? '',
            sessionPersistence: values[8] ?? '',
            durableAccountRecord: durableAccountRecord,
          );
    } on Object {
      return false;
    }
  }

  Future<_BackgroundHttpResponse?> _request(
    Uri origin, {
    required String method,
    required String path,
    String? bearerToken,
    Object? data,
  }) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client
          .openUrl(method, origin.resolve(path))
          .timeout(const Duration(seconds: 10));
      request.followRedirects = false;
      request.maxRedirects = 0;
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      final token = bearerToken?.trim();
      if (token != null && token.isNotEmpty) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      }
      if (data != null) request.write(jsonEncode(data));
      final response = await request.close().timeout(
        const Duration(seconds: 15),
      );
      final bytes = <int>[];
      await for (final chunk in response.timeout(const Duration(seconds: 15))) {
        if (bytes.length + chunk.length > 1024 * 1024) {
          return _BackgroundHttpResponse(response.statusCode, null);
        }
        bytes.addAll(chunk);
      }
      Object? decoded;
      if (bytes.isNotEmpty) {
        try {
          decoded = jsonDecode(utf8.decode(bytes));
        } on FormatException {
          decoded = null;
        }
      }
      return _BackgroundHttpResponse(response.statusCode, decoded);
    } on Object {
      return null;
    } finally {
      client.close(force: true);
    }
  }
}

final class _BackgroundServerBinding {
  _BackgroundServerBinding({
    required this.origin,
    required this.workspaceId,
    required this.instanceId,
    required this.instanceScopeId,
    required this.generation,
    required this.accessToken,
  });

  final Uri origin;
  final String workspaceId;
  final String instanceId;
  final String instanceScopeId;
  final String generation;
  final String accessToken;
}

final class _BackgroundHttpResponse {
  const _BackgroundHttpResponse(this.statusCode, this.jsonBody);

  final int statusCode;
  final Object? jsonBody;

  bool get isSuccess => statusCode >= 200 && statusCode < 300;
}

enum _CallLookup { failed, notFound, ringing, active, terminal }

extension on _CallLookup {
  bool get isRinging => this == _CallLookup.ringing;
  bool get isActive => this == _CallLookup.active;
  bool get isTerminal => this == _CallLookup.terminal;
}

Uri? validatedBackgroundCallHttpsOrigin(String? raw) {
  final uri = Uri.tryParse(raw?.trim() ?? '');
  if (uri == null ||
      uri.scheme.toLowerCase() != 'https' ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment ||
      (uri.path.isNotEmpty && uri.path != '/')) {
    return null;
  }
  return Uri(
    scheme: 'https',
    host: uri.host.toLowerCase(),
    port: uri.hasPort ? uri.port : null,
  );
}

String _originKey(Uri uri) => uri.toString().replaceFirst(RegExp(r'/$'), '');

bool backgroundCallBindingMatches({
  required Uri activeOrigin,
  required Uri actionOrigin,
  required String activeWorkspaceId,
  required String actionWorkspaceId,
}) {
  final activeWorkspace = activeWorkspaceId.trim();
  return activeWorkspace.isNotEmpty &&
      activeWorkspace == actionWorkspaceId.trim() &&
      _originKey(activeOrigin) == _originKey(actionOrigin);
}

bool backgroundCallCredentialBindingMatches({
  required Uri expectedOrigin,
  required Uri currentOrigin,
  required String expectedWorkspaceId,
  required String currentWorkspaceId,
  required String expectedInstanceId,
  required String currentInstanceId,
  required String expectedInstanceScopeId,
  required String activeInstanceScopeId,
  required String liveInstanceScopeId,
  required String sessionInstanceScopeId,
  required String workspaceInstanceScopeId,
  required String expectedGeneration,
  required String currentGeneration,
  required String sessionPersistence,
  bool durableAccountRecord = false,
}) {
  final scopeId = expectedInstanceScopeId.trim();
  final generation = expectedGeneration.trim();
  return scopeId.isNotEmpty &&
      generation.isNotEmpty &&
      sessionPersistence.trim() == durableSessionPersistenceValue &&
      durableAccountRecord &&
      _originKey(expectedOrigin) == _originKey(currentOrigin) &&
      expectedWorkspaceId.trim() == currentWorkspaceId.trim() &&
      expectedWorkspaceId.trim().isNotEmpty &&
      expectedInstanceId.trim().toLowerCase() ==
          currentInstanceId.trim().toLowerCase() &&
      scopeId == activeInstanceScopeId.trim() &&
      scopeId == liveInstanceScopeId.trim() &&
      scopeId == sessionInstanceScopeId.trim() &&
      scopeId == workspaceInstanceScopeId.trim() &&
      generation == currentGeneration.trim();
}

String? _findStringField(Object? value, String key) {
  if (value is Map) {
    final direct = value[key]?.toString().trim();
    if (direct != null && direct.isNotEmpty) return direct;
    for (final nested in value.values) {
      final found = _findStringField(nested, key);
      if (found != null) return found;
    }
  } else if (value is List) {
    for (final nested in value) {
      final found = _findStringField(nested, key);
      if (found != null) return found;
    }
  }
  return null;
}
