import '../../domain/entities/message_outbox_item.dart';
import '../../domain/repositories/message_outbox_repository.dart';
import '../datasources/message_outbox_data_source.dart';

final class LocalMessageOutboxRepository implements MessageOutboxRepository {
  const LocalMessageOutboxRepository(this._dataSource);

  final MessageOutboxDataSource _dataSource;

  @override
  Future<List<MessageOutboxItem>> list({
    required String workspaceId,
    required String channelId,
  }) {
    return _dataSource.list(workspaceId: workspaceId, channelId: channelId);
  }

  @override
  Future<void> upsert(MessageOutboxItem item) {
    return _dataSource.upsert(item);
  }

  @override
  Future<void> delete({
    required String workspaceId,
    required String channelId,
    required String itemId,
  }) {
    return _dataSource.delete(
      workspaceId: workspaceId,
      channelId: channelId,
      itemId: itemId,
    );
  }

  @override
  Future<void> clearWorkspace({required String workspaceId}) {
    return _dataSource.clearWorkspace(workspaceId: workspaceId);
  }
}
