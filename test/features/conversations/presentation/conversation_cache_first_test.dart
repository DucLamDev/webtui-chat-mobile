import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/core/database/app_database.dart';
import 'package:webtui_chat/core/error/failure.dart';
import 'package:webtui_chat/core/result/result.dart';
import 'package:webtui_chat/core/security/instance_scope.dart';
import 'package:webtui_chat/features/conversations/application/use_cases/channel_use_cases.dart';
import 'package:webtui_chat/features/conversations/application/use_cases/load_conversation_home_use_case.dart';
import 'package:webtui_chat/features/conversations/application/use_cases/message_attachment_use_cases.dart';
import 'package:webtui_chat/features/conversations/application/use_cases/open_direct_conversation_use_case.dart';
import 'package:webtui_chat/features/conversations/data/datasources/channel_member_cache_data_source.dart';
import 'package:webtui_chat/features/conversations/domain/entities/channel_file.dart';
import 'package:webtui_chat/features/conversations/domain/entities/chat_message.dart';
import 'package:webtui_chat/features/conversations/domain/entities/conversation_summary.dart';
import 'package:webtui_chat/features/conversations/domain/repositories/conversation_local_cache.dart';
import 'package:webtui_chat/features/conversations/domain/repositories/conversation_repository.dart';
import 'package:webtui_chat/features/conversations/domain/repositories/message_attachment_repository.dart';
import 'package:webtui_chat/features/conversations/presentation/controllers/channel_detail_controller.dart';
import 'package:webtui_chat/features/conversations/presentation/controllers/conversation_home_controller.dart';
import 'package:webtui_chat/features/workspace/domain/repositories/workspace_session_repository.dart';

void main() {
  group('danh sách hội thoại: hiện bản đã lưu trước', () {
    test('đọc bộ đệm: sắp theo giờ mới nhất; chưa lưu thì null', () async {
      final empty = ReadCachedConversationHomeUseCase(_FakeListCache());
      expect(await empty.execute(workspaceId: 'ws'), isNull);

      final cached = ReadCachedConversationHomeUseCase(
        _FakeListCache(
          directs: [
            _summary('dm-old', updatedAt: DateTime.utc(2026, 11, 1)),
            _summary('dm-new', updatedAt: DateTime.utc(2026, 11, 2)),
          ],
        ),
      );
      final data = await cached.execute(workspaceId: 'ws');
      expect(data!.conversations.map((item) => item.id), ['dm-new', 'dm-old']);
      expect(data.channels, isEmpty);
      expect(data.isOffline, isFalse);
    });

    test('đọc bộ đệm lỗi: coi như chưa lưu, không ném lỗi', () async {
      final useCase = ReadCachedConversationHomeUseCase(
        _FakeListCache(throwOnRead: true),
      );
      expect(await useCase.execute(workspaceId: 'ws'), isNull);
    });

    test('mở màn: hiện bản đã lưu ngay, máy chủ trả về thì thay', () async {
      final repository = _FakeRepository(
        directs: [_summary('dm-server')],
        channels: [_summary('group-server', kind: ConversationKind.channel)],
      )..gate = Completer<void>();
      final controller = _homeController(
        repository,
        cache: _FakeListCache(directs: [_summary('dm-cached')]),
      );
      addTearDown(controller.dispose);

      final loading = controller.load();
      await pumpEventQueue();
      expect(controller.state.isLoading, isFalse);
      expect(controller.state.conversations.map((item) => item.id), [
        'dm-cached',
      ]);
      expect(controller.state.errorMessage, isNull);

      repository.gate!.complete();
      await loading;
      expect(controller.state.conversations.map((item) => item.id), [
        'dm-server',
      ]);
      expect(controller.state.channels.map((item) => item.id), [
        'group-server',
      ]);
      expect(controller.state.offlineNotice, isNull);
    });

    test('chưa lưu gì: vẫn hiện đang tải tới khi máy chủ trả về', () async {
      final repository = _FakeRepository(directs: [_summary('dm-1')])
        ..gate = Completer<void>();
      final controller = _homeController(repository, cache: _FakeListCache());
      addTearDown(controller.dispose);

      final loading = controller.load();
      await pumpEventQueue();
      expect(controller.state.isLoading, isTrue);

      repository.gate!.complete();
      await loading;
      expect(controller.state.isLoading, isFalse);
      expect(controller.state.conversations.single.id, 'dm-1');
    });

    test('mất mạng: giữ bản đã lưu, báo nhẹ, không báo lỗi đỏ', () async {
      final repository = _FakeRepository(failure: _offline);
      final controller = _homeController(
        repository,
        cache: _FakeListCache(
          directs: [_summary('dm-cached')],
          channels: [_summary('group-cached', kind: ConversationKind.channel)],
        ),
      );
      addTearDown(controller.dispose);

      await controller.load();

      expect(controller.state.errorMessage, isNull);
      expect(controller.state.isLoading, isFalse);
      expect(controller.state.offlineNotice, isNotNull);
      expect(controller.state.conversations.single.id, 'dm-cached');
      expect(controller.state.channels.single.id, 'group-cached');

      // Có mạng lại: làm mới ngầm thay danh sách, bỏ dòng báo.
      repository
        ..failure = null
        ..directs = [_summary('dm-server')];
      expect(await controller.syncSilently(), isTrue);
      expect(controller.state.conversations.single.id, 'dm-server');
      expect(controller.state.offlineNotice, isNull);
    });

    test('kéo làm mới khi mất mạng: giữ danh sách đang có', () async {
      final repository = _FakeRepository(directs: [_summary('dm-1')]);
      final controller = _homeController(repository);
      addTearDown(controller.dispose);
      await controller.load();

      repository.failure = _offline;
      await controller.refresh();

      expect(controller.state.errorMessage, isNull);
      expect(controller.state.conversations.single.id, 'dm-1');
      expect(controller.state.offlineNotice, isNotNull);
    });

    test('mất mạng và chưa lưu gì: hiện lỗi như cũ', () async {
      final controller = _homeController(
        _FakeRepository(failure: _offline),
        cache: _FakeListCache(),
      );
      addTearDown(controller.dispose);

      await controller.load();

      expect(controller.state.errorMessage, _offline.message);
      expect(controller.state.offlineNotice, isNull);
    });

    test(
      'lỗi không phải mạng (mất quyền): không giấu lỗi sau bản đã lưu',
      () async {
        final controller = _homeController(
          _FakeRepository(failure: _forbidden),
          cache: _FakeListCache(directs: [_summary('dm-cached')]),
        );
        addTearDown(controller.dispose);

        await controller.load();

        expect(controller.state.errorMessage, _forbidden.message);
        expect(controller.state.offlineNotice, isNull);
      },
    );

    test('repository lùi về bản lưu khi mất mạng: dò mất mạng qua mục khác, '
        'giữ danh bạ đang có', () async {
      final repository = _FakeRepository(
        directs: [_summary('dm-1')],
        members: [_contact('user-1')],
      );
      final controller = _homeController(repository);
      addTearDown(controller.dispose);
      await controller.load();
      expect(controller.state.workspaceMembers.single.userId, 'user-1');

      repository.peopleFailure = _offline;
      expect(await controller.syncSilently(), isTrue);

      expect(controller.state.offlineNotice, isNotNull);
      expect(controller.state.errorMessage, isNull);
      expect(controller.state.workspaceMembers.single.userId, 'user-1');
      expect(controller.state.contacts.single.userId, 'user-1');
    });
  });

  group('thành viên nhóm lưu trên máy', () {
    late AppDatabase database;
    late ChannelMemberCacheDataSource memberCache;

    setUp(() {
      database = AppDatabase(createInMemoryDriftConnection());
      memberCache = ChannelMemberCacheDataSource(database, _instance);
    });
    tearDown(() => database.close());

    test('tải chi tiết thành công thì lưu thành viên; mất mạng giữa chừng '
        'dùng bản đã lưu', () async {
      final repository = _FakeRepository(
        channels: [_summary('group-1', kind: ConversationKind.channel)],
        channelMembers: [_member('user-1'), _member('user-2')],
      );
      final useCase = LoadChannelDetailUseCase(
        repository,
        memberCache: memberCache,
      );

      final first = await useCase.execute(
        workspaceId: 'ws',
        channelId: 'group-1',
      );
      expect(first.valueOrNull!.members, hasLength(2));
      expect(
        await memberCache.readMembers(workspaceId: 'ws', channelId: 'group-1'),
        hasLength(2),
      );

      repository.membersFailure = _offline;
      final second = await useCase.execute(
        workspaceId: 'ws',
        channelId: 'group-1',
      );
      expect(second.valueOrNull!.members.map((item) => item.userId), [
        'user-1',
        'user-2',
      ]);
      expect(second.valueOrNull!.membersErrorMessage, isNull);
    });

    test('mất quyền xem nhóm: bỏ thành viên đã lưu của nhóm', () async {
      await memberCache.saveMembers(
        workspaceId: 'ws',
        channelId: 'group-1',
        members: [_member('user-1')],
      );
      final useCase = LoadChannelDetailUseCase(
        _FakeRepository(failure: _forbidden),
        memberCache: memberCache,
      );

      final result = await useCase.execute(
        workspaceId: 'ws',
        channelId: 'group-1',
      );

      expect(result.failureOrNull?.kind, FailureKind.forbidden);
      expect(
        await memberCache.readMembers(workspaceId: 'ws', channelId: 'group-1'),
        isNull,
      );
    });

    test('mời / duyệt thành công thì thêm vào danh sách đã lưu', () async {
      await memberCache.saveMembers(
        workspaceId: 'ws',
        channelId: 'group-1',
        members: [_member('user-1')],
      );
      final repository = _FakeRepository();
      await InviteChannelMemberUseCase(
        repository,
        memberCache: memberCache,
      ).execute(workspaceId: 'ws', channelId: 'group-1', userId: 'user-2');
      await ApproveChannelJoinRequestUseCase(
        repository,
        memberCache: memberCache,
      ).execute(workspaceId: 'ws', channelId: 'group-1', userId: 'user-3');

      final cached = await memberCache.readMembers(
        workspaceId: 'ws',
        channelId: 'group-1',
      );
      expect(cached!.map((item) => item.userId), [
        'user-1',
        'user-2',
        'user-3',
      ]);

      // Máy chủ từ chối: bộ đệm không đổi.
      repository.failure = _forbidden;
      await InviteChannelMemberUseCase(
        repository,
        memberCache: memberCache,
      ).execute(workspaceId: 'ws', channelId: 'group-1', userId: 'user-4');
      expect(
        await memberCache.readMembers(workspaceId: 'ws', channelId: 'group-1'),
        hasLength(3),
      );
    });

    test('màn chi tiết nhóm: hiện thông tin + thành viên đã lưu trước rồi '
        'thay bằng dữ liệu máy chủ', () async {
      await memberCache.saveMembers(
        workspaceId: 'ws',
        channelId: 'group-1',
        members: [_member('user-cached')],
      );
      final repository = _FakeRepository(
        channels: [
          _summary('group-1', kind: ConversationKind.channel, title: 'Mới'),
        ],
        channelMembers: [_member('user-server')],
      )..gate = Completer<void>();
      final controller = _detailController(
        repository,
        memberCache: memberCache,
        listCache: _FakeListCache(
          channels: [
            _summary('group-1', kind: ConversationKind.channel, title: 'Cũ'),
          ],
        ),
      );
      addTearDown(controller.dispose);

      final loading = controller.load();
      await pumpEventQueue();
      expect(controller.state.isLoading, isFalse);
      expect(controller.state.channel?.title, 'Cũ');
      expect(controller.state.members.single.userId, 'user-cached');

      repository.gate!.complete();
      await loading;
      expect(controller.state.channel?.title, 'Mới');
      expect(controller.state.members.single.userId, 'user-server');
      expect(
        (await memberCache.readMembers(
          workspaceId: 'ws',
          channelId: 'group-1',
        ))!.single.userId,
        'user-server',
      );
    });

    test('màn chi tiết nhóm mất mạng: giữ bản đã lưu, báo nhẹ', () async {
      await memberCache.saveMembers(
        workspaceId: 'ws',
        channelId: 'group-1',
        members: [_member('user-cached')],
      );
      final controller = _detailController(
        _FakeRepository(failure: _offline),
        memberCache: memberCache,
        listCache: _FakeListCache(
          channels: [_summary('group-1', kind: ConversationKind.channel)],
        ),
      );
      addTearDown(controller.dispose);

      await controller.load();

      expect(controller.state.errorMessage, isNull);
      expect(controller.state.noticeMessage, isNotNull);
      expect(controller.state.channel?.id, 'group-1');
      expect(controller.state.members.single.userId, 'user-cached');
    });

    test('màn chi tiết nhóm: mất quyền thì bỏ bản đã lưu, hiện lỗi', () async {
      final controller = _detailController(
        _FakeRepository(failure: _forbidden),
        memberCache: memberCache,
        listCache: _FakeListCache(
          channels: [_summary('group-1', kind: ConversationKind.channel)],
        ),
      );
      addTearDown(controller.dispose);

      await controller.load();

      expect(controller.state.errorMessage, _forbidden.message);
      expect(controller.state.channel, isNull);
      expect(controller.state.members, isEmpty);
    });

    test('màn chi tiết nhóm chưa lưu gì, mất mạng: hiện lỗi như cũ', () async {
      final controller = _detailController(
        _FakeRepository(failure: _offline),
        memberCache: memberCache,
        listCache: _FakeListCache(),
      );
      addTearDown(controller.dispose);

      await controller.load();

      expect(controller.state.errorMessage, _offline.message);
      expect(controller.state.channel, isNull);
    });
  });
}

const _offline = Failure(
  kind: FailureKind.network,
  message: 'Không có kết nối mạng.',
);
const _forbidden = Failure(
  kind: FailureKind.forbidden,
  message: 'Bạn không có quyền.',
);

final _instance = InstanceScope(
  instanceId: '11111111-1111-4111-8111-111111111111',
  serverOrigin: Uri.parse('https://one.example'),
);

ConversationHomeController _homeController(
  _FakeRepository repository, {
  ConversationListCacheReader? cache,
}) {
  return ConversationHomeController(
    workspaceId: 'ws',
    loadConversationHomeUseCase: LoadConversationHomeUseCase(
      conversationRepository: repository,
      workspaceSessionRepository: const _FakeWorkspaceSession(),
    ),
    readCachedHomeUseCase: cache == null
        ? null
        : ReadCachedConversationHomeUseCase(cache),
    openDirectConversationUseCase: OpenDirectConversationUseCase(repository),
    openPrivateChannelSessionUseCase: OpenPrivateChannelSessionUseCase(
      repository,
    ),
    currentUserId: () => 'me',
  );
}

ChannelDetailController _detailController(
  _FakeRepository repository, {
  required ChannelMemberCache memberCache,
  required ConversationListCacheReader listCache,
}) {
  return ChannelDetailController(
    scope: const ChannelDetailScope(
      workspaceId: 'ws',
      channelId: 'group-1',
      initialTitle: 'Nhóm',
    ),
    loadChannelDetailUseCase: LoadChannelDetailUseCase(
      repository,
      memberCache: memberCache,
      listCache: listCache,
    ),
    requestJoinChannelUseCase: RequestJoinChannelUseCase(repository),
    inviteChannelMemberUseCase: InviteChannelMemberUseCase(repository),
    loadChannelJoinRequestsUseCase: LoadChannelJoinRequestsUseCase(repository),
    approveChannelJoinRequestUseCase: ApproveChannelJoinRequestUseCase(
      repository,
    ),
    rejectChannelJoinRequestUseCase: RejectChannelJoinRequestUseCase(
      repository,
    ),
    listChannelMediaUseCase: ListChannelMediaUseCase(_FakeMediaRepository()),
  );
}

ConversationSummary _summary(
  String id, {
  ConversationKind kind = ConversationKind.direct,
  DateTime? updatedAt,
  String title = 'Hội thoại',
}) {
  return ConversationSummary(
    id: id,
    workspaceId: 'ws',
    channelId: id,
    kind: kind,
    title: title,
    preview: '',
    updatedAt: updatedAt ?? DateTime.utc(2026, 11, 1),
    channelVisibility: kind == ConversationKind.direct
        ? ChannelVisibility.direct
        : ChannelVisibility.public,
    membershipStatus: MembershipStatus.active,
  );
}

ContactSummary _contact(String userId) {
  return ContactSummary(
    userId: userId,
    email: '$userId@example.com',
    username: userId,
    displayName: userId,
    status: 'active',
  );
}

ChannelMember _member(String userId) {
  return ChannelMember(
    channelId: 'group-1',
    userId: userId,
    email: '$userId@example.com',
    username: userId,
    displayName: userId,
    status: 'active',
    joinedAt: DateTime.utc(2026, 11, 1),
  );
}

final class _FakeListCache implements ConversationListCacheReader {
  _FakeListCache({this.directs, this.channels, this.throwOnRead = false});

  final List<ConversationSummary>? directs;
  final List<ConversationSummary>? channels;
  final bool throwOnRead;

  @override
  Future<List<ConversationSummary>?> readCachedDirectConversations({
    required String workspaceId,
  }) async {
    if (throwOnRead) throw StateError('hỏng');
    return directs;
  }

  @override
  Future<List<ConversationSummary>?> readCachedChannels({
    required String workspaceId,
  }) async {
    if (throwOnRead) throw StateError('hỏng');
    return channels;
  }
}

final class _FakeWorkspaceSession implements WorkspaceSessionRepository {
  const _FakeWorkspaceSession();

  @override
  Future<String?> readActiveWorkspaceId() async => 'ws';

  @override
  Future<void> resetRuntimeForSwitch({
    required String? previousWorkspaceId,
    required String nextWorkspaceId,
  }) async {}

  @override
  Future<void> saveActiveWorkspaceId(String workspaceId) async {}
}

final class _FakeMediaRepository extends Fake
    implements MessageAttachmentRepository {
  @override
  Future<Result<List<MessageAttachment>>> listChannelMedia({
    required String workspaceId,
    required String channelId,
    int limit = 500,
  }) async => const Success([]);
}

/// Máy chủ giả: [failure] = mọi lời gọi lỗi (mất mạng / mất quyền); [gate]
/// giữ lời gọi danh sách / thông tin nhóm tới khi test cho đi tiếp.
final class _FakeRepository extends Fake implements ConversationRepository {
  _FakeRepository({
    this.directs = const [],
    this.channels = const [],
    this.members = const [],
    this.channelMembers = const [],
    this.failure,
  });

  List<ConversationSummary> directs;
  List<ConversationSummary> channels;
  List<ContactSummary> members;
  List<ChannelMember> channelMembers;
  Failure? failure;
  Failure? peopleFailure;
  Failure? membersFailure;
  Completer<void>? gate;

  Future<Result<T>> _answer<T>(T value, {Failure? extra}) async {
    final error = failure ?? extra;
    return error == null ? Success(value) : FailureResult(error);
  }

  @override
  Future<Result<List<ConversationSummary>>> listDirectConversations({
    required String workspaceId,
  }) async {
    await gate?.future;
    return _answer(directs);
  }

  @override
  Future<Result<List<ConversationSummary>>> listChannels({
    required String workspaceId,
  }) => _answer(channels);

  @override
  Future<Result<List<ContactSummary>>> listContacts() =>
      _answer(const <ContactSummary>[], extra: peopleFailure);

  @override
  Future<Result<List<ContactSummary>>> listContactRequests({
    String status = 'all',
  }) => _answer(const <ContactSummary>[], extra: peopleFailure);

  @override
  Future<Result<List<ContactSummary>>> listWorkspaceMembers({
    required String workspaceId,
  }) => _answer(members, extra: peopleFailure);

  @override
  Future<Result<List<PresenceSummary>>> listPresence({
    required String workspaceId,
  }) => _answer(const <PresenceSummary>[], extra: peopleFailure);

  @override
  Future<Result<ConversationSummary>> getChannel({
    required String workspaceId,
    required String channelId,
  }) async {
    await gate?.future;
    final error = failure;
    if (error != null) return FailureResult(error);
    return Success(channels.firstWhere((item) => item.channelId == channelId));
  }

  @override
  Future<Result<List<ChannelMember>>> listMembers({
    required String workspaceId,
    required String channelId,
  }) => _answer(channelMembers, extra: membersFailure);

  @override
  Future<Result<List<ChatMessage>>> listPins({
    required String workspaceId,
    required String channelId,
  }) => _answer(const <ChatMessage>[]);

  @override
  Future<Result<List<ChannelFile>>> listFiles({
    required String workspaceId,
    int limit = 40,
  }) => _answer(const <ChannelFile>[]);

  @override
  Future<Result<List<ChannelMember>>> listJoinRequests({
    required String workspaceId,
    required String channelId,
  }) => _answer(const <ChannelMember>[]);

  @override
  Future<Result<ChannelMember>> addMember({
    required String workspaceId,
    required String channelId,
    required String userId,
  }) => _answer(_member(userId));

  @override
  Future<Result<ChannelMember>> approveJoinRequest({
    required String workspaceId,
    required String channelId,
    required String userId,
  }) => _answer(_member(userId));
}
