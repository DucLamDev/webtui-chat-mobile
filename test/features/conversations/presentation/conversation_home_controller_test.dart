import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/core/result/result.dart';
import 'package:webtui_chat/features/conversations/application/use_cases/channel_use_cases.dart';
import 'package:webtui_chat/features/conversations/application/use_cases/load_conversation_home_use_case.dart';
import 'package:webtui_chat/features/conversations/application/use_cases/open_direct_conversation_use_case.dart';
import 'package:webtui_chat/features/conversations/domain/entities/channel_file.dart';
import 'package:webtui_chat/features/conversations/domain/entities/chat_message.dart';
import 'package:webtui_chat/features/conversations/domain/entities/conversation_summary.dart';
import 'package:webtui_chat/features/conversations/domain/repositories/conversation_repository.dart';
import 'package:webtui_chat/features/conversations/presentation/controllers/conversation_home_controller.dart';
import 'package:webtui_chat/features/workspace/domain/repositories/workspace_session_repository.dart';

void main() {
  test('markConversationOpened clears unread badge in channel list', () async {
    final repository = _FakeConversationRepository(
      conversations: [_summary(id: 'dm-1', channelId: 'dm-channel', unread: 4)],
      channels: [
        _summary(
          id: 'channel-1',
          channelId: 'channel-1',
          kind: ConversationKind.channel,
          unread: 7,
        ),
      ],
    );
    final controller = _controller(repository);
    addTearDown(controller.dispose);

    await controller.load();
    controller.markConversationOpened(controller.state.channels.single);

    expect(controller.state.conversations.single.unreadCount, 4);
    expect(controller.state.channels.single.unreadCount, 0);
  });

  test('selectConversation clears unread badge in conversation list', () async {
    final repository = _FakeConversationRepository(
      conversations: [_summary(id: 'dm-1', channelId: 'dm-channel', unread: 3)],
    );
    final controller = _controller(repository);
    addTearDown(controller.dispose);

    await controller.load();
    controller.selectConversation(controller.state.conversations.single);

    expect(controller.state.conversations.single.unreadCount, 0);
    expect(controller.state.selectedConversation?.unreadCount, 0);
  });
}

ConversationHomeController _controller(_FakeConversationRepository repository) {
  return ConversationHomeController(
    workspaceId: 'workspace-1',
    loadConversationHomeUseCase: LoadConversationHomeUseCase(
      conversationRepository: repository,
      workspaceSessionRepository: const _FakeWorkspaceSessionRepository(),
    ),
    openDirectConversationUseCase: OpenDirectConversationUseCase(repository),
    openPrivateChannelSessionUseCase: OpenPrivateChannelSessionUseCase(
      repository,
    ),
  );
}

ConversationSummary _summary({
  required String id,
  required String channelId,
  ConversationKind kind = ConversationKind.direct,
  int unread = 0,
}) {
  return ConversationSummary(
    id: id,
    workspaceId: 'workspace-1',
    channelId: channelId,
    kind: kind,
    title: kind == ConversationKind.direct ? 'Lam Đức' : 'Thông báo chung',
    preview: 'Tin nhắn mới',
    updatedAt: DateTime.utc(2026, 7, 16),
    unreadCount: unread,
    channelVisibility: kind == ConversationKind.direct
        ? ChannelVisibility.direct
        : ChannelVisibility.public,
    membershipStatus: MembershipStatus.active,
  );
}

final class _FakeWorkspaceSessionRepository
    implements WorkspaceSessionRepository {
  const _FakeWorkspaceSessionRepository();

  @override
  Future<String?> readActiveWorkspaceId() async => 'workspace-1';

  @override
  Future<void> resetRuntimeForSwitch({
    required String? previousWorkspaceId,
    required String nextWorkspaceId,
  }) async {}

  @override
  Future<void> saveActiveWorkspaceId(String workspaceId) async {}
}

final class _FakeConversationRepository implements ConversationRepository {
  _FakeConversationRepository({
    this.conversations = const [],
    this.channels = const [],
  });

  final List<ConversationSummary> conversations;
  final List<ConversationSummary> channels;

  @override
  Future<Result<List<ConversationSummary>>> listDirectConversations({
    required String workspaceId,
  }) async {
    return Success(conversations);
  }

  @override
  Future<Result<List<ConversationSummary>>> listChannels({
    required String workspaceId,
  }) async {
    return Success(channels);
  }

  @override
  Future<Result<List<ContactSummary>>> listContacts() async {
    return const Success([]);
  }

  @override
  Future<Result<List<ContactSummary>>> listWorkspaceMembers({
    required String workspaceId,
  }) async {
    return const Success([]);
  }

  @override
  Future<Result<List<PresenceSummary>>> listPresence({
    required String workspaceId,
  }) async {
    return const Success([]);
  }

  @override
  Future<Result<ChannelMember>> addMember({
    required String workspaceId,
    required String channelId,
    required String userId,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<Result<ChannelMember>> approveJoinRequest({
    required String workspaceId,
    required String channelId,
    required String userId,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<Result<ConversationSummary>> createChannel({
    required String workspaceId,
    required String slug,
    required String name,
    required String description,
    required ChannelVisibility visibility,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<Result<ConversationSummary>> createDirectConversation({
    required String workspaceId,
    required List<String> participantIds,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<Result<ConversationSummary>> getChannel({
    required String workspaceId,
    required String channelId,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<Result<List<ChannelFile>>> listFiles({
    required String workspaceId,
    int limit = 40,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<Result<List<ChannelMember>>> listJoinRequests({
    required String workspaceId,
    required String channelId,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<Result<List<ChannelMember>>> listMembers({
    required String workspaceId,
    required String channelId,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<Result<List<ChatMessage>>> listMessages({
    required String workspaceId,
    required String channelId,
    int limit = 50,
    String? beforeId,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<Result<List<ChatMessage>>> listPins({
    required String workspaceId,
    required String channelId,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<Result<void>> markRead({
    required String workspaceId,
    required String channelId,
    required String lastReadMessageId,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<Result<ConversationSummary>> openPrivateSession({
    required String workspaceId,
    required String channelId,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<Result<ChannelMember>> requestJoinChannel({
    required String workspaceId,
    required String channelId,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<Result<void>> rejectJoinRequest({
    required String workspaceId,
    required String channelId,
    required String userId,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<Result<List<ChatMessage>>> searchMessages({
    required String workspaceId,
    required String query,
    String? channelId,
    String? senderId,
    String? kind,
    DateTime? dateFrom,
    DateTime? dateTo,
    int limit = 30,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<Result<MessagePage>> searchMessagePage({
    required String workspaceId,
    required String query,
    String? channelId,
    String? senderId,
    String? kind,
    DateTime? dateFrom,
    DateTime? dateTo,
    int limit = 30,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<Result<MessagePage>> listMessagePage({
    required String workspaceId,
    required String channelId,
    int limit = 50,
    String? beforeId,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<Result<MessagePage>> listThread({
    required String workspaceId,
    required String channelId,
    required String messageId,
    int limit = 50,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<Result<ChatMessage>> sendMessage({
    required String workspaceId,
    required String channelId,
    required String body,
    String? clientMessageId,
    String? parentId,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<Result<ChatMessage>> editMessage({
    required String workspaceId,
    required String channelId,
    required String messageId,
    required String body,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<Result<void>> deleteMessage({
    required String workspaceId,
    required String channelId,
    required String messageId,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<Result<ChatMessage>> addReaction({
    required String workspaceId,
    required String channelId,
    required String messageId,
    required String emoji,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<Result<ChatMessage>> removeReaction({
    required String workspaceId,
    required String channelId,
    required String messageId,
    required String emoji,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<Result<ChatMessage>> pinMessage({
    required String workspaceId,
    required String channelId,
    required String messageId,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<Result<void>> unpinMessage({
    required String workspaceId,
    required String channelId,
    required String messageId,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<Result<ChatMessage>> forwardMessage({
    required String workspaceId,
    required String channelId,
    required String messageId,
    required String targetChannelId,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<Result<void>> updatePresence({
    required String workspaceId,
    required String deviceId,
    required ConversationPresence status,
    required String platform,
  }) {
    throw UnimplementedError();
  }
}
