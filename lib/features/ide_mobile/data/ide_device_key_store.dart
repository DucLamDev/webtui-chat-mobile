import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import '../../../core/security/secure_key_value_store.dart';
import '../domain/ide_canonical_json.dart';
import '../domain/ide_device_credentials.dart';

/// Khoá thiết bị Ed25519 + thông tin gắn máy, cất qua [SecureKeyValueStore].
final class IdeDeviceKeyStore {
  const IdeDeviceKeyStore(this._store);

  final SecureKeyValueStore _store;

  static final _ed25519 = Ed25519();

  /// Chỉ trả khoá khi khớp người và máy chủ đang dùng; khác thì coi như chưa
  /// gắn. Không tự xoá: việc xoá bản gắn của người cũ do
  /// `IdePairingService.loadCurrent` làm (kèm khoá xác nhận trong chip).
  Future<IdeDeviceCredentials?> load({
    required String chatUserId,
    required String serverScope,
  }) async {
    final raw = await _store.read(SecureStoreKey.ideDevice);
    if (raw == null || raw.isEmpty) return null;
    Object? json;
    try {
      json = jsonDecode(raw);
    } on FormatException {
      return null;
    }
    final creds = IdeDeviceCredentials.fromJson(json);
    if (creds == null) return null;
    if (creds.chatUserId != chatUserId || creds.serverScope != serverScope) {
      return null;
    }
    return creds;
  }

  /// Bản ghi đang cất (bất kể người / máy chủ); dùng để dọn khoá cũ khi gắn lại.
  Future<IdeDeviceCredentials?> loadAny() async {
    final raw = await _store.read(SecureStoreKey.ideDevice);
    if (raw == null || raw.isEmpty) return null;
    try {
      return IdeDeviceCredentials.fromJson(jsonDecode(raw));
    } on FormatException {
      return null;
    }
  }

  Future<void> save(IdeDeviceCredentials creds) =>
      _store.write(SecureStoreKey.ideDevice, jsonEncode(creds.toJson()));

  Future<void> clear() => _store.delete(SecureStoreKey.ideDevice);

  /// Hạt giống mới (32 byte base64) từ bộ sinh số an toàn của gói.
  static Future<String> newSeed() async {
    final pair = await _ed25519.newKeyPair();
    final bytes = await pair.extractPrivateKeyBytes();
    return base64Encode(bytes);
  }

  /// Khoá công khai Ed25519 (32 byte) base64 của [seed].
  static Future<String> publicKeyBase64(String seed) async {
    final pair = await _ed25519.newKeyPairFromSeed(base64Decode(seed));
    final key = await pair.extractPublicKey();
    return base64Encode(key.bytes);
  }

  /// Ký chuỗi bắt tay `webtui-ide-auth:v1|nonce|stream|chat_user`.
  static Future<String> signAuth({
    required String seed,
    required String nonce,
    required String stream,
    required String chatUser,
  }) => signText(
    seed,
    ideAuthSigningString(nonce: nonce, stream: stream, chatUser: chatUser),
  );

  static Future<String> signText(String seed, String text) async {
    final pair = await _ed25519.newKeyPairFromSeed(base64Decode(seed));
    final sig = await _ed25519.sign(utf8.encode(text), keyPair: pair);
    return base64Encode(sig.bytes);
  }
}
