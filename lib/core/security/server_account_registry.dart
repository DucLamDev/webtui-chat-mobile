import 'dart:convert';

import 'instance_scope.dart';
import 'secure_key_value_store.dart';

final class ServerAccountSummary {
  const ServerAccountSummary({
    required this.baseUrl,
    required this.name,
    this.logoUrl,
  });

  final Uri baseUrl;
  final String name;
  final String? logoUrl;
}

final class SecureServerAccountRegistry {
  const SecureServerAccountRegistry(this._store);

  final SecureKeyValueStore _store;

  Future<List<ServerAccountSummary>> list() async {
    final records = await _readRecords();
    return records
        .map((record) {
          final baseUrl = Uri.tryParse(record['base_url']?.toString() ?? '');
          if (baseUrl == null || baseUrl.host.isEmpty) {
            return null;
          }
          return ServerAccountSummary(
            baseUrl: baseUrl,
            name: record['name']?.toString().trim().isNotEmpty == true
                ? record['name']!.toString()
                : baseUrl.host,
            logoUrl: record['logo_url']?.toString(),
          );
        })
        .whereType<ServerAccountSummary>()
        .toList(growable: false);
  }

  Future<void> rememberServer({
    required InstanceScope instanceScope,
    required Uri wsBaseUrl,
    required String name,
    String? logoUrl,
  }) async {
    final baseUrl = instanceScope.origin;
    final records = await _readRecords();
    final key = _serverKey(baseUrl);
    final existing = records
        .where((item) => item['base_url'] == key)
        .firstOrNull;
    final sameInstance =
        existing?['instance_id'] == instanceScope.instanceId &&
        existing?['instance_scope_id'] == instanceScope.storageId;
    final record = <String, Object?>{
      ...?existing,
      'base_url': key,
      'instance_id': instanceScope.instanceId,
      'instance_scope_id': instanceScope.storageId,
      'ws_base_url': wsBaseUrl.toString(),
      'name': name.trim().isEmpty ? baseUrl.host : name.trim(),
      'logo_url': logoUrl,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    if (!sameInstance) {
      // An origin can be reprovisioned with an unrelated database/zone UUID.
      // Never relabel credentials from the prior instance as belonging to the
      // replacement merely because its scheme/host/port are unchanged.
      record
        ..remove('access_token')
        ..remove('refresh_token')
        ..remove(_sessionPersistenceField);
    }
    records.removeWhere((item) => item['base_url'] == key);
    records.insert(0, record);
    await _writeRecords(records.take(10).toList(growable: false));
  }

  Future<void> stashActiveSession() async {
    final values = await Future.wait<String?>([
      _store.read(SecureStoreKey.instanceBaseUrl),
      _store.read(SecureStoreKey.activeInstanceScopeId),
      _store.read(SecureStoreKey.instanceId),
      _store.read(SecureStoreKey.sessionInstanceScopeId),
      _store.read(SecureStoreKey.sessionPersistence),
      _store.read(SecureStoreKey.accessToken),
      _store.read(SecureStoreKey.refreshToken),
    ]);
    final active = values[0];
    final uri = Uri.tryParse(active ?? '');
    if (uri == null || uri.host.isEmpty) {
      return;
    }
    final activeScopeId = values[1];
    final instanceId = values[2];
    final sessionScopeId = values[3];
    final persistence = values[4];
    if (activeScopeId == null ||
        activeScopeId.trim().isEmpty ||
        instanceId == null ||
        instanceId.trim().isEmpty ||
        sessionScopeId != activeScopeId ||
        persistence != durableSessionPersistenceValue) {
      return;
    }
    final accessToken = values[5];
    final refreshToken = values[6];
    if ((accessToken?.trim().isEmpty ?? true) &&
        (refreshToken?.trim().isEmpty ?? true)) {
      return;
    }
    final records = await _readRecords();
    final key = _serverKey(uri);
    final index = records.indexWhere((item) => item['base_url'] == key);
    final record = index >= 0
        ? records[index]
        : <String, Object?>{'base_url': key, 'name': uri.host};
    record['access_token'] = accessToken;
    record['refresh_token'] = refreshToken;
    record['instance_id'] = instanceId;
    record['instance_scope_id'] = activeScopeId;
    record[_sessionPersistenceField] = durableSessionPersistenceValue;
    record['updated_at'] = DateTime.now().toUtc().toIso8601String();
    if (index >= 0) {
      records.removeAt(index);
    }
    records.insert(0, record);
    await _writeRecords(records.take(10).toList(growable: false));
  }

  Future<bool> activate(InstanceScope instanceScope) async {
    final baseUrl = instanceScope.origin;
    final key = _serverKey(baseUrl);
    final records = await _readRecords();
    final match = records
        .where(
          (item) =>
              item['base_url'] == key &&
              item['instance_id'] == instanceScope.instanceId &&
              item['instance_scope_id'] == instanceScope.storageId,
        )
        .firstOrNull;
    final isDurable =
        match?[_sessionPersistenceField] == durableSessionPersistenceValue;
    final accessToken = isDurable && match != null
        ? match['access_token']?.toString().trim() ?? ''
        : '';
    final refreshToken = isDurable && match != null
        ? match['refresh_token']?.toString().trim() ?? ''
        : '';
    await Future.wait([
      _store.delete(SecureStoreKey.accessToken),
      _store.delete(SecureStoreKey.refreshToken),
      _store.delete(SecureStoreKey.sessionInstanceScopeId),
      _store.delete(SecureStoreKey.sessionPersistence),
    ]);
    if (accessToken.isEmpty && refreshToken.isEmpty) {
      return false;
    }
    if (accessToken.isNotEmpty) {
      await _store.write(SecureStoreKey.accessToken, accessToken);
    }
    if (refreshToken.isNotEmpty) {
      await _store.write(SecureStoreKey.refreshToken, refreshToken);
    }
    await _store.write(
      SecureStoreKey.sessionInstanceScopeId,
      instanceScope.storageId,
    );
    await _store.write(
      SecureStoreKey.sessionPersistence,
      durableSessionPersistenceValue,
    );
    return true;
  }

  Future<void> clearActiveSession() async {
    final active = await _store.read(SecureStoreKey.instanceBaseUrl);
    final uri = Uri.tryParse(active ?? '');
    if (uri == null || uri.host.isEmpty) {
      return;
    }
    final key = _serverKey(uri);
    final records = await _readRecords();
    final index = records.indexWhere((item) => item['base_url'] == key);
    if (index < 0) {
      return;
    }
    records[index].remove('access_token');
    records[index].remove('refresh_token');
    records[index].remove(_sessionPersistenceField);
    await _writeRecords(records);
  }

  Future<void> clearSessionForScopeId(String instanceScopeId) async {
    final normalizedScopeId = instanceScopeId.trim();
    if (normalizedScopeId.isEmpty) return;
    final records = await _readRecords();
    var changed = false;
    for (final record in records) {
      if (record['instance_scope_id'] != normalizedScopeId) continue;
      final removedAccessToken = record.remove('access_token') != null;
      final removedRefreshToken = record.remove('refresh_token') != null;
      final removedPersistence =
          record.remove(_sessionPersistenceField) != null;
      changed =
          removedAccessToken ||
          removedRefreshToken ||
          removedPersistence ||
          changed;
    }
    if (changed) {
      await _writeRecords(records);
    }
  }

  Future<bool> hasAnySavedSession() async {
    final records = await _readRecords();
    return records.any((record) {
      if (record[_sessionPersistenceField] != durableSessionPersistenceValue) {
        return false;
      }
      final accessToken = record['access_token']?.toString().trim() ?? '';
      final refreshToken = record['refresh_token']?.toString().trim() ?? '';
      return accessToken.isNotEmpty || refreshToken.isNotEmpty;
    });
  }

  Future<bool> hasDurableSessionForScopeId(String instanceScopeId) async {
    final normalizedScopeId = instanceScopeId.trim();
    if (normalizedScopeId.isEmpty) return false;
    final records = await _readRecords();
    return records.any((record) {
      if (record['instance_scope_id'] != normalizedScopeId ||
          record[_sessionPersistenceField] != durableSessionPersistenceValue) {
        return false;
      }
      final accessToken = record['access_token']?.toString().trim() ?? '';
      final refreshToken = record['refresh_token']?.toString().trim() ?? '';
      return accessToken.isNotEmpty || refreshToken.isNotEmpty;
    });
  }

  Future<List<Map<String, Object?>>> _readRecords() async {
    final raw = await _store.read(SecureStoreKey.serverAccounts);
    if (raw == null || raw.trim().isEmpty) {
      return [];
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        return [];
      }
      return decoded
          .whereType<Map>()
          .map(
            (item) => <String, Object?>{
              for (final entry in item.entries)
                entry.key.toString(): entry.value,
            },
          )
          .toList();
    } on FormatException {
      return [];
    }
  }

  Future<void> _writeRecords(List<Map<String, Object?>> records) {
    return _store.write(SecureStoreKey.serverAccounts, jsonEncode(records));
  }
}

String _serverKey(Uri uri) {
  return uri.toString().replaceFirst(RegExp(r'/$'), '');
}

const _sessionPersistenceField = 'session_persistence';
