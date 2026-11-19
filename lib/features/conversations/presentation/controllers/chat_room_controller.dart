import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers/foundation_providers.dart';
import '../../../../core/result/result.dart';
import '../../../../l10n/app_strings.dart';
import '../../../profile/application/use_cases/profile_use_cases.dart';
import '../../application/message_attachment_memo.dart';
import '../../application/message_sync_service.dart';
import '../../application/use_cases/call_use_cases.dart';
import '../../application/use_cases/conversation_realtime_reducer.dart';
import '../../application/use_cases/message_attachment_use_cases.dart';
import '../../application/use_cases/message_media_uploader.dart';
import '../../application/use_cases/message_outbox_dispatcher.dart';
import '../../application/use_cases/message_outbox_use_cases.dart';
import '../../application/use_cases/message_stream_merger.dart';
import '../../application/use_cases/message_use_cases.dart';
import '../../application/use_cases/rich_message_use_cases.dart';
import '../../domain/entities/call_session.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/entities/conversation_realtime_event.dart';
import '../../domain/entities/message_outbox_item.dart';
import '../../domain/entities/message_voice.dart';
import '../../domain/entities/rich_message.dart';
import 'channel_membership_events.dart';
import 'media_cache_providers.dart';

final chatRoomControllerProvider = StateNotifierProvider.autoDispose
    .family<ChatRoomController, ChatRoomState, ChatRoomScope>((ref, scope) {
      final legalPolicy = ref.watch(legalAcceptanceAccessPolicyProvider);
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
        messageMediaUploader: ref.watch(messageMediaUploaderProvider),
        listMessageAttachmentsUseCase: ref.watch(
          listMessageAttachmentsUseCaseProvider,
        ),
        attachmentMemo: ref.watch(messageAttachmentMemoProvider),
        evictCachedAttachments: ref.watch(
          messageAttachmentCacheEvictionProvider,
        ),
        loadMessageOutboxUseCase: ref.watch(loadMessageOutboxUseCaseProvider),
        enqueueMessageOutboxUseCase: ref.watch(
          enqueueMessageOutboxUseCaseProvider,
        ),
        outboxDispatcher: ref.watch(messageOutboxDispatcherProvider),
        workspaceResets: ref
            .watch(workspaceRefreshSignalProvider)
            .resetsFor(scope.workspaceId),
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
        resolveCurrentUserId: () =>
            ref.read(resolveCurrentUserIdUseCaseProvider).execute(),
        getMessageUseCase: ref.watch(getMessageUseCaseProvider),
        messageSyncService: ref.watch(messageSyncServiceProvider),
        canCreateUserContent: () => legalPolicy.canCreateUserContent,
        onLegalAcceptanceRequired: legalPolicy.requireAcceptance,
        // Rời / xoá nhóm (room kênh): người khác rời thì làm mới số thành
        // viên; nhóm bị xoá / mình rời thì bỏ nhóm và đóng phòng.
        onChannelMembershipEvent: (event, currentUserId) =>
            handleChannelMembershipEvent(
              read: ref.read,
              exists: ref.exists,
              event: event,
              currentUserId: currentUserId,
            ),
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

/// Kết quả tìm kiếm đang hiện lấy từ đâu.
enum MessageSearchSource {
  none,

  /// Tìm trên máy chủ (máy chủ cũ / không lưu tin trên máy).
  server,

  /// Chỉ trong tin đã lưu trên máy (chưa hỏi máy chủ).
  device,

  /// Tin trên máy + kết quả máy chủ đã gộp.
  deviceAndServer,
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
    this.searchSource = MessageSearchSource.none,
    this.isSearchingServer = false,
    this.searchServerError,
    this.syncNotice,
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

  /// Nguồn của [searchResults]; [MessageSearchSource.device] thì màn hiện nút
  /// "Tìm thêm trên máy chủ".
  final MessageSearchSource searchSource;

  /// Đang tìm thêm trên máy chủ (sau khi đã tìm trên máy).
  final bool isSearchingServer;

  /// Tìm thêm trên máy chủ bị lỗi (kết quả trên máy vẫn giữ).
  final String? searchServerError;

  /// Báo nhẹ (không phải lỗi đỏ): chưa kết nối được máy chủ, đang hiện tin đã
  /// lưu trên máy.
  final String? syncNotice;
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

  /// Còn tệp đang nén / tải lên. Vẫn cho gửi: tin hiện ngay với tiến độ và bộ
  /// gửi tin chờ tự gửi khi tải xong (ô tải lỗi thì bị bỏ khi gửi).
  bool get hasUploadingAttachments => pendingAttachments.any(
    (item) => item.status == MessageAttachmentUploadStatus.uploading,
  );
  bool get canSend =>
      draft.trim().isNotEmpty ||
      pendingAttachments.any(
        (item) =>
            item.status == MessageAttachmentUploadStatus.uploaded ||
            item.status == MessageAttachmentUploadStatus.uploading ||
            item.status == MessageAttachmentUploadStatus.queued,
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
    MessageSearchSource? searchSource,
    bool? isSearchingServer,
    String? searchServerError,
    String? syncNotice,
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
    bool clearSearchServerError = false,
    bool clearSyncNotice = false,
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
      searchSource: clearSearch
          ? MessageSearchSource.none
          : searchSource ?? this.searchSource,
      isSearchingServer: clearSearch
          ? false
          : isSearchingServer ?? this.isSearchingServer,
      searchServerError: clearSearch || clearSearchServerError
          ? null
          : searchServerError ?? this.searchServerError,
      syncNotice: clearSyncNotice ? null : syncNotice ?? this.syncNotice,
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
    required MessageMediaUploader messageMediaUploader,
    required ListMessageAttachmentsUseCase listMessageAttachmentsUseCase,
    MessageAttachmentMemo? attachmentMemo,
    Future<void> Function(List<MessageAttachment> attachments)?
    evictCachedAttachments,
    required LoadMessageOutboxUseCase loadMessageOutboxUseCase,
    required EnqueueMessageOutboxUseCase enqueueMessageOutboxUseCase,
    required MessageOutboxDispatcher outboxDispatcher,
    Stream<String>? workspaceResets,
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
    Future<String?> Function()? resolveCurrentUserId,
    GetMessageUseCase? getMessageUseCase,
    MessageSyncService? messageSyncService,
    bool Function()? canCreateUserContent,
    void Function()? onLegalAcceptanceRequired,
    void Function(ConversationRealtimeEvent event, String? currentUserId)?
    onChannelMembershipEvent,
    ConversationRealtimeReducer reducer = const ConversationRealtimeReducer(),
  }) : _onChannelMembershipEvent = onChannelMembershipEvent,
       _loadMessagesUseCase = loadMessagesUseCase,
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
       _messageMediaUploader = messageMediaUploader,
       _listMessageAttachmentsUseCase = listMessageAttachmentsUseCase,
       _attachmentMemo = attachmentMemo,
       _evictCachedAttachments = evictCachedAttachments,
       _loadMessageOutboxUseCase = loadMessageOutboxUseCase,
       _enqueueMessageOutboxUseCase = enqueueMessageOutboxUseCase,
       _outboxDispatcher = outboxDispatcher,
       _workspaceResets = workspaceResets,
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
       _resolveCurrentUserId = resolveCurrentUserId,
       _getMessageUseCase = getMessageUseCase,
       _syncService = messageSyncService,
       _canCreateUserContent =
           canCreateUserContent ?? _allowUserContentByDefault,
       _onLegalAcceptanceRequired = onLegalAcceptanceRequired ?? _noop,
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
  final MessageMediaUploader _messageMediaUploader;
  final ListMessageAttachmentsUseCase _listMessageAttachmentsUseCase;

  /// Tệp đính kèm đã hỏi của từng tin, dùng chung mọi phòng (null = không nhớ).
  final MessageAttachmentMemo? _attachmentMemo;

  /// Xoá tệp đã lưu trên máy của các tệp đính kèm (tin bị thu hồi / xoá /
  /// hết hạn); null = không xoá (kho tự dọn sau 7 ngày như trước).
  final Future<void> Function(List<MessageAttachment> attachments)?
  _evictCachedAttachments;
  final LoadMessageOutboxUseCase _loadMessageOutboxUseCase;
  final EnqueueMessageOutboxUseCase _enqueueMessageOutboxUseCase;
  final MessageOutboxDispatcher _outboxDispatcher;
  final Stream<String>? _workspaceResets;
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

  /// Mã người dùng hiện tại lấy từ token trên máy (không gọi mạng); `null` thì
  /// tải hồ sơ như trước.
  final Future<String?> Function()? _resolveCurrentUserId;

  /// Tải lại một tin chạy dần khi thiếu đoạn (`null` = không tải lại, chờ bản cuối).
  final GetMessageUseCase? _getMessageUseCase;

  /// Lưu tin trên máy + chỉ hỏi máy chủ phần thay đổi; `null` (hoặc máy chủ
  /// cũ chưa có luồng thay đổi) thì tải trang tin như trước.
  final MessageSyncService? _syncService;

  /// Tin cũ nhất của đoạn liền mạch đang hiện (mốc cho "tải tin cũ hơn"); tin
  /// mở từ kết quả tìm kiếm chèn vào không đổi mốc này.
  ChatMessage? _olderAnchor;
  static const _pageSize = 50;
  final bool Function() _canCreateUserContent;
  final void Function() _onLegalAcceptanceRequired;
  final void Function(ConversationRealtimeEvent event, String? currentUserId)?
  _onChannelMembershipEvent;
  final ConversationRealtimeReducer _reducer;

  StreamSubscription<ConversationRealtimeEvent>? _realtimeSubscription;
  StreamSubscription<MessageOutboxDispatchUpdate>? _outboxSubscription;
  StreamSubscription<String>? _workspaceResetSubscription;
  Timer? _typingStopTimer;

  /// Đoạn chữ của tin chạy dần chưa ghép được (đang tải lại tin / chờ đoạn trước).
  final Map<String, List<MessageStreamDelta>> _streamBuffers = {};
  final Set<String> _streamReloads = {};
  final Map<String, int> _streamReloadAttempts = {};
  static const _maxStreamReloads = 3;

  Future<void> load() async {
    // Subscribe before fetching history so a message committed while the
    // request is in flight cannot fall into the gap between GET and WebSocket.
    _subscribeRealtime();
    _subscribeOutboxAndResets();
    final sync = _activeSync;
    if (sync != null) {
      await _loadFromDevice(sync);
      return;
    }
    await _loadFromServerPage();
  }

  /// Dịch vụ đồng bộ khi dùng được (có, và máy chủ không báo "không hỗ trợ"
  /// cho cuộc trò chuyện này).
  MessageSyncService? get _activeSync {
    final sync = _syncService;
    if (sync == null ||
        sync.isUnsupported(
          workspaceId: state.scope.workspaceId,
          channelId: state.scope.channelId,
        )) {
      return null;
    }
    return sync;
  }

  /// Mở cuộc trò chuyện khi lưu tin trên máy: hiện ngay tin đã lưu (không
  /// màn "đang tải" nếu đã có), rồi hỏi máy chủ phần thay đổi, rồi tải trước
  /// tin cũ ở nền. Không có mạng thì giữ tin trên máy và chỉ báo nhẹ.
  Future<void> _loadFromDevice(MessageSyncService sync) async {
    final workspaceId = state.scope.workspaceId;
    final channelId = state.scope.channelId;
    state = state.copyWith(clearError: true, clearNotice: true);
    final draftFuture = _readDraftUseCase.execute(
      workspaceId: workspaceId,
      channelId: channelId,
    );
    final outboxFuture = _loadMessageOutboxUseCase.execute(
      workspaceId: workspaceId,
      channelId: channelId,
    );
    final currentUserIdFuture = resolveChatRoomUserId(
      known: state.currentUserId,
      fromToken: _resolveCurrentUserId,
      fromProfile: () async =>
          (await _loadProfileUseCase.execute()).valueOrNull?.id,
    );
    if (state.messages.isEmpty) {
      final local = await sync.readLatest(
        workspaceId: workspaceId,
        channelId: channelId,
        limit: _pageSize,
      );
      if (!mounted) return;
      if (local.messages.isNotEmpty && state.messages.isEmpty) {
        final shown = _withOwnership(local.messages, state.currentUserId);
        _olderAnchor = shown.first;
        state = state.copyWith(
          messages: _mergeChronological(shown, const []),
          hasMore: local.hasMore,
          isLoading: false,
        );
      } else {
        state = state.copyWith(isLoading: state.messages.isEmpty);
      }
    }
    final draft = await draftFuture;
    final outboxItems = await outboxFuture;
    final currentUserId = await currentUserIdFuture;
    if (!mounted) return;
    final pendingMessages = outboxItems
        .map((item) => _optimisticMessage(item, currentUserId))
        .toList(growable: false);
    state = state.copyWith(
      messages: _mergeChronological(
        _withOwnership(state.messages, currentUserId),
        pendingMessages,
      ),
      draft: draft,
      outboxItems: outboxItems,
      currentUserId: currentUserId,
    );

    final result = await sync.sync(
      workspaceId: workspaceId,
      channelId: channelId,
    );
    if (!mounted) return;
    switch (result.status) {
      case MessageSyncStatus.unsupported:
        // Máy chủ cũ: đúng cách tải trang tin như trước.
        await _loadFromServerPage();
        return;
      case MessageSyncStatus.failed:
        await _applySyncResult(sync, result);
        if (!mounted) return;
        if (state.messages.every((message) => message.isLocalOptimistic)) {
          // Chưa có tin nào trên máy: dùng cách cũ (bộ đệm trang tin, báo lỗi).
          await _loadFromServerPage();
          return;
        }
        state = state.copyWith(
          isLoading: false,
          syncNotice: tr(
            'Chưa kết nối được máy chủ, đang hiện tin đã lưu trên máy.',
            "Can't reach the server. Showing messages saved on this device.",
          ),
        );
        if (_canCreateUserContent()) {
          unawaited(retryOutbox(auto: true));
        }
      case MessageSyncStatus.synced:
        await _applySyncResult(sync, result);
        if (!mounted) return;
        state = state.copyWith(
          isLoading: false,
          clearError: true,
          clearSyncNotice: true,
        );
        unawaited(_hydrateMissingAttachments(state.messages));
        await _markLatestRead();
        if (_canCreateUserContent()) {
          unawaited(retryOutbox(auto: true));
        }
        unawaited(
          sync.prefetchHistory(workspaceId: workspaceId, channelId: channelId),
        );
    }
  }

  /// Áp kết quả đồng bộ vào danh sách đang hiện: dựng lại từ đầu thì đọc lại
  /// tin mới nhất trên máy; không thì áp từng thay đổi (bia mộ → tin đã thu
  /// hồi, xoá lịch sử → bỏ tin cũ, tin mới / đã sửa → ghi đè). Tin mới cũ hơn
  /// đoạn đang hiện thì không chèn (để cuộn lên tải tiếp, không tạo lỗ).
  Future<void> _applySyncResult(
    MessageSyncService sync,
    MessageSyncResult result,
  ) async {
    final currentUserId = state.currentUserId;
    if (result.reset) {
      final window = await sync.readLatest(
        workspaceId: state.scope.workspaceId,
        channelId: state.scope.channelId,
        limit: _pageSize,
      );
      if (!mounted) return;
      final latest = _withOwnership(window.messages, currentUserId);
      _forgetNewlyDeletedAttachments(result.deleted);
      _olderAnchor = latest.isEmpty ? null : latest.first;
      state = state.copyWith(
        messages: _mergeChronological(latest, [
          for (final message in state.messages)
            if (message.isLocalOptimistic) message,
        ]),
        hasMore: window.hasMore,
      );
      return;
    }
    if (result.deleted.isEmpty &&
        result.upserted.isEmpty &&
        result.clearedAt == null) {
      return;
    }
    _forgetNewlyDeletedAttachments(result.deleted);
    var messages = state.messages;
    final clearedAt = result.clearedAt;
    if (clearedAt != null) {
      messages = [
        for (final message in messages)
          if (message.isLocalOptimistic || message.createdAt.isAfter(clearedAt))
            message,
      ];
      final anchor = _olderAnchor;
      if (anchor != null && !anchor.createdAt.isAfter(clearedAt)) {
        _olderAnchor = _oldestServerMessage(messages);
      }
    }
    final known = {for (final message in messages) message.id};
    for (final tombstone in result.deleted) {
      if (!known.contains(tombstone.id)) continue;
      messages = _upsertLocal(messages, _owned(tombstone, currentUserId));
    }
    final anchor = _olderAnchor ?? _oldestServerMessage(messages);
    for (final incoming in result.upserted) {
      final visible =
          known.contains(incoming.id) ||
          anchor == null ||
          !incoming.createdAt.isBefore(anchor.createdAt);
      if (!visible) continue;
      messages = _upsertLocal(messages, _owned(incoming, currentUserId));
    }
    _olderAnchor ??= _oldestServerMessage(messages);
    state = state.copyWith(messages: messages);
  }

  /// Ghi các tin (bản đang hiện) vào máy sau khi realtime / gửi / sửa / thả
  /// cảm xúc thành công. Tin đã xoá thì xoá khỏi máy.
  void _persistMessages(Iterable<String> messageIds) {
    final sync = _syncService;
    if (sync == null) return;
    final messages = <ChatMessage>[];
    for (final id in messageIds) {
      final message = _messageById(id);
      if (message != null && !message.isLocalOptimistic) messages.add(message);
    }
    if (messages.isEmpty) return;
    unawaited(
      sync.recordMessages(
        workspaceId: state.scope.workspaceId,
        channelId: state.scope.channelId,
        messages: messages,
      ),
    );
  }

  void _forgetStoredMessage(String messageId) {
    final sync = _syncService;
    if (sync == null || messageId.isEmpty) return;
    unawaited(
      sync.forgetMessages(
        workspaceId: state.scope.workspaceId,
        channelId: state.scope.channelId,
        messageIds: [messageId],
      ),
    );
  }

  /// Tải trang tin mới nhất từ máy chủ (cách cũ, cũng dùng cho máy chủ chưa
  /// có luồng thay đổi).
  Future<void> _loadFromServerPage() async {
    // Tải lại khi đã có tin (quay lại app, cuộc gọi kết thúc): làm ngầm, không
    // thay danh sách bằng màn "đang tải" và không mất vị trí đang đọc.
    state = state.copyWith(
      isLoading: state.messages.isEmpty,
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
    // Mở phòng, nối lại, đồng bộ đều gọi lại hàm này: đã biết mình là ai thì
    // dùng lại, không tải lại hồ sơ (`/users/me`) mỗi lần.
    final currentUserIdFuture = resolveChatRoomUserId(
      known: state.currentUserId,
      fromToken: _resolveCurrentUserId,
      fromProfile: () async =>
          (await _loadProfileUseCase.execute()).valueOrNull?.id,
    );
    final result = await _loadMessagesUseCase.execute(
      workspaceId: state.scope.workspaceId,
      channelId: state.scope.channelId,
    );
    final draft = await draftFuture;
    final outboxItems = await outboxFuture;
    final currentUserId = await currentUserIdFuture;
    final pendingMessages = outboxItems
        .map((item) => _optimisticMessage(item, currentUserId))
        .toList(growable: false);
    switch (result) {
      case Success<MessagePage>(value: final page):
        final loaded = _chronological(page.messages, currentUserId);
        _forgetNewlyDeletedAttachments(loaded, userId: currentUserId);
        final messages = _mergeChronological(loaded, [
          ...state.messages,
          ...pendingMessages,
        ]);
        state = state.copyWith(
          messages: messages,
          draft: draft,
          outboxItems: outboxItems,
          currentUserId: currentUserId,
          nextCursor: page.nextCursor,
          hasMore: page.hasMore,
          isLoading: false,
          clearError: true,
          clearSyncNotice: true,
        );
        unawaited(_hydrateMissingAttachments(messages));
        await _markLatestRead();
        if (_canCreateUserContent()) {
          unawaited(retryOutbox(auto: true));
        }
      case FailureResult<MessagePage>(failure: final failure):
        state = state.copyWith(
          messages: _mergeChronological(state.messages, pendingMessages),
          draft: draft,
          outboxItems: outboxItems,
          currentUserId: currentUserId,
          isLoading: false,
          errorMessage: failure.message,
        );
        if (_canCreateUserContent()) {
          unawaited(retryOutbox(auto: true));
        }
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
    final sync = _activeSync;
    if (sync != null) {
      await _loadOlderFromDevice(sync);
      return;
    }
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
        _forgetNewlyDeletedAttachments(olderMessages);
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

  /// Tin cũ hơn: đọc trên máy trước, hết đoạn đã lưu mới hỏi máy chủ (dịch vụ
  /// đồng bộ ghi trang đó vào máy và nối dài đoạn đã lưu).
  Future<void> _loadOlderFromDevice(MessageSyncService sync) async {
    if (!state.hasMore || state.isLoadingOlder) return;
    final anchor = _olderAnchor ?? _oldestServerMessage(state.messages);
    if (anchor == null) {
      state = state.copyWith(hasMore: false);
      return;
    }
    state = state.copyWith(isLoadingOlder: true, clearError: true);
    final result = await sync.loadOlder(
      workspaceId: state.scope.workspaceId,
      channelId: state.scope.channelId,
      beforeCreatedAt: anchor.createdAt,
      beforeId: anchor.id,
      limit: _pageSize,
    );
    if (!mounted) return;
    switch (result) {
      case Success<MessageWindow>(value: final window):
        final older = _chronological(window.messages, state.currentUserId);
        _forgetNewlyDeletedAttachments(older);
        if (older.isNotEmpty) _olderAnchor = older.first;
        state = state.copyWith(
          messages: _mergeChronological(older, state.messages),
          hasMore: window.hasMore,
          isLoadingOlder: false,
        );
        unawaited(_hydrateMissingAttachments(older));
      case FailureResult<MessageWindow>(failure: final failure):
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

  Future<void> sendCurrentDraft({bool silent = false}) async {
    final body = state.draft.trim();
    final attachmentsReady = state.pendingAttachments.any(
      (item) =>
          item.status == MessageAttachmentUploadStatus.uploaded ||
          item.status == MessageAttachmentUploadStatus.uploading ||
          item.status == MessageAttachmentUploadStatus.queued,
    );
    if ((body.isEmpty && !attachmentsReady) || state.isSending) {
      return;
    }
    if (!_guardUserContentMutation()) return;
    final attachmentFallback = _attachmentMessageFallback(
      state.pendingAttachments,
    );
    final voice = _uploadedVoiceMetadata(state.pendingAttachments);
    final pendingUploads = pendingOutboxUploads(state.pendingAttachments);
    final clientMessageId = _newClientMessageIdUseCase.execute();
    state = state.copyWith(isSending: true, clearError: true);
    final editing = state.editingMessage;
    if (editing == null) {
      final item = await _enqueueMessageOutboxUseCase.execute(
        workspaceId: state.scope.workspaceId,
        channelId: state.scope.channelId,
        clientMessageId: clientMessageId,
        body: body.isEmpty ? attachmentFallback : body,
        parentId: state.replyToMessage?.id,
        attachments: uploadedOutboxAttachments(state.pendingAttachments),
        pendingUploads: pendingUploads,
        silent: silent,
        metadata: voice == null ? const {} : {'voice': voice.toJson()},
      );
      if (mounted) {
        state = state.copyWith(
          messages: _upsertLocal(
            state.messages,
            _optimisticMessage(item, state.currentUserId),
          ),
          outboxItems: [...state.outboxItems, item],
          pendingAttachments: const [],
          draft: '',
          clearReply: true,
          clearEditing: true,
        );
      }
      await _clearDraftUseCase.execute(
        workspaceId: item.workspaceId,
        channelId: item.channelId,
      );
      await _dispatchOutbox(auto: false, focusItemId: item.id);
      if (mounted) {
        state = state.copyWith(isSending: false);
      }
      return;
    }

    final result = await _editMessageUseCase.execute(
      workspaceId: state.scope.workspaceId,
      channelId: state.scope.channelId,
      messageId: editing.id,
      body: body,
    );
    if (!mounted) {
      return;
    }
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
        _persistMessages([prepared.id]);
        await _clearDraftUseCase.execute(
          workspaceId: state.scope.workspaceId,
          channelId: state.scope.channelId,
        );
        await _markLatestRead();
      case FailureResult<ChatMessage>(failure: final failure):
        state = state.copyWith(isSending: false, errorMessage: failure.message);
        await persistDraft();
    }
  }

  /// Gửi lại tin chờ của phòng này qua bộ gửi lại chung của app (đúng thứ tự
  /// tạo, không gửi trùng khi màn chính cũng đang gửi lại).
  Future<void> retryOutbox({bool auto = false}) async {
    if (!_guardUserContentMutation(notify: !auto)) return;
    await _dispatchOutbox(auto: auto);
  }

  /// Nút `reply` của thẻ bot: gửi chữ của nút như tin người dùng vào cùng
  /// kênh (qua hàng chờ gửi như tin thường), không đụng bản nháp đang gõ.
  Future<void> sendCardReply(String text) async {
    final body = text.trim();
    if (body.isEmpty) return;
    if (!_guardUserContentMutation()) return;
    final item = await _enqueueMessageOutboxUseCase.execute(
      workspaceId: state.scope.workspaceId,
      channelId: state.scope.channelId,
      clientMessageId: _newClientMessageIdUseCase.execute(),
      body: body,
    );
    if (!mounted) return;
    state = state.copyWith(
      messages: _upsertLocal(
        state.messages,
        _optimisticMessage(item, state.currentUserId),
      ),
      outboxItems: _upsertOutboxItem(item),
    );
    await _dispatchOutbox(auto: false, focusItemId: item.id);
  }

  Future<void> _dispatchOutbox({
    required bool auto,
    String? focusItemId,
  }) async {
    final result = await _outboxDispatcher.drainChannel(
      workspaceId: state.scope.workspaceId,
      channelId: state.scope.channelId,
    );
    if (!mounted || auto) return;
    final failure =
        (focusItemId == null ? null : result.updates[focusItemId]) ??
        result.firstFailure;
    if (failure != null && failure.isFailed && failure.error != null) {
      state = state.copyWith(errorMessage: failure.error);
    }
  }

  void _subscribeOutboxAndResets() {
    _outboxSubscription ??= _outboxDispatcher.updates
        .where(
          (update) =>
              update.item.workspaceId == state.scope.workspaceId &&
              update.item.channelId == state.scope.channelId,
        )
        .listen(_applyOutboxUpdate);
    _workspaceResetSubscription ??= _workspaceResets?.listen((_) {
      // Đồng bộ bù bị đặt lại: tải lại tin mới nhất (giữ bản nháp).
      unawaited(_catchUpAfterReconnect());
    });
  }

  /// Cập nhật trạng thái tin chờ khi bộ gửi lại (của phòng này hay của toàn
  /// app) đổi trạng thái tin.
  void _applyOutboxUpdate(MessageOutboxDispatchUpdate update) {
    if (!mounted) return;
    final item = update.item;
    final message = update.message?.copyWith(
      isMine: update.message?.senderId == state.currentUserId,
    );
    switch (update.phase) {
      case MessageOutboxDispatchPhase.sent:
        state = state.copyWith(
          messages: message == null
              ? state.messages
              : _upsertLocal(state.messages, message),
          outboxItems: _removeOutboxItem(item.id),
          clearError: true,
        );
        if (message != null) _persistMessages([message.id]);
        unawaited(_markLatestRead());
      case MessageOutboxDispatchPhase.failed when message != null:
        state = state.copyWith(
          messages: _setOptimisticDeliveryStatus(
            _upsertLocal(state.messages, message),
            item.clientMessageId,
            MessageOutboxStatus.failed,
          ),
          outboxItems: _upsertOutboxItem(item),
        );
      case MessageOutboxDispatchPhase.uploading:
        state = state.copyWith(
          messages: _upsertLocal(
            state.messages,
            _optimisticMessage(
              item,
              state.currentUserId,
              uploadProgress: update.progress,
              uploadStage: _uploadStageOf(item),
            ),
          ),
          outboxItems: _upsertOutboxItem(item),
        );
      case MessageOutboxDispatchPhase.sending ||
          MessageOutboxDispatchPhase.queued ||
          MessageOutboxDispatchPhase.failed:
        state = state.copyWith(
          messages: _upsertLocal(
            state.messages,
            _optimisticMessage(item, state.currentUserId),
          ),
          outboxItems: _upsertOutboxItem(item),
        );
    }
  }

  /// 'compressing' nếu có tệp của tin còn đang nén, ngược lại 'uploading'.
  String _uploadStageOf(MessageOutboxItem item) {
    for (final upload in item.pendingUploads) {
      final progress = _messageMediaUploader.progressOf(
        upload.clientAttachmentId,
      );
      if (progress?.stage == MessageMediaUploadStage.compressing) {
        return 'compressing';
      }
    }
    return 'uploading';
  }

  List<MessageOutboxItem> _upsertOutboxItem(MessageOutboxItem item) {
    final exists = state.outboxItems.any((entry) => entry.id == item.id);
    if (!exists) {
      return [...state.outboxItems, item];
    }
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
        final previous = _messageById(message.id)?.attachments;
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
        _forgetMessageAttachments(message.id, [
          ...?previous,
          ...message.attachments,
        ]);
        _forgetStoredMessage(message.id);
      case FailureResult<void>(failure: final failure):
        state = state.copyWith(errorMessage: failure.message);
    }
  }

  Future<void> toggleReaction(ChatMessage message, String emoji) async {
    if (!_guardUserContentMutation()) return;
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
    if (!_guardUserContentMutation()) return;
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
        _persistMessages([message.id]);
      case FailureResult<ChatMessage?>(failure: final failure):
        state = state.copyWith(errorMessage: failure.message);
    }
  }

  Future<void> forwardMessage(
    ChatMessage message,
    String targetChannelId,
  ) async {
    if (!_guardUserContentMutation()) return;
    final result = await _forwardMessageUseCase.execute(
      workspaceId: state.scope.workspaceId,
      channelId: state.scope.channelId,
      messageId: message.id,
      targetChannelId: targetChannelId,
    );
    switch (result) {
      case Success<ChatMessage>():
        state = state.copyWith(
          noticeMessage: tr('Đã chuyển tiếp tin nhắn.', 'Message forwarded.'),
        );
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
    if (!_guardUserContentMutation()) return;
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
        _persistMessages([prepared.id]);
        await _markLatestRead();
      case FailureResult<ChatMessage>(failure: final failure):
        state = state.copyWith(
          isSendingThread: false,
          errorMessage: failure.message,
        );
    }
  }

  Future<void> pickAttachment(MessageAttachmentPickSource source) async {
    if (!_guardUserContentMutation()) return;
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

  Future<void> queuePickedAttachment(PickedMessageAttachment picked) {
    return _queueAttachment(picked);
  }

  Future<void> startVoiceRecording() async {
    if (state.isRecordingVoice || state.isSending) {
      return;
    }
    if (!_guardUserContentMutation()) return;
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
        if (picked != null && _guardUserContentMutation()) {
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
    if (!_guardUserContentMutation()) return;
    final item = _newAttachmentUploadItemUseCase.execute(picked);
    state = state.copyWith(
      pendingAttachments: [...state.pendingAttachments, item],
      clearError: true,
    );
    await _uploadAttachment(item.clientAttachmentId);
  }

  Future<void> retryAttachment(String clientAttachmentId) {
    if (!_guardUserContentMutation()) return Future<void>.value();
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
    if (!_guardUserContentMutation()) return;
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
    final result = await _messageMediaUploader.upload(
      workspaceId: state.scope.workspaceId,
      clientAttachmentId: clientAttachmentId,
      attachment: picked,
      onProgress: (progress) {
        if (!mounted) return;
        // Ô đã gỡ / đã chuyển vào tin chờ thì bỏ qua tiến độ.
        final current = _attachmentItemById(
          state.pendingAttachments,
          clientAttachmentId,
        );
        if (current == null ||
            current.status != MessageAttachmentUploadStatus.uploading) {
          return;
        }
        state = state.copyWith(
          pendingAttachments: _replaceAttachmentItem(
            state.pendingAttachments,
            current.copyWith(
              progress: progress.progress.clamp(0, 1),
              compressing:
                  progress.stage == MessageMediaUploadStage.compressing,
            ),
          ),
        );
      },
    );
    if (!mounted) return;
    // Ô đã bị gỡ hoặc đã chuyển vào tin chờ (bộ gửi tin chờ lo tiếp).
    if (_attachmentItemById(state.pendingAttachments, clientAttachmentId) ==
        null) {
      return;
    }
    switch (result) {
      case Success<UploadedMessageFile>(value: final file):
        state = state.copyWith(
          pendingAttachments: _replaceAttachmentItem(
            state.pendingAttachments,
            item.copyWith(
              status: MessageAttachmentUploadStatus.uploaded,
              uploadedFile: file,
              progress: 1,
              compressing: false,
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
              compressing: false,
              errorMessage: failure.message,
            ),
          ),
          errorMessage: failure.message,
        );
    }
  }

  /// Tải lại thấy tin đã bị xoá (trước đó còn hiện, hoặc còn trong bộ nhớ tệp
  /// đính kèm): xoá tệp đã lưu trên máy của tin đó. Gọi trước khi thay state.
  void _forgetNewlyDeletedAttachments(
    List<ChatMessage> incoming, {
    String? userId,
  }) {
    for (final message in incoming) {
      if (!message.isDeleted) continue;
      final previous = _messageById(message.id);
      if (previous != null &&
          previous.isDeleted &&
          previous.attachments.isEmpty) {
        // Đã xử lý ở lần trước.
        continue;
      }
      _forgetMessageAttachments(message.id, [
        ...?previous?.attachments,
        ...message.attachments,
      ], userId: userId);
    }
  }

  /// Bỏ mục nhớ tệp của tin [messageId] và xoá tệp kho của mọi tệp đã biết
  /// ([known] + bộ nhớ tệp đính kèm). Lỗi xoá chỉ bỏ qua (kho tự dọn sau).
  void _forgetMessageAttachments(
    String messageId,
    List<MessageAttachment> known, {
    String? userId,
  }) {
    final remembered = _attachmentMemo?.remove(
      MessageAttachmentMemo.keyFor(
        userId: userId ?? state.currentUserId,
        workspaceId: state.scope.workspaceId,
        channelId: state.scope.channelId,
        messageId: messageId,
      ),
    );
    final byId = <String, MessageAttachment>{
      for (final attachment in [...known, ...?remembered])
        '${attachment.id}|${attachment.fileId}': attachment,
    };
    final evict = _evictCachedAttachments;
    if (byId.isEmpty || evict == null) return;
    unawaited(
      evict(byId.values.toList(growable: false)).catchError((Object _) {}),
    );
  }

  Future<void> _hydrateMissingAttachments(List<ChatMessage> messages) async {
    // Máy chủ đã gửi kèm tệp trong danh sách tin: nhớ lại để tin bị thu hồi
    // sau này (kể cả khi mở lại phòng) vẫn biết tệp nào cần xoá khỏi máy.
    for (final message in messages) {
      if (message.attachmentsIncluded &&
          message.attachments.isNotEmpty &&
          !message.isDeleted) {
        _attachmentMemo?.write(
          MessageAttachmentMemo.keyFor(
            userId: state.currentUserId,
            workspaceId: message.workspaceId,
            channelId: message.channelId,
            messageId: message.id,
          ),
          message.attachments,
        );
      }
    }
    final targets = messages
        .where(shouldHydrateMessageAttachments)
        .toList(growable: false);
    if (targets.isEmpty) {
      return;
    }

    // Tin đã hỏi trước đó (kể cả ở lần mở phòng trước): gắn lại ngay, không
    // hỏi lại máy chủ; chỉ hỏi các tin chưa biết.
    final hydrator = MessageAttachmentHydrator(
      memo: _attachmentMemo,
      fetch: (message) async {
        final result = await _listMessageAttachmentsUseCase.execute(
          workspaceId: message.workspaceId,
          channelId: message.channelId,
          messageId: message.id,
        );
        return result.valueOrNull;
      },
    );
    await for (final batch in hydrator.hydrate(
      targets,
      userId: state.currentUserId,
      isActive: () => mounted,
    )) {
      if (!mounted) {
        return;
      }
      _applyHydratedAttachments(batch);
    }
  }

  /// Gắn tệp đã biết vào các tin còn thiếu tệp (không đè tệp đang có).
  void _applyHydratedAttachments(
    Map<String, List<MessageAttachment>> attachmentsByMessageId,
  ) {
    state = state.copyWith(
      messages: state.messages
          .map((item) {
            final attachments = attachmentsByMessageId[item.id];
            return attachments != null && item.attachments.isEmpty
                ? item.copyWith(attachments: attachments)
                : item;
          })
          .toList(growable: false),
    );
  }

  /// Tìm trong cuộc trò chuyện. Lưu tin trên máy: tìm trong tin đã lưu trước
  /// (hiện ngay, không cần mạng), người dùng bấm "Tìm thêm trên máy chủ" thì
  /// gọi [searchOnServer]. Máy chủ cũ: tìm trên máy chủ như trước.
  Future<void> search(String query) async {
    final normalized = query.trim();
    if (normalized.isEmpty) {
      state = state.copyWith(clearSearch: true);
      return;
    }
    final sync = _activeSync;
    if (sync != null) {
      state = state.copyWith(
        searchQuery: normalized,
        searchResults: const [],
        isSearching: true,
        searchSource: MessageSearchSource.device,
        isSearchingServer: false,
        clearSearchServerError: true,
        clearError: true,
      );
      final local = await sync.searchLocal(
        workspaceId: state.scope.workspaceId,
        channelId: state.scope.channelId,
        query: normalized,
      );
      if (!mounted || state.searchQuery != normalized) return;
      state = state.copyWith(
        searchResults: _chronological(local, state.currentUserId),
        isSearching: false,
      );
      return;
    }
    state = state.copyWith(
      searchQuery: normalized,
      isSearching: true,
      searchSource: MessageSearchSource.server,
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

  /// Tìm thêm trên máy chủ (tin chưa lưu trên máy, cũ hơn đoạn đã lưu) rồi gộp
  /// với kết quả trên máy (bỏ trùng theo mã tin). Lỗi thì giữ kết quả trên máy.
  Future<void> searchOnServer() async {
    final query = state.searchQuery;
    if (query.isEmpty || state.isSearchingServer) return;
    state = state.copyWith(
      isSearchingServer: true,
      clearSearchServerError: true,
    );
    final result = await _searchMessagesUseCase.execute(
      MessageSearchCommand(
        workspaceId: state.scope.workspaceId,
        channelId: state.scope.channelId,
        query: query,
      ),
    );
    if (!mounted || state.searchQuery != query) return;
    switch (result) {
      case Success<MessagePage>(value: final page):
        final byId = <String, ChatMessage>{
          for (final message in state.searchResults) message.id: message,
          for (final message in page.messages) message.id: message,
        };
        state = state.copyWith(
          searchResults: _chronological(
            byId.values.toList(growable: false),
            state.currentUserId,
          ),
          searchSource: MessageSearchSource.deviceAndServer,
          isSearchingServer: false,
        );
      case FailureResult<MessagePage>(failure: final failure):
        state = state.copyWith(
          isSearchingServer: false,
          searchServerError: failure.message,
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
    if (!_guardUserContentMutation()) return null;
    if (state.isStartingCall) {
      return null;
    }
    final normalizedTargetUserId = targetUserId.trim();
    final currentUserId = state.currentUserId?.trim();
    if (normalizedTargetUserId.isEmpty) {
      state = state.copyWith(
        errorMessage: tr('Chưa có người nhận cuộc gọi.', 'No call recipient.'),
        clearNotice: true,
      );
      return null;
    }
    if (currentUserId != null &&
        currentUserId.isNotEmpty &&
        normalizedTargetUserId == currentUserId) {
      state = state.copyWith(
        errorMessage: tr(
          'Không thể tự gọi chính mình.',
          'You can\'t call yourself.',
        ),
        clearNotice: true,
      );
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
      targetUserId: normalizedTargetUserId,
      mode: mode,
    );
    switch (result) {
      case Success<CallSession>(value: final call):
        state = state.copyWith(
          activeCall: call,
          isStartingCall: false,
          noticeMessage: mode == CallMode.video
              ? tr('Đang bắt đầu cuộc gọi video.', 'Starting video call…')
              : tr('Đang bắt đầu cuộc gọi thoại.', 'Starting voice call…'),
          clearError: true,
        );
        return call;
      case FailureResult<CallSession>(failure: final failure):
        // 409 bận: không mở màn gọi, chỉ báo đúng câu.
        state = state.copyWith(
          isStartingCall: false,
          errorMessage: startCallFailureMessage(failure),
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

  bool _guardUserContentMutation({bool notify = true}) {
    if (_canCreateUserContent()) return true;
    if (notify) {
      _onLegalAcceptanceRequired();
      if (mounted) {
        state = state.copyWith(
          errorMessage: tr(
            'Bạn cần đồng ý Điều khoản và Chính sách quyền riêng tư trước khi tạo nội dung.',
            'You need to accept the Terms and Privacy Policy before creating content.',
          ),
        );
      }
    }
    return false;
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
        _persistMessages([message.id]);
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

  /// Sau khi nối lại realtime: lấy trang tin mới nhất (tin gửi trong lúc mất
  /// kết nối không được đẩy lại). Giữ bản nháp đang gõ; lỗi mạng thì bỏ qua.
  Future<void> _catchUpAfterReconnect() async {
    unawaited(_refreshOpenThread());
    final sync = _activeSync;
    if (sync != null) {
      // Lưu tin trên máy: chỉ hỏi phần thay đổi từ mốc đã lưu.
      final synced = await sync.sync(
        workspaceId: state.scope.workspaceId,
        channelId: state.scope.channelId,
      );
      if (!mounted) return;
      if (!synced.isUnsupported) {
        await _applySyncResult(sync, synced);
        if (!mounted) return;
        if (synced.isSynced) {
          state = state.copyWith(clearSyncNotice: true);
          unawaited(_hydrateMissingAttachments(state.messages));
          unawaited(_markLatestRead());
        }
        return;
      }
    }
    final result = await _loadMessagesUseCase.execute(
      workspaceId: state.scope.workspaceId,
      channelId: state.scope.channelId,
    );
    if (!mounted) return;
    if (result case Success<MessagePage>(value: final page)) {
      final latest = _chronological(page.messages, state.currentUserId);
      _forgetNewlyDeletedAttachments(latest);
      final knownIds = {for (final message in state.messages) message.id};
      // Mất kết nối lâu (trang mới nhất không nối tiếp tin đang có): bỏ tin cũ
      // để không có khoảng trống giữa hai đoạn, cuộn lên sẽ tải tiếp.
      final hasGap =
          page.hasMore && !latest.any((m) => knownIds.contains(m.id));
      final local = hasGap
          ? state.messages.where((m) => m.isLocalOptimistic).toList()
          : state.messages;
      final messages = _mergeChronological(latest, local);
      state = state.copyWith(
        messages: messages,
        nextCursor: hasGap ? page.nextCursor : state.nextCursor,
        hasMore: hasGap ? page.hasMore : state.hasMore,
      );
      unawaited(_hydrateMissingAttachments(messages));
      unawaited(_markLatestRead());
    }
  }

  List<ChatMessage>? _reduceThread(ConversationRealtimeEvent event) {
    final root = state.threadRootMessage;
    if (root == null) return null;
    return _reducer.reduceThread(
      rootId: root.id,
      messages: state.threadMessages,
      event: event,
      currentUserId: state.currentUserId,
    );
  }

  /// Tải lại trả lời của thread đang mở (giữ bản nháp đang gõ).
  Future<void> _refreshOpenThread() async {
    final root = state.threadRootMessage;
    if (root == null) return;
    final result = await _loadThreadUseCase.execute(
      workspaceId: state.scope.workspaceId,
      channelId: state.scope.channelId,
      messageId: root.id,
    );
    if (!mounted || state.threadRootMessage?.id != root.id) return;
    if (result case Success<MessagePage>(value: final page)) {
      state = state.copyWith(
        threadMessages: _chronological(page.messages, state.currentUserId),
      );
    }
  }

  void _handleRealtimeEvent(ConversationRealtimeEvent event) {
    if (event.type == ConversationRealtimeEventType.channelMemberLeft ||
        event.type == ConversationRealtimeEventType.channelArchived) {
      _onChannelMembershipEvent?.call(event, state.currentUserId);
      return;
    }
    if (event.type == ConversationRealtimeEventType.reconnected) {
      unawaited(_catchUpAfterReconnect());
      return;
    }
    if (event.type == ConversationRealtimeEventType.messageDelta) {
      final delta = event.delta;
      if (delta != null) _handleMessageDelta(delta);
      return;
    }
    if (_isStaleStreamingCopy(event)) return;
    if (event.type == ConversationRealtimeEventType.messageUpdated ||
        event.type == ConversationRealtimeEventType.messageDeleted) {
      // Bản cuối (hoặc tin bị xoá) thay toàn bộ: bỏ các đoạn còn chờ.
      final messageId = event.messageId ?? event.message?.id;
      if (messageId != null) _forgetStream(messageId);
    }
    if (event.type == ConversationRealtimeEventType.messageDeleted) {
      // Thu hồi / xoá / hết hạn (`MessageExpired`): lấy tệp của tin trước khi
      // tin bị thay, xoá luôn ảnh / tệp đã lưu trên máy (như Zalo).
      final messageId = event.messageId ?? event.message?.id;
      if (messageId != null && messageId.isNotEmpty) {
        _forgetMessageAttachments(messageId, [
          ...?_messageById(messageId)?.attachments,
          for (final message in state.threadMessages)
            if (message.id == messageId) ...message.attachments,
          ...?event.message?.attachments,
        ]);
      }
    } else if (event.message case final incoming?
        when incoming.isDeleted &&
            event.type == ConversationRealtimeEventType.messageUpdated) {
      // Máy chủ báo tin đã bị xoá qua bản cập nhật.
      _forgetNewlyDeletedAttachments([incoming]);
    }
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
      threadMessages: _reduceThread(event),
    );
    _persistRealtimeEvent(event);
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

  /// Tin mới / sửa / cảm xúc / ghim / xoá qua realtime: ghi (hoặc xoá) bản
  /// đang hiện vào máy để mở lại không phải hỏi máy chủ.
  void _persistRealtimeEvent(ConversationRealtimeEvent event) {
    final sync = _syncService;
    if (sync == null) return;
    final messageId = event.messageId ?? event.message?.id;
    if (messageId == null || messageId.isEmpty) return;
    switch (event.type) {
      case ConversationRealtimeEventType.messageDeleted:
        _forgetStoredMessage(messageId);
      case ConversationRealtimeEventType.messageCreated ||
          ConversationRealtimeEventType.messageUpdated ||
          ConversationRealtimeEventType.reactionChanged ||
          ConversationRealtimeEventType.messagePinned ||
          ConversationRealtimeEventType.messageUnpinned:
        final current = _messageById(messageId);
        if (current == null) {
          // Tin không có trong danh sách đang hiện (vd. ngoài đoạn đã tải):
          // ghi thẳng bản máy chủ gửi kèm nếu có.
          final incoming = event.message;
          if (incoming != null) {
            unawaited(
              sync.recordMessages(
                workspaceId: state.scope.workspaceId,
                channelId: state.scope.channelId,
                messages: [_owned(incoming, state.currentUserId)],
              ),
            );
          }
          return;
        }
        _persistMessages([messageId]);
      default:
        return;
    }
  }

  /// `MessageCreated` lặp lại đến sau khi đã ghép thêm đoạn: giữ bản mới hơn.
  bool _isStaleStreamingCopy(ConversationRealtimeEvent event) {
    final incoming = event.message;
    if (event.type != ConversationRealtimeEventType.messageCreated ||
        incoming == null ||
        !incoming.isStreaming) {
      return false;
    }
    final current = _messageById(incoming.id);
    return current != null &&
        current.isStreaming &&
        (current.streamSeq ?? 0) > (incoming.streamSeq ?? 0);
  }

  void _handleMessageDelta(MessageStreamDelta delta) {
    final messageId = delta.messageId;
    final buffered = _streamBuffers[messageId] ?? const [];
    if (_streamReloads.contains(messageId)) {
      _streamBuffers[messageId] = [...buffered, delta];
      return;
    }
    final current = _messageById(messageId);
    if (current == null) {
      // Đoạn đến trước MessageCreated (hoặc tin chưa tải): giữ lại, tải tin.
      _streamBuffers[messageId] = [...buffered, delta];
      unawaited(_reloadStreamingMessage(messageId));
      return;
    }
    _applyStreamMerge(mergeMessageStreamDeltas(current, [...buffered, delta]));
  }

  void _applyStreamMerge(MessageStreamMergeResult outcome) {
    final messageId = outcome.message.id;
    if (outcome.hasGap) {
      _streamBuffers[messageId] = outcome.pending;
    } else {
      _streamBuffers.remove(messageId);
    }
    if (outcome.changed) {
      state = state.copyWith(
        messages: _replaceStreamingMessage(state.messages, outcome.message),
        threadMessages: state.threadMessages.any((m) => m.id == messageId)
            ? _replaceStreamingMessage(state.threadMessages, outcome.message)
            : null,
      );
    }
    if (outcome.hasGap) unawaited(_reloadStreamingMessage(messageId));
  }

  /// Thiếu đoạn: tải lại tin rồi chỉ ghép đoạn có `seq` lớn hơn
  /// `metadata.stream_seq` của bản vừa tải.
  Future<void> _reloadStreamingMessage(String messageId) async {
    final getMessage = _getMessageUseCase;
    final attempts = _streamReloadAttempts[messageId] ?? 0;
    if (getMessage == null ||
        attempts >= _maxStreamReloads ||
        !_streamReloads.add(messageId)) {
      return;
    }
    _streamReloadAttempts[messageId] = attempts + 1;
    final result = await getMessage.execute(
      workspaceId: state.scope.workspaceId,
      channelId: state.scope.channelId,
      messageId: messageId,
    );
    _streamReloads.remove(messageId);
    if (!mounted) return;
    final buffered = _streamBuffers.remove(messageId) ?? const [];
    final loaded = result.valueOrNull;
    if (loaded == null) return;
    final current = _messageById(messageId);
    // Bản cuối đã đến qua MessageUpdated trong lúc tải: giữ bản cuối.
    if (current != null && !current.isStreaming) return;
    final prepared = loaded.copyWith(
      isMine: loaded.senderId == state.currentUserId,
    );
    final base =
        current != null &&
            prepared.isStreaming &&
            (current.streamSeq ?? 0) > (prepared.streamSeq ?? 0)
        ? current
        : prepared;
    state = state.copyWith(messages: _upsertLocal(state.messages, base));
    // Bản dở (đang chạy dần) không được lưu; bản cuối thì ghi vào máy.
    _persistMessages([base.id]);
    final outcome = mergeMessageStreamDeltas(base, buffered);
    if (outcome.changed || outcome.hasGap) _applyStreamMerge(outcome);
    if (!base.isStreaming) _forgetStream(messageId);
  }

  void _forgetStream(String messageId) {
    _streamBuffers.remove(messageId);
    _streamReloadAttempts.remove(messageId);
  }

  ChatMessage? _messageById(String messageId) {
    for (final message in state.messages) {
      if (message.id == messageId) return message;
    }
    return null;
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
      // Máy chủ báo vừa gắn thêm tệp: ghi đè bản đã nhớ của tin này.
      _attachmentMemo?.write(
        MessageAttachmentMemo.keyFor(
          userId: state.currentUserId,
          workspaceId: state.scope.workspaceId,
          channelId: state.scope.channelId,
          messageId: messageId,
        ),
        attachments,
      );
      state = state.copyWith(
        messages: state.messages
            .map(
              (message) => message.id == messageId
                  ? message.copyWith(attachments: attachments)
                  : message,
            )
            .toList(growable: false),
      );
      _persistMessages([messageId]);
    }
  }

  Future<void> _markLatestRead() async {
    ChatMessage? latest;
    for (final message in state.messages.reversed) {
      if (!message.isLocalOptimistic) {
        latest = message;
        break;
      }
    }
    if (latest == null) {
      return;
    }
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
    _streamBuffers.clear();
    _streamReloads.clear();
    unawaited(_outboxSubscription?.cancel());
    unawaited(_workspaceResetSubscription?.cancel());
    super.dispose();
  }
}

bool _allowUserContentByDefault() => true;

void _noop() {}

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

/// Đặt `isMine` theo người dùng hiện tại; chưa biết là ai (đang đọc token) thì
/// giữ giá trị đã lưu cùng tin. Tin tạm giữ nguyên.
List<ChatMessage> _withOwnership(
  List<ChatMessage> messages,
  String? currentUserId,
) {
  return [for (final message in messages) _owned(message, currentUserId)];
}

ChatMessage _owned(ChatMessage message, String? currentUserId) {
  final userId = currentUserId?.trim();
  if (userId == null || userId.isEmpty || message.isLocalOptimistic) {
    return message;
  }
  return message.copyWith(isMine: message.senderId == userId);
}

/// Tin cũ nhất (không phải tin tạm) của danh sách xếp CŨ → MỚI.
ChatMessage? _oldestServerMessage(List<ChatMessage> messages) {
  for (final message in messages) {
    if (!message.isLocalOptimistic) return message;
  }
  return null;
}

List<ChatMessage> _mergeChronological(
  List<ChatMessage> older,
  List<ChatMessage> current,
) {
  final result = <ChatMessage>[];
  for (final message in [...older, ...current]) {
    final index = result.indexWhere((existing) {
      if (existing.id == message.id) {
        return true;
      }
      return (existing.isLocalOptimistic || message.isLocalOptimistic) &&
          message.clientMessageId.isNotEmpty &&
          existing.clientMessageId == message.clientMessageId;
    });
    if (index == -1) {
      result.add(message);
    } else if (result[index].isLocalOptimistic || !message.isLocalOptimistic) {
      result[index] = message;
    }
  }
  result.sort((left, right) => left.createdAt.compareTo(right.createdAt));
  return List.unmodifiable(result);
}

ChatMessage _optimisticMessage(
  MessageOutboxItem item,
  String? currentUserId, {
  double? uploadProgress,
  String? uploadStage,
}) {
  final localMessageId = 'local-${item.clientMessageId}';
  final uploading = item.hasPendingUploads;
  return ChatMessage(
    id: localMessageId,
    workspaceId: item.workspaceId,
    channelId: item.channelId,
    kind: item.attachments.isEmpty && !uploading ? 'text' : 'file',
    body: item.body,
    createdAt: item.createdAt,
    senderId: currentUserId?.trim().isNotEmpty == true
        ? currentUserId
        : 'local-current-user',
    parentId: item.parentId,
    metadata: {
      ...item.metadata,
      'client_message_id': item.clientMessageId,
      'delivery_status': uploading && !item.isFailed
          ? 'uploading'
          : item.status.name,
      if (uploading && !item.isFailed) ...{
        'upload_progress': uploadProgress ?? 0.0,
        'upload_stage': uploadStage ?? 'uploading',
      },
    },
    attachments: _optimisticAttachments(item, messageId: localMessageId),
    isMine: true,
  );
}

List<MessageAttachment> _optimisticAttachments(
  MessageOutboxItem item, {
  required String messageId,
}) {
  if (item.attachments.isEmpty && item.pendingUploads.isEmpty) {
    return const [];
  }
  final attachments = [
    ...item.attachments,
    for (final upload in item.pendingUploads)
      MessageOutboxAttachment(
        fileId: 'local-${upload.clientAttachmentId}',
        name: upload.fileName,
        sortOrder: upload.sortOrder,
        mimeType: upload.mimeType,
        byteSize: upload.byteSize,
        downloadPath: '',
        localPath: upload.localPath,
      ),
  ]..sort((left, right) => left.sortOrder.compareTo(right.sortOrder));
  return attachments
      .map(
        (attachment) => MessageAttachment(
          id: 'local-${item.clientMessageId}-${attachment.fileId}-${attachment.sortOrder}',
          workspaceId: item.workspaceId,
          messageId: messageId,
          fileId: attachment.fileId,
          sortOrder: attachment.sortOrder,
          createdAt: item.createdAt,
          file: UploadedMessageFile(
            id: attachment.fileId,
            name: attachment.name,
            mimeType: attachment.mimeType,
            byteSize: attachment.byteSize,
            downloadPath: attachment.downloadPath,
            createdAt: item.createdAt,
            status: 'local-preview',
            localPath: attachment.localPath,
          ),
        ),
      )
      .toList(growable: false);
}

List<ChatMessage> _setOptimisticDeliveryStatus(
  List<ChatMessage> messages,
  String clientMessageId,
  MessageOutboxStatus status,
) {
  return messages
      .map(
        (message) =>
            message.isLocalOptimistic &&
                message.clientMessageId == clientMessageId
            ? message.copyWith(
                metadata: {...message.metadata, 'delivery_status': status.name},
              )
            : message,
      )
      .toList(growable: false);
}

List<ChatMessage> _upsertLocal(
  List<ChatMessage> current,
  ChatMessage incoming,
) {
  // Kết quả reaction / ghim / sửa không kèm danh sách tệp: giữ tệp đã có.
  var merged = incoming;
  for (final message in current) {
    if (message.id == incoming.id &&
        incoming.attachments.isEmpty &&
        message.attachments.isNotEmpty &&
        !incoming.isDeleted) {
      merged = incoming.copyWith(attachments: message.attachments);
    }
  }
  return _mergeChronological(const [], [
    ...current.where((message) => message.id != incoming.id),
    merged,
  ]);
}

/// Tin này có phải hỏi riêng máy chủ danh sách tệp không (máy chủ cũ không
/// gửi kèm tệp trong danh sách tin).
@visibleForTesting
bool shouldHydrateMessageAttachments(ChatMessage message) {
  // Máy chủ đã gửi kèm danh sách tệp (kể cả rỗng): không hỏi riêng tin này.
  if (message.id.startsWith('local-') ||
      message.isDeleted ||
      message.attachmentsIncluded ||
      message.attachments.isNotEmpty) {
    return false;
  }
  // Tin có cả chữ và tệp: backend gắn metadata.has_attachments khi thêm tệp.
  if (message.kind == 'file' || message.metadata['has_attachments'] == true) {
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
      .where(
        (item) =>
            item.status == MessageAttachmentUploadStatus.uploaded ||
            item.status == MessageAttachmentUploadStatus.uploading ||
            item.status == MessageAttachmentUploadStatus.queued,
      )
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

/// Thay tin đang chạy dần bằng bản vừa ghép (giữ tệp, ghim của bản cũ).
List<ChatMessage> _replaceStreamingMessage(
  List<ChatMessage> messages,
  ChatMessage merged,
) {
  return messages
      .map(
        (message) => message.id == merged.id
            ? merged.copyWith(
                attachments: merged.attachments.isEmpty
                    ? message.attachments
                    : null,
                isPinned: message.isPinned || merged.isPinned,
              )
            : message,
      )
      .toList(growable: false);
}

/// Thời lượng / sóng âm của bản ghi âm đầu tiên đã tải lên (gửi kèm tin).
MessageVoiceMetadata? _uploadedVoiceMetadata(
  List<MessageAttachmentUploadItem> attachments,
) {
  for (final item in attachments) {
    final voice = item.picked?.voice;
    if (item.status != MessageAttachmentUploadStatus.failed &&
        item.picked?.kind == MessageAttachmentKind.audio &&
        voice != null) {
      return voice;
    }
  }
  return null;
}

/// Mã người dùng hiện tại cho phòng chat: đã biết ([known]) thì dùng lại; chưa
/// thì lấy từ token trên máy ([fromToken], không gọi mạng); chỉ khi không có /
/// lỗi mới tải hồ sơ ([fromProfile], `GET /users/me`). Phòng chat gọi lại hàm
/// này mỗi lần mở, nối lại realtime, đồng bộ nên không được tải hồ sơ mỗi lần.
Future<String?> resolveChatRoomUserId({
  required String? known,
  required Future<String?> Function()? fromToken,
  required Future<String?> Function() fromProfile,
}) async {
  final knownId = known?.trim();
  if (knownId != null && knownId.isNotEmpty) return knownId;
  if (fromToken != null) {
    try {
      final id = (await fromToken())?.trim();
      if (id != null && id.isNotEmpty) return id;
    } on Object {
      // Đọc token lỗi: tải hồ sơ bên dưới.
    }
  }
  return fromProfile();
}
