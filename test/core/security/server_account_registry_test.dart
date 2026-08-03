import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/core/security/secure_key_value_store.dart';
import 'package:webtui_chat/core/security/server_account_registry.dart';
import 'package:webtui_chat/features/auth/data/repositories/secure_auth_token_repository.dart';
import 'package:webtui_chat/features/auth/domain/entities/auth_tokens.dart';

void main() {
  test(
    'activating a server clears tokens missing from the target account',
    () async {
      final store = _MemorySecureStore()
        ..values[SecureStoreKey.accessToken] = 'access-from-server-one'
        ..values[SecureStoreKey.refreshToken] = 'refresh-from-server-one'
        ..values[SecureStoreKey.serverAccounts] = jsonEncode([
          {
            'base_url': 'https://two.example',
            'name': 'Server two',
            'refresh_token': 'refresh-from-server-two',
          },
        ]);

      final restored = await SecureServerAccountRegistry(
        store,
      ).activate(Uri.parse('https://two.example'));

      expect(restored, isTrue);
      expect(store.values[SecureStoreKey.accessToken], isNull);
      expect(
        store.values[SecureStoreKey.refreshToken],
        'refresh-from-server-two',
      );
    },
  );

  test('saving an access-only token removes a stale refresh token', () async {
    final store = _MemorySecureStore()
      ..values[SecureStoreKey.instanceBaseUrl] = 'https://chat.example'
      ..values[SecureStoreKey.refreshToken] = 'stale-refresh';

    await SecureAuthTokenRepository(
      store,
    ).saveTokens(const AuthTokens(accessToken: 'access', refreshToken: ''));

    expect(store.values[SecureStoreKey.accessToken], 'access');
    expect(store.values[SecureStoreKey.refreshToken], isNull);
  });
}

final class _MemorySecureStore implements SecureKeyValueStore {
  final values = <SecureStoreKey, String>{};

  @override
  Future<void> clearSession() async {
    values.remove(SecureStoreKey.accessToken);
    values.remove(SecureStoreKey.refreshToken);
    values.remove(SecureStoreKey.activeWorkspaceId);
  }

  @override
  Future<void> delete(SecureStoreKey key) async {
    values.remove(key);
  }

  @override
  Future<String?> read(SecureStoreKey key) async => values[key];

  @override
  Future<void> write(SecureStoreKey key, String value) async {
    values[key] = value;
  }
}
