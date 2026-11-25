import 'dart:convert';

import '../../../core/security/secure_key_value_store.dart';
import '../domain/ide_web_device_key.dart';
import '../domain/ide_web_launch.dart';
import '../domain/ide_web_ports.dart';

Object? _decode(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  try {
    return jsonDecode(raw);
  } on FormatException {
    return null;
  }
}

final class SecureIdeWebPendingStore implements IdeWebPendingStore {
  const SecureIdeWebPendingStore(this._store);

  final SecureKeyValueStore _store;

  @override
  Future<PendingIdeWebLaunch?> read() async => PendingIdeWebLaunch.fromJson(
    _decode(await _store.read(SecureStoreKey.ideWebPending)),
  );

  @override
  Future<void> write(PendingIdeWebLaunch launch) =>
      _store.write(SecureStoreKey.ideWebPending, jsonEncode(launch.toJson()));

  @override
  Future<void> clear() => _store.delete(SecureStoreKey.ideWebPending);
}

final class SecureIdeWebKeyMetadataStore implements IdeWebKeyMetadataStore {
  const SecureIdeWebKeyMetadataStore(this._store);

  final SecureKeyValueStore _store;

  static final _digest = RegExp(r'^[0-9a-f]{64}$');

  @override
  Future<IdeWebKeyRecord?> read() async {
    final json = _decode(await _store.read(SecureStoreKey.ideWebDevice));
    if (json is! Map || json['v'] != 1) return null;
    final owner = json['owner'];
    final keys = json['keys'];
    if (owner is! String || !_digest.hasMatch(owner) || keys is! List) {
      return null;
    }
    return IdeWebKeyRecord(
      ownerDigest: owner,
      keys: [for (final item in keys) ?IdeWebDeviceKey.fromJson(item)],
    );
  }

  @override
  Future<void> write(IdeWebKeyRecord record) => _store.write(
    SecureStoreKey.ideWebDevice,
    jsonEncode({
      'v': 1,
      'owner': record.ownerDigest,
      'keys': [for (final key in record.keys) key.toJson()],
    }),
  );

  @override
  Future<void> clear() => _store.delete(SecureStoreKey.ideWebDevice);
}

final class SecureIdeWebDataMarkerStore implements IdeWebDataMarkerStore {
  const SecureIdeWebDataMarkerStore(this._store);

  final SecureKeyValueStore _store;

  static const _needsClear = 'clear';
  static const _usedPrefix = 'used:';

  @override
  Future<IdeWebDataMarker?> read() async {
    final raw = await _store.read(SecureStoreKey.ideWebViewData);
    if (raw == null || raw.isEmpty) return null;
    // Giá trị lạ: coi như phải xoá.
    return raw.startsWith(_usedPrefix)
        ? IdeWebDataMarker.usedBy(raw.substring(_usedPrefix.length))
        : const IdeWebDataMarker.needsClear();
  }

  @override
  Future<void> write(IdeWebDataMarker marker) => _store.write(
    SecureStoreKey.ideWebViewData,
    marker.needsClear ? _needsClear : '$_usedPrefix${marker.ownerDigest}',
  );

  @override
  Future<void> clear() => _store.delete(SecureStoreKey.ideWebViewData);
}
