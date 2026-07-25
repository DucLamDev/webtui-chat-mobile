import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

final class AppDatabase implements QueryExecutorUser {
  AppDatabase(this._executor);

  final QueryExecutor _executor;
  bool _isOpen = false;
  bool _schemaReady = false;

  @override
  int get schemaVersion => 1;

  @override
  Future<void> beforeOpen(
    QueryExecutor executor,
    OpeningDetails details,
  ) async {}

  Future<void> putKeyValue({
    required String scope,
    required String key,
    required String value,
    DateTime? updatedAt,
  }) async {
    await _ensureOpen();

    await _executor.runInsert(
      '''
      INSERT INTO key_value_entries(scope, key, value, updated_at)
      VALUES (?, ?, ?, ?)
      ON CONFLICT(scope, key) DO UPDATE SET
        value = excluded.value,
        updated_at = excluded.updated_at;
      ''',
      [
        scope,
        key,
        value,
        (updatedAt ?? DateTime.now().toUtc()).toIso8601String(),
      ],
    );
  }

  Future<String?> readKeyValue({
    required String scope,
    required String key,
  }) async {
    await _ensureOpen();

    final rows = await _executor.runSelect(
      '''
      SELECT value
      FROM key_value_entries
      WHERE scope = ? AND key = ?
      LIMIT 1;
      ''',
      [scope, key],
    );

    if (rows.isEmpty) {
      return null;
    }
    return rows.single['value']?.toString();
  }

  Future<void> deleteKeyValue({
    required String scope,
    required String key,
  }) async {
    await _ensureOpen();

    await _executor.runDelete(
      '''
      DELETE FROM key_value_entries
      WHERE scope = ? AND key = ?;
      ''',
      [scope, key],
    );
  }

  Future<void> deleteScope(String scope) async {
    await _ensureOpen();

    await _executor.runDelete(
      '''
      DELETE FROM key_value_entries
      WHERE scope = ?;
      ''',
      [scope],
    );
  }

  Future<void> deleteScopesWithPrefix(String prefix) async {
    await _ensureOpen();

    await _executor.runDelete(
      '''
      DELETE FROM key_value_entries
      WHERE scope LIKE ?;
      ''',
      ['$prefix%'],
    );
  }

  Future<void> close() => _executor.close();

  Future<void> _ensureOpen() async {
    if (_isOpen) {
      return;
    }

    await _executor.ensureOpen(this);
    _isOpen = true;
    await _ensureSchema();
  }

  Future<void> _ensureSchema() async {
    if (_schemaReady) {
      return;
    }

    await _executor.runCustom('''
      CREATE TABLE IF NOT EXISTS key_value_entries (
        scope TEXT NOT NULL DEFAULT 'app',
        key TEXT NOT NULL,
        value TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        PRIMARY KEY (scope, key)
      );
    ''');
    _schemaReady = true;
  }
}

QueryExecutor createDriftConnection({String fileName = 'webtui_chat.sqlite'}) {
  return LazyDatabase(() async {
    final supportDirectory = await getApplicationSupportDirectory();
    final file = File(p.join(supportDirectory.path, fileName));
    return NativeDatabase.createInBackground(file);
  });
}

QueryExecutor createInMemoryDriftConnection() {
  return NativeDatabase.memory();
}
