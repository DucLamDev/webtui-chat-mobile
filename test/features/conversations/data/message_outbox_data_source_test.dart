import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/core/database/app_database.dart';
import 'package:webtui_chat/core/security/instance_scope.dart';
import 'package:webtui_chat/core/security/secure_key_value_store.dart';
import 'package:webtui_chat/features/conversations/application/use_cases/message_outbox_use_cases.dart';
import 'package:webtui_chat/features/conversations/data/datasources/message_outbox_data_source.dart';
import 'package:webtui_chat/features/conversations/data/repositories/local_message_outbox_repository.dart';
import 'package:webtui_chat/features/conversations/domain/entities/chat_message.dart';
import 'package:webtui_chat/features/conversations/domain/entities/message_outbox_item.dart';

void main() {
  test('stores outbox items scoped by workspace and channel', () async {
    final database = AppDatabase(createInMemoryDriftConnection());
    addTearDown(database.close);
    final dataSource = MessageOutboxDataSource(
      database,
      _instanceA,
      _MemorySecureStore.boundTo(_instanceA),
    );
    final now = DateTime.utc(2026, 7, 17, 10);

    final item = MessageOutboxItem(
      id: 'outbox-1',
      instanceScopeId: _instanceA.storageId,
      workspaceId: 'workspace-1',
      channelId: 'channel-1',
      clientMessageId: 'client-1',
      body: 'Xin chao',
      status: MessageOutboxStatus.failed,
      attemptCount: 2,
      lastError: 'offline',
      silent: true,
      attachments: const [
        MessageOutboxAttachment(
          byteSize: 12345,
          downloadPath: '/api/v1/workspaces/workspace-1/files/file-1/download',
          fileId: 'file-1',
          localPath: '/local/photo.jpg',
          mimeType: 'image/jpeg',
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
    expect(restored.single.attachments.single.mimeType, 'image/jpeg');
    expect(restored.single.attachments.single.byteSize, 12345);
    expect(
      restored.single.attachments.single.downloadPath,
      '/api/v1/workspaces/workspace-1/files/file-1/download',
    );
    expect(restored.single.attachments.single.localPath, '/local/photo.jpg');
    expect(restored.single.status, MessageOutboxStatus.failed);
    expect(restored.single.silent, isTrue);
    expect(otherChannel, isEmpty);
  });

  test('queues a message durably before the network send starts', () async {
    final database = AppDatabase(createInMemoryDriftConnection());
    addTearDown(database.close);
    final dataSource = MessageOutboxDataSource(
      database,
      _instanceA,
      _MemorySecureStore.boundTo(_instanceA),
    );
    final repository = LocalMessageOutboxRepository(dataSource);
    final enqueue = EnqueueMessageOutboxUseCase(
      repository: repository,
      instanceScopeId: _instanceA.storageId,
    );

    final item = await enqueue.execute(
      workspaceId: 'workspace-1',
      channelId: 'channel-1',
      clientMessageId: 'mobile-client-1',
      body: 'Tin nhan khong bi mat',
      silent: true,
    );

    final restored = await dataSource.list(
      workspaceId: 'workspace-1',
      channelId: 'channel-1',
    );
    expect(item.status, MessageOutboxStatus.queued);
    expect(item.attemptCount, 0);
    expect(restored.single.clientMessageId, 'mobile-client-1');
    expect(restored.single.silent, isTrue);
  });

  test('uploaded outbox attachments keep local image preview metadata', () {
    final now = DateTime.utc(2026, 8, 13, 10);

    final attachments = uploadedOutboxAttachments([
      MessageAttachmentUploadItem(
        clientAttachmentId: 'client-attachment-1',
        status: MessageAttachmentUploadStatus.uploaded,
        picked: const PickedMessageAttachment(
          path: '/device/DCIM/photo.jpg',
          fileName: 'photo.jpg',
          mimeType: 'image/jpeg',
          byteSize: 12345,
          kind: MessageAttachmentKind.image,
        ),
        uploadedFile: UploadedMessageFile(
          id: 'file-1',
          name: 'photo.jpg',
          mimeType: 'image/jpeg',
          byteSize: 12345,
          downloadPath: '/api/v1/workspaces/workspace-1/files/file-1/download',
          createdAt: now,
        ),
      ),
    ]);

    expect(attachments, hasLength(1));
    expect(attachments.single.fileId, 'file-1');
    expect(attachments.single.mimeType, 'image/jpeg');
    expect(attachments.single.byteSize, 12345);
    expect(
      attachments.single.downloadPath,
      '/api/v1/workspaces/workspace-1/files/file-1/download',
    );
    expect(attachments.single.localPath, '/device/DCIM/photo.jpg');
  });

  test('does not lose outbox items when writes overlap', () async {
    final database = AppDatabase(createInMemoryDriftConnection());
    addTearDown(database.close);
    final dataSource = MessageOutboxDataSource(
      database,
      _instanceA,
      _MemorySecureStore.boundTo(_instanceA),
    );
    final now = DateTime.utc(2026, 8, 3, 9);

    await Future.wait([
      for (var index = 0; index < 12; index += 1)
        dataSource.upsert(
          MessageOutboxItem(
            id: 'outbox-$index',
            instanceScopeId: _instanceA.storageId,
            workspaceId: 'workspace-1',
            channelId: 'channel-1',
            clientMessageId: 'client-$index',
            body: 'Message $index',
            createdAt: now,
            updatedAt: now,
          ),
        ),
    ]);

    final restored = await dataSource.list(
      workspaceId: 'workspace-1',
      channelId: 'channel-1',
    );
    expect(restored, hasLength(12));
  });

  test('same IDs cannot leak or dispatch after switching servers', () async {
    final database = AppDatabase(createInMemoryDriftConnection());
    addTearDown(database.close);
    final secureStore = _MemorySecureStore.boundTo(_instanceA);
    final serverA = MessageOutboxDataSource(database, _instanceA, secureStore);
    final serverB = MessageOutboxDataSource(database, _instanceB, secureStore);
    final now = DateTime.utc(2026, 8, 10);
    final item = MessageOutboxItem(
      id: 'same-outbox-id',
      instanceScopeId: _instanceA.storageId,
      workspaceId: 'same-workspace-id',
      channelId: 'same-channel-id',
      clientMessageId: 'same-client-id',
      body: 'server-a-secret',
      createdAt: now,
      updatedAt: now,
    );
    await serverA.upsert(item);

    expect(
      await serverB.list(
        workspaceId: 'same-workspace-id',
        channelId: 'same-channel-id',
      ),
      isEmpty,
    );

    await secureStore.write(
      SecureStoreKey.activeInstanceScopeId,
      _instanceB.storageId,
    );
    await secureStore.write(
      SecureStoreKey.liveDiscoveryValidatedScopeId,
      _instanceB.storageId,
    );
    var networkSendCount = 0;
    if (await serverA.canDispatch(item)) {
      networkSendCount += 1;
    }
    expect(networkSendCount, 0);
  });
}

final _instanceA = InstanceScope(
  instanceId: '11111111-1111-4111-8111-111111111111',
  serverOrigin: Uri.parse('https://one.example'),
);

final _instanceB = InstanceScope(
  instanceId: '22222222-2222-4222-8222-222222222222',
  serverOrigin: Uri.parse('https://two.example'),
);

final class _MemorySecureStore implements SecureKeyValueStore {
  _MemorySecureStore.boundTo(InstanceScope scope) {
    _values[SecureStoreKey.activeInstanceScopeId] = scope.storageId;
    _values[SecureStoreKey.liveDiscoveryValidatedScopeId] = scope.storageId;
  }

  final Map<SecureStoreKey, String> _values = {};

  @override
  Future<String?> read(SecureStoreKey key) async => _values[key];

  @override
  Future<void> write(SecureStoreKey key, String value) async {
    _values[key] = value;
  }

  @override
  Future<void> delete(SecureStoreKey key) async {
    _values.remove(key);
  }

  @override
  Future<void> clearSession() async {
    _values.remove(SecureStoreKey.accessToken);
    _values.remove(SecureStoreKey.refreshToken);
    _values.remove(SecureStoreKey.sessionInstanceScopeId);
    _values.remove(SecureStoreKey.activeWorkspaceId);
    _values.remove(SecureStoreKey.activeWorkspaceInstanceScopeId);
  }
}
