import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/core/security/secure_key_value_store.dart';
import 'package:webtui_chat/features/auth/data/repositories/secure_app_lock_repository.dart';

void main() {
  test('stores a salted PBKDF2 record and verifies the PIN', () async {
    final store = _MemorySecureStore();
    final repository = SecureAppLockRepository(store);

    await repository.enablePin('123456');
    final first = store.values[SecureStoreKey.appLockPinHash];

    expect(first, startsWith(r'pbkdf2_sha256$120000$'));
    expect(first, isNot(contains('123456')));
    expect(await repository.isEnabled(), isTrue);
    expect(await repository.verifyPin('123456'), isTrue);
    expect(await repository.verifyPin('654321'), isFalse);

    await repository.enablePin('123456');
    expect(store.values[SecureStoreKey.appLockPinHash], isNot(first));
  });

  test('migrates a valid legacy SHA-256 hash after unlock', () async {
    final store = _MemorySecureStore()
      ..values[SecureStoreKey.appLockEnabled] = 'true'
      ..values[SecureStoreKey.appLockPinHash] = sha256
          .convert(utf8.encode('123456'))
          .toString();
    final repository = SecureAppLockRepository(store);

    expect(await repository.verifyPin('123456'), isTrue);
    expect(
      store.values[SecureStoreKey.appLockPinHash],
      startsWith(r'pbkdf2_sha256$120000$'),
    );
  });

  test('disable removes both app-lock values', () async {
    final store = _MemorySecureStore();
    final repository = SecureAppLockRepository(store);

    await repository.enablePin('123456');
    await repository.disable();

    expect(await repository.isEnabled(), isFalse);
    expect(store.values[SecureStoreKey.appLockPinHash], isNull);
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
