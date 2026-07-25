import '../entities/message_outbox_item.dart';

abstract interface class MessageOutboxRepository {
  Future<List<MessageOutboxItem>> list({
    required String workspaceId,
    required String channelId,
  });

  Future<void> upsert(MessageOutboxItem item);

  Future<void> delete({
    required String workspaceId,
    required String channelId,
    required String itemId,
  });

  Future<void> clearWorkspace({required String workspaceId});
}
