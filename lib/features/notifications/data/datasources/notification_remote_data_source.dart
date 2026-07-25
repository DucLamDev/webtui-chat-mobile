import '../../../../core/network/api_response.dart';
import '../../../../core/network/api_transport.dart';
import '../../domain/entities/mobile_notification.dart';

final class NotificationRemoteDataSource {
  const NotificationRemoteDataSource(this._api);

  final ApiTransport _api;

  Future<List<MobileNotification>> listNotifications({
    required String workspaceId,
    int limit = 50,
  }) async {
    final response = await _api.get<Object>(
      '/api/v1/notifications',
      queryParameters: {'workspace_id': workspaceId, 'limit': limit},
    );
    return envelopeList(
      response.data,
      'notifications',
    ).map(_notificationFromMap).toList(growable: false);
  }

  Future<void> markRead({required String notificationId}) async {
    await _api.put<Object>('/api/v1/notifications/${_e(notificationId)}/read');
  }

  Future<void> markAllRead({required String workspaceId}) async {
    await _api.put<Object>(
      '/api/v1/notifications/read-all',
      queryParameters: {'workspace_id': workspaceId},
    );
  }

  Future<NotificationPreference> getPreference({
    required String workspaceId,
  }) async {
    final response = await _api.get<Object>(
      '/api/v1/notifications/preferences',
      queryParameters: {'workspace_id': workspaceId},
    );
    return _preferenceFromMap(
      envelopeItem(response.data, 'preference'),
      fallbackWorkspaceId: workspaceId,
    );
  }

  Future<NotificationPreference> savePreference(
    NotificationPreference preference,
  ) async {
    final response = await _api.put<Object>(
      '/api/v1/notifications/preferences',
      queryParameters: {'workspace_id': preference.workspaceId},
      data: {
        'workspace_id': preference.workspaceId,
        'mode': _modeToApi(preference.mode),
        'preview': preference.preview,
        'quiet_hours': preference.quietHours,
        'quiet_start': preference.quietStart,
        'quiet_end': preference.quietEnd,
        'sound': preference.sound,
        'vibrate': preference.vibrate,
        'call_ringing': preference.callRinging,
        'badge_enabled': preference.badgeEnabled,
      },
    );
    return _preferenceFromMap(
      envelopeItem(response.data, 'preference'),
      fallbackWorkspaceId: preference.workspaceId,
    );
  }

  Future<List<PushDeviceRegistration>> listPushDevices() async {
    final response = await _api.get<Object>('/api/v1/mobile/devices');
    return envelopeList(
      response.data,
      'devices',
    ).map(_pushDeviceFromMap).toList(growable: false);
  }

  Future<void> unregisterPushDevice({required String deviceId}) async {
    await _api.delete<Object>('/api/v1/mobile/devices/${_e(deviceId)}');
  }
}

MobileNotification _notificationFromMap(JsonMap map) {
  final data = jsonMap(field(map, const ['data']));
  return MobileNotification(
    id: stringField(map, const ['id', 'notification_id', 'notificationId']),
    workspaceId: stringField(map, const ['workspace_id', 'workspaceId']),
    channelId: nullableStringField(map, const ['channel_id', 'channelId']),
    messageId: nullableStringField(map, const ['message_id', 'messageId']),
    type: stringField(map, const ['type'], fallback: 'notification'),
    title: stringField(map, const ['title'], fallback: 'Thông báo'),
    body: stringField(map, const ['body']),
    data: data.cast<String, Object?>(),
    readAt: nullableDateTimeField(map, const ['read_at', 'readAt']),
    deliveredAt: nullableDateTimeField(map, const [
      'delivered_at',
      'deliveredAt',
    ]),
    createdAt: dateTimeField(map, const ['created_at', 'createdAt']),
  );
}

NotificationPreference _preferenceFromMap(
  JsonMap map, {
  required String fallbackWorkspaceId,
}) {
  return NotificationPreference(
    workspaceId: stringField(map, const [
      'workspace_id',
      'workspaceId',
    ], fallback: fallbackWorkspaceId),
    mode: _modeFromApi(stringField(map, const ['mode'], fallback: 'all')),
    preview: boolField(map, const ['preview'], fallback: true),
    quietHours: boolField(map, const ['quiet_hours', 'quietHours']),
    quietStart: stringField(map, const [
      'quiet_start',
      'quietStart',
    ], fallback: '22:00'),
    quietEnd: stringField(map, const [
      'quiet_end',
      'quietEnd',
    ], fallback: '07:00'),
    sound: boolField(map, const ['sound'], fallback: true),
    vibrate: boolField(map, const ['vibrate'], fallback: true),
    callRinging: boolField(map, const [
      'call_ringing',
      'callRinging',
    ], fallback: true),
    badgeEnabled: boolField(map, const [
      'badge_enabled',
      'badgeEnabled',
    ], fallback: true),
  );
}

PushDeviceRegistration _pushDeviceFromMap(JsonMap map) {
  return PushDeviceRegistration(
    id: stringField(map, const ['id']),
    workspaceId: stringField(map, const ['workspace_id', 'workspaceId']),
    deviceId: stringField(map, const ['device_id', 'deviceId']),
    platform: stringField(map, const ['platform']),
    pushProvider: stringField(map, const [
      'push_provider',
      'pushProvider',
    ], fallback: 'none'),
    hasPushToken: boolField(map, const ['has_push_token', 'hasPushToken']),
    notificationPermission: stringField(map, const [
      'notification_permission',
      'notificationPermission',
    ], fallback: 'unknown'),
    status: stringField(map, const ['status'], fallback: 'active'),
    lastSeenAt: nullableDateTimeField(map, const [
      'last_seen_at',
      'lastSeenAt',
    ]),
  );
}

NotificationMode _modeFromApi(String value) {
  return switch (value.trim().toLowerCase()) {
    'mentions' => NotificationMode.mentions,
    'muted' => NotificationMode.muted,
    _ => NotificationMode.all,
  };
}

String _modeToApi(NotificationMode mode) {
  return switch (mode) {
    NotificationMode.all => 'all',
    NotificationMode.mentions => 'mentions',
    NotificationMode.muted => 'muted',
  };
}

String _e(String value) => Uri.encodeComponent(value);
