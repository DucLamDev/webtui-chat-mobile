import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../../../core/security/secure_key_value_store.dart';
import '../../domain/repositories/app_lock_repository.dart';

final class SecureAppLockRepository implements AppLockRepository {
  const SecureAppLockRepository(this._store);

  final SecureKeyValueStore _store;

  @override
  Future<bool> isEnabled() async {
    return (await _store.read(SecureStoreKey.appLockEnabled)) == 'true';
  }

  @override
  Future<void> enablePin(String pin) async {
    await Future.wait([
      _store.write(SecureStoreKey.appLockPinHash, _hashPin(pin)),
      _store.write(SecureStoreKey.appLockEnabled, 'true'),
    ]);
  }

  @override
  Future<bool> verifyPin(String pin) async {
    final expected = await _store.read(SecureStoreKey.appLockPinHash);
    return expected != null && expected == _hashPin(pin);
  }

  @override
  Future<void> disable() async {
    await Future.wait([
      _store.delete(SecureStoreKey.appLockEnabled),
      _store.delete(SecureStoreKey.appLockPinHash),
    ]);
  }
}

String _hashPin(String pin) {
  return sha256.convert(utf8.encode(pin)).toString();
}
