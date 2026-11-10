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
    this.instanceId,
    this.channelId,
    this.messageId,
    this.deepLink,
    this.targetType,
    this.eventType,
    this.callId,
    this.callMode,
    this.callStatus,
    this.callerName,
    this.groupCallId,
    this.meetingId,
    this.channelName,
    this.organizationName,
    this.organizationLogoUrl,
    this.taskId,

    this.answeredDeviceId,

    this.sessionId,
    this.approvalId,
    this.notificationType,
    this.inboxConversationId,
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
    final payloadEventType = _firstString(data, const [
      'event_type',
      'eventType',
    ]);
    // Lõi 7: gọi nhóm có đổ chuông dùng `group_call_id` làm mã cuộc gọi gốc.
    final isGroupCallPayload =
        payloadEventType?.toLowerCase().startsWith('group_call_') == true;
    final groupCallId = _firstString(data, const [
      'group_call_id',
      'groupCallId',
    ]);
    final type = _firstString(data, const [
      'type',
      'notification_type',
      'notificationType',
      'event_type',
      'eventType',
    ])?.toLowerCase();
    // Hộp thư khách: `conversation_id` là hội thoại khách, không phải kênh chat
    // (không được mở / trả lời nhanh như kênh chat).
    final isInbox =
        type == _inboxConversationType ||
        linkTarget?.inboxConversationId != null;
    return NotificationTarget(
      inboxConversationId: isInbox
          ? _firstString(data, const [
              'conversation_id',
              'conversationId',
            ], fallback: linkTarget?.inboxConversationId)
          : null,
      workspaceId: resolvedWorkspaceId ?? '',
      instanceId: _firstString(data, const [
        'instance_id',
      ], fallback: linkTarget?.instanceId),
      channelId: isInbox
          ? null
          : _firstString(data, const [
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
      targetType: _firstString(
        data,
        const ['target_type', 'targetType'],
        fallback:
            linkTarget?.targetType ?? (isGroupCallPayload ? 'call' : null),
      ),
      eventType: payloadEventType,
      callId: _firstString(data, const [
        'call_id',
        'callId',
      ], fallback: isGroupCallPayload ? groupCallId : null),
      groupCallId: isGroupCallPayload ? groupCallId : null,
      meetingId: isGroupCallPayload
          ? _firstString(data, const ['meeting_id', 'meetingId'])
          : null,
      channelName: isGroupCallPayload
          ? _firstString(data, const ['channel_name', 'channelName'])
          : null,
      callMode: _firstString(data, [
        'mode',
        'call_mode',
        'callMode',
        if (isGroupCallPayload) 'kind',
      ]),
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
      organizationName: _firstString(data, const [
        'app_name',
        'organization_name',
        'organizationName',
      ]),
      organizationLogoUrl: _firstString(data, const [
        'logo_url',
        'organization_logo_url',
        'organizationLogoUrl',
      ]),
      taskId: _firstString(data, const [
        'task_id',
        'taskId',
      ], fallback: linkTarget?.taskId),
      answeredDeviceId: _firstString(data, const [
        'answered_device_id',
        'answeredDeviceId',
      ]),
      sessionId: _firstString(data, const ['session_id', 'sessionId']),
      approvalId: _firstString(data, const ['approval_id', 'approvalId']),
      notificationType: _firstString(data, const [
        'type',
        'notification_type',
        'notificationType',
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
    final inboxLink = _inboxLink(uri);
    if (inboxLink != null) {
      return NotificationTarget(
        workspaceId: inboxLink.workspaceId,
        deepLink: value,
        targetType: _inboxConversationType,
        inboxConversationId: inboxLink.conversationId,
      );
    }
    final segments = uri.pathSegments;
    String? channelId;
    String? targetType;
    if (segments.length >= 2 && segments.first == 'conversations') {
      channelId = segments[1];
    } else if (segments.isNotEmpty && segments.first == 'contacts') {
      targetType = 'contact';
    }
    return NotificationTarget(
      workspaceId:
          uri.queryParameters['workspaceId'] ??
          uri.queryParameters['workspace_id'] ??
          fallbackWorkspaceId,
      instanceId: uri.queryParameters['instance_id'],
      channelId: channelId ?? uri.queryParameters['channelId'],
      messageId:
          uri.queryParameters['messageId'] ?? uri.queryParameters['message_id'],
      deepLink: value,
      targetType:
          uri.queryParameters['targetType'] ??
          (uri.queryParameters['tool'] == 'tasks' ? 'task' : targetType),
      taskId: uri.queryParameters['taskId'] ?? uri.queryParameters['task_id'],
    );
  }

  final String workspaceId;
  final String? instanceId;
  final String? channelId;
  final String? messageId;
  final String? deepLink;
  final String? targetType;
  final String? eventType;
  final String? callId;
  final String? callMode;
  final String? callStatus;
  final String? callerName;

  /// Gọi nhóm (Lõi 7): mã cuộc gọi nhóm, cuộc họp và tên kênh; [callId] trùng
  /// [groupCallId] để dùng chung lớp chuông gốc.
  final String? groupCallId;
  final String? meetingId;
  final String? channelName;
  final String? organizationName;
  final String? organizationLogoUrl;

  /// Việc được giao (thông báo `target_type = task`).
  final String? taskId;

  /// Máy đã nhận cuộc gọi (push `call_answered_elsewhere`).
  final String? answeredDeviceId;

  /// Push báo cuộc gọi đã được nhận ở một máy khác của chính người dùng.
  bool get isCallAnsweredElsewhere =>
      (targetType == null || targetType == 'call') &&
      eventType?.trim().toLowerCase() == 'call_answered_elsewhere' &&
      callId?.trim().isNotEmpty == true;

  /// Phiên đang chờ duyệt (`data.session_id` của thông báo
  /// `device_approval_requested`, Lõi 2.3).
  final String? sessionId;

  /// Hội thoại khách (push `inbox_conversation`, Lõi 6).
  final String? inboxConversationId;

  /// Bấm thông báo thì mở màn hội thoại khách tương ứng.
  bool get isInboxConversation =>
      (_normalizedType == _inboxConversationType ||
          targetType?.trim().toLowerCase() == _inboxConversationType) &&
      inboxConversationId?.trim().isNotEmpty == true;

  /// Loại thông báo (`type` / `notification_type`) khi máy chủ gửi kèm.
  final String? notificationType;

  /// Yêu cầu phê duyệt (push `approval_requested` / `approval_updated`).
  final String? approvalId;

  String get _normalizedType =>
      (notificationType ?? eventType ?? '').trim().toLowerCase();

  /// Có yêu cầu phê duyệt mới cần người nhận duyệt.
  bool get isApprovalRequest =>
      _normalizedType == 'approval_requested' &&
      approvalId?.trim().isNotEmpty == true;

  /// Yêu cầu của người nhận đã đổi trạng thái: chỉ cần tải lại danh sách.
  bool get isApprovalUpdate =>
      _normalizedType == 'approval_updated' &&
      approvalId?.trim().isNotEmpty == true;

  bool get isApproval => isApprovalRequest || isApprovalUpdate;

  /// Có thiết bị mới chờ duyệt: mở màn duyệt (màn tự tải dữ liệu từ máy chủ).
  bool get isDeviceApprovalRequest {
    const kind = 'device_approval_requested';
    final matches =
        eventType?.trim().toLowerCase() == kind ||
        notificationType?.trim().toLowerCase() == kind ||
        targetType?.trim().toLowerCase() == kind;
    return matches && sessionId?.trim().isNotEmpty == true;
  }

  /// Bấm thông báo giao việc / đổi hạn thì mở tab Task của phòng.
  bool get opensTasks => targetType == 'task';

  bool get canOpenConversation =>
      workspaceId.trim().isNotEmpty && channelId?.trim().isNotEmpty == true;

  bool get canOpenContacts {
    final normalizedTargetType = targetType?.trim().toLowerCase();
    final normalizedEventType = eventType?.trim().toLowerCase();
    return workspaceId.trim().isNotEmpty &&
        (normalizedTargetType == 'contact' ||
            normalizedEventType == 'contact_request' ||
            normalizedEventType == 'contact_request_accepted' ||
            _deepLinkOpensContacts(deepLink));
  }

  bool isBoundToInstance(String activeInstanceId) {
    final payloadInstanceId = instanceId?.trim().toLowerCase() ?? '';
    return payloadInstanceId.isNotEmpty &&
        payloadInstanceId == activeInstanceId.trim().toLowerCase();
  }

  /// Push / chuông gốc mời vào cuộc gọi nhóm (`group_call_invite`).
  bool get isGroupCallInvite =>
      eventType?.trim().toLowerCase() == 'group_call_invite' &&
      groupCallId?.trim().isNotEmpty == true;

  /// Hết đổ chuông cuộc gọi nhóm (`group_call_cancel`).
  bool get isGroupCallCancel =>
      eventType?.trim().toLowerCase() == 'group_call_cancel' &&
      groupCallId?.trim().isNotEmpty == true;

  bool get isGroupCall => isGroupCallInvite || isGroupCallCancel;

  bool get isIncomingCall =>
      targetType == 'call' &&
      eventType == 'call_invite' &&
      callStatus == 'ringing' &&
      callId?.trim().isNotEmpty == true;
}

const _inboxConversationType = 'inbox_conversation';

/// `webtui://inbox/<workspace>/<hội thoại>`.
({String workspaceId, String conversationId})? _inboxLink(Uri uri) {
  final segments = uri.pathSegments.where((part) => part.isNotEmpty).toList();
  final List<String> rest;
  if (uri.scheme.toLowerCase() == 'webtui' && uri.host == 'inbox') {
    rest = segments;
  } else if (segments.isNotEmpty && segments.first == 'inbox') {
    rest = segments.sublist(1);
  } else {
    return null;
  }
  if (rest.length < 2 || rest[0].trim().isEmpty || rest[1].trim().isEmpty) {
    return null;
  }
  return (workspaceId: rest[0], conversationId: rest[1]);
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
    return firstSegment == 'conversations' ||
        firstSegment == 'contacts' ||
        firstSegment == 'notifications';
  }
  return scheme == 'webtui';
}

bool _deepLinkOpensContacts(String? value) {
  final uri = value == null ? null : Uri.tryParse(value.trim());
  if (uri == null || !_isInternalUri(uri)) {
    return false;
  }
  return uri.pathSegments.isNotEmpty && uri.pathSegments.first == 'contacts';
}
