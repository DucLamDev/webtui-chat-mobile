import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/core/database/app_database.dart';
import 'package:webtui_chat/core/security/instance_scope.dart';
import 'package:webtui_chat/features/conversations/data/datasources/channel_member_cache_data_source.dart';
import 'package:webtui_chat/features/conversations/data/datasources/conversation_cache_data_source.dart';
import 'package:webtui_chat/features/conversations/data/repositories/caching_conversation_repository.dart';
import 'package:webtui_chat/features/conversations/domain/entities/chat_message.dart';
import 'package:webtui_chat/features/conversations/domain/entities/conversation_summary.dart';
import 'package:webtui_chat/features/conversations/domain/repositories/conversation_repository.dart';
import 'package:webtui_chat/features/settings/application/use_cases/cache_maintenance_use_cases.dart';

void main() {
  test(
    'repository có bộ đệm đọc danh sách đã lưu mà không gọi máy chủ',
    () async {
      final database = AppDatabase(createInMemoryDriftConnection());
      addTearDown(database.close);
      final cache = ConversationCacheDataSource(database, _instanceA);
      // Máy chủ giả ném lỗi với mọi lời gọi: đọc bộ đệm không được chạm tới.
      final repository = CachingConversationRepository(
        remote: _UnreachableRemote(),
        cache: cache,
      );

      expect(await repository.readCachedChannels(workspaceId: 'ws'), isNull);
      expect(
        await repository.readCachedDirectConversations(workspaceId: 'ws'),
        isNull,
      );

      await cache.saveChannels(
        workspaceId: 'ws',
        items: [
          ConversationSummary(
            id: 'group-1',
            workspaceId: 'ws',
            channelId: 'group-1',
            kind: ConversationKind.channel,
            title: 'Nhóm',
            preview: '',
            updatedAt: DateTime.utc(2026, 11, 1),
          ),
        ],
      );
      final channels = await repository.readCachedChannels(workspaceId: 'ws');
      expect(channels!.single.id, 'group-1');
    },
  );

  test('ghi rồi đọc lại đủ thông tin thành viên', () async {
    final database = AppDatabase(createInMemoryDriftConnection());
    addTearDown(database.close);
    final cache = ChannelMemberCacheDataSource(database, _instanceA);

    expect(
      await cache.readMembers(workspaceId: 'ws', channelId: 'group-1'),
      isNull,
    );

    await cache.saveMembers(
      workspaceId: 'ws',
      channelId: 'group-1',
      members: [
        _member(
          'user-1',
          name: 'Lâm Đức',
          avatarUrl: 'https://one.example/a.png',
          gender: 'male',
          lastReadMessageId: 'm-9',
          lastReadAt: DateTime.utc(2026, 11, 19, 8),
        ),
        _member('user-2', name: 'Chị Kha'),
      ],
    );

    final members = await cache.readMembers(
      workspaceId: 'ws',
      channelId: 'group-1',
    );
    expect(members!.map((item) => item.userId), ['user-1', 'user-2']);
    final first = members.first;
    expect(first.channelId, 'group-1');
    expect(first.displayName, 'Lâm Đức');
    expect(first.email, 'user-1@example.com');
    expect(first.username, 'user-1');
    expect(first.status, 'active');
    expect(first.joinedAt, DateTime.utc(2026, 11, 1));
    expect(first.avatarUrl, 'https://one.example/a.png');
    expect(first.gender, 'male');
    expect(first.lastReadMessageId, 'm-9');
    expect(first.lastReadAt, DateTime.utc(2026, 11, 19, 8));
    expect(members.last.avatarUrl, isNull);
    expect(members.last.lastReadAt, isNull);
  });

  test('cô lập theo máy chủ, workspace và nhóm', () async {
    final database = AppDatabase(createInMemoryDriftConnection());
    addTearDown(database.close);
    final serverA = ChannelMemberCacheDataSource(database, _instanceA);
    final serverB = ChannelMemberCacheDataSource(database, _instanceB);

    await serverA.saveMembers(
      workspaceId: 'ws',
      channelId: 'group-1',
      members: [_member('user-a')],
    );
    await serverB.saveMembers(
      workspaceId: 'ws',
      channelId: 'group-1',
      members: [_member('user-b')],
    );

    expect(
      (await serverA.readMembers(
        workspaceId: 'ws',
        channelId: 'group-1',
      ))!.map((item) => item.userId),
      ['user-a'],
    );
    expect(
      (await serverB.readMembers(
        workspaceId: 'ws',
        channelId: 'group-1',
      ))!.map((item) => item.userId),
      ['user-b'],
    );
    expect(
      await serverA.readMembers(workspaceId: 'ws', channelId: 'group-2'),
      isNull,
    );
    expect(
      await serverA.readMembers(workspaceId: 'ws-2', channelId: 'group-1'),
      isNull,
    );

    // Đăng xuất máy chủ A (xoá theo tiền tố máy chủ) không đụng máy chủ B.
    await database.deleteScopesWithPrefix(_instanceA.storagePrefix);
    expect(
      await serverA.readMembers(workspaceId: 'ws', channelId: 'group-1'),
      isNull,
    );
    expect(
      await serverB.readMembers(workspaceId: 'ws', channelId: 'group-1'),
      isNotNull,
    );
  });

  test('"Xoá bộ nhớ đệm" của workspace xoá cả thành viên đã lưu', () async {
    final database = AppDatabase(createInMemoryDriftConnection());
    addTearDown(database.close);
    final cache = ChannelMemberCacheDataSource(database, _instanceA);
    await cache.saveMembers(
      workspaceId: 'ws',
      channelId: 'group-1',
      members: [_member('user-1')],
    );

    await ClearWorkspaceCacheUseCase(
      database,
      _instanceA,
    ).execute(workspaceId: 'ws');

    expect(
      await cache.readMembers(workspaceId: 'ws', channelId: 'group-1'),
      isNull,
    );
  });

  test('upsert thêm / thay một người; chưa lưu thì bỏ qua', () async {
    final database = AppDatabase(createInMemoryDriftConnection());
    addTearDown(database.close);
    final cache = ChannelMemberCacheDataSource(database, _instanceA);

    await cache.upsertMember(
      workspaceId: 'ws',
      channelId: 'group-1',
      member: _member('user-3'),
    );
    expect(
      await cache.readMembers(workspaceId: 'ws', channelId: 'group-1'),
      isNull,
    );

    await cache.saveMembers(
      workspaceId: 'ws',
      channelId: 'group-1',
      members: [
        _member('user-1'),
        _member('user-2', name: 'Tên cũ'),
      ],
    );
    // Hai lần thêm chạy cùng lúc (ghi tuần tự): không mất người nào.
    await Future.wait([
      cache.upsertMember(
        workspaceId: 'ws',
        channelId: 'group-1',
        member: _member('user-2', name: 'Tên mới'),
      ),
      cache.upsertMember(
        workspaceId: 'ws',
        channelId: 'group-1',
        member: _member('user-3'),
      ),
    ]);

    final members = await cache.readMembers(
      workspaceId: 'ws',
      channelId: 'group-1',
    );
    expect(members!.map((item) => item.userId), ['user-1', 'user-2', 'user-3']);
    expect(members[1].displayName, 'Tên mới');

    await cache.removeMembers(workspaceId: 'ws', channelId: 'group-1');
    expect(
      await cache.readMembers(workspaceId: 'ws', channelId: 'group-1'),
      isNull,
    );
  });

  test('bản lưu hỏng / mã rỗng: coi như chưa lưu', () async {
    final database = AppDatabase(createInMemoryDriftConnection());
    addTearDown(database.close);
    final cache = ChannelMemberCacheDataSource(database, _instanceA);
    await database.putKeyValue(
      scope: _instanceA.localScope('conversation_cache:ws'),
      key: 'channel_members:group-1',
      value: '{hong',
    );

    expect(
      await cache.readMembers(workspaceId: 'ws', channelId: 'group-1'),
      isNull,
    );
    await cache.saveMembers(
      workspaceId: ' ',
      channelId: 'group-1',
      members: [_member('user-1')],
    );
    expect(
      await cache.readMembers(workspaceId: ' ', channelId: 'group-1'),
      isNull,
    );
  });
}

ChannelMember _member(
  String userId, {
  String? name,
  String? avatarUrl,
  String? gender,
  String? lastReadMessageId,
  DateTime? lastReadAt,
}) {
  return ChannelMember(
    channelId: 'group-1',
    userId: userId,
    email: '$userId@example.com',
    username: userId,
    displayName: name ?? userId,
    status: 'active',
    joinedAt: DateTime.utc(2026, 11, 1),
    avatarUrl: avatarUrl,
    gender: gender,
    lastReadMessageId: lastReadMessageId,
    lastReadAt: lastReadAt,
  );
}

final _instanceA = InstanceScope(
  instanceId: '11111111-1111-4111-8111-111111111111',
  serverOrigin: Uri.parse('https://one.example'),
);

final _instanceB = InstanceScope(
  instanceId: '22222222-2222-4222-8222-222222222222',
  serverOrigin: Uri.parse('https://two.example'),
);

final class _UnreachableRemote extends Fake implements ConversationRepository {}
