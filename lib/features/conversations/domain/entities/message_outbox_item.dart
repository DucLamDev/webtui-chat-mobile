import 'chat_message.dart';

enum MessageOutboxStatus { queued, sending, failed }

/// Tệp của tin chờ CHƯA tải lên xong (người dùng bấm Gửi khi video còn đang
/// nén / tải). Bộ gửi tin chờ tải nốt rồi mới gửi tin.
final class MessageOutboxPendingUpload {
  const MessageOutboxPendingUpload({
    required this.clientAttachmentId,
    required this.localPath,
    required this.fileName,
    required this.mimeType,
    required this.byteSize,
    required this.kind,
    this.sortOrder = 0,
    this.compressVideo = false,
  });

  /// Cùng id với ô tệp trong khung soạn tin: bộ tải dùng chung việc đang chạy.
  final String clientAttachmentId;
  final String localPath;
  final String fileName;
  final String mimeType;
  final int byteSize;
  final MessageAttachmentKind kind;
  final int sortOrder;
  final bool compressVideo;

  PickedMessageAttachment toPicked() => PickedMessageAttachment(
    path: localPath,
    fileName: fileName,
    mimeType: mimeType,
    byteSize: byteSize,
    kind: kind,
    compressVideo: compressVideo,
  );
}

final class MessageOutboxAttachment {
  const MessageOutboxAttachment({
    required this.fileId,
    required this.name,
    this.sortOrder = 0,
    this.mimeType = '',
    this.byteSize = 0,
    this.downloadPath = '',
    this.localPath,
  });

  final String fileId;
  final String name;
  final int sortOrder;
  final String mimeType;
  final int byteSize;
  final String downloadPath;
  final String? localPath;
}

final class MessageOutboxItem {
  const MessageOutboxItem({
    required this.id,
    required this.instanceScopeId,
    required this.workspaceId,
    required this.channelId,
    required this.clientMessageId,
    required this.body,
    required this.createdAt,
    required this.updatedAt,
    this.parentId,
    this.attachments = const [],
    this.pendingUploads = const [],
    this.silent = false,
    this.metadata = const {},
    this.status = MessageOutboxStatus.queued,
    this.attemptCount = 0,
    this.lastError,
  });

  final String id;
  final String instanceScopeId;
  final String workspaceId;
  final String channelId;
  final String clientMessageId;
  final String body;
  final String? parentId;
  final List<MessageOutboxAttachment> attachments;

  /// Tệp còn phải tải lên trước khi gửi tin (rỗng với tin thường).
  final List<MessageOutboxPendingUpload> pendingUploads;
  final bool silent;

  /// `metadata` gửi kèm tin (vd. `voice` của tin thoại).
  final Map<String, Object?> metadata;
  final MessageOutboxStatus status;
  final int attemptCount;
  final String? lastError;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isFailed => status == MessageOutboxStatus.failed;
  bool get isSending => status == MessageOutboxStatus.sending;
  bool get hasPendingUploads => pendingUploads.isNotEmpty;

  MessageOutboxItem copyWith({
    List<MessageOutboxAttachment>? attachments,
    List<MessageOutboxPendingUpload>? pendingUploads,
    MessageOutboxStatus? status,
    int? attemptCount,
    String? lastError,
    DateTime? updatedAt,
  }) {
    return MessageOutboxItem(
      id: id,
      instanceScopeId: instanceScopeId,
      workspaceId: workspaceId,
      channelId: channelId,
      clientMessageId: clientMessageId,
      body: body,
      parentId: parentId,
      attachments: attachments ?? this.attachments,
      pendingUploads: pendingUploads ?? this.pendingUploads,
      silent: silent,
      metadata: metadata,
      status: status ?? this.status,
      attemptCount: attemptCount ?? this.attemptCount,
      lastError: lastError ?? this.lastError,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
