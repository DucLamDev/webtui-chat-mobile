import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/core/database/app_database.dart';
import 'package:webtui_chat/core/error/failure.dart';
import 'package:webtui_chat/core/result/result.dart';
import 'package:webtui_chat/core/security/instance_scope.dart';
import 'package:webtui_chat/features/conversations/application/message_sync_service.dart';
import 'package:webtui_chat/features/conversations/data/datasources/local_message_store.dart';
import 'package:webtui_chat/features/conversations/domain/entities/chat_message.dart';
import 'package:webtui_chat/features/conversations/domain/entities/message_sync.dart';
import 'package:webtui_chat/features/conversations/domain/repositories/conversation_repository.dart';
import 'package:webtui_chat/features/conversations/domain/repositories/message_changes_repository.dart';

final _now = DateTime.utc(2026, 11, 19, 12);

final _scope = InstanceScope(
  instanceId: '11111111-1111-4111-8111-111111111111',
  serverOrigin: Uri.parse('https://chat.example.com'),
);

/// Tin tạo [daysAgo] ngày (+ [minute] phút) trước [_now].
ChatMessage _msg(
  String id, {
  double daysAgo = 0,
  int minute = 0,
  String body = '',
  DateTime? deletedAt,
}) {
  final at = _now
      .subtract(Duration(minutes: (daysAgo * 24 * 60).round()))
      .add(Duration(minutes: minute));
  return ChatMessage(
    id: id,
    workspaceId: 'w1',
    channelId: 'c1',
    kind: 'text',
    body: deletedAt != null ? '' : (body.isEmpty ? 'tin $id' : body),
    createdAt: at,
    senderId: 'u1',
    deletedAt: deletedAt,
  );
}

ChatMessage _tombstone(ChatMessage message) => ChatMessage(
  id: message.id,
  workspaceId: message.workspaceId,
  channelId: message.channelId,
  kind: message.kind,
  body: '',
  createdAt: message.createdAt,
  deletedAt: _now,
);

Failure _failure(FailureKind kind) => Failure(kind: kind, message: kind.name);

final class _FakeChanges implements MessageChangesRepository {
  _FakeChanges(this.log);

  final List<String> log;

  /// Trả lời theo `since` (null = mốc bắt đầu).
  Result<MessageChangesPage> Function(String? since) respond = (since) =>
      const Success(MessageChangesPage(messages: [], nextCursor: 'c0'));

  @override
  Future<Result<MessageChangesPage>> listMessageChanges({
    required String workspaceId,
    required String channelId,
    String? since,
    int limit = 200,
  }) async {
    log.add('changes:${since ?? '-'}');
    return respond(since);
  }
}

final class _FakeMessages implements ConversationRepository {
  _FakeMessages(this.log);

  final List<String> log;
  final List<({String? beforeId, int limit})> pageCalls = [];

  Result<MessagePage> Function(String? beforeId, int limit) respond =
      (beforeId, limit) => const Success(MessagePage(messages: []));

  @override
  Future<Result<MessagePage>> listMessagePage({
    required String workspaceId,
    required String channelId,
    int limit = 50,
    String? beforeId,
  }) async {
    log.add('page:${beforeId ?? '-'}');
    pageCalls.add((beforeId: beforeId, limit: limit));
    return respond(beforeId, limit);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late AppDatabase database;
  late LocalMessageStore store;
  late List<String> log;
  late _FakeChanges changes;
  late _FakeMessages messages;

  MessageSyncService service({int maxChangePages = 25}) => MessageSyncService(
    local: store,
    changes: changes,
    messages: messages,
    now: () => _now,
    pageSize: 3,
    maxChangePages: maxChangePages,
    prefetchPageSize: 2,
    maxPrefetchPages: 10,
  );

  setUp(() {
    database = AppDatabase(createInMemoryDriftConnection());
    store = LocalMessageStore(database, _scope);
    log = [];
    changes = _FakeChanges(log);
    messages = _FakeMessages(log);
  });

  tearDown(() => database.close());

  Future<List<String>> storedIds() async => [
    for (final m in await store.readLatest(
      workspaceId: 'w1',
      channelId: 'c1',
      limit: 1000,
    ))
      m.id,
  ];

  Future<ChannelSyncState?> syncState() =>
      store.readSyncState(workspaceId: 'w1', channelId: 'c1');

  Future<MessageSyncResult> runSync(MessageSyncService sync) =>
      sync.sync(workspaceId: 'w1', channelId: 'c1');

  /// Đồng bộ lần đầu với trang mới nhất m2, m3, m4 (còn tin cũ hơn).
  Future<void> seed(MessageSyncService sync) async {
    messages.respond = (beforeId, limit) => Success(
      MessagePage(
        messages: [
          _msg('m4', minute: 4),
          _msg('m3', minute: 3),
          _msg('m2', minute: 2),
        ],
        hasMore: true,
      ),
    );
    changes.respond = (since) => Success(
      MessageChangesPage(messages: const [], nextCursor: since ?? 'c0'),
    );
    await runSync(sync);
    log.clear();
  }

  group('sync lần đầu', () {
    test('lấy mốc luồng thay đổi TRƯỚC rồi mới tải trang mới nhất', () async {
      final sync = service();
      messages.respond = (beforeId, limit) => Success(
        MessagePage(
          messages: [_msg('m2', minute: 2), _msg('m1', minute: 1)],
          hasMore: true,
        ),
      );
      changes.respond = (since) => Success(
        MessageChangesPage(
          messages: const [],
          nextCursor: since == null ? 'c0' : 'c1',
        ),
      );

      final result = await runSync(sync);

      expect(log, ['changes:-', 'page:-', 'changes:c0']);
      expect(result.isSynced, isTrue);
      expect(result.reset, isTrue);
      expect(await storedIds(), ['m1', 'm2']);
      final state = await syncState();
      expect(state?.changeCursor, 'c1');
      expect(state?.oldestMessageId, 'm1');
      expect(state?.reachedBeginning, isFalse);
      expect(state?.syncedAt, _now);
    });

    test('trang mới nhất hết tin (has_more = false) → đã tới đầu', () async {
      final sync = service();
      messages.respond = (beforeId, limit) =>
          Success(MessagePage(messages: [_msg('m1')]));

      await runSync(sync);

      expect((await syncState())?.reachedBeginning, isTrue);
    });

    test('hai lượt cùng lúc chỉ chạy một lần', () async {
      final sync = service();
      final first = runSync(sync);
      final second = runSync(sync);
      expect(identical(first, second), isTrue);
      await first;
      expect(log.where((entry) => entry == 'changes:-'), hasLength(1));
    });
  });

  group('luồng thay đổi', () {
    test(
      'áp bia mộ / sửa / tin mới; tin cũ hơn đoạn đã lưu không ghi',
      () async {
        final sync = service();
        await seed(sync);
        changes.respond = (since) => Success(
          MessageChangesPage(
            messages: [
              _tombstone(_msg('m3', minute: 3)),
              _msg('m4', minute: 4, body: 'đã sửa'),
              _msg('m5', minute: 5),
              // Sửa một tin cũ chưa lưu: không được ghi (sẽ tạo lỗ).
              _msg('old', minute: -30, body: 'cũ đã sửa'),
            ],
            nextCursor: 'c1',
          ),
        );

        final result = await runSync(sync);

        expect(log, ['changes:c0']);
        expect(result.reset, isFalse);
        expect(await storedIds(), ['m2', 'm4', 'm5']);
        final stored = await store.readLatest(
          workspaceId: 'w1',
          channelId: 'c1',
        );
        expect(stored.firstWhere((m) => m.id == 'm4').body, 'đã sửa');
        expect([for (final m in result.deleted) m.id], ['m3']);
        expect([for (final m in result.upserted) m.id], ['m4', 'm5']);
        expect((await syncState())?.changeCursor, 'c1');
      },
    );

    test(
      'cleared_at: bỏ tin tạo trước / bằng mốc, đoạn đã lưu là trọn vẹn',
      () async {
        final sync = service();
        await seed(sync);
        final clearedAt = _msg('m3', minute: 3).createdAt;
        changes.respond = (since) => Success(
          MessageChangesPage(
            messages: const [],
            nextCursor: 'c1',
            clearedAt: clearedAt,
          ),
        );

        final result = await runSync(sync);

        expect(await storedIds(), ['m4']);
        expect(result.clearedAt, clearedAt);
        final state = await syncState();
        expect(state?.reachedBeginning, isTrue);
        expect(state?.oldestCreatedAt, isNull);
      },
    );

    test('has_more: hỏi tiếp từng trang theo next_cursor', () async {
      final sync = service();
      await seed(sync);
      changes.respond = (since) => switch (since) {
        'c0' => Success(
          MessageChangesPage(
            messages: [_msg('m5', minute: 5)],
            nextCursor: 'c1',
            hasMore: true,
          ),
        ),
        'c1' => Success(
          MessageChangesPage(
            messages: [_msg('m6', minute: 6)],
            nextCursor: 'c2',
            hasMore: true,
          ),
        ),
        _ => const Success(MessageChangesPage(messages: [], nextCursor: 'c3')),
      };

      await runSync(sync);

      expect(log, ['changes:c0', 'changes:c1', 'changes:c2']);
      expect(await storedIds(), ['m2', 'm3', 'm4', 'm5', 'm6']);
      expect((await syncState())?.changeCursor, 'c3');
    });

    test(
      'vượt giới hạn số trang → xoá tin trên máy và đồng bộ lại từ đầu',
      () async {
        final sync = service(maxChangePages: 2);
        await seed(sync);
        var counter = 0;
        changes.respond = (since) {
          if (since == null) {
            return const Success(
              MessageChangesPage(messages: [], nextCursor: 'fresh'),
            );
          }
          if (since == 'fresh') {
            return const Success(
              MessageChangesPage(messages: [], nextCursor: 'done'),
            );
          }
          counter++;
          return Success(
            MessageChangesPage(
              messages: [_msg('x$counter', minute: 10 + counter)],
              nextCursor: 'k$counter',
              hasMore: true,
            ),
          );
        };
        messages.respond = (beforeId, limit) => Success(
          MessagePage(
            messages: [_msg('n2', minute: 20), _msg('n1', minute: 19)],
            hasMore: true,
          ),
        );

        final result = await runSync(sync);

        expect(log, [
          'changes:c0',
          'changes:k1',
          'changes:-',
          'page:-',
          'changes:fresh',
        ]);
        expect(result.isSynced, isTrue);
        expect(result.reset, isTrue);
        expect(await storedIds(), ['n1', 'n2']);
        final state = await syncState();
        expect(state?.changeCursor, 'done');
        expect(state?.oldestMessageId, 'n1');
      },
    );

    test(
      'lỗi mạng giữa chừng: báo lỗi, giữ tin trên máy và phần đã áp',
      () async {
        final sync = service();
        await seed(sync);
        changes.respond = (since) => since == 'c0'
            ? Success(
                MessageChangesPage(
                  messages: [_msg('m5', minute: 5)],
                  nextCursor: 'c1',
                  hasMore: true,
                ),
              )
            : FailureResult(_failure(FailureKind.network));

        final result = await runSync(sync);

        expect(result.status, MessageSyncStatus.failed);
        expect(result.failure?.kind, FailureKind.network);
        expect([for (final m in result.upserted) m.id], ['m5']);
        expect(await storedIds(), ['m2', 'm3', 'm4', 'm5']);
        expect((await syncState())?.changeCursor, 'c1');
      },
    );

    test('máy chủ cũ (404) → không hỗ trợ, không ghi gì', () async {
      final sync = service();
      changes.respond = (since) =>
          FailureResult(_failure(FailureKind.notFound));

      final result = await runSync(sync);

      expect(result.isUnsupported, isTrue);
      expect(sync.isUnsupported(workspaceId: 'w1', channelId: 'c1'), isTrue);
      expect(log, ['changes:-']);
      expect(await storedIds(), isEmpty);
      expect(await syncState(), isNull);
    });
  });

  group('prefetchHistory', () {
    /// Máy chủ có tin mỗi ngày một tin, từ 0 tới [days] ngày trước.
    void serveDays(int days) {
      final all = [
        for (var d = 0; d <= days; d++) _msg('d$d', daysAgo: d.toDouble()),
      ];
      messages.respond = (beforeId, limit) {
        final start = beforeId == null
            ? 0
            : all.indexWhere((m) => m.id == beforeId) + 1;
        final page = all.skip(start).take(limit).toList();
        return Success(
          MessagePage(messages: page, hasMore: start + limit < all.length),
        );
      };
    }

    test('tải tiếp tới khi tin cũ nhất cũ hơn 30 ngày', () async {
      final sync = MessageSyncService(
        local: store,
        changes: changes,
        messages: messages,
        now: () => _now,
        pageSize: 3,
        prefetchPageSize: 10,
        maxPrefetchPages: 20,
      );
      serveDays(60);
      await runSync(sync);
      log.clear();

      await sync.prefetchHistory(workspaceId: 'w1', channelId: 'c1');

      // d0..d2 lúc đồng bộ; mỗi trang 10 tin: d12, d22, d32 (> 30 ngày) → dừng.
      expect(log, ['page:d2', 'page:d12', 'page:d22']);
      final state = await syncState();
      expect(state?.oldestMessageId, 'd32');
      expect(state?.reachedBeginning, isFalse);
      expect(await storedIds(), hasLength(33));
    });

    test('hết tin thì dừng và đánh dấu đã tới đầu', () async {
      final sync = service();
      serveDays(5);
      await runSync(sync);
      log.clear();

      await sync.prefetchHistory(workspaceId: 'w1', channelId: 'c1');

      expect(log, ['page:d2', 'page:d4']);
      expect((await syncState())?.reachedBeginning, isTrue);
      expect(await storedIds(), hasLength(6));
    });

    test('lỗi thì dừng, không đổi mốc', () async {
      final sync = service();
      serveDays(60);
      await runSync(sync);
      log.clear();
      messages.respond = (beforeId, limit) =>
          FailureResult(_failure(FailureKind.network));

      await sync.prefetchHistory(workspaceId: 'w1', channelId: 'c1');

      expect(log, ['page:d2']);
      expect((await syncState())?.oldestMessageId, 'd2');
    });

    test('chưa đồng bộ thì không tải trước', () async {
      await service().prefetchHistory(workspaceId: 'w1', channelId: 'c1');
      expect(log, isEmpty);
    });
  });

  group('loadOlder', () {
    test(
      'đọc trên máy trước, hết đoạn đã lưu mới hỏi máy chủ và nối dài',
      () async {
        final sync = service();
        final all = [
          for (var i = 20; i >= 1; i--)
            _msg('m${i.toString().padLeft(2, '0')}', minute: i),
        ];
        messages.respond = (beforeId, limit) {
          final start = beforeId == null
              ? 0
              : all.indexWhere((m) => m.id == beforeId) + 1;
          return Success(
            MessagePage(
              messages: all.skip(start).take(limit).toList(),
              hasMore: start + limit < all.length,
            ),
          );
        };
        await runSync(sync); // lưu m18..m20
        log.clear();
        final m20 = all.first;

        // Trên máy đủ 2 tin trước m20: không hỏi máy chủ.
        final local = await sync.loadOlder(
          workspaceId: 'w1',
          channelId: 'c1',
          beforeCreatedAt: m20.createdAt,
          beforeId: m20.id,
          limit: 2,
        );
        expect(
          [for (final m in local.valueOrNull!.messages) m.id],
          ['m18', 'm19'],
        );
        expect(local.valueOrNull!.hasMore, isTrue);
        expect(log, isEmpty);

        // Cần 5 tin: trên máy chỉ còn 2 → hỏi máy chủ trước tin cũ nhất (m18).
        final mixed = await sync.loadOlder(
          workspaceId: 'w1',
          channelId: 'c1',
          beforeCreatedAt: m20.createdAt,
          beforeId: m20.id,
          limit: 5,
        );
        expect(log, ['page:m18']);
        expect(
          [for (final m in mixed.valueOrNull!.messages) m.id],
          ['m13', 'm14', 'm15', 'm16', 'm17', 'm18', 'm19'],
        );
        expect((await syncState())?.oldestMessageId, 'm13');
        expect(await storedIds(), hasLength(8));
      },
    );

    test('đã tới đầu cuộc trò chuyện: không hỏi máy chủ', () async {
      final sync = service();
      messages.respond = (beforeId, limit) => Success(
        MessagePage(messages: [_msg('m2', minute: 2), _msg('m1', minute: 1)]),
      );
      await runSync(sync);
      log.clear();
      final m2 = _msg('m2', minute: 2);

      final result = await sync.loadOlder(
        workspaceId: 'w1',
        channelId: 'c1',
        beforeCreatedAt: m2.createdAt,
        beforeId: 'm2',
      );

      expect([for (final m in result.valueOrNull!.messages) m.id], ['m1']);
      expect(result.valueOrNull!.hasMore, isFalse);
      expect(log, isEmpty);
    });

    test(
      'máy chủ lỗi: có tin trên máy thì vẫn trả, không thì báo lỗi',
      () async {
        final sync = service();
        await seed(sync);
        messages.respond = (beforeId, limit) =>
            FailureResult(_failure(FailureKind.network));
        final m4 = _msg('m4', minute: 4);
        final m2 = _msg('m2', minute: 2);

        final partial = await sync.loadOlder(
          workspaceId: 'w1',
          channelId: 'c1',
          beforeCreatedAt: m4.createdAt,
          beforeId: 'm4',
          limit: 10,
        );
        expect(
          [for (final m in partial.valueOrNull!.messages) m.id],
          ['m2', 'm3'],
        );

        final none = await sync.loadOlder(
          workspaceId: 'w1',
          channelId: 'c1',
          beforeCreatedAt: m2.createdAt,
          beforeId: 'm2',
        );
        expect(none.failureOrNull?.kind, FailureKind.network);
      },
    );
  });

  test('ghi tin realtime: chỉ khi đã đồng bộ và trong đoạn đã lưu', () async {
    final sync = service();
    await sync.recordMessages(
      workspaceId: 'w1',
      channelId: 'c1',
      messages: [_msg('early', minute: 9)],
    );
    expect(await storedIds(), isEmpty);

    await seed(sync);
    await sync.recordMessages(
      workspaceId: 'w1',
      channelId: 'c1',
      messages: [
        _msg('m5', minute: 5),
        _msg('old', minute: -10),
        _msg('m3', minute: 3, deletedAt: _now),
      ],
    );
    expect(await storedIds(), ['m2', 'm4', 'm5']);

    await sync.forgetMessages(
      workspaceId: 'w1',
      channelId: 'c1',
      messageIds: ['m5'],
    );
    expect(await storedIds(), ['m2', 'm4']);
  });
}
