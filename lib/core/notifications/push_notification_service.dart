import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/widgets.dart';

import '../../features/auth/domain/repositories/device_identity_repository.dart';
import '../../features/notifications/domain/entities/mobile_notification.dart';
import '../network/api_transport.dart';
import 'firebase_runtime_options.dart';
import 'native_incoming_call_service.dart';

@pragma('vm:entry-point')
Future<void> webTuiFirebaseMessagingBackgroundHandler(
  RemoteMessage message,
) async {
  DartPluginRegistrant.ensureInitialized();
  await ensureFirebaseRuntime();
  await NativeIncomingCallService.syncRemoteMessagePayload(
    fallbackWorkspaceId:
        message.data['workspace_id']?.toString() ??
        message.data['workspaceId']?.toString() ??
        '',
    data: message.data.cast<String, Object?>(),
  );
}

Future<bool> ensureFirebaseRuntime() async {
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

final class PushNotificationService {
  PushNotificationService({
    required ApiTransport api,
    required DeviceIdentityRepository deviceIdentityRepository,
  }) : _api = api,
       _deviceIdentityRepository = deviceIdentityRepository;

  final ApiTransport _api;
  final DeviceIdentityRepository _deviceIdentityRepository;
  final _openedTargets = StreamController<NotificationTarget>.broadcast();
  final _foregroundTargets = StreamController<NotificationTarget>.broadcast();
  final _seenEventIds = <String>{};
  String? _registeredKey;
  String? _registeredWorkspaceId;
  bool _tokenRefreshListening = false;
  bool _messageHandlersStarted = false;
  StreamSubscription<String>? _tokenRefreshSubscription;
  StreamSubscription<RemoteMessage>? _messageOpenedSubscription;
  StreamSubscription<RemoteMessage>? _foregroundSubscription;

  Stream<NotificationTarget> get openedTargets => _openedTargets.stream;
  Stream<NotificationTarget> get foregroundTargets => _foregroundTargets.stream;

  Future<void> registerForWorkspace(String workspaceId) async {
    final normalizedWorkspaceId = workspaceId.trim();
    if (normalizedWorkspaceId.isEmpty) {
      return;
    }

    final device = await _deviceIdentityRepository.currentDevice();
    final firebase = await ensureFirebaseRuntime();
    final permission = firebase ? await _requestPermission() : 'unknown';
    final token = firebase ? await _readFcmToken() : null;
    final key =
        '${device.id}:$normalizedWorkspaceId:${token ?? ''}:$permission';
    if (_registeredKey == key) {
      return;
    }

    await _upsertDevice(
      workspaceId: normalizedWorkspaceId,
      deviceId: device.id,
      platform: _platform(),
      pushToken: token,
      notificationPermission: permission,
    );
    _registeredKey = key;
    _registeredWorkspaceId = normalizedWorkspaceId;

    if (firebase) {
      unawaited(NativeIncomingCallService.prepareDevicePermissions());
      _startMessageHandlers(normalizedWorkspaceId);
      if (!_tokenRefreshListening) {
        _tokenRefreshListening = true;
        _tokenRefreshSubscription = FirebaseMessaging.instance.onTokenRefresh
            .listen((nextToken) {
              _registeredKey = null;
              _upsertDevice(
                workspaceId: _registeredWorkspaceId ?? normalizedWorkspaceId,
                deviceId: device.id,
                platform: _platform(),
                pushToken: nextToken,
                notificationPermission: permission,
              );
            });
      }
    }
  }

  Future<void> unregister() async {
    final device = await _deviceIdentityRepository.currentDevice();
    await _api.delete<Object>('/api/v1/mobile/devices/${_e(device.id)}');
    _registeredKey = null;
    _registeredWorkspaceId = null;
  }

  Future<void> dispose() async {
    await _tokenRefreshSubscription?.cancel();
    await _messageOpenedSubscription?.cancel();
    await _foregroundSubscription?.cancel();
    await _openedTargets.close();
    await _foregroundTargets.close();
  }

  void _startMessageHandlers(String workspaceId) {
    if (_messageHandlersStarted) {
      return;
    }
    _messageHandlersStarted = true;
    configureFirebaseBackgroundMessaging();
    _messageOpenedSubscription = FirebaseMessaging.onMessageOpenedApp.listen(
      (message) => _emitTarget(message, workspaceId, _openedTargets),
    );
    _foregroundSubscription = FirebaseMessaging.onMessage.listen(
      (message) => _emitTarget(message, workspaceId, _foregroundTargets),
    );
    FirebaseMessaging.instance.getInitialMessage().then((message) {
      if (message != null) {
        _emitTarget(message, workspaceId, _openedTargets);
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
      return switch (settings.authorizationStatus) {
        AuthorizationStatus.authorized => 'granted',
        AuthorizationStatus.provisional => 'provisional',
        AuthorizationStatus.denied => 'denied',
        AuthorizationStatus.notDetermined => 'unknown',
      };
    } on Object {
      return 'unknown';
    }
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
    required String? pushToken,
    required String notificationPermission,
  }) async {
    await _api.post<Object>(
      '/api/v1/mobile/devices',
      data: {
        'workspace_id': workspaceId,
        'device_id': deviceId,
        'platform': platform,
        'push_provider': pushToken == null ? 'none' : 'fcm',
        'push_token': pushToken ?? '',
        'notification_permission': notificationPermission,
        'release_channel': 'mobile',
        'locale': WidgetsBinding.instance.platformDispatcher.locale
            .toLanguageTag(),
        'timezone': DateTime.now().timeZoneName,
      },
    );
  }

  void _emitTarget(
    RemoteMessage message,
    String workspaceId,
    StreamController<NotificationTarget> controller,
  ) {
    final eventId = _eventId(message);
    if (eventId != null && !_seenEventIds.add(eventId)) {
      return;
    }
    if (_seenEventIds.length > 128) {
      _seenEventIds.clear();
      if (eventId != null) {
        _seenEventIds.add(eventId);
      }
    }
    final target = NotificationTarget.fromPayload(
      workspaceId: workspaceId,
      data: message.data.cast<String, Object?>(),
    );
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

String? _eventId(RemoteMessage message) {
  for (final key in const [
    'event_id',
    'eventId',
    'notification_id',
    'notificationId',
  ]) {
    final value = message.data[key]?.toString().trim();
    if (value != null && value.isNotEmpty) {
      return value;
    }
  }
  return message.messageId;
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
