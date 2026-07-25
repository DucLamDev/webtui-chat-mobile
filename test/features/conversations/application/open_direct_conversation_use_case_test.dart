import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/core/result/result.dart';
import 'package:webtui_chat/features/conversations/application/use_cases/open_direct_conversation_use_case.dart';
import 'package:webtui_chat/features/conversations/domain/entities/channel_file.dart';
import 'package:webtui_chat/features/conversations/domain/entities/chat_message.dart';
import 'package:webtui_chat/features/conversations/domain/entities/conversation_summary.dart';
import 'package:webtui_chat/features/conversations/domain/repositories/conversation_repository.dart';

void main() {
  test('không gọi create khi direct conversation đã tồn tại', () async {
    final existing = ConversationSummary(
      id: 'direct-1',
      workspaceId: 'workspace-1',
      channelId: 'channel-1',
      kind: ConversationKind.direct,
      title: 'Lam Đức',
      preview: 'Chưa có tin nhắn',
      updatedAt: DateTime.utc(2026, 7, 15),
      participantIds: const ['current-user', 'peer-1'],
    );
    final repository = _FakeConversationRepository(existing: [existing]);
    final useCase = OpenDirectConversationUseCase(repository);

    final result = await useCase.execute(
      workspaceId: 'workspace-1',
      participantIds: const ['peer-1'],
    );

    expect(result.valueOrNull, existing);
    expect(repository.createCalls, 0);
  });

  test('gọi create khi chưa có direct conversation phù hợp', () async {
    final created = ConversationSummary(
      id: 'direct-2',
      workspaceId: 'workspace-1',
      channelId: 'channel-2',
      kind: ConversationKind.direct,
      title: 'Tô Thanh Trang',
      preview: 'Chưa có tin nhắn',
      updatedAt: DateTime.utc(2026, 7, 15),
      participantIds: const ['current-user', 'peer-2'],
    );
    final repository = _FakeConversationRepository(created: created);
    final useCase = OpenDirectConversationUseCase(repository);

    final result = await useCase.execute(
      workspaceId: 'workspace-1',
      participantIds: const ['peer-2'],
    );

    expect(result.valueOrNull, created);
    expect(repository.createCalls, 1);
  });
}

final class _FakeConversationRepository implements ConversationRepository {
  _FakeConversationRepository({
    this.existing = const [],
    ConversationSummary? created,
  }) : created =
           created ??
           ConversationSummary(
             id: 'direct-created',
             workspaceId: 'workspace-1',
             channelId: 'channel-created',
             kind: ConversationKind.direct,
             title: 'Hội thoại mới',
             preview: 'Chưa có tin nhắn',
             updatedAt: DateTime.utc(2026, 7, 15),
           );

  final List<ConversationSummary> existing;
  final ConversationSummary created;
  int createCalls = 0;

  @override
  Future<Result<List<ConversationSummary>>> listDirectConversations({
    required String workspaceId,
  }) async {
    return Success(existing);
  }

  @override
  Future<Result<ConversationSummary>> createDirectConversation({
    required String workspaceId,
    required List<String> participantIds,
  }) async {
    createCalls += 1;
    return Success(created);
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
  Future<Result<ConversationSummary>> getChannel({
    required String workspaceId,
    required String channelId,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<Result<List<ConversationSummary>>> listChannels({
    required String workspaceId,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<Result<List<ContactSummary>>> listContacts() {
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
  Future<Result<List<ContactSummary>>> listWorkspaceMembers({
    required String workspaceId,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<Result<List<PresenceSummary>>> listPresence({
    required String workspaceId,
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
}
