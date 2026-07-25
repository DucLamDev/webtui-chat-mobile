import 'dart:typed_data';

import '../../../../core/result/result.dart';
import '../../../../core/result/result_guard.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/repositories/message_attachment_repository.dart';
import '../datasources/message_attachment_remote_data_source.dart';

final class MessageAttachmentRepositoryImpl
    implements MessageAttachmentRepository {
  const MessageAttachmentRepositoryImpl(this._remote);

  final MessageAttachmentRemoteDataSource _remote;

  @override
  Future<Result<UploadedMessageFile>> uploadFile({
    required String workspaceId,
    required PickedMessageAttachment attachment,
  }) {
    return guardResult(
      () =>
          _remote.uploadFile(workspaceId: workspaceId, attachment: attachment),
    );
  }

  @override
  Future<Result<MessageAttachment>> attachFile({
    required String workspaceId,
    required String channelId,
    required String messageId,
    required String fileId,
    int sortOrder = 0,
  }) {
    return guardResult(
      () => _remote.attachFile(
        workspaceId: workspaceId,
        channelId: channelId,
        messageId: messageId,
        fileId: fileId,
        sortOrder: sortOrder,
      ),
    );
  }

  @override
  Future<Result<List<MessageAttachment>>> listAttachments({
    required String workspaceId,
    required String channelId,
    required String messageId,
  }) {
    return guardResult(
      () => _remote.listAttachments(
        workspaceId: workspaceId,
        channelId: channelId,
        messageId: messageId,
      ),
    );
  }

  @override
  Future<Result<List<MessageAttachment>>> listChannelMedia({
    required String workspaceId,
    required String channelId,
    int limit = 500,
  }) {
    return guardResult(
      () => _remote.listChannelMedia(
        workspaceId: workspaceId,
        channelId: channelId,
        limit: limit,
      ),
    );
  }

  @override
  Future<Result<Uint8List>> downloadFileBytes({
    required String downloadPath,
    String? mimeType,
  }) {
    return guardResult(
      () => _remote.downloadFileBytes(
        downloadPath: downloadPath,
        mimeType: mimeType,
      ),
    );
  }
}
