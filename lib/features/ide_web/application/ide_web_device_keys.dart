import 'package:uuid/uuid.dart';

import '../domain/ide_web_device_key.dart';
import '../domain/ide_web_owner.dart';
import '../domain/ide_web_ports.dart';
import 'ide_web_serial.dart';

final class IdeWebKeyStatus {
  const IdeWebKeyStatus({required this.key, required this.usable});

  final IdeWebDeviceKey key;
  final bool usable;
}

final class IdeWebRegisteredKey {
  const IdeWebRegisteredKey({
    required this.keyId,
    required this.publicKey,
    required this.hardware,
    required this.proof,
  });

  final String keyId;
  final String publicKey;
  final String hardware;
  final String proof;
}

/// Khoá thiết bị của VPSTTT IDE theo người + máy chủ. Đăng xuất GIỮ khoá (cùng
/// người đăng nhập lại còn dùng Smart OTP); người khác đăng nhập hoặc xoá tài
/// khoản thì xoá hẳn.
final class IdeWebDeviceKeys {
  IdeWebDeviceKeys({
    required IdeWebKeyChip chip,
    required IdeWebKeyMetadataStore store,
    Uuid uuid = const Uuid(),
    DateTime Function()? clock,
  }) : _chip = chip,
       _store = store,
       _uuid = uuid,
       _clock = clock ?? DateTime.now;

  /// Đủ cho xoay khoá cả hai loại; chặn trang tạo khoá vô hạn.
  static const maxKeys = 10;

  final IdeWebKeyChip _chip;
  final IdeWebKeyMetadataStore _store;
  final Uuid _uuid;
  final DateTime Function() _clock;
  final _serial = IdeWebSerial();

  Future<IdeWebBiometricState> biometricState() => _chip.biometricState();

  Future<List<IdeWebKeyStatus>> status(IdeWebOwner owner) async {
    final keys = await _serial.run(() => _keysOf(owner));
    return [
      for (final key in keys)
        if (key.ready)
          IdeWebKeyStatus(
            key: key,
            usable:
                !key.invalid &&
                await _chip.isUsable(key.purpose, _alias(owner, key)),
          ),
    ];
  }

  /// Mã khoá mới nhất từng loại, chỉ là gợi ý cho máy chủ.
  Future<String?> hint(IdeWebOwner owner, IdeWebKeyPurpose purpose) async {
    final keys = await _serial.run(() => _keysOf(owner));
    for (final key in keys.reversed) {
      if (key.purpose == purpose && key.ready && !key.invalid) return key.keyId;
    }
    return null;
  }

  /// Tạo khoá và ký chuỗi đăng ký. Ký hỏng hoặc [stillWanted] sai thì xoá khoá
  /// vừa tạo (không để lại khoá mồ côi trong chip).
  Future<IdeWebRegisteredKey> create({
    required IdeWebOwner owner,
    required IdeWebKeyPurpose purpose,
    required String origin,
    required String challenge,
    required bool Function() stillWanted,
  }) async {
    final key = IdeWebDeviceKey(
      keyId: _uuid.v4(),
      purpose: purpose,
      createdAt: _clock().toUtc(),
    );
    final alias = _alias(owner, key);
    await _serial.run(() async {
      await _dropOther(owner);
      final keys = await _keysOf(owner);
      if (keys.length >= maxKeys) throw const IdeWebKeyException('failed');
      await _save(owner, [...keys, key]);
    });
    try {
      final created = await _chip.create(purpose, alias);
      if (!stillWanted()) throw const IdeWebKeyException('cancelled');
      final signature = await _chip.sign(
        purpose,
        alias,
        ideWebUtf8(
          ideWebSigningString(
            action: IdeWebSigningAction.register,
            purpose: purpose,
            origin: origin,
            keyId: key.keyId,
            challenge: challenge,
          ),
        ),
      );
      if (!stillWanted()) throw const IdeWebKeyException('cancelled');
      // Bản ghi có thể đã bị xoá (người khác đăng nhập) trong lúc hỏi sinh trắc.
      if (!await _update(owner, key.keyId, (k) => k.copyWith(ready: true))) {
        throw const IdeWebKeyException('cancelled');
      }
      return IdeWebRegisteredKey(
        keyId: key.keyId,
        publicKey: created.publicKey,
        hardware: created.hardware,
        proof: ideWebBase64Url(signature),
      );
    } on Object {
      await _discard(owner, key);
      rethrow;
    }
  }

  Future<String> sign({
    required IdeWebOwner owner,
    required String keyId,
    required String origin,
    required String challenge,
  }) async {
    final key = await find(owner, keyId);
    if (key == null) throw const IdeWebKeyException('key_missing');
    if (key.invalid) throw const IdeWebKeyException('key_invalid');
    try {
      final signature = await _chip.sign(
        key.purpose,
        _alias(owner, key),
        ideWebUtf8(
          ideWebSigningString(
            action: IdeWebSigningAction.sign,
            purpose: key.purpose,
            origin: origin,
            keyId: key.keyId,
            challenge: challenge,
          ),
        ),
      );
      return ideWebBase64Url(signature);
    } on IdeWebKeyException catch (error) {
      if (error.code == 'key_invalid') {
        await _update(owner, keyId, (k) => k.copyWith(invalid: true));
      }
      rethrow;
    }
  }

  /// Khoá đã đăng ký của đúng người này.
  Future<IdeWebDeviceKey?> find(IdeWebOwner owner, String keyId) async {
    final keys = await _serial.run(() => _keysOf(owner));
    for (final key in keys) {
      if (key.keyId == keyId && key.ready) return key;
    }
    return null;
  }

  Future<void> delete(IdeWebOwner owner, String keyId) async {
    final key = await find(owner, keyId);
    if (key == null) throw const IdeWebKeyException('key_missing');
    await _chip.delete(key.purpose, _alias(owner, key));
    await _serial.run(() async {
      final keys = await _keysOf(owner);
      await _save(owner, [
        for (final item in keys)
          if (item.keyId != keyId) item,
      ]);
    });
  }

  /// Người [current] vừa đăng nhập: xoá khoá của người khác (nếu có).
  Future<void> dropOtherOwner(IdeWebOwner current) =>
      _serial.run(() => _dropOther(current));

  /// Tài khoản bị xoá: xoá mọi khoá đang có.
  Future<void> purge() => _serial.run(_purge);

  Future<void> _dropOther(IdeWebOwner current) async {
    final record = await _store.read();
    if (record != null && record.ownerDigest != current.digest) await _purge();
  }

  /// Khoá nào chip chưa xoá được thì giữ lại bản ghi để lần sau xoá tiếp.
  Future<void> _purge() async {
    final record = await _store.read();
    if (record == null) return;
    final left = <IdeWebDeviceKey>[];
    for (final key in record.keys) {
      try {
        await _chip.delete(
          key.purpose,
          ideWebKeyAliasOfDigest(
            ownerDigest: record.ownerDigest,
            purpose: key.purpose,
            keyId: key.keyId,
          ),
        );
      } on Object {
        left.add(key);
      }
    }
    if (left.isEmpty) {
      await _store.clear();
      return;
    }
    await _store.write(
      IdeWebKeyRecord(ownerDigest: record.ownerDigest, keys: left),
    );
    throw const IdeWebKeyException('failed');
  }

  Future<List<IdeWebDeviceKey>> _keysOf(IdeWebOwner owner) async {
    final record = await _store.read();
    if (record == null || record.ownerDigest != owner.digest) return const [];
    return record.keys;
  }

  Future<void> _save(IdeWebOwner owner, List<IdeWebDeviceKey> keys) =>
      _store.write(IdeWebKeyRecord(ownerDigest: owner.digest, keys: keys));

  Future<bool> _update(
    IdeWebOwner owner,
    String keyId,
    IdeWebDeviceKey Function(IdeWebDeviceKey key) change,
  ) => _serial.run(() async {
    final keys = await _keysOf(owner);
    if (!keys.any((key) => key.keyId == keyId)) return false;
    await _save(owner, [
      for (final key in keys) key.keyId == keyId ? change(key) : key,
    ]);
    return true;
  });

  Future<void> _discard(IdeWebOwner owner, IdeWebDeviceKey key) async {
    try {
      await _chip.delete(key.purpose, _alias(owner, key));
      await _serial.run(() async {
        final keys = await _keysOf(owner);
        if (!keys.any((item) => item.keyId == key.keyId)) return;
        await _save(owner, [
          for (final item in keys)
            if (item.keyId != key.keyId) item,
        ]);
      });
    } on Object {
      // Bản ghi chưa `ready` còn đó: không dùng được, đổi người sẽ xoá tiếp.
    }
  }

  String _alias(IdeWebOwner owner, IdeWebDeviceKey key) =>
      ideWebKeyAlias(owner: owner, purpose: key.purpose, keyId: key.keyId);
}
