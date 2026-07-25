import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/core/database/app_database.dart';
import 'package:webtui_chat/features/conversations/data/datasources/conversation_cache_data_source.dart';
import 'package:webtui_chat/features/conversations/domain/entities/chat_message.dart';
import 'package:webtui_chat/features/conversations/domain/entities/conversation_summary.dart';

void main() {
  test('restores cached conversations and latest message page', () async {
    final database = AppDatabase(createInMemoryDriftConnection());
    addTearDown(database.close);
    final cache = ConversationCacheDataSource(database);
    final updatedAt = DateTime.utc(2026, 7, 17, 8);
    final createdAt = DateTime.utc(2026, 7, 17, 8, 30);

    await cache.saveDirectConversations(
      workspaceId: 'workspace-1',
      items: [
        ConversationSummary(
          id: 'conversation-1',
          workspaceId: 'workspace-1',
          channelId: 'channel-1',
          kind: ConversationKind.direct,
          title: 'Chi Kha',
          preview: 'Hen gap lai sau',
          updatedAt: updatedAt,
          peerUserId: 'user-2',
          unreadCount: 2,
          participantIds: const ['user-1', 'user-2'],
          membershipStatus: MembershipStatus.active,
        ),
      ],
    );

    await cache.saveLatestMessagePage(
      workspaceId: 'workspace-1',
      channelId: 'channel-1',
      page: MessagePage(
        nextCursor: 'message-1',
        hasMore: true,
        messages: [
          ChatMessage(
            id: 'message-1',
            workspaceId: 'workspace-1',
            channelId: 'channel-1',
            kind: 'text',
            body: 'Xin chao',
            createdAt: createdAt,
            senderId: 'user-1',
            reactions: const [
              MessageReactionSummary(
                emoji: 'like',
                count: 1,
                reactedByMe: true,
              ),
            ],
            attachments: [
              MessageAttachment(
                id: 'attachment-1',
                workspaceId: 'workspace-1',
                messageId: 'message-1',
                fileId: 'file-1',
                file: UploadedMessageFile(
                  id: 'file-1',
                  name: 'photo.jpg',
                  mimeType: 'image/jpeg',
                  byteSize: 2048,
                  downloadPath: '/files/file-1',
                  createdAt: createdAt,
                ),
                createdAt: createdAt,
              ),
            ],
            isMine: true,
            isPinned: true,
          ),
        ],
      ),
    );

    final conversations = await cache.readDirectConversations(
      workspaceId: 'workspace-1',
    );
    final page = await cache.readLatestMessagePage(
      workspaceId: 'workspace-1',
      channelId: 'channel-1',
    );

    expect(conversations, hasLength(1));
    expect(conversations!.single.title, 'Chi Kha');
    expect(conversations.single.unreadCount, 2);
    expect(conversations.single.participantIds, const ['user-1', 'user-2']);
    expect(page!.nextCursor, 'message-1');
    expect(page.hasMore, isTrue);
    expect(page.messages.single.body, 'Xin chao');
    expect(page.messages.single.reactions.single.reactedByMe, isTrue);
    expect(page.messages.single.attachments.single.file.name, 'photo.jpg');
    expect(page.messages.single.isPinned, isTrue);

    await cache.updateLatestMessagePin(
      workspaceId: 'workspace-1',
      channelId: 'channel-1',
      messageId: 'message-1',
      isPinned: false,
    );

    final unpinnedPage = await cache.readLatestMessagePage(
      workspaceId: 'workspace-1',
      channelId: 'channel-1',
    );
    expect(unpinnedPage!.messages.single.isPinned, isFalse);
  });
}
