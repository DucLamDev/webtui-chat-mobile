import 'dart:typed_data';

import '../../../../core/result/result.dart';
import '../entities/chat_message.dart';

abstract interface class MessageAttachmentPickerRepository {
  Future<Result<PickedMessageAttachment?>> pick(
    MessageAttachmentPickSource source,
  );
}

abstract interface class MessageVoiceRecorderRepository {
  Future<Result<void>> start();

  Future<Result<PickedMessageAttachment?>> stop();

  Future<Result<void>> cancel();
}

abstract interface class MessageAttachmentRepository {
  Future<Result<UploadedMessageFile>> uploadFile({
    required String workspaceId,
    required PickedMessageAttachment attachment,
  });

  Future<Result<MessageAttachment>> attachFile({
    required String workspaceId,
    required String channelId,
    required String messageId,
    required String fileId,
    int sortOrder = 0,
  });

  Future<Result<List<MessageAttachment>>> listAttachments({
    required String workspaceId,
    required String channelId,
    required String messageId,
  });

  Future<Result<List<MessageAttachment>>> listChannelMedia({
    required String workspaceId,
    required String channelId,
    int limit = 500,
  });

  Future<Result<Uint8List>> downloadFileBytes({
    required String downloadPath,
    String? mimeType,
  });
}
