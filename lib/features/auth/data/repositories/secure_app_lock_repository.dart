import 'dart:convert';
import 'dart:isolate';
import 'dart:math';

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
    final encoded = await _encodePin(pin);
    await Future.wait([
      _store.write(SecureStoreKey.appLockPinHash, encoded),
      _store.write(SecureStoreKey.appLockEnabled, 'true'),
    ]);
  }

  @override
  Future<bool> verifyPin(String pin) async {
    final expected = await _store.read(SecureStoreKey.appLockPinHash);
    if (expected == null) {
      return false;
    }
    final verified = await _verifyEncodedPin(pin, expected);
    if (verified && RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(expected)) {
      // Transparently migrate the legacy unsalted SHA-256 value after a
      // successful unlock.
      await enablePin(pin);
    }
    return verified;
  }

  @override
  Future<void> disable() async {
    await Future.wait([
      _store.delete(SecureStoreKey.appLockEnabled),
      _store.delete(SecureStoreKey.appLockPinHash),
    ]);
  }
}

const _pinKdfIterations = 120000;
const _pinKdfName = 'pbkdf2_sha256';

Future<String> _encodePin(String pin) async {
  final random = Random.secure();
  final salt = List<int>.generate(16, (_) => random.nextInt(256));
  final derived = await Isolate.run(
    () => _pbkdf2Sha256(utf8.encode(pin), salt, _pinKdfIterations, 32),
  );
  return [
    _pinKdfName,
    _pinKdfIterations.toString(),
    base64Url.encode(salt).replaceAll('=', ''),
    base64Url.encode(derived).replaceAll('=', ''),
  ].join(r'$');
}

Future<bool> _verifyEncodedPin(String pin, String encoded) async {
  if (RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(encoded)) {
    final legacy = sha256.convert(utf8.encode(pin)).toString();
    return _constantTimeEquals(
      utf8.encode(legacy),
      utf8.encode(encoded.toLowerCase()),
    );
  }
  final parts = encoded.split(r'$');
  if (parts.length != 4 || parts[0] != _pinKdfName) {
    return false;
  }
  final iterations = int.tryParse(parts[1]);
  if (iterations == null || iterations < 100000 || iterations > 1000000) {
    return false;
  }
  try {
    final salt = base64Url.decode(base64Url.normalize(parts[2]));
    final expected = base64Url.decode(base64Url.normalize(parts[3]));
    final actual = await Isolate.run(
      () => _pbkdf2Sha256(utf8.encode(pin), salt, iterations, expected.length),
    );
    return _constantTimeEquals(actual, expected);
  } on FormatException {
    return false;
  }
}

List<int> _pbkdf2Sha256(
  List<int> password,
  List<int> salt,
  int iterations,
  int length,
) {
  final result = <int>[];
  final hmac = Hmac(sha256, password);
  for (var block = 1; result.length < length; block += 1) {
    final blockIndex = [
      (block >> 24) & 0xff,
      (block >> 16) & 0xff,
      (block >> 8) & 0xff,
      block & 0xff,
    ];
    var previous = hmac.convert([...salt, ...blockIndex]).bytes;
    final accumulator = List<int>.from(previous);
    for (var round = 1; round < iterations; round += 1) {
      previous = hmac.convert(previous).bytes;
      for (var index = 0; index < accumulator.length; index += 1) {
        accumulator[index] ^= previous[index];
      }
    }
    result.addAll(accumulator);
  }
  return result.sublist(0, length);
}

bool _constantTimeEquals(List<int> left, List<int> right) {
  var difference = left.length ^ right.length;
  final length = left.length > right.length ? left.length : right.length;
  for (var index = 0; index < length; index += 1) {
    final a = index < left.length ? left[index] : 0;
    final b = index < right.length ? right[index] : 0;
    difference |= a ^ b;
  }
  return difference == 0;
}
