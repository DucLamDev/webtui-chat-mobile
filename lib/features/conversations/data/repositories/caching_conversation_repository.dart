import '../../../../core/result/result.dart';
import '../../domain/entities/channel_file.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/entities/conversation_summary.dart';
import '../../domain/repositories/conversation_repository.dart';
import '../datasources/conversation_cache_data_source.dart';

final class CachingConversationRepository implements ConversationRepository {
  const CachingConversationRepository({
    required ConversationRepository remote,
    required ConversationCacheDataSource cache,
  }) : _remote = remote,
       _cache = cache;

  final ConversationRepository _remote;
  final ConversationCacheDataSource _cache;

  @override
  Future<Result<List<ConversationSummary>>> listDirectConversations({
    required String workspaceId,
  }) async {
    final result = await _remote.listDirectConversations(
      workspaceId: workspaceId,
    );
    switch (result) {
      case Success<List<ConversationSummary>>(value: final items):
        await _cacheWrite(
          () => _cache.saveDirectConversations(
            workspaceId: workspaceId,
            items: items,
          ),
        );
        return result;
      case FailureResult<List<ConversationSummary>>():
        final cached = await _cacheRead(
          () => _cache.readDirectConversations(workspaceId: workspaceId),
        );
        return cached == null ? result : Success(cached);
    }
  }

  @override
  Future<Result<List<ConversationSummary>>> listChannels({
    required String workspaceId,
  }) async {
    final result = await _remote.listChannels(workspaceId: workspaceId);
    switch (result) {
      case Success<List<ConversationSummary>>(value: final items):
        await _cacheWrite(
          () => _cache.saveChannels(workspaceId: workspaceId, items: items),
        );
        return result;
      case FailureResult<List<ConversationSummary>>():
        final cached = await _cacheRead(
          () => _cache.readChannels(workspaceId: workspaceId),
        );
        return cached == null ? result : Success(cached);
    }
  }

  @override
  Future<Result<List<ContactSummary>>> listContacts() {
    return _remote.listContacts();
  }

  @override
  Future<Result<List<ContactSummary>>> listWorkspaceMembers({
    required String workspaceId,
  }) {
    return _remote.listWorkspaceMembers(workspaceId: workspaceId);
  }

  @override
  Future<Result<List<PresenceSummary>>> listPresence({
    required String workspaceId,
  }) {
    return _remote.listPresence(workspaceId: workspaceId);
  }

  @override
  Future<Result<void>> updatePresence({
    required String workspaceId,
    required String deviceId,
    required ConversationPresence status,
    required String platform,
  }) {
    return _remote.updatePresence(
      workspaceId: workspaceId,
      deviceId: deviceId,
      status: status,
      platform: platform,
    );
  }

  @override
  Future<Result<ConversationSummary>> getChannel({
    required String workspaceId,
    required String channelId,
  }) {
    return _remote.getChannel(workspaceId: workspaceId, channelId: channelId);
  }

  @override
  Future<Result<ConversationSummary>> createChannel({
    required String workspaceId,
    required String slug,
    required String name,
    required String description,
    required ChannelVisibility visibility,
  }) {
    return _remote.createChannel(
      workspaceId: workspaceId,
      slug: slug,
      name: name,
      description: description,
      visibility: visibility,
    );
  }

  @override
  Future<Result<ChannelMember>> requestJoinChannel({
    required String workspaceId,
    required String channelId,
  }) {
    return _remote.requestJoinChannel(
      workspaceId: workspaceId,
      channelId: channelId,
    );
  }

  @override
  Future<Result<ConversationSummary>> openPrivateSession({
    required String workspaceId,
    required String channelId,
  }) {
    return _remote.openPrivateSession(
      workspaceId: workspaceId,
      channelId: channelId,
    );
  }

  @override
  Future<Result<ConversationSummary>> createDirectConversation({
    required String workspaceId,
    required List<String> participantIds,
  }) {
    return _remote.createDirectConversation(
      workspaceId: workspaceId,
      participantIds: participantIds,
    );
  }

  @override
  Future<Result<void>> markRead({
    required String workspaceId,
    required String channelId,
    required String lastReadMessageId,
  }) {
    return _remote.markRead(
      workspaceId: workspaceId,
      channelId: channelId,
      lastReadMessageId: lastReadMessageId,
    );
  }

  @override
  Future<Result<List<ChannelMember>>> listMembers({
    required String workspaceId,
    required String channelId,
  }) {
    return _remote.listMembers(workspaceId: workspaceId, channelId: channelId);
  }

  @override
  Future<Result<ChannelMember>> addMember({
    required String workspaceId,
    required String channelId,
    required String userId,
  }) {
    return _remote.addMember(
      workspaceId: workspaceId,
      channelId: channelId,
      userId: userId,
    );
  }

  @override
  Future<Result<List<ChannelMember>>> listJoinRequests({
    required String workspaceId,
    required String channelId,
  }) {
    return _remote.listJoinRequests(
      workspaceId: workspaceId,
      channelId: channelId,
    );
  }

  @override
  Future<Result<ChannelMember>> approveJoinRequest({
    required String workspaceId,
    required String channelId,
    required String userId,
  }) {
    return _remote.approveJoinRequest(
      workspaceId: workspaceId,
      channelId: channelId,
      userId: userId,
    );
  }

  @override
  Future<Result<void>> rejectJoinRequest({
    required String workspaceId,
    required String channelId,
    required String userId,
  }) {
    return _remote.rejectJoinRequest(
      workspaceId: workspaceId,
      channelId: channelId,
      userId: userId,
    );
  }

  @override
  Future<Result<List<ChatMessage>>> listMessages({
    required String workspaceId,
    required String channelId,
    int limit = 50,
    String? beforeId,
  }) async {
    final result = await listMessagePage(
      workspaceId: workspaceId,
      channelId: channelId,
      limit: limit,
      beforeId: beforeId,
    );
    return switch (result) {
      Success<MessagePage>(value: final page) => Success(page.messages),
      FailureResult<MessagePage>(failure: final failure) => FailureResult(
        failure,
      ),
    };
  }

  @override
  Future<Result<MessagePage>> listMessagePage({
    required String workspaceId,
    required String channelId,
    int limit = 50,
    String? beforeId,
  }) async {
    final result = await _remote.listMessagePage(
      workspaceId: workspaceId,
      channelId: channelId,
      limit: limit,
      beforeId: beforeId,
    );
    if (beforeId != null) {
      return result;
    }

    switch (result) {
      case Success<MessagePage>(value: final page):
        await _cacheWrite(
          () => _cache.saveLatestMessagePage(
            workspaceId: workspaceId,
            channelId: channelId,
            page: page,
          ),
        );
        return result;
      case FailureResult<MessagePage>():
        final cached = await _cacheRead(
          () => _cache.readLatestMessagePage(
            workspaceId: workspaceId,
            channelId: channelId,
          ),
        );
        return cached == null ? result : Success(cached);
    }
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
    return _remote.searchMessages(
      workspaceId: workspaceId,
      query: query,
      channelId: channelId,
      senderId: senderId,
      kind: kind,
      dateFrom: dateFrom,
      dateTo: dateTo,
      limit: limit,
    );
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
    return _remote.searchMessagePage(
      workspaceId: workspaceId,
      query: query,
      channelId: channelId,
      senderId: senderId,
      kind: kind,
      dateFrom: dateFrom,
      dateTo: dateTo,
      limit: limit,
    );
  }

  @override
  Future<Result<MessagePage>> listThread({
    required String workspaceId,
    required String channelId,
    required String messageId,
    int limit = 50,
  }) {
    return _remote.listThread(
      workspaceId: workspaceId,
      channelId: channelId,
      messageId: messageId,
      limit: limit,
    );
  }

  @override
  Future<Result<List<ChatMessage>>> listPins({
    required String workspaceId,
    required String channelId,
  }) {
    return _remote.listPins(workspaceId: workspaceId, channelId: channelId);
  }

  @override
  Future<Result<ChatMessage>> sendMessage({
    required String workspaceId,
    required String channelId,
    required String body,
    String? clientMessageId,
    String? parentId,
  }) async {
    final result = await _remote.sendMessage(
      workspaceId: workspaceId,
      channelId: channelId,
      body: body,
      clientMessageId: clientMessageId,
      parentId: parentId,
    );
    if (result case Success<ChatMessage>(value: final message)) {
      await _cacheMessage(
        workspaceId: workspaceId,
        channelId: channelId,
        message: message,
      );
    }
    return result;
  }

  @override
  Future<Result<ChatMessage>> editMessage({
    required String workspaceId,
    required String channelId,
    required String messageId,
    required String body,
  }) async {
    final result = await _remote.editMessage(
      workspaceId: workspaceId,
      channelId: channelId,
      messageId: messageId,
      body: body,
    );
    if (result case Success<ChatMessage>(value: final message)) {
      await _cacheMessage(
        workspaceId: workspaceId,
        channelId: channelId,
        message: message,
      );
    }
    return result;
  }

  @override
  Future<Result<void>> deleteMessage({
    required String workspaceId,
    required String channelId,
    required String messageId,
  }) async {
    final result = await _remote.deleteMessage(
      workspaceId: workspaceId,
      channelId: channelId,
      messageId: messageId,
    );
    if (result is Success<void>) {
      await _cacheWrite(
        () => _cache.removeLatestMessage(
          workspaceId: workspaceId,
          channelId: channelId,
          messageId: messageId,
        ),
      );
    }
    return result;
  }

  @override
  Future<Result<ChatMessage>> addReaction({
    required String workspaceId,
    required String channelId,
    required String messageId,
    required String emoji,
  }) async {
    final result = await _remote.addReaction(
      workspaceId: workspaceId,
      channelId: channelId,
      messageId: messageId,
      emoji: emoji,
    );
    if (result case Success<ChatMessage>(value: final message)) {
      await _cacheMessage(
        workspaceId: workspaceId,
        channelId: channelId,
        message: message,
      );
    }
    return result;
  }

  @override
  Future<Result<ChatMessage>> removeReaction({
    required String workspaceId,
    required String channelId,
    required String messageId,
    required String emoji,
  }) async {
    final result = await _remote.removeReaction(
      workspaceId: workspaceId,
      channelId: channelId,
      messageId: messageId,
      emoji: emoji,
    );
    if (result case Success<ChatMessage>(value: final message)) {
      await _cacheMessage(
        workspaceId: workspaceId,
        channelId: channelId,
        message: message,
      );
    }
    return result;
  }

  @override
  Future<Result<ChatMessage>> pinMessage({
    required String workspaceId,
    required String channelId,
    required String messageId,
  }) async {
    final result = await _remote.pinMessage(
      workspaceId: workspaceId,
      channelId: channelId,
      messageId: messageId,
    );
    if (result case Success<ChatMessage>(value: final message)) {
      await _cacheMessage(
        workspaceId: workspaceId,
        channelId: channelId,
        message: message,
      );
    }
    return result;
  }

  @override
  Future<Result<void>> unpinMessage({
    required String workspaceId,
    required String channelId,
    required String messageId,
  }) async {
    final result = await _remote.unpinMessage(
      workspaceId: workspaceId,
      channelId: channelId,
      messageId: messageId,
    );
    if (result is Success<void>) {
      await _cacheWrite(
        () => _cache.updateLatestMessagePin(
          workspaceId: workspaceId,
          channelId: channelId,
          messageId: messageId,
          isPinned: false,
        ),
      );
    }
    return result;
  }

  @override
  Future<Result<ChatMessage>> forwardMessage({
    required String workspaceId,
    required String channelId,
    required String messageId,
    required String targetChannelId,
  }) async {
    final result = await _remote.forwardMessage(
      workspaceId: workspaceId,
      channelId: channelId,
      messageId: messageId,
      targetChannelId: targetChannelId,
    );
    if (result case Success<ChatMessage>(value: final message)) {
      await _cacheMessage(
        workspaceId: workspaceId,
        channelId: targetChannelId,
        message: message,
      );
    }
    return result;
  }

  @override
  Future<Result<List<ChannelFile>>> listFiles({
    required String workspaceId,
    int limit = 40,
  }) {
    return _remote.listFiles(workspaceId: workspaceId, limit: limit);
  }

  Future<void> _cacheMessage({
    required String workspaceId,
    required String channelId,
    required ChatMessage message,
  }) {
    return _cacheWrite(
      () => _cache.upsertLatestMessage(
        workspaceId: workspaceId,
        channelId: channelId,
        message: message,
      ),
    );
  }
}

Future<T?> _cacheRead<T>(Future<T?> Function() action) async {
  try {
    return await action();
  } on Object {
    return null;
  }
}

Future<void> _cacheWrite(Future<void> Function() action) async {
  try {
    await action();
  } on Object {
    return;
  }
}
