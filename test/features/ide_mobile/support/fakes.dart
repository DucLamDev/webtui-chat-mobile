import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:pointycastle/export.dart' as pc;
import 'package:webtui_chat/core/security/secure_key_value_store.dart';
import 'package:webtui_chat/features/ide_mobile/data/ide_channel.dart';
import 'package:webtui_chat/features/ide_mobile/domain/ide_device_security.dart';

/// Ổ cắm giả: tự bắt tay (challenge -> auth -> ready), ghi lại mọi khung gửi.
final class FakeIdeSocket implements IdeSocket {
  FakeIdeSocket({
    this.ops = const ['ai.sessions'],
    this.stream = 's_AAAAAAAAAAAAAAAAAAAAAA',
    this.chatUser = 'u_1',
    this.autoReady = true,
  }) {
    scheduleMicrotask(
      () => emit({
        'type': 'challenge',
        'nonce': base64Encode(List<int>.filled(32, 7)),
        'stream': stream,
        'chat_user': chatUser,
      }),
    );
  }

  final List<String> ops;
  final String stream;
  final String chatUser;
  final bool autoReady;
  final _incoming = StreamController<String>();
  final sent = <Map<String, Object?>>[];
  bool closed = false;

  @override
  Stream<String> get messages => _incoming.stream;

  @override
  void send(String text) {
    final frame = Map<String, Object?>.from(jsonDecode(text) as Map);
    sent.add(frame);
    if (frame['type'] == 'auth' && autoReady) {
      emit({
        'type': 'ready',
        'user': chatUser,
        'protocol': 2,
        'ide_version': 'test',
        'ops': ops,
        'features': {'step_up': true},
      });
    }
  }

  void emit(Map<String, Object?> frame) {
    if (!_incoming.isClosed) _incoming.add(jsonEncode(frame));
  }

  /// Gửi chuỗi JSON thô (vd `1e999` mà jsonEncode không tạo được).
  void emitRaw(String text) {
    if (!_incoming.isClosed) _incoming.add(text);
  }

  /// Rớt kết nối từ phía IDE.
  Future<void> drop() => _incoming.close();

  @override
  Future<void> close() async {
    closed = true;
    if (!_incoming.isClosed) await _incoming.close();
  }

  Iterable<Map<String, Object?>> sentOfType(String type) =>
      sent.where((f) => f['type'] == type);
}

Future<String> fakeSignAuth(String nonce, String stream, String user) async =>
    'sig';

/// Kho bí mật trong bộ nhớ.
final class MemorySecureStore implements SecureKeyValueStore {
  final values = <SecureStoreKey, String>{};

  @override
  Future<void> clearSession() async => values.clear();

  @override
  Future<void> delete(SecureStoreKey key) async => values.remove(key);

  @override
  Future<String?> read(SecureStoreKey key) async => values[key];

  /// Giả kho bảo mật từ chối ghi.
  bool failWrites = false;

  @override
  Future<void> write(SecureStoreKey key, String value) async {
    if (failWrites) throw StateError('keychain từ chối');
    values[key] = value;
  }
}

/// Khoá ECDSA P-256 thuần Dart thay cho chip bảo mật; ký DER như máy thật.
final class FakeStepKey {
  FakeStepKey() {
    final random = pc.FortunaRandom()
      ..seed(
        pc.KeyParameter(
          Uint8List.fromList(List<int>.generate(32, (i) => i + 1)),
        ),
      );
    final generator = pc.ECKeyGenerator()
      ..init(
        pc.ParametersWithRandom(
          pc.ECKeyGeneratorParameters(pc.ECCurve_secp256r1()),
          random,
        ),
      );
    final pair = generator.generateKeyPair();
    publicKey = pair.publicKey;
    _private = pair.privateKey;
  }

  late final pc.ECPublicKey publicKey;
  late final pc.ECPrivateKey _private;

  String signDerBase64(List<int> data) {
    final signer = pc.ECDSASigner(pc.SHA256Digest())
      ..init(
        true,
        pc.ParametersWithRandom(
          pc.PrivateKeyParameter<pc.ECPrivateKey>(_private),
          pc.FortunaRandom()..seed(
            pc.KeyParameter(Uint8List.fromList(List<int>.filled(32, 9))),
          ),
        ),
      );
    final sig =
        signer.generateSignature(Uint8List.fromList(data)) as pc.ECSignature;
    final r = _derInt(sig.r);
    final s = _derInt(sig.s);
    final body = [0x02, r.length, ...r, 0x02, s.length, ...s];
    return base64Encode([0x30, body.length, ...body]);
  }

  /// Kiểm chữ ký DER (base64) trên [data].
  bool verifyDerBase64(List<int> data, String signature) {
    final der = base64Decode(signature);
    if (der.length < 8 || der[0] != 0x30) return false;
    var i = 2;
    BigInt readInt() {
      if (der[i] != 0x02) throw const FormatException('der');
      final len = der[i + 1];
      final value = BigInt.parse(
        der
            .sublist(i + 2, i + 2 + len)
            .map((b) => b.toRadixString(16).padLeft(2, '0'))
            .join(),
        radix: 16,
      );
      i += 2 + len;
      return value;
    }

    final r = readInt();
    final s = readInt();
    final verifier = pc.ECDSASigner(pc.SHA256Digest())
      ..init(false, pc.PublicKeyParameter<pc.ECPublicKey>(publicKey));
    return verifier.verifySignature(
      Uint8List.fromList(data),
      pc.ECSignature(r, s),
    );
  }

  static List<int> _derInt(BigInt v) {
    var hex = v.toRadixString(16);
    if (hex.length.isOdd) hex = '0$hex';
    final bytes = [
      for (var i = 0; i < hex.length; i += 2)
        int.parse(hex.substring(i, i + 2), radix: 16),
    ];
    return bytes.first >= 0x80 ? [0, ...bytes] : bytes;
  }
}

/// Vân tay giả: kết quả cài sẵn, đếm số lần hỏi.
final class FakeIdeSecurity implements IdeDeviceSecurity {
  FakeIdeSecurity({this.auth = DeviceOwnerAuthResult.ok, FakeStepKey? key})
    : key = key ?? FakeStepKey();

  DeviceOwnerAuthResult auth;
  final FakeStepKey key;
  int authCalls = 0;
  bool stepCancelled = false;
  final created = <String>[];
  final deleted = <String>[];

  /// Mã lỗi giả khi tạo khoá (`null` = tạo được).
  String? createError;

  /// Hộp xác thực không bao giờ trả lời (Activity bị huỷ).
  bool hangAuth = false;

  /// Đồng hồ native giả (ms, `null` = không đọc được).
  int? uptime = 0;

  @override
  Future<int?> uptimeMs() async => uptime;

  @override
  Future<DeviceOwnerAuthResult> authenticateDeviceOwner(String reason) {
    authCalls++;
    if (hangAuth) return Completer<DeviceOwnerAuthResult>().future;
    return Future.value(auth);
  }

  @override
  Future<String> createStepKey(String alias) async {
    created.add(alias);
    final error = createError;
    if (error != null) throw StepKeyException(error);
    return 'c3RlcC1wdWJrZXk=';
  }

  @override
  Future<void> deleteStepKey(String alias) async => deleted.add(alias);

  @override
  Future<String> signWithStepKey({
    required String alias,
    required List<int> data,
    required String reason,
  }) async {
    if (stepCancelled) throw const StepKeyException('cancelled');
    return key.signDerBase64(data);
  }
}
