import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/core/database/app_database.dart';

void main() {
  test('stores key value metadata in Drift foundation database', () async {
    final database = AppDatabase(createInMemoryDriftConnection());
    addTearDown(database.close);

    await database.putKeyValue(
      scope: 'workspace:w1',
      key: 'cursor',
      value: 'cursor-1',
    );

    expect(
      await database.readKeyValue(scope: 'workspace:w1', key: 'cursor'),
      'cursor-1',
    );
  });

  Future<void> insertMessage(
    SqlRunner sql, {
    required String scope,
    required String id,
  }) {
    return sql.execute(
      'INSERT INTO $localMessagesTable '
      '(scope, workspace_id, channel_id, id, created_at_us, payload) '
      'VALUES (?, ?, ?, ?, ?, ?)',
      [scope, 'w1', 'c1', id, 1, '{}'],
    );
  }

  Future<List<String>> messageIds(AppDatabase database) async {
    final rows = await database.select(
      'SELECT id FROM $localMessagesTable ORDER BY id',
    );
    return [for (final row in rows) row['id']! as String];
  }

  test('giao dịch lỗi thì bỏ hết, xong thì ghi đủ', () async {
    final database = AppDatabase(createInMemoryDriftConnection());
    addTearDown(database.close);

    await expectLater(
      database.transaction((sql) async {
        await insertMessage(
          sql,
          scope: 'instance_v2:a:message_store',
          id: 'm1',
        );
        throw StateError('lỗi giữa chừng');
      }),
      throwsStateError,
    );
    expect(await messageIds(database), isEmpty);

    final written = await database.transaction((sql) async {
      await insertMessage(sql, scope: 'instance_v2:a:message_store', id: 'm1');
      await insertMessage(sql, scope: 'instance_v2:a:message_store', id: 'm2');
      return 2;
    });
    expect(written, 2);
    expect(await messageIds(database), ['m1', 'm2']);
  });

  test(
    'đăng xuất (xoá theo tiền tố máy chủ) xoá luôn tin lưu trên máy',
    () async {
      final database = AppDatabase(createInMemoryDriftConnection());
      addTearDown(database.close);

      await insertMessage(
        database,
        scope: 'instance_v2:a:message_store',
        id: 'm1',
      );
      await insertMessage(
        database,
        scope: 'instance_v2:b:message_store',
        id: 'm2',
      );
      // `_` trong tiền tố không được thành ký tự đại diện (LIKE sẽ khớp nhầm).
      await insertMessage(
        database,
        scope: 'instanceXv2:a:message_store',
        id: 'm3',
      );
      await database.execute(
        'INSERT INTO $localChannelSyncTable (scope, workspace_id, channel_id) '
        'VALUES (?, ?, ?)',
        ['instance_v2:a:message_store', 'w1', 'c1'],
      );

      await database.deleteScopesWithPrefix('instance_v2:a:');

      expect(await messageIds(database), ['m2', 'm3']);
      expect(
        await database.select('SELECT scope FROM $localChannelSyncTable'),
        isEmpty,
      );
    },
  );
}
