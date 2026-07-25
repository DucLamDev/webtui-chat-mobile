import 'dart:async';

import '../../../../core/error/failure.dart';
import '../../../../core/result/result.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/entities/conversation_realtime_event.dart';
import '../../domain/repositories/conversation_repository.dart';

final class LoadMessagesUseCase {
  const LoadMessagesUseCase(this._repository);

  final ConversationRepository _repository;

  Future<Result<MessagePage>> execute({
    required String workspaceId,
    required String channelId,
    int limit = 50,
    String? beforeId,
  }) {
    return _repository.listMessagePage(
      workspaceId: workspaceId,
      channelId: channelId,
      limit: limit,
      beforeId: beforeId,
    );
  }
}

final class SendMessageUseCase {
  const SendMessageUseCase(this._repository);

  final ConversationRepository _repository;

  Future<Result<ChatMessage>> execute({
    required String workspaceId,
    required String channelId,
    required String body,
    String? clientMessageId,
    String? parentId,
  }) {
    final normalized = body.trim();
    final failure = _validateMessageBody(normalized);
    if (failure != null) {
      return Future.value(FailureResult(failure));
    }
    return _repository.sendMessage(
      workspaceId: workspaceId,
      channelId: channelId,
      body: normalized,
      clientMessageId: clientMessageId,
      parentId: parentId,
    );
  }
}

final class EditMessageUseCase {
  const EditMessageUseCase(this._repository);

  final ConversationRepository _repository;

  Future<Result<ChatMessage>> execute({
    required String workspaceId,
    required String channelId,
    required String messageId,
    required String body,
  }) {
    final normalized = body.trim();
    final failure = _validateMessageBody(normalized);
    if (failure != null) {
      return Future.value(FailureResult(failure));
    }
    return _repository.editMessage(
      workspaceId: workspaceId,
      channelId: channelId,
      messageId: messageId,
      body: normalized,
    );
  }
}

final class DeleteMessageUseCase {
  const DeleteMessageUseCase(this._repository);

  final ConversationRepository _repository;

  Future<Result<void>> execute({
    required String workspaceId,
    required String channelId,
    required String messageId,
  }) {
    return _repository.deleteMessage(
      workspaceId: workspaceId,
      channelId: channelId,
      messageId: messageId,
    );
  }
}

final class ToggleReactionUseCase {
  const ToggleReactionUseCase(this._repository);

  final ConversationRepository _repository;

  Future<Result<ChatMessage>> execute({
    required String workspaceId,
    required String channelId,
    required String messageId,
    required String emoji,
    required bool reactedByMe,
  }) {
    final normalized = emoji.trim();
    if (normalized.isEmpty || normalized.runes.length > 32) {
      return Future.value(
        const FailureResult(
          Failure(
            kind: FailureKind.validation,
            message: 'Reaction không hợp lệ.',
            code: 'REACTION_INVALID',
          ),
        ),
      );
    }
    if (reactedByMe) {
      return _repository.removeReaction(
        workspaceId: workspaceId,
        channelId: channelId,
        messageId: messageId,
        emoji: normalized,
      );
    }
    return _repository.addReaction(
      workspaceId: workspaceId,
      channelId: channelId,
      messageId: messageId,
      emoji: normalized,
    );
  }
}

final class TogglePinMessageUseCase {
  const TogglePinMessageUseCase(this._repository);

  final ConversationRepository _repository;

  Future<Result<ChatMessage?>> execute({
    required String workspaceId,
    required String channelId,
    required String messageId,
    required bool isPinned,
  }) async {
    if (isPinned) {
      final result = await _repository.unpinMessage(
        workspaceId: workspaceId,
        channelId: channelId,
        messageId: messageId,
      );
      return switch (result) {
        Success<void>() => const Success(null),
        FailureResult<void>(failure: final failure) => FailureResult(failure),
      };
    }
    return _repository.pinMessage(
      workspaceId: workspaceId,
      channelId: channelId,
      messageId: messageId,
    );
  }
}

final class ForwardMessageUseCase {
  const ForwardMessageUseCase(this._repository);

  final ConversationRepository _repository;

  Future<Result<ChatMessage>> execute({
    required String workspaceId,
    required String channelId,
    required String messageId,
    required String targetChannelId,
  }) {
    final target = targetChannelId.trim();
    if (target.isEmpty) {
      return Future.value(
        const FailureResult(
          Failure(
            kind: FailureKind.validation,
            message: 'Bạn cần chọn kênh nhận tin nhắn chuyển tiếp.',
            code: 'FORWARD_TARGET_REQUIRED',
          ),
        ),
      );
    }
    return _repository.forwardMessage(
      workspaceId: workspaceId,
      channelId: channelId,
      messageId: messageId,
      targetChannelId: target,
    );
  }
}

final class LoadThreadUseCase {
  const LoadThreadUseCase(this._repository);

  final ConversationRepository _repository;

  Future<Result<MessagePage>> execute({
    required String workspaceId,
    required String channelId,
    required String messageId,
    int limit = 50,
  }) {
    return _repository.listThread(
      workspaceId: workspaceId,
      channelId: channelId,
      messageId: messageId,
      limit: limit,
    );
  }
}

final class SearchMessagesUseCase {
  const SearchMessagesUseCase(this._repository);

  final ConversationRepository _repository;

  Future<Result<MessagePage>> execute(MessageSearchCommand command) {
    final query = command.query.trim();
    if (query.isEmpty) {
      return Future.value(
        const FailureResult(
          Failure(
            kind: FailureKind.validation,
            message: 'Từ khóa tìm kiếm không được để trống.',
            code: 'SEARCH_QUERY_REQUIRED',
          ),
        ),
      );
    }
    return _repository.searchMessagePage(
      workspaceId: command.workspaceId,
      channelId: command.channelId,
      query: query,
      senderId: command.senderId,
      kind: command.kind,
      dateFrom: command.dateFrom,
      dateTo: command.dateTo,
      limit: command.limit,
    );
  }
}

final class MessageSearchCommand {
  const MessageSearchCommand({
    required this.workspaceId,
    required this.query,
    this.channelId,
    this.senderId,
    this.kind,
    this.dateFrom,
    this.dateTo,
    this.limit = 30,
  });

  final String workspaceId;
  final String query;
  final String? channelId;
  final String? senderId;
  final String? kind;
  final DateTime? dateFrom;
  final DateTime? dateTo;
  final int limit;
}

final class MarkConversationReadUseCase {
  const MarkConversationReadUseCase(this._repository);

  final ConversationRepository _repository;

  Future<Result<void>> execute({
    required String workspaceId,
    required String channelId,
    required String lastReadMessageId,
  }) {
    return _repository.markRead(
      workspaceId: workspaceId,
      channelId: channelId,
      lastReadMessageId: lastReadMessageId,
    );
  }
}

final class SubscribeConversationRealtimeUseCase {
  const SubscribeConversationRealtimeUseCase(this._repository);

  final ConversationRealtimeRepository _repository;

  Stream<ConversationRealtimeEvent> execute({
    required String workspaceId,
    required String channelId,
  }) {
    return _repository.subscribeToChannel(
      workspaceId: workspaceId,
      channelId: channelId,
    );
  }
}

final class SendTypingUseCase {
  SendTypingUseCase(
    this._repository, {
    Duration throttle = const Duration(seconds: 2),
  }) : _throttle = throttle;

  final ConversationRealtimeRepository _repository;
  final Duration _throttle;
  DateTime? _lastSentAt;
  bool _lastState = false;

  Future<void> execute({
    required String workspaceId,
    required String channelId,
    required bool isTyping,
  }) async {
    final now = DateTime.now();
    final shouldThrottle =
        _lastState == isTyping &&
        _lastSentAt != null &&
        now.difference(_lastSentAt!) < _throttle;
    if (shouldThrottle) {
      return;
    }
    _lastSentAt = now;
    _lastState = isTyping;
    await _repository.sendTyping(
      workspaceId: workspaceId,
      channelId: channelId,
      isTyping: isTyping,
    );
  }
}

final class ReadDraftUseCase {
  const ReadDraftUseCase(this._repository);

  final ConversationDraftRepository _repository;

  Future<String> execute({
    required String workspaceId,
    required String channelId,
  }) {
    return _repository.readDraft(
      workspaceId: workspaceId,
      channelId: channelId,
    );
  }
}

final class SaveDraftUseCase {
  const SaveDraftUseCase(this._repository);

  final ConversationDraftRepository _repository;

  Future<void> execute({
    required String workspaceId,
    required String channelId,
    required String body,
  }) {
    return _repository.saveDraft(
      workspaceId: workspaceId,
      channelId: channelId,
      body: body,
    );
  }
}

final class ClearDraftUseCase {
  const ClearDraftUseCase(this._repository);

  final ConversationDraftRepository _repository;

  Future<void> execute({
    required String workspaceId,
    required String channelId,
  }) {
    return _repository.clearDraft(
      workspaceId: workspaceId,
      channelId: channelId,
    );
  }
}

Failure? _validateMessageBody(String body) {
  if (body.isEmpty || body.runes.length > 8000) {
    return const Failure(
      kind: FailureKind.validation,
      message: 'Nội dung tin nhắn phải dài từ 1 đến 8000 ký tự.',
      code: 'MESSAGE_BODY_INVALID',
    );
  }
  return null;
}
