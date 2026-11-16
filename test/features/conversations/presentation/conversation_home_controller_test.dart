import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/core/result/result.dart';
import 'package:webtui_chat/features/conversations/application/use_cases/channel_use_cases.dart';
import 'package:webtui_chat/features/conversations/application/use_cases/load_conversation_home_use_case.dart';
import 'package:webtui_chat/features/conversations/application/use_cases/open_direct_conversation_use_case.dart';
import 'package:webtui_chat/features/conversations/domain/entities/channel_file.dart';
import 'package:webtui_chat/features/conversations/domain/entities/chat_message.dart';
import 'package:webtui_chat/features/conversations/domain/entities/conversation_realtime_event.dart';
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

  test('removeChannel bỏ nhóm khỏi danh sách và bỏ chọn nhóm đó', () async {
    final repository = _FakeConversationRepository(
      conversations: [_summary(id: 'dm-1', channelId: 'dm-channel')],
      channels: [
        _summary(
          id: 'group-1',
          channelId: 'group-1',
          kind: ConversationKind.channel,
        ),
        _summary(
          id: 'group-2',
          channelId: 'group-2',
          kind: ConversationKind.channel,
        ),
      ],
    );
    final controller = _controller(repository);
    addTearDown(controller.dispose);

    await controller.load();
    controller.selectConversation(controller.state.channels.first);
    controller.removeChannel('group-1');

    expect(controller.state.channels.map((item) => item.channelId), [
      'group-2',
    ]);
    expect(controller.state.conversations.map((item) => item.channelId), [
      'dm-channel',
    ]);
    expect(controller.state.selectedConversation, isNull);

    // Nhóm khác đang chọn thì giữ nguyên lựa chọn.
    controller.selectConversation(controller.state.channels.single);
    controller.removeChannel('khong-co');
    expect(controller.state.selectedConversation?.channelId, 'group-2');
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

  test('bot chats are hidden from Messages when disabled', () async {
    final repository = _FakeConversationRepository(
      conversations: [
        _summary(id: 'dm-1', channelId: 'dm-channel'),
        _summary(
          id: 'bot-session',
          channelId: 'bot-session',
          isAutomation: true,
          slug: 'orders',
        ),
      ],
    );
    final disabled = _controller(repository);
    addTearDown(disabled.dispose);
    await disabled.load();
    expect(disabled.state.filteredConversations.map((item) => item.id), [
      'dm-1',
    ]);

    final enabled = _controller(repository, automationEnabled: true);
    addTearDown(enabled.dispose);
    await enabled.load();
    expect(enabled.state.filteredConversations.map((item) => item.id), [
      'dm-1',
      'bot-session',
    ]);
  });

  test('automation channels are hidden when automation is disabled', () async {
    final repository = _FakeConversationRepository(
      channels: [
        _summary(
          id: 'channel-1',
          channelId: 'channel-1',
          kind: ConversationKind.channel,
        ),
        _summary(
          id: 'orders',
          channelId: 'orders',
          kind: ConversationKind.channel,
          isAutomation: true,
          slug: 'orders',
        ),
      ],
    );
    final controller = _controller(repository);
    addTearDown(controller.dispose);

    await controller.load();

    expect(controller.state.automationEnabled, isFalse);
    expect(controller.state.channelTabCount, 3);
    // Tab "Tất cả": chỉ còn kênh thường, kênh automation bị ẩn.
    expect(controller.state.filteredChannels.map((channel) => channel.id), [
      'channel-1',
    ]);
  });

  test(
    'automation channels only appear on the Automation tab when enabled',
    () async {
      final repository = _FakeConversationRepository(
        channels: [
          _summary(
            id: 'channel-1',
            channelId: 'channel-1',
            kind: ConversationKind.channel,
          ),
          _summary(
            id: 'orders',
            channelId: 'orders',
            kind: ConversationKind.channel,
            isAutomation: true,
            slug: 'orders',
          ),
        ],
      );
      final controller = _controller(repository, automationEnabled: true);
      addTearDown(controller.dispose);

      await controller.load();

      expect(controller.state.channelTabCount, 4);
      // Tab 0 "Tất cả" chỉ có kênh thường.
      expect(controller.state.filteredChannels.map((channel) => channel.id), [
        'channel-1',
      ]);
      // Tab Automation chỉ có kênh automation.
      controller.setChannelTab(controller.state.automationChannelTab);
      expect(controller.state.filteredChannels.map((channel) => channel.id), [
        'orders',
      ]);
    },
  );

  test(
    'tin mới ở phòng chưa mở: cộng chưa đọc tại chỗ, không gọi lại máy chủ',
    () async {
      final repository = _FakeConversationRepository(
        conversations: [
          _summary(id: 'dm-1', channelId: 'dm-channel'),
          _summary(id: 'dm-2', channelId: 'dm-other'),
        ],
        channels: [
          _summary(
            id: 'group-1',
            channelId: 'group-1',
            kind: ConversationKind.channel,
          ),
          _summary(
            id: 'public-not-joined',
            channelId: 'public-not-joined',
            kind: ConversationKind.channel,
            membership: MembershipStatus.none,
          ),
        ],
      );
      final realtime = _FakeRealtimeRepository();
      final controller = _controller(repository, realtime: realtime);
      addTearDown(controller.dispose);

      await controller.load();
      expect(realtime.watched.last, {'dm-channel', 'dm-other', 'group-1'});
      final channelLoads = repository.channelLoads;
      final contactLoads = repository.contactLoads;

      // Tin tới hai lần (cùng mã): chỉ cộng một.
      realtime.emitMessage('group-1', id: 'm-1');
      realtime.emitMessage('group-1', id: 'm-1');
      realtime.emitMessage('group-1', id: 'm-2');
      // Tin của chính mình (máy khác): không cộng chưa đọc.
      realtime.emitMessage('group-1', id: 'm-3', senderId: 'me');
      // Sự kiện khác / nhóm chưa tham gia: bỏ qua.
      realtime.emit(ConversationRealtimeEventType.typingStarted, 'group-1');
      realtime.emitMessage('public-not-joined', id: 'm-4');
      // Chat 1-1: dòng phụ là tin cuối, hội thoại lên đầu danh sách.
      realtime.emitMessage('dm-other', id: 'm-5', body: 'Hẹn 3 giờ nhé');
      await Future<void>.delayed(Duration.zero);

      final group = controller.state.channels.firstWhere(
        (item) => item.channelId == 'group-1',
      );
      expect(group.unreadCount, 2);
      // Nhóm giữ mô tả ở dòng phụ.
      expect(group.preview, 'Tin nhắn mới');
      expect(
        controller.state.channels
            .firstWhere((item) => item.channelId == 'public-not-joined')
            .unreadCount,
        0,
      );
      final first = controller.state.conversations.first;
      expect(first.channelId, 'dm-other');
      expect(first.unreadCount, 1);
      expect(first.preview, 'Hẹn 3 giờ nhé');
      // Không tải lại gì từ máy chủ.
      expect(repository.channelLoads, channelLoads);
      expect(repository.contactLoads, contactLoads);
    },
  );

  test('đang mở hội thoại (máy tính bảng): không cộng chưa đọc', () async {
    final dm = _summary(id: 'dm-1', channelId: 'dm-channel');
    final repository = _FakeConversationRepository(conversations: [dm]);
    final realtime = _FakeRealtimeRepository();
    final controller = _controller(repository, realtime: realtime);
    addTearDown(controller.dispose);
    await controller.load();
    controller.reportSplitView(true);
    controller.selectConversation(dm);

    realtime.emitMessage('dm-channel', id: 'm-1');
    await Future<void>.delayed(Duration.zero);

    expect(controller.state.conversations.single.unreadCount, 0);
  });

  test(
    'điện thoại: hội thoại chọn lần trước (đã rời phòng) vẫn được cộng',
    () async {
      final dm = _summary(id: 'dm-1', channelId: 'dm-channel');
      final repository = _FakeConversationRepository(conversations: [dm]);
      final realtime = _FakeRealtimeRepository();
      final controller = _controller(repository, realtime: realtime);
      addTearDown(controller.dispose);
      await controller.load();
      controller.reportSplitView(false);
      controller.selectConversation(dm);

      realtime.emitMessage('dm-channel', id: 'm-1');
      await Future<void>.delayed(Duration.zero);

      expect(controller.state.conversations.single.unreadCount, 1);
    },
  );

  test('tin vừa cộng bị thu hồi / hết hạn: trừ lại', () async {
    final repository = _FakeConversationRepository(
      channels: [
        _summary(id: 'g', channelId: 'g', kind: ConversationKind.channel),
      ],
    );
    final realtime = _FakeRealtimeRepository();
    final controller = _controller(repository, realtime: realtime);
    addTearDown(controller.dispose);
    await controller.load();

    realtime.emitMessage('g', id: 'm-1');
    realtime.emitMessage('g', id: 'm-2');
    realtime.emitDeleted('g', 'm-1');
    // Xoá lại lần nữa / tin không được cộng: không trừ thêm.
    realtime.emitDeleted('g', 'm-1');
    realtime.emitDeleted('g', 'm-cu');
    await Future<void>.delayed(Duration.zero);

    expect(controller.state.channels.single.unreadCount, 1);
  });

  test(
    'dòng phụ chat 1-1: tin bí mật không lộ nội dung, tin rỗng giữ dòng cũ',
    () async {
      final repository = _FakeConversationRepository(
        conversations: [
          _summary(id: 'dm-1', channelId: 'dm-a'),
          _summary(id: 'dm-2', channelId: 'dm-b'),
        ],
      );
      final realtime = _FakeRealtimeRepository();
      final controller = _controller(repository, realtime: realtime);
      addTearDown(controller.dispose);
      await controller.load();

      realtime.emitMessage('dm-a', id: 'm-1', body: 'mật', isSecret: true);
      realtime.emitMessage('dm-b', id: 'm-2', body: '  ');
      await Future<void>.delayed(Duration.zero);

      String preview(String channelId) => controller.state.conversations
          .firstWhere((item) => item.channelId == channelId)
          .preview;
      expect(preview('dm-a'), 'Tin nhắn bí mật');
      expect(preview('dm-b'), 'Tin nhắn mới');
    },
  );

  test('chưa biết mình là ai: không cộng chưa đọc, vẫn đưa lên đầu', () async {
    final repository = _FakeConversationRepository(
      conversations: [
        _summary(id: 'dm-1', channelId: 'dm-a'),
        _summary(id: 'dm-2', channelId: 'dm-b'),
      ],
    );
    final realtime = _FakeRealtimeRepository();
    final controller = _controller(
      repository,
      realtime: realtime,
      currentUserId: () => null,
    );
    addTearDown(controller.dispose);
    await controller.load();

    realtime.emitMessage('dm-b', id: 'm-1');
    await Future<void>.delayed(Duration.zero);

    final first = controller.state.conversations.first;
    expect(first.channelId, 'dm-b');
    expect(first.unreadCount, 0);
  });

  test('rời / xoá nhóm: rời phòng realtime của nhóm ngay', () async {
    final repository = _FakeConversationRepository(
      channels: [
        _summary(id: 'g1', channelId: 'g1', kind: ConversationKind.channel),
        _summary(id: 'g2', channelId: 'g2', kind: ConversationKind.channel),
      ],
    );
    final realtime = _FakeRealtimeRepository();
    final controller = _controller(repository, realtime: realtime);
    addTearDown(controller.dispose);
    await controller.load();
    expect(realtime.watched.last, {'g1', 'g2'});

    controller.removeChannel('g1');

    expect(realtime.watched.last, {'g2'});
  });

  test('số chưa đọc dừng ở 100 như máy chủ', () async {
    final repository = _FakeConversationRepository(
      channels: [
        _summary(
          id: 'g',
          channelId: 'g',
          kind: ConversationKind.channel,
          unread: 99,
        ),
      ],
    );
    final realtime = _FakeRealtimeRepository();
    final controller = _controller(repository, realtime: realtime);
    addTearDown(controller.dispose);
    await controller.load();

    realtime.emitMessage('g', id: 'm-1');
    realtime.emitMessage('g', id: 'm-2');
    await Future<void>.delayed(Duration.zero);

    expect(controller.state.channels.single.unreadCount, 100);
  });

  test('kết nối nền chưa mở: không theo dõi, lần tải sau thử lại', () async {
    final repository = _FakeConversationRepository(
      conversations: [_summary(id: 'dm-1', channelId: 'dm-channel')],
    );
    final realtime = _FakeRealtimeRepository()..ready = false;
    final controller = _controller(repository, realtime: realtime);
    addTearDown(controller.dispose);

    await controller.load();
    expect(realtime.watchedOk, isEmpty);

    realtime.ready = true;
    await controller.syncSilently();
    expect(realtime.watchedOk.single, {'dm-channel'});
  });

  test('đóng danh sách: rời các phòng đã theo dõi', () async {
    final repository = _FakeConversationRepository(
      conversations: [_summary(id: 'dm-1', channelId: 'dm-channel')],
    );
    final realtime = _FakeRealtimeRepository();
    final controller = _controller(repository, realtime: realtime);

    await controller.load();
    controller.dispose();
    expect(realtime.watched.last, isEmpty);
  });
}

final class _FakeRealtimeRepository implements ConversationRealtimeRepository {
  final _events = StreamController<ConversationRealtimeEvent>.broadcast();
  final watched = <Set<String>>[];
  final watchedOk = <Set<String>>[];
  bool ready = true;

  void emitMessage(
    String channelId, {
    required String id,
    String senderId = 'u-2',
    String body = 'Chào',
    bool isSecret = false,
  }) {
    _events.add(
      ConversationRealtimeEvent(
        type: ConversationRealtimeEventType.messageCreated,
        workspaceId: 'workspace-1',
        channelId: channelId,
        message: ChatMessage(
          id: id,
          workspaceId: 'workspace-1',
          channelId: channelId,
          kind: 'text',
          body: body,
          createdAt: DateTime.utc(2026, 11, 16, 9),
          senderId: senderId,
          isSecret: isSecret,
        ),
      ),
    );
  }

  void emitDeleted(String channelId, String messageId) {
    _events.add(
      ConversationRealtimeEvent(
        type: ConversationRealtimeEventType.messageDeleted,
        workspaceId: 'workspace-1',
        channelId: channelId,
        messageId: messageId,
      ),
    );
  }

  void emit(ConversationRealtimeEventType type, String channelId) {
    _events.add(
      ConversationRealtimeEvent(
        type: type,
        workspaceId: 'workspace-1',
        channelId: channelId,
      ),
    );
  }

  @override
  Stream<ConversationRealtimeEvent>? watchChannels({
    required String workspaceId,
    required Iterable<String> channelIds,
  }) {
    watched.add(channelIds.toSet());
    if (!ready) return null;
    watchedOk.add(channelIds.toSet());
    return _events.stream;
  }

  @override
  Stream<ConversationRealtimeEvent> subscribeToUser({
    required String workspaceId,
  }) => _events.stream;

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
  Future<void> disconnect() async {}
}

ConversationHomeController _controller(
  _FakeConversationRepository repository, {
  bool automationEnabled = false,
  ConversationRealtimeRepository? realtime,
  String? Function()? currentUserId,
}) {
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
    automationEnabled: automationEnabled,
    realtime: realtime,
    currentUserId: currentUserId ?? () => 'me',
  );
}

ConversationSummary _summary({
  required String id,
  required String channelId,
  ConversationKind kind = ConversationKind.direct,
  MembershipStatus membership = MembershipStatus.active,
  int unread = 0,
  bool isAutomation = false,
  String? slug,
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
    membershipStatus: membership,
    isAutomation: isAutomation,
    slug: slug,
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

  List<ConversationSummary> conversations;
  List<ConversationSummary> channels;
  int channelLoads = 0;
  int contactLoads = 0;

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
    channelLoads++;
    return Success(channels);
  }

  @override
  Future<Result<List<ContactSummary>>> listContacts() async {
    contactLoads++;
    return const Success([]);
  }

  @override
  Future<Result<List<ContactSummary>>> listContactRequests({
    String status = 'all',
  }) async {
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
    bool silent = false,
    Map<String, Object?> metadata = const {},
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
