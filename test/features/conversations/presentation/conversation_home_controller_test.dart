import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/core/result/result.dart';
import 'package:webtui_chat/features/conversations/application/use_cases/channel_use_cases.dart';
import 'package:webtui_chat/features/conversations/application/use_cases/load_conversation_home_use_case.dart';
import 'package:webtui_chat/features/conversations/application/use_cases/open_direct_conversation_use_case.dart';
import 'package:webtui_chat/features/conversations/domain/entities/channel_file.dart';
import 'package:webtui_chat/features/conversations/domain/entities/chat_message.dart';
import 'package:webtui_chat/features/conversations/domain/entities/conversation_list_prefs.dart';
import 'package:webtui_chat/features/conversations/domain/entities/conversation_realtime_event.dart';
import 'package:webtui_chat/features/conversations/domain/entities/conversation_summary.dart';
import 'package:webtui_chat/features/conversations/domain/repositories/conversation_list_prefs_repository.dart';
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
      // Nhóm: dòng phụ là tin mới nhất; chưa biết tên người gửi (chưa tải
      // thành viên) thì chỉ nội dung.
      expect(group.preview, 'Chào');
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

  test(
    'tin mới ở nhóm: dòng phụ "Tên: nội dung", tin mình "Bạn: ..."',
    () async {
      final repository = _FakeConversationRepository(
        channels: [
          _summary(id: 'g', channelId: 'g', kind: ConversationKind.channel),
        ],
        members: const [
          ContactSummary(
            userId: 'u-2',
            displayName: 'Bình',
            username: 'binh',
            email: 'binh@example.com',
            status: 'active',
          ),
        ],
      );
      final realtime = _FakeRealtimeRepository();
      final controller = _controller(repository, realtime: realtime);
      addTearDown(controller.dispose);
      await controller.load();

      String preview() => controller.state.channels
          .firstWhere((item) => item.channelId == 'g')
          .preview;

      realtime.emitMessage(
        'g',
        id: 'a',
        body: 'Họp lúc 3 giờ',
        at: DateTime.utc(2026, 11, 16, 9),
      );
      await Future<void>.delayed(Duration.zero);
      expect(preview(), 'Bình: Họp lúc 3 giờ');

      realtime.emitMessage(
        'g',
        id: 'b',
        senderId: 'me',
        body: 'Ok',
        at: DateTime.utc(2026, 11, 16, 9, 1),
      );
      await Future<void>.delayed(Duration.zero);
      expect(preview(), 'Bạn: Ok');

      realtime.emitMessage(
        'g',
        id: 'c',
        body: 'bí mật',
        isSecret: true,
        at: DateTime.utc(2026, 11, 16, 9, 2),
      );
      await Future<void>.delayed(Duration.zero);
      expect(preview(), 'Tin nhắn bí mật');
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

  group('menu ấn giữ: ghim / chưa đọc / ẩn lưu trên máy', () {
    List<String> inboxIds(ConversationHomeController controller) => [
      for (final item in controller.state.inbox) item.channelId,
    ];

    _FakeConversationRepository twoChats() => _FakeConversationRepository(
      conversations: [
        _summary(
          id: 'dm-new',
          channelId: 'dm-new',
          updatedAt: DateTime.utc(2026, 11, 2),
        ),
        _summary(
          id: 'dm-old',
          channelId: 'dm-old',
          updatedAt: DateTime.utc(2026, 11, 1),
        ),
      ],
    );

    test('ghim đưa lên đầu, lưu theo tài khoản + không gian', () async {
      final prefsRepo = _FakeListPrefsRepository();
      final controller = _controller(twoChats(), listPrefs: prefsRepo);
      addTearDown(controller.dispose);
      await controller.load();
      expect(inboxIds(controller), ['dm-new', 'dm-old']);

      controller.setPinned(controller.state.inbox.last, true);
      expect(inboxIds(controller), ['dm-old', 'dm-new']);
      expect(controller.state.inbox.first.favorite, isTrue);
      expect(prefsRepo.saved['me:workspace-1']?.pinned, {'dm-old'});

      controller.setPinned(controller.state.inbox.first, false);
      expect(inboxIds(controller), ['dm-new', 'dm-old']);
    });

    test('mở lại app: đọc tuỳ chọn đã lưu trước khi dựng danh sách', () async {
      final prefsRepo = _FakeListPrefsRepository()
        ..saved['me:workspace-1'] = ConversationListPrefs.empty.withPinned(
          'dm-old',
          true,
        );
      final controller = _controller(twoChats(), listPrefs: prefsRepo);
      addTearDown(controller.dispose);
      await controller.load();
      expect(inboxIds(controller), ['dm-old', 'dm-new']);

      // Tài khoản khác trên cùng máy chủ không thấy ghim của người này.
      final other = _controller(
        twoChats(),
        listPrefs: prefsRepo,
        currentUserId: () => 'nguoi-khac',
      );
      addTearDown(other.dispose);
      await other.load();
      expect(inboxIds(other), ['dm-new', 'dm-old']);
    });

    test('đánh dấu chưa đọc: hiện số 1, mở hội thoại thì hết', () async {
      final controller = _controller(
        twoChats(),
        listPrefs: _FakeListPrefsRepository(),
      );
      addTearDown(controller.dispose);
      await controller.load();

      controller.setMarkedUnread(controller.state.inbox.first, true);
      expect(controller.state.inbox.first.unreadCount, 1);
      expect(controller.state.unreadBadgeCount(), 1);

      controller.selectConversation(controller.state.inbox.first);
      expect(controller.state.listPrefs.markedUnread, isEmpty);
      expect(controller.state.inbox.first.unreadCount, 0);
    });

    test('đánh dấu đã đọc xoá số chưa đọc trên danh sách', () async {
      final repository = _FakeConversationRepository(
        conversations: [_summary(id: 'dm', channelId: 'dm', unread: 4)],
      );
      final controller = _controller(repository);
      addTearDown(controller.dispose);
      await controller.load();

      controller.setMarkedUnread(controller.state.inbox.single, false);
      expect(controller.state.inbox.single.unreadCount, 0);
      expect(controller.state.unreadBadgeCount(), 0);
    });

    test(
      'ẩn: mất khỏi danh sách, tìm vẫn thấy, tin mới thì hiện lại',
      () async {
        final repository = twoChats();
        final controller = _controller(
          repository,
          listPrefs: _FakeListPrefsRepository(),
        );
        addTearDown(controller.dispose);
        await controller.load();

        final target = controller.state.inbox.first;
        controller.setHidden(target, true);
        expect(inboxIds(controller), ['dm-old']);
        expect(controller.state.isHiddenOnDevice(target), isTrue);

        controller.setSearchQuery('Lam');
        expect(inboxIds(controller), contains('dm-new'));
        controller.setSearchQuery('');

        // Có tin mới (hoạt động sau mốc ẩn): tải lại thì hiện.
        repository.conversations = [
          _summary(
            id: 'dm-new',
            channelId: 'dm-new',
            updatedAt: DateTime.utc(2026, 11, 3),
          ),
          repository.conversations.last,
        ];
        await controller.load();
        expect(inboxIds(controller), ['dm-new', 'dm-old']);
      },
    );

    test('gỡ khỏi danh sách: bỏ ghim, bỏ chọn hội thoại đang mở', () async {
      final controller = _controller(
        twoChats(),
        listPrefs: _FakeListPrefsRepository(),
      );
      addTearDown(controller.dispose);
      await controller.load();
      controller.setPinned(controller.state.inbox.last, true);
      final target = controller.state.inbox.first;
      controller.selectConversation(target);

      controller.removeFromList(target);
      expect(inboxIds(controller), ['dm-new']);
      expect(controller.state.selectedConversation, isNull);
      expect(controller.state.listPrefs.pinned, isEmpty);
    });

    test('tắt tiếng cập nhật ngay trên danh sách', () async {
      final controller = _controller(twoChats());
      addTearDown(controller.dispose);
      await controller.load();

      controller.setMutedLocally('dm-old', true);
      expect(
        controller.state.inbox.firstWhere((c) => c.channelId == 'dm-old').muted,
        isTrue,
      );
      expect(
        controller.state.inbox.firstWhere((c) => c.channelId == 'dm-new').muted,
        isFalse,
      );
    });

    test('đọc tuỳ chọn lỗi: danh sách vẫn tải bình thường', () async {
      final controller = _controller(
        twoChats(),
        listPrefs: _FakeListPrefsRepository(failRead: true),
      );
      addTearDown(controller.dispose);
      await controller.load();
      expect(inboxIds(controller), ['dm-new', 'dm-old']);
    });
  });
}

final class _FakeListPrefsRepository
    implements ConversationListPrefsRepository {
  _FakeListPrefsRepository({this.failRead = false});

  final bool failRead;
  final Map<String, ConversationListPrefs> saved = {};

  @override
  Future<ConversationListPrefs> read({
    required String userId,
    required String workspaceId,
  }) async {
    if (failRead) throw StateError('hỏng bộ nhớ');
    return saved['$userId:$workspaceId'] ?? ConversationListPrefs.empty;
  }

  @override
  Future<void> save({
    required String userId,
    required String workspaceId,
    required ConversationListPrefs prefs,
  }) async {
    saved['$userId:$workspaceId'] = prefs;
  }
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
    DateTime? at,
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
          createdAt: at ?? DateTime.utc(2026, 11, 16, 9),
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
  Future<bool> ensureConnected({
    required String workspaceId,
    Duration timeout = const Duration(seconds: 5),
  }) async => true;

  @override
  Future<void> disconnect() async {}
}

ConversationHomeController _controller(
  _FakeConversationRepository repository, {
  bool automationEnabled = false,
  ConversationRealtimeRepository? realtime,
  String? Function()? currentUserId,
  ConversationListPrefsRepository? listPrefs,
}) {
  return ConversationHomeController(
    listPrefs: listPrefs,
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
  DateTime? updatedAt,
}) {
  return ConversationSummary(
    id: id,
    workspaceId: 'workspace-1',
    channelId: channelId,
    kind: kind,
    title: kind == ConversationKind.direct ? 'Lam Đức' : 'Thông báo chung',
    preview: 'Tin nhắn mới',
    updatedAt: updatedAt ?? DateTime.utc(2026, 7, 16),
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
    this.members = const [],
  });

  List<ConversationSummary> conversations;
  List<ConversationSummary> channels;
  List<ContactSummary> members;
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
    return Success(members);
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
