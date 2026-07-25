import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/core/database/app_database.dart';
import 'package:webtui_chat/features/conversations/data/datasources/message_outbox_data_source.dart';
import 'package:webtui_chat/features/conversations/domain/entities/message_outbox_item.dart';

void main() {
  test('stores outbox items scoped by workspace and channel', () async {
    final database = AppDatabase(createInMemoryDriftConnection());
    addTearDown(database.close);
    final dataSource = MessageOutboxDataSource(database);
    final now = DateTime.utc(2026, 7, 17, 10);

    final item = MessageOutboxItem(
      id: 'outbox-1',
      workspaceId: 'workspace-1',
      channelId: 'channel-1',
      clientMessageId: 'client-1',
      body: 'Xin chao',
      status: MessageOutboxStatus.failed,
      attemptCount: 2,
      lastError: 'offline',
      attachments: const [
        MessageOutboxAttachment(
          fileId: 'file-1',
          name: 'photo.jpg',
          sortOrder: 0,
        ),
      ],
      createdAt: now,
      updatedAt: now,
    );

    await dataSource.upsert(item);

    final restored = await dataSource.list(
      workspaceId: 'workspace-1',
      channelId: 'channel-1',
    );
    final otherChannel = await dataSource.list(
      workspaceId: 'workspace-1',
      channelId: 'channel-2',
    );

    expect(restored, hasLength(1));
    expect(restored.single.clientMessageId, 'client-1');
    expect(restored.single.attachments.single.fileId, 'file-1');
    expect(restored.single.status, MessageOutboxStatus.failed);
    expect(otherChannel, isEmpty);
  });
}
