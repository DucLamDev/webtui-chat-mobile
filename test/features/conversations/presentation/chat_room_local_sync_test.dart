import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/core/database/app_database.dart';
import 'package:webtui_chat/core/error/failure.dart';
import 'package:webtui_chat/core/result/result.dart';
import 'package:webtui_chat/core/security/instance_scope.dart';
import 'package:webtui_chat/features/conversations/application/message_sync_service.dart';
import 'package:webtui_chat/features/conversations/application/use_cases/call_use_cases.dart';
import 'package:webtui_chat/features/conversations/application/use_cases/message_attachment_use_cases.dart';
import 'package:webtui_chat/features/conversations/application/use_cases/message_media_uploader.dart';
import 'package:webtui_chat/features/conversations/application/use_cases/message_outbox_dispatcher.dart';
import 'package:webtui_chat/features/conversations/application/use_cases/message_outbox_use_cases.dart';
import 'package:webtui_chat/features/conversations/application/use_cases/message_use_cases.dart';
import 'package:webtui_chat/features/conversations/data/datasources/local_message_store.dart';
import 'package:webtui_chat/features/conversations/domain/entities/chat_message.dart';
import 'package:webtui_chat/features/conversations/domain/entities/conversation_realtime_event.dart';
import 'package:webtui_chat/features/conversations/domain/entities/message_outbox_item.dart';
import 'package:webtui_chat/features/conversations/domain/entities/message_sync.dart';
import 'package:webtui_chat/features/conversations/domain/repositories/call_repository.dart';
import 'package:webtui_chat/features/conversations/domain/repositories/conversation_repository.dart';
import 'package:webtui_chat/features/conversations/domain/repositories/message_attachment_repository.dart';
import 'package:webtui_chat/features/conversations/domain/repositories/message_changes_repository.dart';
import 'package:webtui_chat/features/conversations/domain/repositories/message_outbox_repository.dart';
import 'package:webtui_chat/features/conversations/presentation/controllers/chat_room_controller.dart';
import 'package:webtui_chat/features/profile/application/use_cases/profile_use_cases.dart';
import 'package:webtui_chat/features/profile/domain/repositories/profile_repository.dart';

final _base = DateTime.utc(2026, 11, 19, 8);

ChatMessage _msg(String id, int minute, {String? body}) => ChatMessage(
  id: id,
  workspaceId: 'w1',
  channelId: 'c1',
  kind: 'text',
  body: body ?? 'tin $id',
  createdAt: _base.add(Duration(minutes: minute)),
  senderId: minute.isEven ? 'me' : 'peer',
);

void main() {
  late AppDatabase database;
  late LocalMessageStore store;
  late _Server server;
  late MessageSyncService sync;

  setUp(() {
    database = AppDatabase(createInMemoryDriftConnection());
    store = LocalMessageStore(
      database,
      InstanceScope(
        instanceId: '11111111-1111-4111-8111-111111111111',
        serverOrigin: Uri.parse('https://chat.example.com'),
      ),
    );
    server = _Server();
    sync = MessageSyncService(
      local: store,
      changes: server,
      messages: server,
      now: () => _base.add(const Duration(days: 1)),
      pageSize: 50,
    );
  });

  tearDown(() => database.close());

  ChatRoomController controller() {
    final c = _controller(server, sync);
    addTearDown(c.dispose);
    return c;
  }

  Future<void> seedDevice(List<ChatMessage> messages) async {
    await store.upsert(workspaceId: 'w1', channelId: 'c1', messages: messages);
    await store.writeSyncState(
      ChannelSyncState(
        workspaceId: 'w1',
        channelId: 'c1',
        changeCursor: 'c0',
        oldestMessageId: messages.first.id,
        oldestCreatedAt: messages.first.createdAt,
      ),
    );
  }

  test('không có mạng: hiện tin trên máy, chỉ báo nhẹ, không lỗi đỏ', () async {
    await seedDevice([_msg('m1', 1), _msg('m2', 2)]);
    server.changes = (since) => FailureResult(
      const Failure(kind: FailureKind.network, message: 'mất mạng'),
    );
    final room = controller();

    await room.load();

    expect([for (final m in room.state.messages) m.id], ['m1', 'm2']);
    expect(room.state.isLoading, isFalse);
    expect(room.state.errorMessage, isNull);
    expect(room.state.syncNotice, isNotNull);
    expect(room.state.messages.last.isMine, isTrue);
    // Không tải lại trang tin cũ kiểu cũ.
    expect(server.pageCalls, isEmpty);
  });

  test('có mạng: chỉ hỏi phần thay đổi rồi áp vào danh sách', () async {
    await seedDevice([_msg('m1', 1), _msg('m2', 2)]);
    server.changes = (since) => Success(
      MessageChangesPage(
        messages: [
          _msg('m2', 2, body: 'đã sửa'),
          _msg('m3', 3),
          ChatMessage(
            id: 'm1',
            workspaceId: 'w1',
            channelId: 'c1',
            kind: 'text',
            body: '',
            createdAt: _msg('m1', 1).createdAt,
            deletedAt: _base,
          ),
        ],
        nextCursor: 'c1',
      ),
    );
    final room = controller();

    await room.load();

    final byId = {for (final m in room.state.messages) m.id: m};
    expect(byId.keys, ['m1', 'm2', 'm3']);
    expect(byId['m1']!.isDeleted, isTrue);
    expect(byId['m2']!.body, 'đã sửa');
    expect(room.state.syncNotice, isNull);
    expect(server.changeCalls, ['c0']);
    expect(
      [
        for (final m in await store.readLatest(
          workspaceId: 'w1',
          channelId: 'c1',
        ))
          m.id,
      ],
      ['m2', 'm3'],
    );
  });

  test('máy chủ cũ (404): tải trang tin như trước', () async {
    server.changes = (since) => FailureResult(
      const Failure(kind: FailureKind.notFound, message: '404'),
    );
    server.page = (beforeId) =>
        Success(MessagePage(messages: [_msg('s1', 1)], nextCursor: 's1'));
    final room = controller();

    await room.load();

    expect([for (final m in room.state.messages) m.id], ['s1']);
    expect(room.state.nextCursor, 's1');
    expect(room.state.errorMessage, isNull);
  });

  test('tìm trên máy trước, "tìm thêm trên máy chủ" gộp bỏ trùng', () async {
    await seedDevice([
      _msg('m1', 1, body: 'Họp sáng'),
      _msg('m2', 2, body: 'ăn trưa'),
    ]);
    server.changes = (since) =>
        const Success(MessageChangesPage(messages: [], nextCursor: 'c1'));
    server.search = (query) => Success(
      MessagePage(
        messages: [
          _msg('m1', 1, body: 'Họp sáng'),
          _msg('old', -100, body: 'họp cũ'),
        ],
      ),
    );
    final room = controller();
    await room.load();

    await room.search('hop');
    expect([for (final m in room.state.searchResults) m.id], ['m1']);
    expect(room.state.searchSource, MessageSearchSource.device);
    expect(server.searchCalls, isEmpty);

    await room.searchOnServer();
    expect([for (final m in room.state.searchResults) m.id], ['old', 'm1']);
    expect(room.state.searchSource, MessageSearchSource.deviceAndServer);
    expect(room.state.isSearchingServer, isFalse);

    room.clearSearch();
    expect(room.state.searchSource, MessageSearchSource.none);
  });

  test(
    'tìm thêm trên máy chủ lỗi: giữ kết quả trên máy, báo lỗi riêng',
    () async {
      await seedDevice([_msg('m1', 1, body: 'Họp sáng')]);
      server.changes = (since) =>
          const Success(MessageChangesPage(messages: [], nextCursor: 'c1'));
      server.search = (query) => FailureResult(
        const Failure(kind: FailureKind.network, message: 'lỗi'),
      );
      final room = controller();
      await room.load();
      await room.search('họp');

      await room.searchOnServer();

      expect([for (final m in room.state.searchResults) m.id], ['m1']);
      expect(room.state.searchServerError, 'lỗi');
      expect(room.state.errorMessage, isNull);
    },
  );

  test('tải tin cũ hơn: đọc trên máy, không hỏi máy chủ khi còn đủ', () async {
    await seedDevice([for (var i = 1; i <= 60; i++) _msg('m${100 + i}', i)]);
    server.changes = (since) =>
        const Success(MessageChangesPage(messages: [], nextCursor: 'c1'));
    final room = controller();
    await room.load();
    // Chờ lượt tải trước chạy ngầm xong.
    await sync.prefetchHistory(workspaceId: 'w1', channelId: 'c1');
    final pageCallsBefore = server.pageCalls.length;
    expect(room.state.messages, hasLength(50));
    expect(room.state.hasMore, isTrue);

    await room.loadOlder();

    expect(room.state.messages, hasLength(60));
    expect(room.state.messages.first.id, 'm101');
    expect(server.pageCalls.length, pageCallsBefore);
  });
}

ChatRoomController _controller(_Server server, MessageSyncService sync) {
  final outbox = _EmptyOutbox();
  return ChatRoomController(
    scope: const ChatRoomScope(
      workspaceId: 'w1',
      channelId: 'c1',
      title: 'Nhóm',
    ),
    loadMessagesUseCase: LoadMessagesUseCase(server),
    sendMessageUseCase: SendMessageUseCase(server),
    editMessageUseCase: EditMessageUseCase(server),
    deleteMessageUseCase: DeleteMessageUseCase(server),
    toggleReactionUseCase: ToggleReactionUseCase(server),
    togglePinMessageUseCase: TogglePinMessageUseCase(server),
    forwardMessageUseCase: ForwardMessageUseCase(server),
    loadThreadUseCase: LoadThreadUseCase(server),
    searchMessagesUseCase: SearchMessagesUseCase(server),
    pickMessageAttachmentUseCase: PickMessageAttachmentUseCase(_Unused()),
    startVoiceMessageRecordingUseCase: StartVoiceMessageRecordingUseCase(
      _Unused(),
    ),
    stopVoiceMessageRecordingUseCase: StopVoiceMessageRecordingUseCase(
      _Unused(),
    ),
    cancelVoiceMessageRecordingUseCase: CancelVoiceMessageRecordingUseCase(
      _Unused(),
    ),
    messageMediaUploader: _Unused(),
    listMessageAttachmentsUseCase: ListMessageAttachmentsUseCase(_Unused()),
    loadMessageOutboxUseCase: LoadMessageOutboxUseCase(outbox),
    enqueueMessageOutboxUseCase: EnqueueMessageOutboxUseCase(
      repository: outbox,
      instanceScopeId: 'scope',
    ),
    outboxDispatcher: MessageOutboxDispatcher(
      repository: outbox,
      sendMessage: (_) async => throw UnimplementedError(),
      attachFile: (_, _, _) async => throw UnimplementedError(),
    ),
    newClientMessageIdUseCase: const NewClientMessageIdUseCase(),
    newAttachmentUploadItemUseCase: const NewAttachmentUploadItemUseCase(),
    startCallUseCase: StartCallUseCase(_Unused()),
    endCallUseCase: EndCallUseCase(_Unused()),
    markConversationReadUseCase: MarkConversationReadUseCase(server),
    subscribeConversationRealtimeUseCase: SubscribeConversationRealtimeUseCase(
      server.realtime,
    ),
    sendTypingUseCase: SendTypingUseCase(server.realtime),
    readDraftUseCase: ReadDraftUseCase(server.drafts),
    saveDraftUseCase: SaveDraftUseCase(server.drafts),
    clearDraftUseCase: ClearDraftUseCase(server.drafts),
    loadProfileUseCase: LoadProfileUseCase(_Unused()),
    resolveCurrentUserId: () async => 'me',
    messageSyncService: sync,
  );
}

/// Máy chủ giả: danh sách tin, tìm kiếm, luồng thay đổi.
final class _Server
    implements ConversationRepository, MessageChangesRepository {
  final realtime = _Realtime();
  final drafts = _Drafts();
  final List<String?> pageCalls = [];
  final List<String?> changeCalls = [];
  final List<String> searchCalls = [];

  Result<MessageChangesPage> Function(String? since) changes = (since) =>
      const Success(MessageChangesPage(messages: [], nextCursor: 'c0'));
  Result<MessagePage> Function(String? beforeId) page = (beforeId) =>
      const Success(MessagePage(messages: []));
  Result<MessagePage> Function(String query) search = (query) =>
      const Success(MessagePage(messages: []));

  @override
  Future<Result<MessageChangesPage>> listMessageChanges({
    required String workspaceId,
    required String channelId,
    String? since,
    int limit = 200,
  }) async {
    changeCalls.add(since);
    return changes(since);
  }

  @override
  Future<Result<MessagePage>> listMessagePage({
    required String workspaceId,
    required String channelId,
    int limit = 50,
    String? beforeId,
  }) async {
    pageCalls.add(beforeId);
    return page(beforeId);
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
  }) async {
    searchCalls.add(query);
    return search(query);
  }

  @override
  Future<Result<void>> markRead({
    required String workspaceId,
    required String channelId,
    required String lastReadMessageId,
  }) async => const Success(null);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _Realtime implements ConversationRealtimeRepository {
  final _events = StreamController<ConversationRealtimeEvent>.broadcast();

  @override
  Stream<ConversationRealtimeEvent> subscribeToChannel({
    required String workspaceId,
    required String channelId,
  }) => _events.stream;

  @override
  Future<void> sendTyping({
    required String workspaceId,
    required String channelId,
    required bool isTyping,
  }) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _Drafts implements ConversationDraftRepository {
  @override
  Future<String> readDraft({
    required String workspaceId,
    required String channelId,
  }) async => '';

  @override
  Future<void> saveDraft({
    required String workspaceId,
    required String channelId,
    required String body,
  }) async {}

  @override
  Future<void> clearDraft({
    required String workspaceId,
    required String channelId,
  }) async {}
}

final class _EmptyOutbox implements MessageOutboxRepository {
  @override
  Future<List<MessageOutboxItem>> list({
    required String workspaceId,
    required String channelId,
  }) async => const [];

  @override
  Future<List<MessageOutboxItem>> listWorkspace({
    required String workspaceId,
  }) async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Phụ thuộc không dùng tới trong các ca này.
final class _Unused
    implements
        MessageAttachmentPickerRepository,
        MessageAttachmentRepository,
        MessageVoiceRecorderRepository,
        MessageMediaUploader,
        CallRepository,
        ProfileRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
