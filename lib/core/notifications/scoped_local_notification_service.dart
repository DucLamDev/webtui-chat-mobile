import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../features/notifications/domain/entities/mobile_notification.dart';

const _messageChannelId = 'webtui_messages';
const _messageChannelName = 'Tin nhắn';
const _messageChannelDescription = 'Tin nhắn mới và cập nhật cuộc trò chuyện';
const _notificationIcon = 'ic_stat_webtui_chat';

/// A data-only push that is safe to render after the caller has validated the
/// persisted active instance binding.
final class ScopedLocalNotification {
  const ScopedLocalNotification._({
    required this.id,
    required this.tag,
    required this.title,
    required this.body,
    required this.encodedRoutingPayload,
  });

  factory ScopedLocalNotification.fromData(Map<String, Object?> data) {
    final routingData = scopedNotificationRoutingData(data);
    if (routingData == null) {
      throw const FormatException('Notification routing payload is invalid.');
    }
    final instanceId = routingData['instance_id']!;
    final eventId = routingData['event_id']!;
    final digest = sha256.convert(utf8.encode('$instanceId|$eventId'));
    final rawId =
        (digest.bytes[0] << 24) |
        (digest.bytes[1] << 16) |
        (digest.bytes[2] << 8) |
        digest.bytes[3];
    final id = rawId & 0x7fffffff;
    final title = _cleanDisplayText(
      data['title'],
      maxLength: 160,
      fallback: 'WebTUI Chat',
    );
    final body = _cleanDisplayText(
      data['body'],
      maxLength: 512,
      fallback: 'Bạn có thông báo mới',
    );
    return ScopedLocalNotification._(
      id: id == 0 ? 1 : id,
      tag: 'webtui-${digest.toString().substring(0, 32)}',
      title: title,
      body: body,
      encodedRoutingPayload: jsonEncode(<String, Object?>{
        'schema': 1,
        'data': routingData,
      }),
    );
  }

  final int id;
  final String tag;
  final String title;
  final String body;

  /// Contains only instance/workspace/navigation identifiers. Message previews
  /// are never duplicated into the notification tap payload.
  final String encodedRoutingPayload;
}

/// Returns a canonical, allowlisted routing payload, or null for calls and
/// malformed/non-navigable notifications.
Map<String, String>? scopedNotificationRoutingData(Map<String, Object?> data) {
  final instanceId = _normalizedUuid(data['instance_id']);
  final workspaceId = _boundedValue(data['workspace_id'], 128);
  final eventType = _boundedValue(data['event_type'], 64)?.toLowerCase();
  final targetType = _boundedValue(data['target_type'], 64)?.toLowerCase();
  final eventId = _firstBoundedValue(data, const [
    'event_id',
    'notification_id',
    'message_id',
  ], 256);
  if (instanceId == null ||
      workspaceId == null ||
      eventId == null ||
      targetType == 'call' ||
      eventType?.startsWith('call_') == true) {
    return null;
  }

  final target = NotificationTarget.fromPayload(
    workspaceId: workspaceId,
    data: data,
  );
  if (!target.isBoundToInstance(instanceId) ||
      (!target.canOpenConversation && target.deepLink == null)) {
    return null;
  }

  return <String, String>{
    'instance_id': instanceId,
    'workspace_id': workspaceId,
    'event_id': eventId,
    'event_type': ?eventType,
    'target_type': ?targetType,
    'notification_id': ?_boundedValue(data['notification_id'], 256),
    'channel_id': ?_boundedValue(target.channelId, 256),
    'message_id': ?_boundedValue(target.messageId, 256),
    'deep_link': ?_boundedValue(target.deepLink, 1024),
  };
}

Map<String, Object?>? decodeScopedNotificationRoutingPayload(String? encoded) {
  final value = encoded?.trim() ?? '';
  if (value.isEmpty || value.length > 4096) return null;
  try {
    final decoded = jsonDecode(value);
    if (decoded is! Map || decoded['schema'] != 1 || decoded['data'] is! Map) {
      return null;
    }
    final rawData = Map<String, Object?>.from(
      (decoded['data'] as Map).map(
        (key, value) => MapEntry(key.toString(), value),
      ),
    );
    final canonical = scopedNotificationRoutingData(rawData);
    if (canonical == null) return null;
    return canonical.cast<String, Object?>();
  } on Object {
    return null;
  }
}

final class ScopedLocalNotificationService {
  ScopedLocalNotificationService._();

  static final instance = ScopedLocalNotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  final StreamController<Map<String, Object?>> _tapController =
      StreamController<Map<String, Object?>>.broadcast();
  final List<Map<String, Object?>> _pendingTaps = [];
  Future<void>? _initialization;

  Stream<Map<String, Object?>> get taps {
    return Stream.multi((controller) {
      for (final payload in _pendingTaps) {
        controller.add(payload);
      }
      _pendingTaps.clear();
      final subscription = _tapController.stream.listen(
        controller.add,
        onError: controller.addError,
        onDone: controller.close,
      );
      controller.onCancel = subscription.cancel;
    });
  }

  Future<void> initialize({bool inspectLaunchDetails = true}) {
    if (!Platform.isAndroid) return Future.value();
    return _initialization ??=
        _initialize(inspectLaunchDetails: inspectLaunchDetails).catchError((_) {
          _initialization = null;
        });
  }

  Future<void> _initialize({required bool inspectLaunchDetails}) async {
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings(_notificationIcon),
      ),
      onDidReceiveNotificationResponse: _handleResponse,
    );
    if (!inspectLaunchDetails) return;
    final launchDetails = await _plugin.getNotificationAppLaunchDetails();
    if (launchDetails?.didNotificationLaunchApp == true) {
      _recordTap(launchDetails?.notificationResponse?.payload);
    }
  }

  Future<bool> showData(
    Map<String, Object?> data, {
    required Future<bool> Function() isStillCurrent,
  }) async {
    if (!Platform.isAndroid) return false;
    final notification = ScopedLocalNotification.fromData(data);
    await initialize(inspectLaunchDetails: false);
    // Initialization and NotificationManager IPC can each cross a server
    // switch. Revalidate before display and cancel the exact notification if
    // the binding changes while Android is accepting it.
    return showScopedNotificationIfCurrent(
      isStillCurrent: isStillCurrent,
      show: () => _plugin.show(
        id: notification.id,
        title: notification.title,
        body: notification.body,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            _messageChannelId,
            _messageChannelName,
            channelDescription: _messageChannelDescription,
            icon: _notificationIcon,
            importance: Importance.high,
            priority: Priority.high,
            playSound: true,
            enableVibration: true,
            visibility: NotificationVisibility.private,
            fullScreenIntent: false,
            tag: notification.tag,
          ),
        ),
        payload: notification.encodedRoutingPayload,
      ),
      cancel: () => _plugin.cancel(id: notification.id, tag: notification.tag),
    );
  }

  /// Removes only ordinary message notifications. CallKit uses separate
  /// native channels and must survive a chat-server switch/logout long enough
  /// to complete its own terminal lifecycle.
  Future<void> clearMessageNotifications({bool clearPendingTaps = true}) async {
    if (clearPendingTaps) _pendingTaps.clear();
    if (!Platform.isAndroid) return;
    try {
      await initialize(inspectLaunchDetails: false);
      final active = await _plugin.getActiveNotifications();
      for (final target in messageNotificationCancelTargets(active)) {
        await _plugin.cancel(id: target.id, tag: target.tag);
      }
    } on Object {
      // Session invalidation must still complete when an OEM notification
      // service is temporarily unavailable. Tap routing remains fail-closed.
    }
  }

  void _handleResponse(NotificationResponse response) {
    _recordTap(response.payload);
  }

  void _recordTap(String? encoded) {
    final data = decodeScopedNotificationRoutingPayload(encoded);
    if (data == null) return;
    if (_tapController.hasListener) {
      _tapController.add(data);
      return;
    }
    if (_pendingTaps.length >= 16) {
      _pendingTaps.removeAt(0);
    }
    _pendingTaps.add(data);
  }
}

/// Performs the last display boundary as a small transaction. The post-show
/// check closes the final TOCTOU window where a switch invalidates the session
/// after the precheck but before Android records the notification.
Future<bool> showScopedNotificationIfCurrent({
  required Future<bool> Function() isStillCurrent,
  required Future<void> Function() show,
  required Future<void> Function() cancel,
}) async {
  if (!await isStillCurrent()) return false;
  await show();
  if (await isStillCurrent()) return true;
  await cancel();
  return false;
}

List<({int id, String? tag})> messageNotificationCancelTargets(
  Iterable<ActiveNotification> active,
) {
  return active
      .where(
        (notification) =>
            notification.channelId == _messageChannelId &&
            notification.id != null,
      )
      .map((notification) => (id: notification.id!, tag: notification.tag))
      .toList(growable: false);
}

String _cleanDisplayText(
  Object? value, {
  required int maxLength,
  required String fallback,
}) {
  final normalized = value
      ?.toString()
      .replaceAll(RegExp(r'[\u0000-\u001f\u007f]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  final selected = normalized?.isNotEmpty == true ? normalized! : fallback;
  return selected.length <= maxLength
      ? selected
      : selected.substring(0, maxLength);
}

String? _boundedValue(Object? value, int maxLength) {
  final normalized = value?.toString().trim();
  if (normalized == null ||
      normalized.isEmpty ||
      normalized.length > maxLength ||
      normalized.contains(RegExp(r'[\u0000-\u001f\u007f]'))) {
    return null;
  }
  return normalized;
}

String? _firstBoundedValue(
  Map<String, Object?> data,
  List<String> keys,
  int maxLength,
) {
  for (final key in keys) {
    final value = _boundedValue(data[key], maxLength);
    if (value != null) return value;
  }
  return null;
}

String? _normalizedUuid(Object? value) {
  final normalized = value?.toString().trim().toLowerCase() ?? '';
  return _uuidPattern.hasMatch(normalized) ? normalized : null;
}

final _uuidPattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);
