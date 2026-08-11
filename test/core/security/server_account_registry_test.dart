import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/core/security/instance_scope.dart';
import 'package:webtui_chat/core/security/secure_key_value_store.dart';
import 'package:webtui_chat/core/security/server_account_registry.dart';
import 'package:webtui_chat/features/auth/data/repositories/secure_auth_token_repository.dart';
import 'package:webtui_chat/features/auth/domain/entities/auth_tokens.dart';
import 'package:webtui_chat/features/auth/domain/repositories/auth_token_repository.dart';

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
            'instance_id': _instanceTwo.instanceId,
            'instance_scope_id': _instanceTwo.storageId,
            'name': 'Server two',
            'refresh_token': 'refresh-from-server-two',
            'session_persistence': durableSessionPersistenceValue,
          },
        ]);

      final restored = await SecureServerAccountRegistry(
        store,
      ).activate(_instanceTwo);

      expect(restored, isTrue);
      expect(store.values[SecureStoreKey.accessToken], isNull);
      expect(
        store.values[SecureStoreKey.refreshToken],
        'refresh-from-server-two',
      );
    },
  );

  test(
    'same origin with a replacement instance never inherits tokens',
    () async {
      final store = _MemorySecureStore();
      final registry = SecureServerAccountRegistry(store);
      final instanceA = InstanceScope(
        instanceId: '11111111-1111-4111-8111-111111111111',
        serverOrigin: Uri.parse('https://chat.example'),
      );
      final instanceB = InstanceScope(
        instanceId: '22222222-2222-4222-8222-222222222222',
        serverOrigin: Uri.parse('https://chat.example'),
      );
      await registry.rememberServer(
        instanceScope: instanceA,
        wsBaseUrl: Uri.parse('wss://chat.example/ws'),
        name: 'Instance A',
      );
      await _activateRaw(
        store,
        instanceA,
        access: 'access-a',
        refresh: 'refresh-a',
      );
      await registry.stashActiveSession();

      await registry.rememberServer(
        instanceScope: instanceB,
        wsBaseUrl: Uri.parse('wss://chat.example/ws'),
        name: 'Instance B',
      );

      expect(await registry.activate(instanceB), isFalse);
      expect(await store.read(SecureStoreKey.accessToken), isNull);
      expect(await store.read(SecureStoreKey.refreshToken), isNull);
    },
  );

  test('saving an access-only token removes a stale refresh token', () async {
    final store = _MemorySecureStore()
      ..values[SecureStoreKey.instanceBaseUrl] = 'https://chat.example'
      ..values[SecureStoreKey.instanceId] = _instanceChat.instanceId
      ..values[SecureStoreKey.activeInstanceScopeId] = _instanceChat.storageId
      ..values[SecureStoreKey.liveDiscoveryValidatedScopeId] =
          _instanceChat.storageId
      ..values[SecureStoreKey.activeInstanceGeneration] = 'generation-chat'
      ..values[SecureStoreKey.refreshToken] = 'stale-refresh';

    await SecureAuthTokenRepository(
      store,
    ).saveTokens(const AuthTokens(accessToken: 'access', refreshToken: ''));

    expect(store.values[SecureStoreKey.accessToken], 'access');
    expect(store.values[SecureStoreKey.refreshToken], isNull);
    expect(
      store.values[SecureStoreKey.sessionPersistence],
      durableSessionPersistenceValue,
    );
  });

  test(
    'session-only tokens never enter secure storage or account records',
    () async {
      final store = _MemorySecureStore();
      await _activateRaw(
        store,
        _instanceChat,
        access: 'old-durable-access',
        refresh: 'old-durable-refresh',
      );
      final registry = SecureServerAccountRegistry(store);
      await registry.rememberServer(
        instanceScope: _instanceChat,
        wsBaseUrl: Uri.parse('wss://chat.example/ws'),
        name: 'Chat',
      );
      await registry.stashActiveSession();
      expect(await registry.hasAnySavedSession(), isTrue);
      final nativeDurability = <bool>[];
      final repository = SecureAuthTokenRepository(
        store,
        setNativeSessionDurable: (durable) async {
          nativeDurability.add(durable);
        },
      );
      final captured = await repository.captureMutationGuard();
      expect(captured, isNotNull);

      expect(
        await repository.saveTokensIfCurrent(
          const AuthTokens(
            accessToken: 'memory-access',
            refreshToken: 'memory-refresh',
          ),
          captured!,
          persistence: AuthTokenPersistence.sessionOnly,
        ),
        isTrue,
      );
      expect(await repository.readAccessToken(), 'memory-access');
      expect(await repository.readRefreshToken(), 'memory-refresh');
      expect(store.values[SecureStoreKey.accessToken], isNull);
      expect(store.values[SecureStoreKey.refreshToken], isNull);
      expect(store.values[SecureStoreKey.sessionPersistence], isNull);
      expect(nativeDurability.last, isFalse);
      expect(
        jsonDecode(store.values[SecureStoreKey.serverAccounts]!) as List,
        everyElement(
          allOf(
            isNot(contains('access_token')),
            isNot(contains('refresh_token')),
            isNot(contains('session_persistence')),
          ),
        ),
      );

      // Refresh rotation preserves the in-memory-only policy.
      expect(
        await repository.saveTokensIfCurrent(
          const AuthTokens(
            accessToken: 'rotated-access',
            refreshToken: 'rotated-refresh',
          ),
          captured,
        ),
        isTrue,
      );
      expect(await repository.readRefreshToken(), 'rotated-refresh');
      expect(store.values[SecureStoreKey.refreshToken], isNull);

      // Simulated process/provider recreation has no credentials to recover.
      final recreated = SecureAuthTokenRepository(store);
      expect(await recreated.readAccessToken(), isNull);
      expect(await recreated.readRefreshToken(), isNull);
      expect(
        await registry.activate(_instanceChat),
        isFalse,
        reason: 'a session-only transition must revoke the account record',
      );
    },
  );

  test(
    'fresh repository rejects raw tokens without a durable marker',
    () async {
      final store = _MemorySecureStore();
      await _activateRaw(
        store,
        _instanceChat,
        access: 'partial-access',
        refresh: 'partial-refresh',
      );
      store.values.remove(SecureStoreKey.sessionPersistence);
      final repository = SecureAuthTokenRepository(store);

      expect(await repository.readAccessToken(), isNull);
      expect(await repository.readRefreshToken(), isNull);

      store.values[SecureStoreKey.sessionPersistence] = 'stale_v0';
      expect(await repository.readAccessToken(), isNull);
      expect(await repository.readRefreshToken(), isNull);
    },
  );

  test('registry ignores credential records missing durable marker', () async {
    final store = _MemorySecureStore()
      ..values[SecureStoreKey.serverAccounts] = jsonEncode([
        {
          'base_url': _instanceChat.origin.toString(),
          'instance_id': _instanceChat.instanceId,
          'instance_scope_id': _instanceChat.storageId,
          'name': 'Legacy partial record',
          'access_token': 'legacy-access',
          'refresh_token': 'legacy-refresh',
        },
      ]);

    expect(
      await SecureServerAccountRegistry(store).activate(_instanceChat),
      isFalse,
    );
    expect(store.values[SecureStoreKey.accessToken], isNull);
    expect(store.values[SecureStoreKey.refreshToken], isNull);
    expect(store.values[SecureStoreKey.sessionPersistence], isNull);
  });

  test('stash ignores raw tokens when durable intent is absent', () async {
    final store = _MemorySecureStore();
    await _activateRaw(
      store,
      _instanceChat,
      access: 'partial-access',
      refresh: 'partial-refresh',
    );
    store.values.remove(SecureStoreKey.sessionPersistence);
    final registry = SecureServerAccountRegistry(store);
    await registry.rememberServer(
      instanceScope: _instanceChat,
      wsBaseUrl: Uri.parse('wss://chat.example/ws'),
      name: 'Chat',
    );

    await registry.stashActiveSession();

    final record =
        (jsonDecode(store.values[SecureStoreKey.serverAccounts]!) as List)
                .single
            as Map<String, dynamic>;
    expect(record, isNot(contains('access_token')));
    expect(record, isNot(contains('refresh_token')));
    expect(record, isNot(contains('session_persistence')));
    expect(await registry.hasAnySavedSession(), isFalse);
  });

  test('switching A to B and back restores the stashed A session', () async {
    final store = _MemorySecureStore();
    final registry = SecureServerAccountRegistry(store);

    await _activateRaw(
      store,
      _instanceChat,
      access: 'access-a',
      refresh: 'refresh-a',
    );
    await registry.rememberServer(
      instanceScope: _instanceChat,
      wsBaseUrl: Uri.parse('wss://chat.example/ws'),
      name: 'A',
    );
    await registry.stashActiveSession();

    await store.clearSession();
    await _activateRaw(
      store,
      _instanceTwo,
      access: 'access-b',
      refresh: 'refresh-b',
    );
    await registry.rememberServer(
      instanceScope: _instanceTwo,
      wsBaseUrl: Uri.parse('wss://two.example/ws'),
      name: 'B',
    );
    await registry.stashActiveSession();
    await store.clearSession();

    expect(await registry.activate(_instanceChat), isTrue);
    expect(store.values[SecureStoreKey.accessToken], 'access-a');
    expect(store.values[SecureStoreKey.refreshToken], 'refresh-a');
    expect(
      store.values[SecureStoreKey.sessionPersistence],
      durableSessionPersistenceValue,
    );
  });
}

Future<void> _activateRaw(
  _MemorySecureStore store,
  InstanceScope scope, {
  required String access,
  required String refresh,
}) async {
  store.values[SecureStoreKey.instanceBaseUrl] = scope.origin.toString();
  store.values[SecureStoreKey.instanceId] = scope.instanceId;
  store.values[SecureStoreKey.activeInstanceScopeId] = scope.storageId;
  store.values[SecureStoreKey.liveDiscoveryValidatedScopeId] = scope.storageId;
  store.values[SecureStoreKey.activeInstanceGeneration] = 'generation-test';
  store.values[SecureStoreKey.accessToken] = access;
  store.values[SecureStoreKey.refreshToken] = refresh;
  store.values[SecureStoreKey.sessionInstanceScopeId] = scope.storageId;
  if (access.isNotEmpty || refresh.isNotEmpty) {
    store.values[SecureStoreKey.sessionPersistence] =
        durableSessionPersistenceValue;
  } else {
    store.values.remove(SecureStoreKey.sessionPersistence);
  }
}

final _instanceTwo = InstanceScope(
  instanceId: '22222222-2222-4222-8222-222222222222',
  serverOrigin: Uri.parse('https://two.example'),
);

final _instanceChat = InstanceScope(
  instanceId: '11111111-1111-4111-8111-111111111111',
  serverOrigin: Uri.parse('https://chat.example'),
);

final class _MemorySecureStore implements SecureKeyValueStore {
  final values = <SecureStoreKey, String>{};

  @override
  Future<void> clearSession() async {
    values.remove(SecureStoreKey.accessToken);
    values.remove(SecureStoreKey.refreshToken);
    values.remove(SecureStoreKey.sessionInstanceScopeId);
    values.remove(SecureStoreKey.sessionPersistence);
    values.remove(SecureStoreKey.activeWorkspaceId);
    values.remove(SecureStoreKey.activeWorkspaceInstanceScopeId);
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
