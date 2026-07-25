final class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.workspaceId,
    required this.channelId,
    required this.kind,
    required this.body,
    required this.createdAt,
    this.senderId,
    this.parentId,
    this.threadRootId,
    this.editedAt,
    this.deletedAt,
    this.updatedAt,
    this.mentions = const [],
    this.reactions = const [],
    this.attachments = const [],
    this.isPinned = false,
    this.isMine = false,
  });

  final String id;
  final String workspaceId;
  final String channelId;
  final String kind;
  final String body;
  final DateTime createdAt;
  final String? senderId;
  final String? parentId;
  final String? threadRootId;
  final DateTime? editedAt;
  final DateTime? deletedAt;
  final DateTime? updatedAt;
  final List<String> mentions;
  final List<MessageReactionSummary> reactions;
  final List<MessageAttachment> attachments;
  final bool isPinned;
  final bool isMine;

  bool get isDeleted => deletedAt != null;
  bool get isSystem => kind == 'system' || senderId == null;
  bool get hasThread => threadRootId != null || parentId != null;

  ChatMessage copyWith({
    String? body,
    DateTime? editedAt,
    DateTime? deletedAt,
    DateTime? updatedAt,
    List<String>? mentions,
    List<MessageReactionSummary>? reactions,
    List<MessageAttachment>? attachments,
    bool? isPinned,
    bool? isMine,
  }) {
    return ChatMessage(
      id: id,
      workspaceId: workspaceId,
      channelId: channelId,
      kind: kind,
      body: body ?? this.body,
      createdAt: createdAt,
      senderId: senderId,
      parentId: parentId,
      threadRootId: threadRootId,
      editedAt: editedAt ?? this.editedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      updatedAt: updatedAt ?? this.updatedAt,
      mentions: mentions ?? this.mentions,
      reactions: reactions ?? this.reactions,
      attachments: attachments ?? this.attachments,
      isPinned: isPinned ?? this.isPinned,
      isMine: isMine ?? this.isMine,
    );
  }
}

enum MessageAttachmentKind { image, video, audio, file }

enum MessageAttachmentPickSource { camera, gallery }

enum MessageAttachmentUploadStatus {
  queued,
  picking,
  uploading,
  uploaded,
  attached,
  failed,
  canceled,
}

final class PickedMessageAttachment {
  const PickedMessageAttachment({
    required this.path,
    required this.fileName,
    required this.mimeType,
    required this.byteSize,
    required this.kind,
  });

  final String path;
  final String fileName;
  final String mimeType;
  final int byteSize;
  final MessageAttachmentKind kind;
}

final class UploadedMessageFile {
  const UploadedMessageFile({
    required this.id,
    required this.name,
    required this.mimeType,
    required this.byteSize,
    required this.downloadPath,
    required this.createdAt,
    this.status = 'ready',
  });

  final String id;
  final String name;
  final String mimeType;
  final int byteSize;
  final String downloadPath;
  final DateTime createdAt;
  final String status;
}

final class MessageAttachment {
  const MessageAttachment({
    required this.id,
    required this.workspaceId,
    required this.messageId,
    required this.fileId,
    required this.file,
    required this.createdAt,
    this.sortOrder = 0,
  });

  final String id;
  final String workspaceId;
  final String messageId;
  final String fileId;
  final UploadedMessageFile file;
  final DateTime createdAt;
  final int sortOrder;

  MessageAttachmentKind get kind =>
      _attachmentKind(file.mimeType, fileName: file.name);
  bool get isImage => kind == MessageAttachmentKind.image;
  bool get isAudio => kind == MessageAttachmentKind.audio;
  bool get isVideo => kind == MessageAttachmentKind.video;
}

final class MessageAttachmentUploadItem {
  const MessageAttachmentUploadItem({
    required this.clientAttachmentId,
    required this.status,
    this.picked,
    this.uploadedFile,
    this.attachment,
    this.progress = 0,
    this.errorMessage,
  });

  final String clientAttachmentId;
  final MessageAttachmentUploadStatus status;
  final PickedMessageAttachment? picked;
  final UploadedMessageFile? uploadedFile;
  final MessageAttachment? attachment;
  final double progress;
  final String? errorMessage;

  MessageAttachmentUploadItem copyWith({
    MessageAttachmentUploadStatus? status,
    PickedMessageAttachment? picked,
    UploadedMessageFile? uploadedFile,
    MessageAttachment? attachment,
    double? progress,
    String? errorMessage,
    bool clearError = false,
  }) {
    return MessageAttachmentUploadItem(
      clientAttachmentId: clientAttachmentId,
      status: status ?? this.status,
      picked: picked ?? this.picked,
      uploadedFile: uploadedFile ?? this.uploadedFile,
      attachment: attachment ?? this.attachment,
      progress: progress ?? this.progress,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    );
  }
}

final class MessagePage {
  const MessagePage({
    required this.messages,
    this.nextCursor,
    this.hasMore = false,
  });

  final List<ChatMessage> messages;
  final String? nextCursor;
  final bool hasMore;
}

final class MessageReactionSummary {
  const MessageReactionSummary({
    required this.emoji,
    required this.count,
    required this.reactedByMe,
  });

  final String emoji;
  final int count;
  final bool reactedByMe;
}

final class ChannelMember {
  const ChannelMember({
    required this.channelId,
    required this.userId,
    required this.email,
    required this.username,
    required this.displayName,
    required this.status,
    required this.joinedAt,
    this.avatarUrl,
    this.lastReadMessageId,
  });

  final String channelId;
  final String userId;
  final String email;
  final String username;
  final String displayName;
  final String status;
  final DateTime joinedAt;
  final String? avatarUrl;
  final String? lastReadMessageId;
}

MessageAttachmentKind _attachmentKind(String mimeType, {String fileName = ''}) {
  final normalized = mimeType.trim().toLowerCase();
  final nameParts = fileName.trim().toLowerCase().split('.');
  final extension = nameParts.length > 1 ? nameParts.last : '';
  if (normalized.startsWith('image/') ||
      const {
        'gif',
        'heic',
        'heif',
        'jpeg',
        'jpg',
        'png',
        'webp',
      }.contains(extension)) {
    return MessageAttachmentKind.image;
  }
  if (normalized.startsWith('video/') ||
      const {'m4v', 'mov', 'mp4', 'webm'}.contains(extension)) {
    return MessageAttachmentKind.video;
  }
  if (normalized.startsWith('audio/') ||
      const {'aac', 'm4a', 'mp3', 'ogg', 'opus', 'wav'}.contains(extension)) {
    return MessageAttachmentKind.audio;
  }
  return MessageAttachmentKind.file;
}
