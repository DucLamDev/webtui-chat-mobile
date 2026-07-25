import 'package:uuid/uuid.dart';

import '../../domain/entities/chat_message.dart';
import '../../domain/entities/message_outbox_item.dart';
import '../../domain/repositories/message_outbox_repository.dart';

final class LoadMessageOutboxUseCase {
  const LoadMessageOutboxUseCase(this._repository);

  final MessageOutboxRepository _repository;

  Future<List<MessageOutboxItem>> execute({
    required String workspaceId,
    required String channelId,
  }) {
    return _repository.list(workspaceId: workspaceId, channelId: channelId);
  }
}

final class EnqueueMessageOutboxUseCase {
  const EnqueueMessageOutboxUseCase({
    required MessageOutboxRepository repository,
    Uuid uuid = const Uuid(),
  }) : _repository = repository,
       _uuid = uuid;

  final MessageOutboxRepository _repository;
  final Uuid _uuid;

  Future<MessageOutboxItem> execute({
    required String workspaceId,
    required String channelId,
    required String clientMessageId,
    required String body,
    String? parentId,
    List<MessageOutboxAttachment> attachments = const [],
    String? lastError,
  }) async {
    final now = DateTime.now().toUtc();
    final item = MessageOutboxItem(
      id: _uuid.v4(),
      workspaceId: workspaceId,
      channelId: channelId,
      clientMessageId: clientMessageId,
      body: body,
      parentId: parentId,
      attachments: attachments,
      status: MessageOutboxStatus.failed,
      attemptCount: 1,
      lastError: lastError,
      createdAt: now,
      updatedAt: now,
    );
    await _repository.upsert(item);
    return item;
  }
}

final class SaveMessageOutboxItemUseCase {
  const SaveMessageOutboxItemUseCase(this._repository);

  final MessageOutboxRepository _repository;

  Future<void> execute(MessageOutboxItem item) {
    return _repository.upsert(item);
  }
}

final class DeleteMessageOutboxItemUseCase {
  const DeleteMessageOutboxItemUseCase(this._repository);

  final MessageOutboxRepository _repository;

  Future<void> execute(MessageOutboxItem item) {
    return _repository.delete(
      workspaceId: item.workspaceId,
      channelId: item.channelId,
      itemId: item.id,
    );
  }
}

final class NewClientMessageIdUseCase {
  const NewClientMessageIdUseCase({Uuid uuid = const Uuid()}) : _uuid = uuid;

  final Uuid _uuid;

  String execute() => _uuid.v4();
}

List<MessageOutboxAttachment> uploadedOutboxAttachments(
  List<MessageAttachmentUploadItem> items,
) {
  final result = <MessageOutboxAttachment>[];
  for (var index = 0; index < items.length; index += 1) {
    final file = items[index].uploadedFile;
    if (items[index].status == MessageAttachmentUploadStatus.uploaded &&
        file != null) {
      result.add(
        MessageOutboxAttachment(
          fileId: file.id,
          name: file.name,
          sortOrder: index,
        ),
      );
    }
  }
  return result;
}
