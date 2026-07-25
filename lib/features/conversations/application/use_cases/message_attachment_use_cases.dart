import 'dart:typed_data';

import 'package:uuid/uuid.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/result/result.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/repositories/message_attachment_repository.dart';

final class PickMessageAttachmentUseCase {
  const PickMessageAttachmentUseCase(this._repository);

  final MessageAttachmentPickerRepository _repository;

  Future<Result<PickedMessageAttachment?>> execute(
    MessageAttachmentPickSource source,
  ) {
    return _repository.pick(source);
  }
}

final class StartVoiceMessageRecordingUseCase {
  const StartVoiceMessageRecordingUseCase(this._repository);

  final MessageVoiceRecorderRepository _repository;

  Future<Result<void>> execute() {
    return _repository.start();
  }
}

final class StopVoiceMessageRecordingUseCase {
  const StopVoiceMessageRecordingUseCase(this._repository);

  final MessageVoiceRecorderRepository _repository;

  Future<Result<PickedMessageAttachment?>> execute() {
    return _repository.stop();
  }
}

final class CancelVoiceMessageRecordingUseCase {
  const CancelVoiceMessageRecordingUseCase(this._repository);

  final MessageVoiceRecorderRepository _repository;

  Future<Result<void>> execute() {
    return _repository.cancel();
  }
}

final class UploadMessageAttachmentUseCase {
  const UploadMessageAttachmentUseCase(this._repository);

  final MessageAttachmentRepository _repository;

  static const maxBytes = 100 * 1024 * 1024;
  static const allowedPrefixes = ['image/', 'video/', 'audio/'];
  static const allowedExact = {
    'application/pdf',
    'text/plain',
    'application/zip',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  };

  Future<Result<UploadedMessageFile>> execute({
    required String workspaceId,
    required PickedMessageAttachment attachment,
  }) {
    final failure = _validateAttachment(attachment);
    if (failure != null) {
      return Future.value(FailureResult(failure));
    }
    return _repository.uploadFile(
      workspaceId: workspaceId,
      attachment: attachment,
    );
  }
}

final class AttachUploadedFileUseCase {
  const AttachUploadedFileUseCase(this._repository);

  final MessageAttachmentRepository _repository;

  Future<Result<MessageAttachment>> execute({
    required String workspaceId,
    required String channelId,
    required String messageId,
    required String fileId,
    int sortOrder = 0,
  }) {
    if (fileId.trim().isEmpty) {
      return Future.value(
        const FailureResult(
          Failure(
            kind: FailureKind.validation,
            message: 'File chưa sẵn sàng để gắn vào tin nhắn.',
            code: 'ATTACHMENT_FILE_REQUIRED',
          ),
        ),
      );
    }
    return _repository.attachFile(
      workspaceId: workspaceId,
      channelId: channelId,
      messageId: messageId,
      fileId: fileId,
      sortOrder: sortOrder,
    );
  }
}

final class ListMessageAttachmentsUseCase {
  const ListMessageAttachmentsUseCase(this._repository);

  final MessageAttachmentRepository _repository;

  Future<Result<List<MessageAttachment>>> execute({
    required String workspaceId,
    required String channelId,
    required String messageId,
  }) {
    return _repository.listAttachments(
      workspaceId: workspaceId,
      channelId: channelId,
      messageId: messageId,
    );
  }
}

final class ListChannelMediaUseCase {
  const ListChannelMediaUseCase(this._repository);

  final MessageAttachmentRepository _repository;

  Future<Result<List<MessageAttachment>>> execute({
    required String workspaceId,
    required String channelId,
    int limit = 500,
  }) {
    return _repository.listChannelMedia(
      workspaceId: workspaceId,
      channelId: channelId,
      limit: limit,
    );
  }
}

final class DownloadMessageAttachmentBytesUseCase {
  const DownloadMessageAttachmentBytesUseCase(this._repository);

  final MessageAttachmentRepository _repository;

  Future<Result<Uint8List>> execute({
    required Uri downloadUri,
    String? mimeType,
  }) {
    if (downloadUri.toString().trim().isEmpty) {
      return Future.value(
        const FailureResult(
          Failure(
            kind: FailureKind.validation,
            message: 'Đường dẫn ảnh không hợp lệ.',
            code: 'ATTACHMENT_DOWNLOAD_URL_INVALID',
          ),
        ),
      );
    }
    return _repository.downloadFileBytes(
      downloadPath: downloadUri.toString(),
      mimeType: mimeType,
    );
  }
}

final class NewAttachmentUploadItemUseCase {
  const NewAttachmentUploadItemUseCase({Uuid uuid = const Uuid()})
    : _uuid = uuid;

  final Uuid _uuid;

  MessageAttachmentUploadItem execute(PickedMessageAttachment picked) {
    return MessageAttachmentUploadItem(
      clientAttachmentId: _uuid.v4(),
      status: MessageAttachmentUploadStatus.queued,
      picked: picked,
    );
  }
}

Failure? _validateAttachment(PickedMessageAttachment attachment) {
  if (attachment.byteSize <= 0 ||
      attachment.byteSize > UploadMessageAttachmentUseCase.maxBytes) {
    return const Failure(
      kind: FailureKind.validation,
      message: 'Tệp phải nhỏ hơn 100MB.',
      code: 'ATTACHMENT_SIZE_INVALID',
    );
  }
  final mime = attachment.mimeType.trim().toLowerCase();
  final allowed =
      UploadMessageAttachmentUseCase.allowedExact.contains(mime) ||
      UploadMessageAttachmentUseCase.allowedPrefixes.any(
        (prefix) => mime.startsWith(prefix),
      );
  if (!allowed) {
    return const Failure(
      kind: FailureKind.validation,
      message: 'Định dạng tệp chưa được hỗ trợ.',
      code: 'ATTACHMENT_MIME_INVALID',
    );
  }
  return null;
}
