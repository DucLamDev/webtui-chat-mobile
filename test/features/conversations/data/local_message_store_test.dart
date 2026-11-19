import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/core/database/app_database.dart';
import 'package:webtui_chat/core/security/instance_scope.dart';
import 'package:webtui_chat/features/conversations/data/datasources/local_message_store.dart';
import 'package:webtui_chat/features/conversations/domain/entities/chat_message.dart';
import 'package:webtui_chat/features/conversations/domain/entities/message_sync.dart';

final _instanceA = InstanceScope(
  instanceId: '11111111-1111-4111-8111-111111111111',
  serverOrigin: Uri.parse('https://a.example.com'),
);
final _instanceB = InstanceScope(
  instanceId: '22222222-2222-4222-8222-222222222222',
  serverOrigin: Uri.parse('https://b.example.com'),
);

final _base = DateTime.utc(2026, 11, 1, 8);

ChatMessage _message(
  String id, {
  int minute = 0,
  String body = '',
  String channelId = 'c1',
  DateTime? createdAt,
  DateTime? deletedAt,
  bool secret = false,
  Map<String, Object?> metadata = const {},
  List<MessageAttachment> attachments = const [],
}) {
  return ChatMessage(
    id: id,
    workspaceId: 'w1',
    channelId: channelId,
    kind: 'text',
    body: body.isEmpty ? 'tin $id' : body,
    createdAt: createdAt ?? _base.add(Duration(minutes: minute)),
    senderId: 'u1',
    deletedAt: deletedAt,
    isSecret: secret,
    metadata: metadata,
    attachments: attachments,
  );
}

void main() {
  late AppDatabase database;
  late LocalMessageStore store;

  setUp(() {
    database = AppDatabase(createInMemoryDriftConnection());
    store = LocalMessageStore(database, _instanceA);
  });

  tearDown(() => database.close());

  Future<void> save(List<ChatMessage> messages, {String channelId = 'c1'}) {
    return store.upsert(
      workspaceId: 'w1',
      channelId: channelId,
      messages: messages,
    );
  }

  Future<List<String>> latestIds({String channelId = 'c1', int limit = 50}) {
    return store
        .readLatest(workspaceId: 'w1', channelId: channelId, limit: limit)
        .then((messages) => [for (final m in messages) m.id]);
  }

  test('ghi rồi đọc: xếp cũ → mới, lấy đúng N tin mới nhất', () async {
    await save([
      _message('m3', minute: 3),
      _message('m1', minute: 1),
      _message('m2', minute: 2),
    ]);

    expect(await latestIds(), ['m1', 'm2', 'm3']);
    expect(await latestIds(limit: 2), ['m2', 'm3']);
  });

  test('thứ tự theo micro giây và mã tin khi trùng thời điểm', () async {
    final at = DateTime.utc(2026, 11, 1, 8, 0, 0, 0, 5);
    await save([
      _message('b', createdAt: at),
      _message('a', createdAt: at),
      _message(
        'early',
        createdAt: at.subtract(const Duration(microseconds: 1)),
      ),
    ]);
    expect(await latestIds(), ['early', 'a', 'b']);
  });

  test('readBefore: tin ngay trước mốc, cùng thời điểm thì theo mã', () async {
    final at = _base.add(const Duration(minutes: 5));
    await save([
      for (var i = 1; i <= 4; i++) _message('m$i', minute: i),
      _message('m5a', createdAt: at),
      _message('m5b', createdAt: at),
    ]);

    final before = await store.readBefore(
      workspaceId: 'w1',
      channelId: 'c1',
      beforeCreatedAt: at,
      beforeId: 'm5b',
      limit: 3,
    );
    expect([for (final m in before) m.id], ['m3', 'm4', 'm5a']);
  });

  test('upsert ghi đè theo mã tin, giữ đủ nội dung / tệp / cảm xúc', () async {
    await save([_message('m1', minute: 1, body: 'bản đầu')]);
    final edited = _message('m1', minute: 1, body: 'bản đã sửa').copyWith(
      editedAt: _base.add(const Duration(minutes: 9)),
      reactions: const [
        MessageReactionSummary(emoji: '👍', count: 2, reactedByMe: true),
      ],
    );
    await save([edited]);

    final stored = await store.readLatest(workspaceId: 'w1', channelId: 'c1');
    expect(stored, hasLength(1));
    expect(stored.single.body, 'bản đã sửa');
    expect(stored.single.editedAt, edited.editedAt);
    expect(stored.single.reactions.single.count, 2);
  });

  test(
    'tin đã xoá thì xoá dòng; tin bí mật / tạm / đang chạy dần không lưu',
    () async {
      await save([_message('m1', minute: 1), _message('m2', minute: 2)]);
      await save([
        _message('m1', minute: 1, deletedAt: _base),
        _message('secret', minute: 3, secret: true),
        _message('local-abc', minute: 4),
        _message('stream', minute: 5, metadata: const {'streaming': true}),
      ]);

      expect(await latestIds(), ['m2']);
    },
  );

  test('remove và removeCreatedUpTo (tính cả tin đúng mốc)', () async {
    await save([for (var i = 1; i <= 5; i++) _message('m$i', minute: i)]);

    await store.remove(workspaceId: 'w1', channelId: 'c1', messageIds: ['m5']);
    await store.removeCreatedUpTo(
      workspaceId: 'w1',
      channelId: 'c1',
      clearedAt: _base.add(const Duration(minutes: 2)),
    );

    expect(await latestIds(), ['m3', 'm4']);
  });

  group('search', () {
    setUp(() async {
      await save([
        _message('hop', minute: 1, body: 'Họp giao ban lúc 9 giờ'),
        _message('hop2', minute: 2, body: 'HỌP dự án mới'),
        _message('pct', minute: 3, body: 'Giảm 50% phí'),
        _message('under', minute: 4, body: 'tên tệp a_b'),
        _message('other', minute: 5, body: 'ăn trưa'),
        _message(
          'file',
          minute: 6,
          body: 'Đã gửi tệp đính kèm',
          attachments: [_attachment('Báo cáo quý.pdf')],
        ),
      ]);
    });

    Future<List<String>> find(String query) async {
      final results = await store.search(
        workspaceId: 'w1',
        channelId: 'c1',
        query: query,
      );
      return [for (final m in results) m.id];
    }

    test('không phân biệt dấu / hoa thường, mới nhất trước', () async {
      expect(await find('hop'), ['hop2', 'hop']);
      expect(await find('HỌP'), ['hop2', 'hop']);
    });

    test('nhiều từ: phải có đủ mọi từ, không cần đúng thứ tự', () async {
      expect(await find('ban giao'), ['hop']);
      expect(await find('họp trưa'), isEmpty);
    });

    test('% và _ là chữ thường, không phải ký tự đại diện', () async {
      expect(await find('50%'), ['pct']);
      expect(await find('%'), ['pct']);
      expect(await find('a_b'), ['under']);
      expect(await find('_'), ['under']);
    });

    test('tìm theo tên tệp đính kèm', () async {
      expect(await find('bao cao'), ['file']);
    });

    test('chữ rỗng thì không trả gì', () async {
      expect(await find('   '), isEmpty);
    });
  });

  test('cô lập theo máy chủ và theo cuộc trò chuyện', () async {
    final other = LocalMessageStore(database, _instanceB);
    await save([_message('a1', minute: 1, body: 'chung')]);
    await save([
      _message('c2', minute: 1, channelId: 'c2', body: 'chung'),
    ], channelId: 'c2');
    await other.upsert(
      workspaceId: 'w1',
      channelId: 'c1',
      messages: [_message('b1', minute: 1, body: 'chung')],
    );

    expect(await latestIds(), ['a1']);
    expect(await latestIds(channelId: 'c2'), ['c2']);
    expect(
      [
        for (final m in await other.readLatest(
          workspaceId: 'w1',
          channelId: 'c1',
        ))
          m.id,
      ],
      ['b1'],
    );
    expect(
      [
        for (final m in await store.search(
          workspaceId: 'w1',
          channelId: 'c1',
          query: 'chung',
        ))
          m.id,
      ],
      ['a1'],
    );

    await store.clearChannel(workspaceId: 'w1', channelId: 'c1');
    expect(await latestIds(), isEmpty);
    expect(await latestIds(channelId: 'c2'), ['c2']);
    expect(
      await other.readLatest(workspaceId: 'w1', channelId: 'c1'),
      hasLength(1),
    );
  });

  test(
    'trạng thái đồng bộ: ghi / đọc lại / xoá cùng cuộc trò chuyện',
    () async {
      expect(
        await store.readSyncState(workspaceId: 'w1', channelId: 'c1'),
        isNull,
      );
      final state = ChannelSyncState(
        workspaceId: 'w1',
        channelId: 'c1',
        changeCursor: 'cursor-1',
        oldestMessageId: 'm1',
        oldestCreatedAt: DateTime.utc(2026, 11, 1, 8, 0, 0, 0, 7),
        reachedBeginning: true,
        syncedAt: DateTime.utc(2026, 11, 2),
      );
      await store.writeSyncState(state);

      final read = await store.readSyncState(
        workspaceId: 'w1',
        channelId: 'c1',
      );
      expect(read?.changeCursor, 'cursor-1');
      expect(read?.oldestMessageId, 'm1');
      expect(read?.oldestCreatedAt, state.oldestCreatedAt);
      expect(read?.reachedBeginning, isTrue);
      expect(read?.syncedAt, state.syncedAt);

      await store.clearChannel(workspaceId: 'w1', channelId: 'c1');
      expect(
        await store.readSyncState(workspaceId: 'w1', channelId: 'c1'),
        isNull,
      );
    },
  );

  test(
    'ghi nhiều tin trong một giao dịch: lỗi giữa chừng thì không ghi gì',
    () async {
      await database.execute(
        'CREATE TRIGGER chan_bad BEFORE INSERT ON $localMessagesTable '
        "WHEN NEW.id = 'bad' BEGIN SELECT RAISE(ABORT, 'loi'); END;",
      );

      await expectLater(
        save([
          _message('m1', minute: 1),
          _message('bad', minute: 2),
          _message('m3', minute: 3),
        ]),
        throwsA(anything),
      );
      expect(await latestIds(), isEmpty);
    },
  );

  test(
    'đăng xuất (xoá theo tiền tố máy chủ) xoá cả tin và trạng thái',
    () async {
      await save([_message('m1', minute: 1)]);
      await store.writeSyncState(
        const ChannelSyncState(
          workspaceId: 'w1',
          channelId: 'c1',
          changeCursor: 'x',
        ),
      );
      await database.deleteScopesWithPrefix(_instanceA.storagePrefix);

      expect(await latestIds(), isEmpty);
      expect(
        await store.readSyncState(workspaceId: 'w1', channelId: 'c1'),
        isNull,
      );
    },
  );
}

MessageAttachment _attachment(String name) {
  return MessageAttachment(
    id: 'att-$name',
    workspaceId: 'w1',
    messageId: 'file',
    fileId: 'f-$name',
    createdAt: _base,
    file: UploadedMessageFile(
      id: 'f-$name',
      name: name,
      mimeType: 'application/pdf',
      byteSize: 10,
      downloadPath: '/files/f',
      createdAt: _base,
    ),
  );
}
