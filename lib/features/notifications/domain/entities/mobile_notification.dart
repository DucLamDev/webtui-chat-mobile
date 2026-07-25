enum NotificationMode { all, mentions, muted }

final class MobileNotification {
  const MobileNotification({
    required this.id,
    required this.workspaceId,
    required this.type,
    required this.title,
    required this.body,
    required this.createdAt,
    this.channelId,
    this.messageId,
    this.data = const {},
    this.readAt,
    this.deliveredAt,
  });

  final String id;
  final String workspaceId;
  final String? channelId;
  final String? messageId;
  final String type;
  final String title;
  final String body;
  final Map<String, Object?> data;
  final DateTime? readAt;
  final DateTime? deliveredAt;
  final DateTime createdAt;

  bool get isRead => readAt != null;

  NotificationTarget get target {
    return NotificationTarget.fromPayload(
      workspaceId: workspaceId,
      channelId: channelId,
      messageId: messageId,
      data: data,
    );
  }

  MobileNotification copyWith({DateTime? readAt}) {
    return MobileNotification(
      id: id,
      workspaceId: workspaceId,
      channelId: channelId,
      messageId: messageId,
      type: type,
      title: title,
      body: body,
      data: data,
      readAt: readAt ?? this.readAt,
      deliveredAt: deliveredAt,
      createdAt: createdAt,
    );
  }
}

final class NotificationPreference {
  const NotificationPreference({
    required this.workspaceId,
    this.mode = NotificationMode.all,
    this.preview = true,
    this.quietHours = false,
    this.quietStart = '22:00',
    this.quietEnd = '07:00',
    this.sound = true,
    this.vibrate = true,
    this.callRinging = true,
    this.badgeEnabled = true,
  });

  final String workspaceId;
  final NotificationMode mode;
  final bool preview;
  final bool quietHours;
  final String quietStart;
  final String quietEnd;
  final bool sound;
  final bool vibrate;
  final bool callRinging;
  final bool badgeEnabled;
}

final class PushDeviceRegistration {
  const PushDeviceRegistration({
    required this.id,
    required this.workspaceId,
    required this.deviceId,
    required this.platform,
    required this.pushProvider,
    required this.notificationPermission,
    required this.status,
    this.hasPushToken = false,
    this.lastSeenAt,
  });

  final String id;
  final String workspaceId;
  final String deviceId;
  final String platform;
  final String pushProvider;
  final bool hasPushToken;
  final String notificationPermission;
  final String status;
  final DateTime? lastSeenAt;
}

final class NotificationTarget {
  const NotificationTarget({
    required this.workspaceId,
    this.channelId,
    this.messageId,
    this.deepLink,
    this.targetType,
    this.eventType,
    this.callId,
    this.callMode,
    this.callStatus,
    this.callerName,
  });

  factory NotificationTarget.fromPayload({
    required String workspaceId,
    String? channelId,
    String? messageId,
    Map<String, Object?> data = const {},
  }) {
    final deepLink = _firstString(data, const ['deep_link', 'deepLink']);
    final linkTarget = deepLink == null || !_isInternalDeepLink(deepLink)
        ? null
        : NotificationTarget.fromUri(
            deepLink,
            fallbackWorkspaceId: workspaceId,
          );
    final resolvedWorkspaceId = _firstString(data, const [
      'workspace_id',
      'workspaceId',
    ], fallback: linkTarget?.workspaceId ?? workspaceId);
    return NotificationTarget(
      workspaceId: resolvedWorkspaceId ?? '',
      channelId: _firstString(data, const [
        'channel_id',
        'channelId',
        'conversation_id',
        'conversationId',
      ], fallback: channelId ?? linkTarget?.channelId),
      messageId: _firstString(data, const [
        'message_id',
        'messageId',
      ], fallback: messageId ?? linkTarget?.messageId),
      deepLink: linkTarget?.deepLink,
      targetType: _firstString(data, const ['target_type', 'targetType']),
      eventType: _firstString(data, const ['event_type', 'eventType']),
      callId: _firstString(data, const ['call_id', 'callId']),
      callMode: _firstString(data, const ['mode', 'call_mode', 'callMode']),
      callStatus: _firstString(data, const [
        'status',
        'call_status',
        'callStatus',
      ]),
      callerName: _firstString(data, const [
        'caller_name',
        'callerName',
        'body',
      ]),
    );
  }

  factory NotificationTarget.fromUri(
    String value, {
    required String fallbackWorkspaceId,
  }) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null || !_isInternalUri(uri)) {
      return NotificationTarget(workspaceId: fallbackWorkspaceId);
    }
    final segments = uri.pathSegments;
    String? channelId;
    if (segments.length >= 2 && segments.first == 'conversations') {
      channelId = segments[1];
    }
    return NotificationTarget(
      workspaceId:
          uri.queryParameters['workspaceId'] ??
          uri.queryParameters['workspace_id'] ??
          fallbackWorkspaceId,
      channelId: channelId ?? uri.queryParameters['channelId'],
      messageId:
          uri.queryParameters['messageId'] ?? uri.queryParameters['message_id'],
      deepLink: value,
      targetType: uri.queryParameters['targetType'],
    );
  }

  final String workspaceId;
  final String? channelId;
  final String? messageId;
  final String? deepLink;
  final String? targetType;
  final String? eventType;
  final String? callId;
  final String? callMode;
  final String? callStatus;
  final String? callerName;

  bool get canOpenConversation =>
      workspaceId.trim().isNotEmpty && channelId?.trim().isNotEmpty == true;

  bool get isIncomingCall =>
      targetType == 'call' &&
      eventType == 'call_invite' &&
      callStatus == 'ringing' &&
      callId?.trim().isNotEmpty == true;
}

String? _firstString(
  Map<String, Object?> data,
  Iterable<String> keys, {
  String? fallback,
}) {
  for (final key in keys) {
    final value = data[key]?.toString().trim();
    if (value != null && value.isNotEmpty) {
      return value;
    }
  }
  final normalizedFallback = fallback?.trim();
  if (normalizedFallback != null && normalizedFallback.isNotEmpty) {
    return normalizedFallback;
  }
  return null;
}

bool _isInternalDeepLink(String value) {
  final uri = Uri.tryParse(value.trim());
  return uri != null && _isInternalUri(uri);
}

bool _isInternalUri(Uri uri) {
  final scheme = uri.scheme.toLowerCase();
  if (scheme.isEmpty) {
    final firstSegment = uri.pathSegments.isEmpty
        ? null
        : uri.pathSegments.first;
    return firstSegment == 'conversations' || firstSegment == 'notifications';
  }
  return scheme == 'webtui';
}
