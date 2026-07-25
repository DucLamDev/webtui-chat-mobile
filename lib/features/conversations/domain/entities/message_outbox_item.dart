enum MessageOutboxStatus { queued, sending, failed }

final class MessageOutboxAttachment {
  const MessageOutboxAttachment({
    required this.fileId,
    required this.name,
    this.sortOrder = 0,
  });

  final String fileId;
  final String name;
  final int sortOrder;
}

final class MessageOutboxItem {
  const MessageOutboxItem({
    required this.id,
    required this.workspaceId,
    required this.channelId,
    required this.clientMessageId,
    required this.body,
    required this.createdAt,
    required this.updatedAt,
    this.parentId,
    this.attachments = const [],
    this.status = MessageOutboxStatus.queued,
    this.attemptCount = 0,
    this.lastError,
  });

  final String id;
  final String workspaceId;
  final String channelId;
  final String clientMessageId;
  final String body;
  final String? parentId;
  final List<MessageOutboxAttachment> attachments;
  final MessageOutboxStatus status;
  final int attemptCount;
  final String? lastError;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isFailed => status == MessageOutboxStatus.failed;
  bool get isSending => status == MessageOutboxStatus.sending;

  MessageOutboxItem copyWith({
    MessageOutboxStatus? status,
    int? attemptCount,
    String? lastError,
    DateTime? updatedAt,
  }) {
    return MessageOutboxItem(
      id: id,
      workspaceId: workspaceId,
      channelId: channelId,
      clientMessageId: clientMessageId,
      body: body,
      parentId: parentId,
      attachments: attachments,
      status: status ?? this.status,
      attemptCount: attemptCount ?? this.attemptCount,
      lastError: lastError ?? this.lastError,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
