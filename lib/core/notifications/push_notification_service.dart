import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../features/auth/domain/repositories/device_identity_repository.dart';
import '../../features/notifications/domain/entities/mobile_notification.dart';
import '../network/api_transport.dart';
import '../security/instance_scope.dart';
import '../security/secure_key_value_store.dart';
import '../security/server_account_registry.dart';
import 'firebase_runtime_options.dart';
import 'native_incoming_call_service.dart';
import 'scoped_local_notification_service.dart';

@pragma('vm:entry-point')
Future<void> webTuiFirebaseMessagingBackgroundHandler(
  RemoteMessage message,
) async {
  DartPluginRegistrant.ensureInitialized();
  await ensureFirebaseRuntime();
  final data = message.data.cast<String, Object?>();
  if (_isCallPayload(data)) {
    if (!await _payloadMatchesPersistedActiveInstance(
      data,
      requireDurableSession: true,
    )) {
      return;
    }
    await NativeIncomingCallService.syncRemoteMessagePayload(
      fallbackWorkspaceId: data['workspace_id']?.toString() ?? '',
      data: data,
    );
    return;
  }
  await displayScopedDataOnlyNotification(
    data: data,
    bindingMatches: (payload) => _payloadMatchesPersistedActiveInstance(
      payload,
      requireDurableSession: true,
    ),
    display: (payload) => ScopedLocalNotificationService.instance.showData(
      payload,
      isStillCurrent: () => _payloadMatchesPersistedActiveInstance(
        payload,
        requireDurableSession: true,
      ),
    ),
  );
}

Future<bool>? _firebaseRuntimeInitialization;

Future<bool> ensureFirebaseRuntime() {
  final inFlight = _firebaseRuntimeInitialization;
  if (inFlight != null) {
    return inFlight;
  }
  final initialization = _initializeFirebaseRuntime();
  _firebaseRuntimeInitialization = initialization;
  return initialization.whenComplete(() {
    if (identical(_firebaseRuntimeInitialization, initialization)) {
      _firebaseRuntimeInitialization = null;
    }
  });
}

Future<bool> _initializeFirebaseRuntime() async {
  try {
    if (Firebase.apps.isEmpty) {
      final options = FirebaseRuntimeOptions.currentPlatform();
      if (options == null) {
        await Firebase.initializeApp();
      } else {
        await Firebase.initializeApp(options: options);
      }
    }
    return true;
  } on Object {
    return false;
  }
}

void configureFirebaseBackgroundMessaging() {
  FirebaseMessaging.onBackgroundMessage(
    webTuiFirebaseMessagingBackgroundHandler,
  );
}

final class WorkspaceRegistrationTicket {
  const WorkspaceRegistrationTicket._({
    required this.workspaceId,
    required this.generation,
    required LatestWorkspaceRegistration coordinator,
  }) : _coordinator = coordinator;

  final String workspaceId;
  final int generation;
  final LatestWorkspaceRegistration _coordinator;

  bool get isCurrent => _coordinator.isCurrent(this);
}

/// Serializes device registrations while exposing the latest routing workspace
/// synchronously. A slow or failed registration can never become the local or
/// server-side winner after a newer workspace has been selected.
final class LatestWorkspaceRegistration {
  String? _workspaceId;
  int _generation = 0;
  Future<void> _tail = Future<void>.value();

  String? get workspaceId => _workspaceId;

  WorkspaceRegistrationTicket? get currentTicket {
    final workspaceId = _workspaceId;
    if (workspaceId == null) return null;
    return WorkspaceRegistrationTicket._(
      workspaceId: workspaceId,
      generation: _generation,
      coordinator: this,
    );
  }

  WorkspaceRegistrationTicket select(String workspaceId) {
    final normalized = workspaceId.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(
        workspaceId,
        'workspaceId',
        'must not be empty',
      );
    }
    _workspaceId = normalized;
    _generation += 1;
    return WorkspaceRegistrationTicket._(
      workspaceId: normalized,
      generation: _generation,
      coordinator: this,
    );
  }

  bool isCurrent(WorkspaceRegistrationTicket ticket) {
    return ticket.generation == _generation &&
        ticket.workspaceId == _workspaceId;
  }

  Future<void> enqueue(
    WorkspaceRegistrationTicket ticket,
    Future<void> Function() operation,
  ) {
    return _append(() async {
      if (!isCurrent(ticket)) return;
      await operation();
    });
  }

  Future<void> clearAndEnqueue(Future<void> Function() operation) {
    invalidate();
    return _append(operation);
  }

  void invalidate() {
    _workspaceId = null;
    _generation += 1;
  }

  Future<void> _append(Future<void> Function() operation) {
    final previous = _tail;
    final next = () async {
      try {
        await previous;
      } on Object {
        // A failed older registration must not poison the latest queued one.
      }
      await operation();
    }();
    _tail = next.then<void>((_) {}, onError: (_, _) {});
    return next;
  }
}

final class PushNotificationService {
  PushNotificationService({
    required ApiTransport api,
    required DeviceIdentityRepository deviceIdentityRepository,
    required InstanceScope instanceScope,
  }) : _api = api,
       _deviceIdentityRepository = deviceIdentityRepository,
       _instanceScope = instanceScope;

  final ApiTransport _api;
  final DeviceIdentityRepository _deviceIdentityRepository;
  final InstanceScope _instanceScope;
  final _openedTargets = StreamController<NotificationTarget>.broadcast();
  final _foregroundTargets = StreamController<NotificationTarget>.broadcast();
  final _seenEventIds = <String>{};
  final _workspaceRegistration = LatestWorkspaceRegistration();
  String? _registeredKey;
  bool _tokenRefreshListening = false;
  bool _messageHandlersStarted = false;
  bool _disposed = false;
  StreamSubscription<String>? _tokenRefreshSubscription;
  StreamSubscription<String>? _voipTokenSubscription;
  StreamSubscription<RemoteMessage>? _messageOpenedSubscription;
  StreamSubscription<RemoteMessage>? _foregroundSubscription;
  StreamSubscription<Map<String, Object?>>? _localNotificationTapSubscription;

  Stream<NotificationTarget> get openedTargets => _openedTargets.stream;
  Stream<NotificationTarget> get foregroundTargets => _foregroundTargets.stream;

  Future<void> registerForWorkspace(String workspaceId) {
    if (_disposed) return Future<void>.value();
    final normalizedWorkspaceId = workspaceId.trim();
    if (normalizedWorkspaceId.isEmpty) {
      return Future<void>.value();
    }
    final ticket = _workspaceRegistration.select(normalizedWorkspaceId);
    _registeredKey = null;
    return _workspaceRegistration.enqueue(
      ticket,
      () => _registerForWorkspace(ticket),
    );
  }

  Future<void> _registerForWorkspace(WorkspaceRegistrationTicket ticket) async {
    final normalizedWorkspaceId = ticket.workspaceId;
    final device = await _deviceIdentityRepository.currentDevice();
    if (!_canContinue(ticket)) return;
    final firebase = await ensureFirebaseRuntime();
    if (!_canContinue(ticket)) return;
    final permission = firebase
        ? await notificationPermissionStatus()
        : 'unknown';
    if (!_canContinue(ticket)) return;
    final canReceivePush =
        permission == 'granted' || permission == 'provisional';
    final token = firebase && canReceivePush ? await _readFcmToken() : null;
    if (!_canContinue(ticket)) return;
    final voipToken = canReceivePush
        ? await NativeIncomingCallService.readVoipPushToken()
        : null;
    if (!_canContinue(ticket)) return;
    final key =
        '${device.id}:$normalizedWorkspaceId:${token ?? ''}:${voipToken ?? ''}:$permission';
    if (_registeredKey == key) {
      return;
    }

    await _upsertDevice(
      workspaceId: normalizedWorkspaceId,
      deviceId: device.id,
      platform: _platform(),
      pushProvider: token == null ? 'none' : 'fcm',
      pushToken: token,
      notificationPermission: permission,
    );
    if (!_canContinue(ticket)) return;
    if (voipToken != null) {
      await _upsertDevice(
        workspaceId: normalizedWorkspaceId,
        deviceId: '${device.id}:voip',
        platform: 'ios',
        pushProvider: 'apns',
        pushToken: voipToken,
        notificationPermission: permission == 'denied' ? 'denied' : 'granted',
      );
      if (!_canContinue(ticket)) return;
    }
    _registeredKey = key;
    if (canReceivePush) {
      _voipTokenSubscription ??= NativeIncomingCallService.voipTokens.listen((
        nextToken,
      ) {
        final currentTicket = _workspaceRegistration.currentTicket;
        if (currentTicket == null) return;
        _registeredKey = null;
        unawaited(
          _workspaceRegistration.enqueue(currentTicket, () async {
            if (nextToken.trim().isEmpty) {
              await _api.delete<Object>(
                '/api/v1/mobile/devices/${_e('${device.id}:voip')}',
              );
              return;
            }
            await _upsertDevice(
              workspaceId: currentTicket.workspaceId,
              deviceId: '${device.id}:voip',
              platform: 'ios',
              pushProvider: 'apns',
              pushToken: nextToken.trim(),
              notificationPermission: 'granted',
            );
          }),
        );
      });
    }

    if (firebase && _canContinue(ticket)) {
      _startMessageHandlers();
      if (canReceivePush && !_tokenRefreshListening) {
        _tokenRefreshListening = true;
        _tokenRefreshSubscription = FirebaseMessaging.instance.onTokenRefresh
            .listen((nextToken) {
              final currentTicket = _workspaceRegistration.currentTicket;
              if (currentTicket == null) return;
              _registeredKey = null;
              unawaited(
                _workspaceRegistration.enqueue(currentTicket, () async {
                  await _upsertDevice(
                    workspaceId: currentTicket.workspaceId,
                    deviceId: device.id,
                    platform: _platform(),
                    pushProvider: 'fcm',
                    pushToken: nextToken,
                    notificationPermission: permission,
                  );
                }),
              );
            });
      }
    }
  }

  Future<String> notificationPermissionStatus() async {
    try {
      final settings = await FirebaseMessaging.instance
          .getNotificationSettings();
      return _permissionLabel(settings.authorizationStatus);
    } on Object {
      return 'unknown';
    }
  }

  Future<String> requestNotificationPermissionForWorkspace(
    String workspaceId,
  ) async {
    final firebase = await ensureFirebaseRuntime();
    if (!firebase) {
      return 'unknown';
    }
    final permission = await _requestPermission();
    if (permission == 'granted' || permission == 'provisional') {
      await NativeIncomingCallService.prepareDevicePermissions();
    }
    _registeredKey = null;
    await registerForWorkspace(workspaceId);
    return permission;
  }

  Future<void> unregister() {
    if (_disposed) return Future<void>.value();
    _registeredKey = null;
    return _workspaceRegistration.clearAndEnqueue(() async {
      final device = await _deviceIdentityRepository.currentDevice();
      await _api.delete<Object>('/api/v1/mobile/devices/${_e(device.id)}');
      if (Platform.isIOS) {
        await _api.delete<Object>(
          '/api/v1/mobile/devices/${_e('${device.id}:voip')}',
        );
      }
    });
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _workspaceRegistration.invalidate();
    await _tokenRefreshSubscription?.cancel();
    await _voipTokenSubscription?.cancel();
    await _messageOpenedSubscription?.cancel();
    await _foregroundSubscription?.cancel();
    await _localNotificationTapSubscription?.cancel();
    await _openedTargets.close();
    await _foregroundTargets.close();
  }

  String? get _currentRegisteredWorkspaceId {
    final workspaceId = _workspaceRegistration.workspaceId?.trim();
    return workspaceId == null || workspaceId.isEmpty ? null : workspaceId;
  }

  bool _canContinue(WorkspaceRegistrationTicket ticket) {
    return !_disposed && ticket.isCurrent;
  }

  void _startMessageHandlers() {
    if (_messageHandlersStarted) {
      return;
    }
    _messageHandlersStarted = true;
    configureFirebaseBackgroundMessaging();
    _localNotificationTapSubscription ??= ScopedLocalNotificationService
        .instance
        .taps
        .listen((data) {
          unawaited(
            _emitDataForRegisteredWorkspace(
              data,
              _openedTargets,
              eventId: _eventIdFromData(data),
            ),
          );
        });
    _messageOpenedSubscription = FirebaseMessaging.onMessageOpenedApp.listen(
      (message) => unawaited(
        _emitRemoteMessageForRegisteredWorkspace(message, _openedTargets),
      ),
    );
    _foregroundSubscription = FirebaseMessaging.onMessage.listen(
      (message) => unawaited(
        _emitRemoteMessageForRegisteredWorkspace(message, _foregroundTargets),
      ),
    );
    FirebaseMessaging.instance.getInitialMessage().then((message) {
      if (message != null) {
        unawaited(
          _emitRemoteMessageForRegisteredWorkspace(message, _openedTargets),
        );
      }
    });
  }

  Future<String> _requestPermission() async {
    try {
      final settings = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      return _permissionLabel(settings.authorizationStatus);
    } on Object {
      return 'unknown';
    }
  }

  String _permissionLabel(AuthorizationStatus status) {
    return switch (status) {
      AuthorizationStatus.authorized => 'granted',
      AuthorizationStatus.provisional => 'provisional',
      AuthorizationStatus.denied => 'denied',
      AuthorizationStatus.notDetermined => 'unknown',
    };
  }

  Future<String?> _readFcmToken() async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      final trimmed = token?.trim();
      return trimmed == null || trimmed.isEmpty ? null : trimmed;
    } on Object {
      return null;
    }
  }

  Future<void> _upsertDevice({
    required String workspaceId,
    required String deviceId,
    required String platform,
    required String pushProvider,
    required String? pushToken,
    required String notificationPermission,
  }) async {
    await _api.post<Object>(
      '/api/v1/mobile/devices',
      data: {
        'workspace_id': workspaceId,
        'device_id': deviceId,
        'platform': platform,
        'push_provider': pushProvider,
        'push_token': pushToken ?? '',
        'notification_permission': notificationPermission,
        'release_channel': 'mobile',
        'locale': WidgetsBinding.instance.platformDispatcher.locale
            .toLanguageTag(),
        'timezone': DateTime.now().timeZoneName,
      },
    );
  }

  Future<void> _emitRemoteMessageIfCurrent(
    RemoteMessage message,
    String workspaceId,
    StreamController<NotificationTarget> controller,
  ) {
    return _emitDataIfCurrent(
      message.data.cast<String, Object?>(),
      workspaceId,
      controller,
      eventId: _eventId(message),
    );
  }

  Future<void> _emitRemoteMessageForRegisteredWorkspace(
    RemoteMessage message,
    StreamController<NotificationTarget> controller,
  ) async {
    final workspaceId = _currentRegisteredWorkspaceId;
    if (workspaceId == null) return;
    await _emitRemoteMessageIfCurrent(message, workspaceId, controller);
  }

  Future<void> _emitDataForRegisteredWorkspace(
    Map<String, Object?> data,
    StreamController<NotificationTarget> controller, {
    required String? eventId,
  }) async {
    final workspaceId = _currentRegisteredWorkspaceId;
    if (workspaceId == null) return;
    await _emitDataIfCurrent(data, workspaceId, controller, eventId: eventId);
  }

  Future<void> _emitDataIfCurrent(
    Map<String, Object?> data,
    String workspaceId,
    StreamController<NotificationTarget> controller, {
    required String? eventId,
  }) async {
    final persistedBindingMatches =
        await _payloadMatchesPersistedActiveInstance(data);
    final target = scopedNotificationTargetIfCurrent(
      data: data,
      instanceScope: _instanceScope,
      workspaceId: workspaceId,
      persistedBindingMatches: persistedBindingMatches,
    );
    if (target == null) return;
    if (eventId != null && !_seenEventIds.add(eventId)) {
      return;
    }
    if (_seenEventIds.length > 128) {
      _seenEventIds.clear();
      if (eventId != null) {
        _seenEventIds.add(eventId);
      }
    }
    if (target.targetType == 'call' &&
        target.eventType == 'call_ended' &&
        target.callId?.trim().isNotEmpty == true) {
      unawaited(NativeIncomingCallService.endCall(target.callId!));
    }
    if (target.canOpenConversation || target.deepLink != null) {
      controller.add(target);
    }
  }
}

Future<bool> _payloadMatchesPersistedActiveInstance(
  Map<String, Object?> data, {
  bool requireDurableSession = false,
}) async {
  try {
    const storage = FlutterSecureKeyValueStore(FlutterSecureStorage());
    final values = await Future.wait<String?>([
      storage.read(SecureStoreKey.instanceBaseUrl),
      storage.read(SecureStoreKey.instanceId),
      storage.read(SecureStoreKey.activeInstanceScopeId),
      storage.read(SecureStoreKey.liveDiscoveryValidatedScopeId),
      storage.read(SecureStoreKey.sessionInstanceScopeId),
      storage.read(SecureStoreKey.activeWorkspaceId),
      storage.read(SecureStoreKey.activeWorkspaceInstanceScopeId),
      storage.read(SecureStoreKey.activeInstanceGeneration),
      storage.read(SecureStoreKey.sessionPersistence),
    ]);
    final durableAccountRecord =
        !requireDurableSession ||
        await SecureServerAccountRegistry(
          storage,
        ).hasDurableSessionForScopeId(values[2] ?? '');
    return notificationBindingMatches(
      payloadInstanceId: data['instance_id']?.toString(),
      payloadWorkspaceId: data['workspace_id']?.toString(),
      activeServerBaseUrl: values[0],
      activeInstanceId: values[1],
      activeInstanceScopeId: values[2],
      liveInstanceScopeId: values[3],
      sessionInstanceScopeId: values[4],
      activeWorkspaceId: values[5],
      workspaceInstanceScopeId: values[6],
      activeInstanceGeneration: values[7],
      sessionPersistence: values[8],
      requireDurableSession: requireDurableSession,
      durableAccountRecord: durableAccountRecord,
    );
  } on Object {
    return false;
  }
}

Future<bool> displayScopedDataOnlyNotification({
  required Map<String, Object?> data,
  required Future<bool> Function(Map<String, Object?> data) bindingMatches,
  required Future<bool> Function(Map<String, Object?> data) display,
}) async {
  if (!await bindingMatches(data) ||
      scopedNotificationRoutingData(data) == null) {
    return false;
  }
  try {
    if (!await bindingMatches(data)) return false;
    return await display(data);
  } on Object {
    return false;
  }
}

NotificationTarget? scopedNotificationTargetIfCurrent({
  required Map<String, Object?> data,
  required InstanceScope instanceScope,
  required String workspaceId,
  required bool persistedBindingMatches,
}) {
  if (!persistedBindingMatches) return null;
  final expectedWorkspaceId = workspaceId.trim();
  final payloadWorkspaceId = data['workspace_id']?.toString().trim() ?? '';
  if (expectedWorkspaceId.isEmpty ||
      payloadWorkspaceId != expectedWorkspaceId) {
    return null;
  }
  final target = NotificationTarget.fromPayload(
    workspaceId: payloadWorkspaceId,
    data: data,
  );
  if (!target.isBoundToInstance(instanceScope.instanceId) ||
      (!target.canOpenConversation && target.deepLink == null)) {
    return null;
  }
  return target;
}

bool notificationBindingMatches({
  required String? payloadInstanceId,
  required String? payloadWorkspaceId,
  required String? activeServerBaseUrl,
  required String? activeInstanceId,
  required String? activeInstanceScopeId,
  required String? liveInstanceScopeId,
  required String? sessionInstanceScopeId,
  required String? activeWorkspaceId,
  required String? workspaceInstanceScopeId,
  required String? activeInstanceGeneration,
  String? sessionPersistence,
  bool requireDurableSession = false,
  bool durableAccountRecord = false,
}) {
  final origin = Uri.tryParse(activeServerBaseUrl?.trim() ?? '');
  if (origin == null) return false;
  try {
    final activeScope = InstanceScope(
      instanceId: activeInstanceId ?? '',
      serverOrigin: origin,
    );
    final scopeId = activeScope.storageId;
    return (!requireDurableSession ||
            (sessionPersistence?.trim() == durableSessionPersistenceValue &&
                durableAccountRecord)) &&
        notificationInstanceMatches(
          payloadInstanceId: payloadInstanceId,
          activeInstanceId: activeScope.instanceId,
        ) &&
        payloadWorkspaceId?.trim().isNotEmpty == true &&
        payloadWorkspaceId?.trim() == activeWorkspaceId?.trim() &&
        scopeId == activeInstanceScopeId?.trim() &&
        scopeId == liveInstanceScopeId?.trim() &&
        scopeId == sessionInstanceScopeId?.trim() &&
        scopeId == workspaceInstanceScopeId?.trim() &&
        activeInstanceGeneration?.trim().isNotEmpty == true;
  } on FormatException {
    return false;
  }
}

bool notificationInstanceMatches({
  required String? payloadInstanceId,
  required String? activeInstanceId,
}) {
  final payload = payloadInstanceId?.trim().toLowerCase() ?? '';
  final active = activeInstanceId?.trim().toLowerCase() ?? '';
  return payload.isNotEmpty && active.isNotEmpty && payload == active;
}

String? _eventId(RemoteMessage message) {
  return _eventIdFromData(message.data) ?? message.messageId;
}

String? _eventIdFromData(Map<String, Object?> data) {
  for (final key in const [
    'event_id',
    'eventId',
    'notification_id',
    'notificationId',
  ]) {
    final value = data[key]?.toString().trim();
    if (value != null && value.isNotEmpty) {
      return value;
    }
  }
  return null;
}

bool _isCallPayload(Map<String, Object?> data) {
  final targetType = data['target_type']?.toString().trim().toLowerCase();
  final eventType = data['event_type']?.toString().trim().toLowerCase();
  return targetType == 'call' || eventType?.startsWith('call_') == true;
}

String _platform() {
  if (Platform.isAndroid) {
    return 'android';
  }
  if (Platform.isIOS) {
    return 'ios';
  }
  return 'desktop';
}

String _e(String value) => Uri.encodeComponent(value);
