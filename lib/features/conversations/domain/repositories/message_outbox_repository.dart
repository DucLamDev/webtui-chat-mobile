import '../entities/message_outbox_item.dart';

abstract interface class MessageOutboxRepository {
  Future<List<MessageOutboxItem>> list({
    required String workspaceId,
    required String channelId,
  });

  /// Mọi tin chờ của workspace, ở mọi hội thoại.
  Future<List<MessageOutboxItem>> listWorkspace({required String workspaceId});

  Future<void> upsert(MessageOutboxItem item);

  Future<bool> canDispatch(MessageOutboxItem item);

  Future<void> delete({
    required String workspaceId,
    required String channelId,
    required String itemId,
  });

  Future<void> clearWorkspace({required String workspaceId});
}
