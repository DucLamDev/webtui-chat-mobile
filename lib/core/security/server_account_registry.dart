import 'dart:convert';

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
    required Uri baseUrl,
    required Uri wsBaseUrl,
    required String name,
    String? logoUrl,
  }) async {
    final records = await _readRecords();
    final key = _serverKey(baseUrl);
    final existing = records
        .where((item) => item['base_url'] == key)
        .firstOrNull;
    final record = <String, Object?>{
      ...?existing,
      'base_url': key,
      'ws_base_url': wsBaseUrl.toString(),
      'name': name.trim().isEmpty ? baseUrl.host : name.trim(),
      'logo_url': logoUrl,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    records.removeWhere((item) => item['base_url'] == key);
    records.insert(0, record);
    await _writeRecords(records.take(10).toList(growable: false));
  }

  Future<void> stashActiveSession() async {
    final active = await _store.read(SecureStoreKey.instanceBaseUrl);
    final uri = Uri.tryParse(active ?? '');
    if (uri == null || uri.host.isEmpty) {
      return;
    }
    final accessToken = await _store.read(SecureStoreKey.accessToken);
    final refreshToken = await _store.read(SecureStoreKey.refreshToken);
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
    record['updated_at'] = DateTime.now().toUtc().toIso8601String();
    if (index >= 0) {
      records.removeAt(index);
    }
    records.insert(0, record);
    await _writeRecords(records.take(10).toList(growable: false));
  }

  Future<bool> activate(Uri baseUrl) async {
    final key = _serverKey(baseUrl);
    final records = await _readRecords();
    final match = records.where((item) => item['base_url'] == key).firstOrNull;
    final accessToken = match?['access_token']?.toString().trim() ?? '';
    final refreshToken = match?['refresh_token']?.toString().trim() ?? '';
    await Future.wait([
      _store.delete(SecureStoreKey.accessToken),
      _store.delete(SecureStoreKey.refreshToken),
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
    await _writeRecords(records);
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
