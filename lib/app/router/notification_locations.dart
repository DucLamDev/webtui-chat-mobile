import '../../features/conversations/domain/entities/message_card.dart';
import '../../features/inbox/presentation/screens/inbox_list_screen.dart';
import '../../features/notifications/domain/entities/mobile_notification.dart';

/// Đường dẫn của màn cần mở cho một thông báo / liên kết đã phân tích; `null`
/// khi không đủ thông tin để mở.
String? locationForNotificationTarget(NotificationTarget target) {
  if (target.isInboxConversation) {
    return inboxConversationLocation(
      conversationId: target.inboxConversationId!,
      workspaceId: target.workspaceId,
    );
  }
  if (target.isApproval) {
    return Uri(
      path: '/approvals/${Uri.encodeComponent(target.approvalId!.trim())}',
      queryParameters: <String, String>{'workspaceId': target.workspaceId},
    ).toString();
  }
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
    if (target.opensTasks) 'tool': 'tasks',
    if (target.opensTasks && target.taskId?.trim().isNotEmpty == true)
      'taskId': target.taskId!.trim(),
  };
  return Uri(
    path: '/conversations/$channelId',
    queryParameters: params,
  ).toString();
}

/// Đường dẫn cho nút `open` của thẻ bot. Id lấy từ [target] (đã kiểm UUID khi
/// đọc thẻ); thiếu workspace thì dùng [fallbackWorkspaceId] (workspace của tin).
String? locationForCardOpenTarget(
  MessageCardOpenTarget target, {
  required String fallbackWorkspaceId,
}) {
  final workspaceId = (target.workspaceId ?? fallbackWorkspaceId).trim();
  if (workspaceId.isEmpty) return null;

  switch (target.type) {
    case MessageCardOpenTargetType.conversation:
      final channelId = target.channelId;
      if (channelId == null) return null;
      return Uri(
        path: '/conversations/${Uri.encodeComponent(channelId)}',
        queryParameters: <String, String>{
          'workspaceId': workspaceId,
          'title': 'Hội thoại',
          if (target.messageId != null) 'messageId': target.messageId!,
        },
      ).toString();
    case MessageCardOpenTargetType.task:
      final channelId = target.channelId;
      final taskId = target.taskId;
      if (channelId == null || taskId == null) return null;
      return Uri(
        path: '/conversations/${Uri.encodeComponent(channelId)}',
        queryParameters: <String, String>{
          'workspaceId': workspaceId,
          'title': 'Hội thoại',
          'tool': 'tasks',
          'taskId': taskId,
        },
      ).toString();
    case MessageCardOpenTargetType.contacts:
      return Uri(
        path: '/',
        queryParameters: <String, String>{
          'tab': 'contacts',
          'workspaceId': workspaceId,
        },
      ).toString();
    case MessageCardOpenTargetType.approval:
      final approvalId = target.approvalId;
      if (approvalId == null) return null;
      return Uri(
        path: '/approvals/${Uri.encodeComponent(approvalId)}',
        queryParameters: <String, String>{'workspaceId': workspaceId},
      ).toString();
    case MessageCardOpenTargetType.inboxConversation:
      final conversationId = target.conversationId;
      if (conversationId == null) return null;
      return inboxConversationLocation(
        conversationId: conversationId,
        workspaceId: workspaceId,
      );
    case MessageCardOpenTargetType.deviceApproval:
      final sessionId = target.sessionId;
      if (sessionId == null) return null;
      return '/device-approvals/${Uri.encodeComponent(sessionId)}';
    case MessageCardOpenTargetType.callBack:
      final channelId = target.channelId;
      final userId = target.userId;
      final mode = target.callMode;
      if (channelId == null || userId == null || mode == null) return null;
      return Uri(
        path: '/conversations/${Uri.encodeComponent(channelId)}',
        queryParameters: <String, String>{
          'workspaceId': workspaceId,
          'title': 'Hội thoại',
          'peerUserId': userId,
          'startCall': mode == MessageCardCallMode.video ? 'video' : 'audio',
        },
      ).toString();
  }
}
