import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/core/database/app_database.dart';
import 'package:webtui_chat/core/security/instance_scope.dart';
import 'package:webtui_chat/features/conversations/data/datasources/conversation_cache_data_source.dart';
import 'package:webtui_chat/features/conversations/domain/entities/chat_message.dart';

void main() {
  test('cache giữ cờ/hạn tin bí mật nhưng loại plaintext', () async {
    final db = AppDatabase(createInMemoryDriftConnection());
    addTearDown(db.close);
    final cache = ConversationCacheDataSource(
      db,
      InstanceScope(
        instanceId: '11111111-1111-4111-8111-111111111111',
        serverOrigin: Uri.parse('https://example.test'),
      ),
    );
    final expires = DateTime.utc(2026, 11, 11);
    await cache.saveLatestMessagePage(
      workspaceId: 'w',
      channelId: 'c',
      page: MessagePage(
        messages: [
          ChatMessage(
            id: 'm',
            workspaceId: 'w',
            channelId: 'c',
            kind: 'text',
            body: 'must-never-persist',
            createdAt: DateTime.utc(2026, 11, 10),
            isSecret: true,
            expiresAt: expires,
          ),
        ],
        hasMore: false,
      ),
    );
    final page = await cache.readLatestMessagePage(
      workspaceId: 'w',
      channelId: 'c',
    );
    expect(page!.messages.single.body, isEmpty);
    expect(page.messages.single.isSecret, isTrue);
    expect(page.messages.single.expiresAt, expires);
  });
}
