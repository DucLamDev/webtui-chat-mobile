import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers/foundation_providers.dart';
import '../../../../core/result/result.dart';
import '../../../profile/application/use_cases/profile_use_cases.dart';
import '../../application/use_cases/call_use_cases.dart';
import '../../application/use_cases/conversation_realtime_reducer.dart';
import '../../application/use_cases/message_attachment_use_cases.dart';
import '../../application/use_cases/message_outbox_use_cases.dart';
import '../../application/use_cases/message_use_cases.dart';
import '../../domain/entities/call_session.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/entities/conversation_realtime_event.dart';
import '../../domain/entities/message_outbox_item.dart';

final chatRoomControllerProvider = StateNotifierProvider.autoDispose
    .family<ChatRoomController, ChatRoomState, ChatRoomScope>((ref, scope) {
      final controller = ChatRoomController(
        scope: scope,
        loadMessagesUseCase: ref.watch(loadMessagesUseCaseProvider),
        sendMessageUseCase: ref.watch(sendMessageUseCaseProvider),
        editMessageUseCase: ref.watch(editMessageUseCaseProvider),
        deleteMessageUseCase: ref.watch(deleteMessageUseCaseProvider),
        toggleReactionUseCase: ref.watch(toggleReactionUseCaseProvider),
        togglePinMessageUseCase: ref.watch(togglePinMessageUseCaseProvider),
        forwardMessageUseCase: ref.watch(forwardMessageUseCaseProvider),
        loadThreadUseCase: ref.watch(loadThreadUseCaseProvider),
        searchMessagesUseCase: ref.watch(searchMessagesUseCaseProvider),
        pickMessageAttachmentUseCase: ref.watch(
          pickMessageAttachmentUseCaseProvider,
        ),
        startVoiceMessageRecordingUseCase: ref.watch(
          startVoiceMessageRecordingUseCaseProvider,
        ),
        stopVoiceMessageRecordingUseCase: ref.watch(
          stopVoiceMessageRecordingUseCaseProvider,
        ),
        cancelVoiceMessageRecordingUseCase: ref.watch(
          cancelVoiceMessageRecordingUseCaseProvider,
        ),
        uploadMessageAttachmentUseCase: ref.watch(
          uploadMessageAttachmentUseCaseProvider,
        ),
        attachUploadedFileUseCase: ref.watch(attachUploadedFileUseCaseProvider),
        listMessageAttachmentsUseCase: ref.watch(
          listMessageAttachmentsUseCaseProvider,
        ),
        loadMessageOutboxUseCase: ref.watch(loadMessageOutboxUseCaseProvider),
        enqueueMessageOutboxUseCase: ref.watch(
          enqueueMessageOutboxUseCaseProvider,
        ),
        saveMessageOutboxItemUseCase: ref.watch(
          saveMessageOutboxItemUseCaseProvider,
        ),
        deleteMessageOutboxItemUseCase: ref.watch(
          deleteMessageOutboxItemUseCaseProvider,
        ),
        newClientMessageIdUseCase: ref.watch(newClientMessageIdUseCaseProvider),
        newAttachmentUploadItemUseCase: ref.watch(
          newAttachmentUploadItemUseCaseProvider,
        ),
        startCallUseCase: ref.watch(startCallUseCaseProvider),
        endCallUseCase: ref.watch(endCallUseCaseProvider),
        markConversationReadUseCase: ref.watch(
          markConversationReadUseCaseProvider,
        ),
        subscribeConversationRealtimeUseCase: ref.watch(
          subscribeConversationRealtimeUseCaseProvider,
        ),
        sendTypingUseCase: ref.watch(sendTypingUseCaseProvider),
        readDraftUseCase: ref.watch(readDraftUseCaseProvider),
        saveDraftUseCase: ref.watch(saveDraftUseCaseProvider),
        clearDraftUseCase: ref.watch(clearDraftUseCaseProvider),
        loadProfileUseCase: ref.watch(loadProfileUseCaseProvider),
      )..load();
      return controller;
    });

final class ChatRoomScope {
  const ChatRoomScope({
    required this.workspaceId,
    required this.channelId,
    required this.title,
  });

  final String workspaceId;
  final String channelId;
  final String title;

  @override
  bool operator ==(Object other) {
    return other is ChatRoomScope &&
        other.workspaceId == workspaceId &&
        other.channelId == channelId &&
        other.title == title;
  }

  @override
  int get hashCode => Object.hash(workspaceId, channelId, title);
}

final class ChatRoomState {
  const ChatRoomState({
    required this.scope,
    this.messages = const [],
    this.searchResults = const [],
    this.threadMessages = const [],
    this.pendingAttachments = const [],
    this.outboxItems = const [],
    this.threadRootMessage,
    this.typingUserIds = const {},
    this.draft = '',
    this.threadDraft = '',
    this.searchQuery = '',
    this.nextCursor,
    this.hasMore = false,
    this.isLoading = false,
    this.isLoadingOlder = false,
    this.isSending = false,
    this.isSendingThread = false,
    this.isSearching = false,
    this.isRecordingVoice = false,
    this.isStartingCall = false,
    this.errorMessage,
    this.noticeMessage,
    this.currentUserId,
    this.highlightedMessageId,
    this.activeCall,
    this.voiceRecordingStartedAt,
    this.replyToMessage,
    this.editingMessage,
  });

  final ChatRoomScope scope;
  final List<ChatMessage> messages;
  final List<ChatMessage> searchResults;
  final List<ChatMessage> threadMessages;
  final List<MessageAttachmentUploadItem> pendingAttachments;
  final List<MessageOutboxItem> outboxItems;
  final ChatMessage? threadRootMessage;
  final Set<String> typingUserIds;
  final String draft;
  final String threadDraft;
  final String searchQuery;
  final String? nextCursor;
  final bool hasMore;
  final bool isLoading;
  final bool isLoadingOlder;
  final bool isSending;
  final bool isSendingThread;
  final bool isSearching;
  final bool isRecordingVoice;
  final bool isStartingCall;
  final String? errorMessage;
  final String? noticeMessage;
  final String? currentUserId;
  final String? highlightedMessageId;
  final CallSession? activeCall;
  final DateTime? voiceRecordingStartedAt;
  final ChatMessage? replyToMessage;
  final ChatMessage? editingMessage;

  bool get hasComposerContext =>
      replyToMessage != null || editingMessage != null;
  bool get hasTypingUsers => typingUserIds.isNotEmpty;
  bool get hasPendingAttachments => pendingAttachments.isNotEmpty;
  bool get hasOutboxItems => outboxItems.isNotEmpty;
  int get failedOutboxCount =>
      outboxItems.where((item) => item.isFailed).length;
  int get sendingOutboxCount =>
      outboxItems.where((item) => item.isSending).length;
  bool get canSend =>
      draft.trim().isNotEmpty ||
      pendingAttachments.any(
        (item) => item.status == MessageAttachmentUploadStatus.uploaded,
      );
  List<ChatMessage> get pinnedMessages => messages
      .where((message) => message.isPinned && !message.isDeleted)
      .toList(growable: false);

  ChatRoomState copyWith({
    List<ChatMessage>? messages,
    List<ChatMessage>? searchResults,
    List<ChatMessage>? threadMessages,
    List<MessageAttachmentUploadItem>? pendingAttachments,
    List<MessageOutboxItem>? outboxItems,
    ChatMessage? threadRootMessage,
    Set<String>? typingUserIds,
    String? draft,
    String? threadDraft,
    String? searchQuery,
    String? nextCursor,
    bool? hasMore,
    bool? isLoading,
    bool? isLoadingOlder,
    bool? isSending,
    bool? isSendingThread,
    bool? isSearching,
    bool? isRecordingVoice,
    bool? isStartingCall,
    String? errorMessage,
    String? noticeMessage,
    String? currentUserId,
    String? highlightedMessageId,
    CallSession? activeCall,
    DateTime? voiceRecordingStartedAt,
    ChatMessage? replyToMessage,
    ChatMessage? editingMessage,
    bool clearError = false,
    bool clearNotice = false,
    bool clearSearch = false,
    bool clearThread = false,
    bool clearHighlight = false,
    bool clearActiveCall = false,
    bool clearVoiceRecording = false,
    bool clearReply = false,
    bool clearEditing = false,
  }) {
    return ChatRoomState(
      scope: scope,
      messages: messages ?? this.messages,
      searchResults: clearSearch
          ? const []
          : searchResults ?? this.searchResults,
      threadMessages: clearThread
          ? const []
          : threadMessages ?? this.threadMessages,
      pendingAttachments: pendingAttachments ?? this.pendingAttachments,
      outboxItems: outboxItems ?? this.outboxItems,
      threadRootMessage: clearThread
          ? null
          : threadRootMessage ?? this.threadRootMessage,
      typingUserIds: typingUserIds ?? this.typingUserIds,
      draft: draft ?? this.draft,
      threadDraft: clearThread ? '' : threadDraft ?? this.threadDraft,
      searchQuery: clearSearch ? '' : searchQuery ?? this.searchQuery,
      nextCursor: nextCursor ?? this.nextCursor,
      hasMore: hasMore ?? this.hasMore,
      isLoading: isLoading ?? this.isLoading,
      isLoadingOlder: isLoadingOlder ?? this.isLoadingOlder,
      isSending: isSending ?? this.isSending,
      isSendingThread: isSendingThread ?? this.isSendingThread,
      isSearching: isSearching ?? this.isSearching,
      isRecordingVoice: isRecordingVoice ?? this.isRecordingVoice,
      isStartingCall: isStartingCall ?? this.isStartingCall,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
      noticeMessage: clearNotice ? null : noticeMessage ?? this.noticeMessage,
      currentUserId: currentUserId ?? this.currentUserId,
      highlightedMessageId: clearHighlight
          ? null
          : highlightedMessageId ?? this.highlightedMessageId,
      activeCall: clearActiveCall ? null : activeCall ?? this.activeCall,
      voiceRecordingStartedAt: clearVoiceRecording
          ? null
          : voiceRecordingStartedAt ?? this.voiceRecordingStartedAt,
      replyToMessage: clearReply ? null : replyToMessage ?? this.replyToMessage,
      editingMessage: clearEditing
          ? null
          : editingMessage ?? this.editingMessage,
    );
  }
}

final class ChatRoomController extends StateNotifier<ChatRoomState> {
  ChatRoomController({
    required ChatRoomScope scope,
    required LoadMessagesUseCase loadMessagesUseCase,
    required SendMessageUseCase sendMessageUseCase,
    required EditMessageUseCase editMessageUseCase,
    required DeleteMessageUseCase deleteMessageUseCase,
    required ToggleReactionUseCase toggleReactionUseCase,
    required TogglePinMessageUseCase togglePinMessageUseCase,
    required ForwardMessageUseCase forwardMessageUseCase,
    required LoadThreadUseCase loadThreadUseCase,
    required SearchMessagesUseCase searchMessagesUseCase,
    required PickMessageAttachmentUseCase pickMessageAttachmentUseCase,
    required StartVoiceMessageRecordingUseCase
    startVoiceMessageRecordingUseCase,
    required StopVoiceMessageRecordingUseCase stopVoiceMessageRecordingUseCase,
    required CancelVoiceMessageRecordingUseCase
    cancelVoiceMessageRecordingUseCase,
    required UploadMessageAttachmentUseCase uploadMessageAttachmentUseCase,
    required AttachUploadedFileUseCase attachUploadedFileUseCase,
    required ListMessageAttachmentsUseCase listMessageAttachmentsUseCase,
    required LoadMessageOutboxUseCase loadMessageOutboxUseCase,
    required EnqueueMessageOutboxUseCase enqueueMessageOutboxUseCase,
    required SaveMessageOutboxItemUseCase saveMessageOutboxItemUseCase,
    required DeleteMessageOutboxItemUseCase deleteMessageOutboxItemUseCase,
    required NewClientMessageIdUseCase newClientMessageIdUseCase,
    required NewAttachmentUploadItemUseCase newAttachmentUploadItemUseCase,
    required StartCallUseCase startCallUseCase,
    required EndCallUseCase endCallUseCase,
    required MarkConversationReadUseCase markConversationReadUseCase,
    required SubscribeConversationRealtimeUseCase
    subscribeConversationRealtimeUseCase,
    required SendTypingUseCase sendTypingUseCase,
    required ReadDraftUseCase readDraftUseCase,
    required SaveDraftUseCase saveDraftUseCase,
    required ClearDraftUseCase clearDraftUseCase,
    required LoadProfileUseCase loadProfileUseCase,
    ConversationRealtimeReducer reducer = const ConversationRealtimeReducer(),
  }) : _loadMessagesUseCase = loadMessagesUseCase,
       _sendMessageUseCase = sendMessageUseCase,
       _editMessageUseCase = editMessageUseCase,
       _deleteMessageUseCase = deleteMessageUseCase,
       _toggleReactionUseCase = toggleReactionUseCase,
       _togglePinMessageUseCase = togglePinMessageUseCase,
       _forwardMessageUseCase = forwardMessageUseCase,
       _loadThreadUseCase = loadThreadUseCase,
       _searchMessagesUseCase = searchMessagesUseCase,
       _pickMessageAttachmentUseCase = pickMessageAttachmentUseCase,
       _startVoiceMessageRecordingUseCase = startVoiceMessageRecordingUseCase,
       _stopVoiceMessageRecordingUseCase = stopVoiceMessageRecordingUseCase,
       _cancelVoiceMessageRecordingUseCase = cancelVoiceMessageRecordingUseCase,
       _uploadMessageAttachmentUseCase = uploadMessageAttachmentUseCase,
       _attachUploadedFileUseCase = attachUploadedFileUseCase,
       _listMessageAttachmentsUseCase = listMessageAttachmentsUseCase,
       _loadMessageOutboxUseCase = loadMessageOutboxUseCase,
       _enqueueMessageOutboxUseCase = enqueueMessageOutboxUseCase,
       _saveMessageOutboxItemUseCase = saveMessageOutboxItemUseCase,
       _deleteMessageOutboxItemUseCase = deleteMessageOutboxItemUseCase,
       _newClientMessageIdUseCase = newClientMessageIdUseCase,
       _newAttachmentUploadItemUseCase = newAttachmentUploadItemUseCase,
       _startCallUseCase = startCallUseCase,
       _endCallUseCase = endCallUseCase,
       _markConversationReadUseCase = markConversationReadUseCase,
       _subscribeConversationRealtimeUseCase =
           subscribeConversationRealtimeUseCase,
       _sendTypingUseCase = sendTypingUseCase,
       _readDraftUseCase = readDraftUseCase,
       _saveDraftUseCase = saveDraftUseCase,
       _clearDraftUseCase = clearDraftUseCase,
       _loadProfileUseCase = loadProfileUseCase,
       _reducer = reducer,
       super(ChatRoomState(scope: scope));

  final LoadMessagesUseCase _loadMessagesUseCase;
  final SendMessageUseCase _sendMessageUseCase;
  final EditMessageUseCase _editMessageUseCase;
  final DeleteMessageUseCase _deleteMessageUseCase;
  final ToggleReactionUseCase _toggleReactionUseCase;
  final TogglePinMessageUseCase _togglePinMessageUseCase;
  final ForwardMessageUseCase _forwardMessageUseCase;
  final LoadThreadUseCase _loadThreadUseCase;
  final SearchMessagesUseCase _searchMessagesUseCase;
  final PickMessageAttachmentUseCase _pickMessageAttachmentUseCase;
  final StartVoiceMessageRecordingUseCase _startVoiceMessageRecordingUseCase;
  final StopVoiceMessageRecordingUseCase _stopVoiceMessageRecordingUseCase;
  final CancelVoiceMessageRecordingUseCase _cancelVoiceMessageRecordingUseCase;
  final UploadMessageAttachmentUseCase _uploadMessageAttachmentUseCase;
  final AttachUploadedFileUseCase _attachUploadedFileUseCase;
  final ListMessageAttachmentsUseCase _listMessageAttachmentsUseCase;
  final LoadMessageOutboxUseCase _loadMessageOutboxUseCase;
  final EnqueueMessageOutboxUseCase _enqueueMessageOutboxUseCase;
  final SaveMessageOutboxItemUseCase _saveMessageOutboxItemUseCase;
  final DeleteMessageOutboxItemUseCase _deleteMessageOutboxItemUseCase;
  final NewClientMessageIdUseCase _newClientMessageIdUseCase;
  final NewAttachmentUploadItemUseCase _newAttachmentUploadItemUseCase;
  final StartCallUseCase _startCallUseCase;
  final EndCallUseCase _endCallUseCase;
  final MarkConversationReadUseCase _markConversationReadUseCase;
  final SubscribeConversationRealtimeUseCase
  _subscribeConversationRealtimeUseCase;
  final SendTypingUseCase _sendTypingUseCase;
  final ReadDraftUseCase _readDraftUseCase;
  final SaveDraftUseCase _saveDraftUseCase;
  final ClearDraftUseCase _clearDraftUseCase;
  final LoadProfileUseCase _loadProfileUseCase;
  final ConversationRealtimeReducer _reducer;

  StreamSubscription<ConversationRealtimeEvent>? _realtimeSubscription;
  Timer? _typingStopTimer;
  bool _outboxRetryInFlight = false;

  Future<void> load() async {
    state = state.copyWith(
      isLoading: true,
      clearError: true,
      clearNotice: true,
    );
    final draftFuture = _readDraftUseCase.execute(
      workspaceId: state.scope.workspaceId,
      channelId: state.scope.channelId,
    );
    final outboxFuture = _loadMessageOutboxUseCase.execute(
      workspaceId: state.scope.workspaceId,
      channelId: state.scope.channelId,
    );
    final profileFuture = _loadProfileUseCase.execute();
    final result = await _loadMessagesUseCase.execute(
      workspaceId: state.scope.workspaceId,
      channelId: state.scope.channelId,
    );
    final draft = await draftFuture;
    final outboxItems = await outboxFuture;
    final profileResult = await profileFuture;
    final currentUserId = profileResult.valueOrNull?.id;
    switch (result) {
      case Success<MessagePage>(value: final page):
        final messages = _chronological(page.messages, currentUserId);
        state = state.copyWith(
          messages: messages,
          draft: draft,
          outboxItems: outboxItems,
          currentUserId: currentUserId,
          nextCursor: page.nextCursor,
          hasMore: page.hasMore,
          isLoading: false,
          clearError: true,
        );
        _subscribeRealtime();
        unawaited(_hydrateMissingAttachments(messages));
        await _markLatestRead();
        unawaited(retryOutbox(auto: true));
      case FailureResult<MessagePage>(failure: final failure):
        state = state.copyWith(
          draft: draft,
          outboxItems: outboxItems,
          currentUserId: currentUserId,
          isLoading: false,
          errorMessage: failure.message,
        );
    }
  }

  void suspendRealtime() {
    _typingStopTimer?.cancel();
    _typingStopTimer = null;
    unawaited(
      _sendTypingUseCase.execute(
        workspaceId: state.scope.workspaceId,
        channelId: state.scope.channelId,
        isTyping: false,
      ),
    );
    final subscription = _realtimeSubscription;
    _realtimeSubscription = null;
    if (subscription != null) {
      unawaited(subscription.cancel());
    }
    state = state.copyWith(typingUserIds: const {});
  }

  Future<void> loadOlder() async {
    if (!state.hasMore || state.isLoadingOlder || state.nextCursor == null) {
      return;
    }
    state = state.copyWith(isLoadingOlder: true, clearError: true);
    final result = await _loadMessagesUseCase.execute(
      workspaceId: state.scope.workspaceId,
      channelId: state.scope.channelId,
      beforeId: state.nextCursor,
    );
    switch (result) {
      case Success<MessagePage>(value: final page):
        final olderMessages = _chronological(
          page.messages,
          state.currentUserId,
        );
        final messages = _mergeChronological(olderMessages, state.messages);
        state = state.copyWith(
          messages: messages,
          nextCursor: page.nextCursor,
          hasMore: page.hasMore,
          isLoadingOlder: false,
        );
        unawaited(_hydrateMissingAttachments(olderMessages));
      case FailureResult<MessagePage>(failure: final failure):
        state = state.copyWith(
          isLoadingOlder: false,
          errorMessage: failure.message,
        );
    }
  }

  void updateDraft(String body) {
    state = state.copyWith(draft: body);
    unawaited(
      _sendTypingUseCase.execute(
        workspaceId: state.scope.workspaceId,
        channelId: state.scope.channelId,
        isTyping: body.trim().isNotEmpty,
      ),
    );
    _typingStopTimer?.cancel();
    if (body.trim().isNotEmpty) {
      _typingStopTimer = Timer(const Duration(seconds: 3), () {
        unawaited(
          _sendTypingUseCase.execute(
            workspaceId: state.scope.workspaceId,
            channelId: state.scope.channelId,
            isTyping: false,
          ),
        );
      });
    }
  }

  Future<void> persistDraft() {
    return _saveDraftUseCase.execute(
      workspaceId: state.scope.workspaceId,
      channelId: state.scope.channelId,
      body: state.draft,
    );
  }

  void startReply(ChatMessage message) {
    state = state.copyWith(replyToMessage: message, clearEditing: true);
  }

  void startEdit(ChatMessage message) {
    if (!message.isMine || message.isDeleted) {
      return;
    }
    state = state.copyWith(
      draft: message.body,
      editingMessage: message,
      clearReply: true,
    );
  }

  void cancelComposerContext() {
    state = state.copyWith(clearReply: true, clearEditing: true);
  }

  Future<void> sendCurrentDraft() async {
    final body = state.draft.trim();
    final attachmentsReady = state.pendingAttachments.any(
      (item) => item.status == MessageAttachmentUploadStatus.uploaded,
    );
    if ((body.isEmpty && !attachmentsReady) || state.isSending) {
      return;
    }
    final attachmentFallback = _attachmentMessageFallback(
      state.pendingAttachments,
    );
    final clientMessageId = _newClientMessageIdUseCase.execute();
    state = state.copyWith(isSending: true, clearError: true);
    final editing = state.editingMessage;
    final result = editing == null
        ? await _sendMessageUseCase.execute(
            workspaceId: state.scope.workspaceId,
            channelId: state.scope.channelId,
            body: body.isEmpty ? attachmentFallback : body,
            clientMessageId: clientMessageId,
            parentId: state.replyToMessage?.id,
          )
        : await _editMessageUseCase.execute(
            workspaceId: state.scope.workspaceId,
            channelId: state.scope.channelId,
            messageId: editing.id,
            body: body,
          );
    switch (result) {
      case Success<ChatMessage>(value: final message):
        final prepared = message.copyWith(
          isMine: message.senderId == state.currentUserId,
        );
        state = state.copyWith(
          messages: _upsertLocal(state.messages, prepared),
          draft: '',
          isSending: false,
          clearError: true,
          clearReply: true,
          clearEditing: true,
        );
        await _clearDraftUseCase.execute(
          workspaceId: state.scope.workspaceId,
          channelId: state.scope.channelId,
        );
        await _attachPendingFiles(prepared);
        await _markLatestRead();
      case FailureResult<ChatMessage>(failure: final failure):
        if (editing == null) {
          await _enqueueFailedSend(
            body: body.isEmpty ? attachmentFallback : body,
            clientMessageId: clientMessageId,
            parentId: state.replyToMessage?.id,
            errorMessage: failure.message,
          );
        } else {
          state = state.copyWith(
            isSending: false,
            errorMessage: failure.message,
          );
        }
        await persistDraft();
    }
  }

  Future<void> retryOutbox({bool auto = false}) async {
    if (_outboxRetryInFlight) {
      return;
    }
    final candidates = state.outboxItems
        .where((item) => !item.isSending)
        .toList(growable: false);
    if (candidates.isEmpty) {
      return;
    }
    _outboxRetryInFlight = true;
    try {
      for (final item in candidates) {
        await _retryOutboxItem(item, auto: auto);
      }
    } finally {
      _outboxRetryInFlight = false;
    }
  }

  Future<void> _enqueueFailedSend({
    required String body,
    required String clientMessageId,
    required String? parentId,
    required String errorMessage,
  }) async {
    final item = await _enqueueMessageOutboxUseCase.execute(
      workspaceId: state.scope.workspaceId,
      channelId: state.scope.channelId,
      clientMessageId: clientMessageId,
      body: body,
      parentId: parentId,
      attachments: uploadedOutboxAttachments(state.pendingAttachments),
      lastError: errorMessage,
    );
    state = state.copyWith(
      outboxItems: [...state.outboxItems, item],
      pendingAttachments: const [],
      draft: '',
      isSending: false,
      clearError: true,
      clearReply: true,
      clearEditing: true,
    );
    await _clearDraftUseCase.execute(
      workspaceId: state.scope.workspaceId,
      channelId: state.scope.channelId,
    );
  }

  Future<void> _retryOutboxItem(
    MessageOutboxItem item, {
    required bool auto,
  }) async {
    final sending = item.copyWith(
      status: MessageOutboxStatus.sending,
      attemptCount: item.attemptCount + 1,
      updatedAt: DateTime.now().toUtc(),
    );
    await _saveMessageOutboxItemUseCase.execute(sending);
    state = state.copyWith(outboxItems: _replaceOutboxItem(sending));

    final result = await _sendMessageUseCase.execute(
      workspaceId: sending.workspaceId,
      channelId: sending.channelId,
      body: sending.body,
      clientMessageId: sending.clientMessageId,
      parentId: sending.parentId,
    );
    switch (result) {
      case Success<ChatMessage>(value: final message):
        final prepared = message.copyWith(
          isMine: message.senderId == state.currentUserId,
        );
        final attachmentError = await _attachOutboxFiles(prepared, sending);
        if (attachmentError != null) {
          final failed = sending.copyWith(
            status: MessageOutboxStatus.failed,
            lastError: attachmentError,
            updatedAt: DateTime.now().toUtc(),
          );
          await _saveMessageOutboxItemUseCase.execute(failed);
          state = state.copyWith(
            messages: _upsertLocal(state.messages, prepared),
            outboxItems: _replaceOutboxItem(failed),
            errorMessage: auto ? null : attachmentError,
          );
          return;
        }
        await _deleteMessageOutboxItemUseCase.execute(sending);
        state = state.copyWith(
          messages: _upsertLocal(state.messages, prepared),
          outboxItems: _removeOutboxItem(sending.id),
          clearError: true,
        );
        await _markLatestRead();
      case FailureResult<ChatMessage>(failure: final failure):
        final failed = sending.copyWith(
          status: MessageOutboxStatus.failed,
          lastError: failure.message,
          updatedAt: DateTime.now().toUtc(),
        );
        await _saveMessageOutboxItemUseCase.execute(failed);
        state = state.copyWith(
          outboxItems: _replaceOutboxItem(failed),
          errorMessage: auto ? null : failure.message,
        );
    }
  }

  Future<String?> _attachOutboxFiles(
    ChatMessage message,
    MessageOutboxItem item,
  ) async {
    final attachments = [...item.attachments]
      ..sort((left, right) => left.sortOrder.compareTo(right.sortOrder));
    for (final attachment in attachments) {
      final result = await _attachUploadedFileUseCase.execute(
        workspaceId: item.workspaceId,
        channelId: item.channelId,
        messageId: message.id,
        fileId: attachment.fileId,
        sortOrder: attachment.sortOrder,
      );
      if (result case FailureResult<MessageAttachment>(
        failure: final failure,
      )) {
        return failure.message;
      }
    }
    return null;
  }

  List<MessageOutboxItem> _replaceOutboxItem(MessageOutboxItem item) {
    return state.outboxItems
        .map((entry) => entry.id == item.id ? item : entry)
        .toList(growable: false);
  }

  List<MessageOutboxItem> _removeOutboxItem(String itemId) {
    return state.outboxItems
        .where((entry) => entry.id != itemId)
        .toList(growable: false);
  }

  Future<void> deleteMessage(ChatMessage message) async {
    final result = await _deleteMessageUseCase.execute(
      workspaceId: state.scope.workspaceId,
      channelId: state.scope.channelId,
      messageId: message.id,
    );
    switch (result) {
      case Success<void>():
        state = state.copyWith(
          messages: state.messages
              .map(
                (item) => item.id == message.id
                    ? item.copyWith(
                        body: '',
                        deletedAt: item.deletedAt ?? DateTime.now().toUtc(),
                      )
                    : item,
              )
              .toList(growable: false),
        );
      case FailureResult<void>(failure: final failure):
        state = state.copyWith(errorMessage: failure.message);
    }
  }

  Future<void> toggleReaction(ChatMessage message, String emoji) async {
    final reacted = message.reactions.any(
      (reaction) => reaction.emoji == emoji && reaction.reactedByMe,
    );
    final result = await _toggleReactionUseCase.execute(
      workspaceId: state.scope.workspaceId,
      channelId: state.scope.channelId,
      messageId: message.id,
      emoji: emoji,
      reactedByMe: reacted,
    );
    _mergeActionResult(result);
  }

  Future<void> togglePin(ChatMessage message) async {
    final result = await _togglePinMessageUseCase.execute(
      workspaceId: state.scope.workspaceId,
      channelId: state.scope.channelId,
      messageId: message.id,
      isPinned: message.isPinned,
    );
    switch (result) {
      case Success<ChatMessage?>(value: final updated):
        if (updated == null) {
          state = state.copyWith(
            messages: state.messages
                .map(
                  (item) => item.id == message.id
                      ? item.copyWith(isPinned: false)
                      : item,
                )
                .toList(growable: false),
          );
        } else {
          state = state.copyWith(
            messages: _upsertLocal(
              state.messages,
              updated.copyWith(isPinned: true),
            ),
          );
        }
      case FailureResult<ChatMessage?>(failure: final failure):
        state = state.copyWith(errorMessage: failure.message);
    }
  }

  Future<void> forwardMessage(
    ChatMessage message,
    String targetChannelId,
  ) async {
    final result = await _forwardMessageUseCase.execute(
      workspaceId: state.scope.workspaceId,
      channelId: state.scope.channelId,
      messageId: message.id,
      targetChannelId: targetChannelId,
    );
    switch (result) {
      case Success<ChatMessage>():
        state = state.copyWith(noticeMessage: 'Đã chuyển tiếp tin nhắn.');
      case FailureResult<ChatMessage>(failure: final failure):
        state = state.copyWith(errorMessage: failure.message);
    }
  }

  Future<void> loadThread(ChatMessage message) async {
    final result = await _loadThreadUseCase.execute(
      workspaceId: state.scope.workspaceId,
      channelId: state.scope.channelId,
      messageId: message.id,
    );
    switch (result) {
      case Success<MessagePage>(value: final page):
        state = state.copyWith(
          threadRootMessage: message,
          threadMessages: _chronological(page.messages, state.currentUserId),
          threadDraft: '',
        );
      case FailureResult<MessagePage>(failure: final failure):
        state = state.copyWith(errorMessage: failure.message);
    }
  }

  void updateThreadDraft(String body) {
    state = state.copyWith(threadDraft: body);
  }

  Future<void> sendThreadDraft() async {
    final root = state.threadRootMessage;
    final body = state.threadDraft.trim();
    if (root == null || body.isEmpty || state.isSendingThread) {
      return;
    }
    state = state.copyWith(isSendingThread: true, clearError: true);
    final result = await _sendMessageUseCase.execute(
      workspaceId: state.scope.workspaceId,
      channelId: state.scope.channelId,
      body: body,
      parentId: root.id,
    );
    switch (result) {
      case Success<ChatMessage>(value: final message):
        final prepared = message.copyWith(
          isMine: message.senderId == state.currentUserId,
        );
        state = state.copyWith(
          messages: _upsertLocal(state.messages, prepared),
          threadMessages: _upsertLocal(state.threadMessages, prepared),
          threadDraft: '',
          isSendingThread: false,
          clearError: true,
        );
        await _markLatestRead();
      case FailureResult<ChatMessage>(failure: final failure):
        state = state.copyWith(
          isSendingThread: false,
          errorMessage: failure.message,
        );
    }
  }

  Future<void> pickAttachment(MessageAttachmentPickSource source) async {
    final pickedResult = await _pickMessageAttachmentUseCase.execute(source);
    switch (pickedResult) {
      case Success<PickedMessageAttachment?>(value: final picked):
        if (picked == null) {
          return;
        }
        await _queueAttachment(picked);
      case FailureResult<PickedMessageAttachment?>(failure: final failure):
        state = state.copyWith(errorMessage: failure.message);
    }
  }

  Future<void> startVoiceRecording() async {
    if (state.isRecordingVoice || state.isSending) {
      return;
    }
    state = state.copyWith(clearError: true, clearNotice: true);
    final result = await _startVoiceMessageRecordingUseCase.execute();
    switch (result) {
      case Success<void>():
        state = state.copyWith(
          isRecordingVoice: true,
          voiceRecordingStartedAt: DateTime.now(),
          clearError: true,
        );
      case FailureResult<void>(failure: final failure):
        state = state.copyWith(errorMessage: failure.message);
    }
  }

  Future<void> stopVoiceRecording() async {
    if (!state.isRecordingVoice) {
      return;
    }
    final result = await _stopVoiceMessageRecordingUseCase.execute();
    state = state.copyWith(
      isRecordingVoice: false,
      clearVoiceRecording: true,
      clearError: true,
    );
    switch (result) {
      case Success<PickedMessageAttachment?>(value: final picked):
        if (picked != null) {
          await _queueAttachment(picked);
        }
      case FailureResult<PickedMessageAttachment?>(failure: final failure):
        state = state.copyWith(errorMessage: failure.message);
    }
  }

  Future<void> cancelVoiceRecording() async {
    if (!state.isRecordingVoice) {
      return;
    }
    final result = await _cancelVoiceMessageRecordingUseCase.execute();
    state = state.copyWith(
      isRecordingVoice: false,
      clearVoiceRecording: true,
      clearError: result.isSuccess,
      errorMessage: result.failureOrNull?.message,
    );
  }

  Future<void> _queueAttachment(PickedMessageAttachment picked) async {
    final item = _newAttachmentUploadItemUseCase.execute(picked);
    state = state.copyWith(
      pendingAttachments: [...state.pendingAttachments, item],
      clearError: true,
    );
    await _uploadAttachment(item.clientAttachmentId);
  }

  Future<void> retryAttachment(String clientAttachmentId) {
    return _uploadAttachment(clientAttachmentId);
  }

  void removeAttachment(String clientAttachmentId) {
    state = state.copyWith(
      pendingAttachments: state.pendingAttachments
          .where((item) => item.clientAttachmentId != clientAttachmentId)
          .toList(growable: false),
    );
  }

  Future<void> _uploadAttachment(String clientAttachmentId) async {
    final item = _attachmentItemById(
      state.pendingAttachments,
      clientAttachmentId,
    );
    final picked = item?.picked;
    if (item == null || picked == null) {
      return;
    }
    state = state.copyWith(
      pendingAttachments: _replaceAttachmentItem(
        state.pendingAttachments,
        item.copyWith(
          status: MessageAttachmentUploadStatus.uploading,
          progress: 0.08,
          clearError: true,
        ),
      ),
    );
    final result = await _uploadMessageAttachmentUseCase.execute(
      workspaceId: state.scope.workspaceId,
      attachment: picked,
    );
    switch (result) {
      case Success<UploadedMessageFile>(value: final file):
        state = state.copyWith(
          pendingAttachments: _replaceAttachmentItem(
            state.pendingAttachments,
            item.copyWith(
              status: MessageAttachmentUploadStatus.uploaded,
              uploadedFile: file,
              progress: 1,
              clearError: true,
            ),
          ),
        );
      case FailureResult<UploadedMessageFile>(failure: final failure):
        state = state.copyWith(
          pendingAttachments: _replaceAttachmentItem(
            state.pendingAttachments,
            item.copyWith(
              status: MessageAttachmentUploadStatus.failed,
              progress: 0,
              errorMessage: failure.message,
            ),
          ),
          errorMessage: failure.message,
        );
    }
  }

  Future<void> _attachPendingFiles(ChatMessage message) async {
    final readyItems = state.pendingAttachments
        .where(
          (item) =>
              item.status == MessageAttachmentUploadStatus.uploaded &&
              item.uploadedFile != null,
        )
        .toList(growable: false);
    if (readyItems.isEmpty) {
      return;
    }
    final attached = <MessageAttachment>[];
    for (var index = 0; index < readyItems.length; index += 1) {
      final item = readyItems[index];
      final file = item.uploadedFile!;
      final result = await _attachUploadedFileUseCase.execute(
        workspaceId: state.scope.workspaceId,
        channelId: state.scope.channelId,
        messageId: message.id,
        fileId: file.id,
        sortOrder: index,
      );
      switch (result) {
        case Success<MessageAttachment>(value: final attachment):
          attached.add(attachment);
          state = state.copyWith(
            pendingAttachments: _replaceAttachmentItem(
              state.pendingAttachments,
              item.copyWith(
                status: MessageAttachmentUploadStatus.attached,
                attachment: attachment,
                clearError: true,
              ),
            ),
          );
        case FailureResult<MessageAttachment>(failure: final failure):
          state = state.copyWith(
            pendingAttachments: _replaceAttachmentItem(
              state.pendingAttachments,
              item.copyWith(
                status: MessageAttachmentUploadStatus.failed,
                errorMessage: failure.message,
              ),
            ),
            errorMessage: failure.message,
          );
      }
    }
    if (attached.isNotEmpty) {
      state = state.copyWith(
        messages: state.messages
            .map(
              (item) => item.id == message.id
                  ? item.copyWith(attachments: attached)
                  : item,
            )
            .toList(growable: false),
        pendingAttachments: state.pendingAttachments
            .where(
              (item) => item.status != MessageAttachmentUploadStatus.attached,
            )
            .toList(growable: false),
      );
    }
  }

  Future<void> _hydrateMissingAttachments(List<ChatMessage> messages) async {
    final targets = messages
        .where(_shouldHydrateAttachments)
        .toList(growable: false);
    if (targets.isEmpty) {
      return;
    }

    for (final message in targets) {
      final result = await _listMessageAttachmentsUseCase.execute(
        workspaceId: message.workspaceId,
        channelId: message.channelId,
        messageId: message.id,
      );
      if (!mounted) {
        return;
      }
      switch (result) {
        case Success<List<MessageAttachment>>(value: final attachments):
          if (attachments.isEmpty) {
            continue;
          }
          state = state.copyWith(
            messages: state.messages
                .map(
                  (item) => item.id == message.id && item.attachments.isEmpty
                      ? item.copyWith(attachments: attachments)
                      : item,
                )
                .toList(growable: false),
          );
        case FailureResult<List<MessageAttachment>>():
          continue;
      }
    }
  }

  Future<void> search(String query) async {
    final normalized = query.trim();
    if (normalized.isEmpty) {
      state = state.copyWith(clearSearch: true);
      return;
    }
    state = state.copyWith(
      searchQuery: normalized,
      isSearching: true,
      clearError: true,
    );
    final result = await _searchMessagesUseCase.execute(
      MessageSearchCommand(
        workspaceId: state.scope.workspaceId,
        channelId: state.scope.channelId,
        query: normalized,
      ),
    );
    switch (result) {
      case Success<MessagePage>(value: final page):
        state = state.copyWith(
          searchResults: _chronological(page.messages, state.currentUserId),
          isSearching: false,
        );
      case FailureResult<MessagePage>(failure: final failure):
        state = state.copyWith(
          isSearching: false,
          errorMessage: failure.message,
        );
    }
  }

  void clearSearch() {
    state = state.copyWith(clearSearch: true, clearHighlight: true);
  }

  void clearThread() {
    state = state.copyWith(clearThread: true);
  }

  void focusMessage(ChatMessage message) {
    state = state.copyWith(
      messages: _upsertLocal(
        state.messages,
        message.copyWith(isMine: message.senderId == state.currentUserId),
      ),
      highlightedMessageId: message.id,
    );
  }

  void highlightMessage(String messageId) {
    final normalized = messageId.trim();
    if (normalized.isEmpty) {
      return;
    }
    state = state.copyWith(highlightedMessageId: normalized);
  }

  Future<CallSession?> startCall({
    required String targetUserId,
    required CallMode mode,
  }) async {
    if (state.isStartingCall) {
      return null;
    }
    state = state.copyWith(
      isStartingCall: true,
      clearError: true,
      clearNotice: true,
    );
    final result = await _startCallUseCase.execute(
      workspaceId: state.scope.workspaceId,
      channelId: state.scope.channelId,
      targetUserId: targetUserId,
      mode: mode,
    );
    switch (result) {
      case Success<CallSession>(value: final call):
        state = state.copyWith(
          activeCall: call,
          isStartingCall: false,
          noticeMessage: mode == CallMode.video
              ? 'Đang bắt đầu cuộc gọi video.'
              : 'Đang bắt đầu cuộc gọi thoại.',
          clearError: true,
        );
        return call;
      case FailureResult<CallSession>(failure: final failure):
        state = state.copyWith(
          isStartingCall: false,
          errorMessage: failure.message,
        );
        return null;
    }
  }

  Future<void> endActiveCall({
    String? reason,
    CallStatus? currentStatus,
  }) async {
    final call = state.activeCall;
    if (call == null) {
      return;
    }
    final result = await _endCallUseCase.execute(
      workspaceId: state.scope.workspaceId,
      callId: call.id,
      currentStatus: currentStatus ?? call.status,
      reason: reason,
    );
    switch (result) {
      case Success<CallSession>():
        state = state.copyWith(clearActiveCall: true, clearError: true);
      case FailureResult<CallSession>(failure: final failure):
        state = state.copyWith(errorMessage: failure.message);
    }
  }

  void _mergeActionResult(Result<ChatMessage> result) {
    switch (result) {
      case Success<ChatMessage>(value: final message):
        state = state.copyWith(
          messages: _upsertLocal(
            state.messages,
            message.copyWith(isMine: message.senderId == state.currentUserId),
          ),
        );
      case FailureResult<ChatMessage>(failure: final failure):
        state = state.copyWith(errorMessage: failure.message);
    }
  }

  void _subscribeRealtime() {
    _realtimeSubscription ??= _subscribeConversationRealtimeUseCase
        .execute(
          workspaceId: state.scope.workspaceId,
          channelId: state.scope.channelId,
        )
        .where(
          (event) => event.belongsTo(
            workspaceId: state.scope.workspaceId,
            channelId: state.scope.channelId,
          ),
        )
        .listen(_handleRealtimeEvent);
  }

  void _handleRealtimeEvent(ConversationRealtimeEvent event) {
    final reduced = _reducer.reduce(
      ConversationRealtimeState(
        messages: state.messages,
        typingUserIds: state.typingUserIds,
      ),
      event,
      currentUserId: state.currentUserId,
    );
    state = state.copyWith(
      messages: reduced.messages,
      typingUserIds: reduced.typingUserIds,
    );
    if (event.isCallEvent) {
      _handleRealtimeCallEvent(event);
    }
    if (event.type == ConversationRealtimeEventType.messageCreated ||
        event.type == ConversationRealtimeEventType.messageUpdated) {
      final messageId = event.messageId ?? event.message?.id;
      if (messageId != null && messageId.isNotEmpty) {
        final targets = state.messages
            .where((message) => message.id == messageId)
            .toList(growable: false);
        unawaited(_hydrateMissingAttachments(targets));
      }
      unawaited(_markLatestRead());
    }
    if (event.type == ConversationRealtimeEventType.attachmentCreated) {
      final messageId = event.messageId;
      if (messageId != null && messageId.isNotEmpty) {
        unawaited(_hydrateMessageAttachments(messageId));
      }
    }
  }

  void _handleRealtimeCallEvent(ConversationRealtimeEvent event) {
    final call = state.activeCall;
    final eventCallId = event.callId?.trim();
    if (call == null || eventCallId == null || eventCallId != call.id) {
      if (event.callStatus?.isTerminal == true) {
        unawaited(load());
      }
      return;
    }
    final status = event.callStatus;
    if (status == null) {
      return;
    }
    if (status.isTerminal) {
      state = state.copyWith(clearActiveCall: true, clearError: true);
      unawaited(load());
      return;
    }
    state = state.copyWith(
      activeCall: call.copyWith(
        status: status,
        startedAt: status == CallStatus.accepted
            ? call.startedAt ?? event.timestamp ?? DateTime.now().toUtc()
            : call.startedAt,
        updatedAt: event.timestamp ?? DateTime.now().toUtc(),
      ),
    );
  }

  Future<void> _hydrateMessageAttachments(String messageId) async {
    final result = await _listMessageAttachmentsUseCase.execute(
      workspaceId: state.scope.workspaceId,
      channelId: state.scope.channelId,
      messageId: messageId,
    );
    if (!mounted) {
      return;
    }
    if (result case Success<List<MessageAttachment>>(
      value: final attachments,
    )) {
      if (attachments.isEmpty) {
        return;
      }
      state = state.copyWith(
        messages: state.messages
            .map(
              (message) => message.id == messageId
                  ? message.copyWith(attachments: attachments)
                  : message,
            )
            .toList(growable: false),
      );
    }
  }

  Future<void> _markLatestRead() async {
    if (state.messages.isEmpty) {
      return;
    }
    final latest = state.messages.last;
    await _markConversationReadUseCase.execute(
      workspaceId: state.scope.workspaceId,
      channelId: state.scope.channelId,
      lastReadMessageId: latest.id,
    );
  }

  @override
  void dispose() {
    _typingStopTimer?.cancel();
    unawaited(_realtimeSubscription?.cancel());
    super.dispose();
  }
}

List<ChatMessage> _chronological(
  List<ChatMessage> messages,
  String? currentUserId,
) {
  final sorted = messages
      .map(
        (message) => message.copyWith(
          isMine:
              currentUserId != null &&
              currentUserId.trim().isNotEmpty &&
              message.senderId == currentUserId,
        ),
      )
      .toList(growable: false);
  sorted.sort((left, right) => left.createdAt.compareTo(right.createdAt));
  return sorted;
}

List<ChatMessage> _mergeChronological(
  List<ChatMessage> older,
  List<ChatMessage> current,
) {
  final byId = <String, ChatMessage>{};
  for (final message in [...older, ...current]) {
    byId[message.id] = message;
  }
  final result = byId.values.toList(growable: false);
  result.sort((left, right) => left.createdAt.compareTo(right.createdAt));
  return result;
}

List<ChatMessage> _upsertLocal(
  List<ChatMessage> current,
  ChatMessage incoming,
) {
  return _mergeChronological(const [], [
    ...current.where((message) => message.id != incoming.id),
    incoming,
  ]);
}

bool _shouldHydrateAttachments(ChatMessage message) {
  if (message.id.startsWith('local-') ||
      message.isDeleted ||
      message.attachments.isNotEmpty) {
    return false;
  }
  if (message.kind == 'file') {
    return true;
  }

  final normalized = _compactAttachmentBody(message.body);
  if (normalized.isEmpty) {
    return false;
  }
  return normalized == 'đã gửi tệp đính kèm' ||
      _sameAttachmentTextWithoutVietnameseDiacritics(
        normalized,
        'đã gửi tệp đính kèm',
      ) ||
      RegExp(
        r'^đã gửi(?: \d+)? (?:ảnh|file|tin nhắn thoại)$',
      ).hasMatch(normalized) ||
      _matchesGeneratedAttachmentBody(normalized, noun: 'ảnh') ||
      _matchesGeneratedAttachmentBody(normalized, noun: 'file') ||
      _matchesGeneratedAttachmentBody(normalized, noun: 'tin nhắn thoại') ||
      RegExp(r'^đã gửi file .+').hasMatch(normalized) ||
      _matchesGeneratedFileAttachmentBody(normalized);
}

String _compactAttachmentBody(String value) {
  return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
}

bool _matchesGeneratedAttachmentBody(String value, {required String noun}) {
  final normalized = _removeVietnameseDiacritics(value);
  final sent = _removeVietnameseDiacritics('đã gửi');
  final normalizedNoun = _removeVietnameseDiacritics(noun);
  return RegExp(
    '^${RegExp.escape(sent)}(?: \\d+)? ${RegExp.escape(normalizedNoun)}\$',
  ).hasMatch(normalized);
}

bool _matchesGeneratedFileAttachmentBody(String value) {
  final normalized = _removeVietnameseDiacritics(value);
  final prefix = _removeVietnameseDiacritics('đã gửi file ');
  return normalized.startsWith(prefix) && normalized.length > prefix.length;
}

bool _sameAttachmentTextWithoutVietnameseDiacritics(String left, String right) {
  return _removeVietnameseDiacritics(left) ==
      _removeVietnameseDiacritics(right);
}

String _removeVietnameseDiacritics(String value) {
  const groups = {
    'a': 'àáạảãâầấậẩẫăằắặẳẵ',
    'A': 'ÀÁẠẢÃÂẦẤẬẨẪĂẰẮẶẲẴ',
    'e': 'èéẹẻẽêềếệểễ',
    'E': 'ÈÉẸẺẼÊỀẾỆỂỄ',
    'i': 'ìíịỉĩ',
    'I': 'ÌÍỊỈĨ',
    'o': 'òóọỏõôồốộổỗơờớợởỡ',
    'O': 'ÒÓỌỎÕÔỒỐỘỔỖƠỜỚỢỞỠ',
    'u': 'ùúụủũưừứựửữ',
    'U': 'ÙÚỤỦŨƯỪỨỰỬỮ',
    'y': 'ỳýỵỷỹ',
    'Y': 'ỲÝỴỶỸ',
    'd': 'đ',
    'D': 'Đ',
  };
  final buffer = StringBuffer();
  for (final rune in value.runes) {
    final char = String.fromCharCode(rune);
    var replacement = char;
    for (final entry in groups.entries) {
      if (entry.value.contains(char)) {
        replacement = entry.key;
        break;
      }
    }
    buffer.write(replacement);
  }
  return buffer.toString();
}

MessageAttachmentUploadItem? _attachmentItemById(
  List<MessageAttachmentUploadItem> items,
  String clientAttachmentId,
) {
  for (final item in items) {
    if (item.clientAttachmentId == clientAttachmentId) {
      return item;
    }
  }
  return null;
}

List<MessageAttachmentUploadItem> _replaceAttachmentItem(
  List<MessageAttachmentUploadItem> items,
  MessageAttachmentUploadItem replacement,
) {
  return items
      .map(
        (item) => item.clientAttachmentId == replacement.clientAttachmentId
            ? replacement
            : item,
      )
      .toList(growable: false);
}

String _attachmentMessageFallback(
  List<MessageAttachmentUploadItem> attachments,
) {
  final ready = attachments
      .where((item) => item.status == MessageAttachmentUploadStatus.uploaded)
      .toList(growable: false);
  if (ready.isEmpty) return 'Đã gửi tệp đính kèm';
  final kinds = ready
      .map((item) => item.picked?.kind)
      .whereType<MessageAttachmentKind>()
      .toSet();
  if (kinds.length == 1 && kinds.first == MessageAttachmentKind.image) {
    return ready.length == 1 ? 'Đã gửi ảnh' : 'Đã gửi ${ready.length} ảnh';
  }
  if (kinds.length == 1 && kinds.first == MessageAttachmentKind.audio) {
    return ready.length == 1
        ? 'Đã gửi tin nhắn thoại'
        : 'Đã gửi ${ready.length} tin nhắn thoại';
  }
  return ready.length == 1
      ? 'Đã gửi tệp đính kèm'
      : 'Đã gửi ${ready.length} file';
}
