import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:pointycastle/export.dart' as pc;
import 'package:webtui_chat/core/error/failure.dart';
import 'package:webtui_chat/core/platform/external_url_launcher.dart';
import 'package:webtui_chat/core/result/result.dart';
import 'package:webtui_chat/core/security/secure_key_value_store.dart';
import 'package:webtui_chat/features/auth/domain/entities/auth_tokens.dart';
import 'package:webtui_chat/features/auth/domain/repositories/auth_token_repository.dart';
import 'package:webtui_chat/features/ide_web/application/ide_web_prompter.dart';
import 'package:webtui_chat/features/ide_web/application/ide_web_view.dart';
import 'package:webtui_chat/features/ide_web/domain/ide_web_device_key.dart';
import 'package:webtui_chat/features/ide_web/domain/ide_web_file.dart';
import 'package:webtui_chat/features/ide_web/domain/ide_web_launch.dart';
import 'package:webtui_chat/features/ide_web/domain/ide_web_owner.dart';
import 'package:webtui_chat/features/ide_web/domain/ide_web_ports.dart';

const testOrigin = 'https://ide.chat.example.com';
final testBase = Uri.parse(testOrigin);
const testAuthOrigin = 'https://ide.example.net';
final testAuthBase = Uri.parse(testAuthOrigin);
const testOwner = IdeWebOwner(scopeId: 'scope-1', userId: 'user-1');
const otherOwner = IdeWebOwner(scopeId: 'scope-1', userId: 'user-2');
const testState = 'c3RhdGUtdmF0LW1hdS0wMTIzNDU2Nzg5MDEyMzQ1Njc4OQ';
const testChallenge = 'AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8';

Map<String, dynamic> fixture(String name) =>
    jsonDecode(File('test/fixtures/ide_web/$name').readAsStringSync())
        as Map<String, dynamic>;

Uri callbackUri({String state = testState, String code = 'ma-callback'}) => Uri(
  scheme: 'webtui',
  host: 'ide-web',
  path: '/callback',
  queryParameters: {'state': state, 'code': code},
);

IdeWebEntry testEntry({bool bridge = true, String? enterUrl}) => IdeWebEntry(
  enterUrl: Uri.parse(enterUrl ?? '$testOrigin/_appchat/enter'),
  gateToken: 'token-cong',
  openCode: 'ma-mo',
  expiresAt: DateTime.utc(2030),
  bridgeEnabled: bridge,
);

IdeWebBrowserLaunch testBrowserLaunch({String? url, String id = 'launch-1'}) =>
    IdeWebBrowserLaunch(
      launchId: id,
      state: testState,
      browserUrl: Uri.parse(url ?? '$testAuthOrigin/appchat/auth/?flow=ve'),
      expiresAt: DateTime.utc(2030),
    );

IdeWebDirectLaunch testDirectLaunch({
  String id = 'l',
  IdeWebEntry? entry,
  DateTime? launchExpiresAt,
}) => IdeWebDirectLaunch(
  launchId: id,
  state: testState,
  entry: entry ?? testEntry(),
  launchExpiresAt: launchExpiresAt ?? DateTime.utc(2030),
);

FailureResult<T> failResult<T>(FailureKind kind, {String? code}) =>
    FailureResult(Failure(kind: kind, message: 'lỗi', code: code));

final class FakeIdeWebRepository implements IdeWebRepository {
  FakeIdeWebRepository({Result<IdeWebLaunch>? launch})
    : launchResult = launch ?? Success(testBrowserLaunch());

  Result<IdeWebLaunch> launchResult;
  Result<IdeWebEntry> completeResult = Success(testEntry());
  Completer<void>? launchGate;
  Completer<void>? endGate;
  Object? endError;
  final launches = <IdeWebLaunchRequest>[];
  final completes = <Map<String, String>>[];
  final cancelled = <String>[];
  int ended = 0;
  void Function()? onComplete;

  @override
  Future<Result<IdeWebLaunch>> launch(IdeWebLaunchRequest request) async {
    launches.add(request);
    await launchGate?.future;
    return launchResult;
  }

  @override
  Future<Result<IdeWebEntry>> complete({
    required String launchId,
    required String code,
    required String state,
    required String codeVerifier,
  }) async {
    completes.add({
      'launch_id': launchId,
      'code': code,
      'state': state,
      'code_verifier': codeVerifier,
    });
    onComplete?.call();
    return completeResult;
  }

  @override
  Future<Result<void>> cancel(String launchId) async {
    cancelled.add(launchId);
    return const Success(null);
  }

  @override
  Future<Result<void>> endCurrentSession() async {
    ended++;
    await endGate?.future;
    if (endError != null) throw endError!;
    return const Success(null);
  }
}

final class FakePendingStore implements IdeWebPendingStore {
  PendingIdeWebLaunch? value;
  Object? clearError;
  final log = <String>[];

  @override
  Future<void> clear() async {
    if (clearError != null) throw clearError!;
    log.add('clear');
    value = null;
  }

  @override
  Future<PendingIdeWebLaunch?> read() async => value;

  void Function()? onWrite;

  @override
  Future<void> write(PendingIdeWebLaunch launch) async {
    log.add('write');
    value = launch;
    onWrite?.call();
  }
}

final class FakeTokenRepository implements AuthTokenRepository {
  AuthTokenMutationGuard? guard = const AuthTokenMutationGuard(
    instanceScopeId: 'scope-1',
    generation: 'g1',
  );
  String? token = 'token';

  @override
  Future<AuthTokenMutationGuard?> captureMutationGuard() async => guard;

  @override
  Future<bool> isMutationGuardCurrent(AuthTokenMutationGuard g) async =>
      g == guard;

  @override
  Future<String?> readAccessTokenIfCurrent(AuthTokenMutationGuard g) async =>
      g == guard ? token : null;

  @override
  Future<String?> readAccessToken() async => token;

  @override
  Future<String?> readRefreshToken() async => null;

  @override
  Future<String?> readRefreshTokenIfCurrent(AuthTokenMutationGuard g) async =>
      null;

  @override
  Future<void> saveTokens(AuthTokens tokens) async {}

  @override
  Future<bool> saveTokensIfCurrent(
    AuthTokens tokens,
    AuthTokenMutationGuard guard, {
    AuthTokenPersistence? persistence,
  }) async => true;

  @override
  Future<void> clearTokens() async => token = null;

  @override
  Future<bool> clearTokensIfCurrent(AuthTokenMutationGuard guard) async => true;
}

/// Kho bí mật trong bộ nhớ, `clearSession` xoá đúng những khoá app thật xoá.
final class MemorySecureStore implements SecureKeyValueStore {
  final values = <SecureStoreKey, String>{};

  @override
  Future<String?> read(SecureStoreKey key) async => values[key];

  @override
  Future<void> write(SecureStoreKey key, String value) async =>
      values[key] = value;

  @override
  Future<void> delete(SecureStoreKey key) async => values.remove(key);

  @override
  Future<void> clearSession() async {
    for (final key in const [
      SecureStoreKey.accessToken,
      SecureStoreKey.refreshToken,
      SecureStoreKey.ideWebPending,
    ]) {
      values.remove(key);
    }
  }
}

final class MemoryKeyStore implements IdeWebKeyMetadataStore {
  IdeWebKeyRecord? value;

  @override
  Future<void> clear() async => value = null;

  @override
  Future<IdeWebKeyRecord?> read() async => value;

  @override
  Future<void> write(IdeWebKeyRecord record) async => value = record;
}

final class MemoryMarkerStore implements IdeWebDataMarkerStore {
  IdeWebDataMarker? value;

  @override
  Future<void> clear() async => value = null;

  @override
  Future<IdeWebDataMarker?> read() async => value;

  @override
  Future<void> write(IdeWebDataMarker marker) async => value = marker;
}

final p256 = pc.ECCurve_secp256r1();

/// Chip khoá giả: ký P-256 thật bằng pointycastle.
final class FakeKeyChip implements IdeWebKeyChip {
  final keys = <String, pc.ECPrivateKey>{};
  final public = <String, pc.ECPublicKey>{};
  final deleted = <String>[];
  final signed = <String>[];
  String? createError;
  String? signError;
  bool deleteFails = false;
  Completer<void>? signGate;
  Completer<void>? createGate;

  @override
  Future<IdeWebCreatedKey> create(
    IdeWebKeyPurpose purpose,
    String alias,
  ) async {
    await createGate?.future;
    if (createError != null) throw IdeWebKeyException(createError!);
    final generator = pc.ECKeyGenerator()
      ..init(
        pc.ParametersWithRandom(
          pc.ECKeyGeneratorParameters(p256),
          pc.FortunaRandom()..seed(
            pc.KeyParameter(
              Uint8List.fromList(List.generate(32, (i) => i + keys.length)),
            ),
          ),
        ),
      );
    final pair = generator.generateKeyPair();
    keys[alias] = pair.privateKey;
    public[alias] = pair.publicKey;
    return IdeWebCreatedKey(publicKey: 'spki-$alias', hardware: 'tee');
  }

  @override
  Future<Uint8List> sign(
    IdeWebKeyPurpose purpose,
    String alias,
    Uint8List data,
  ) async {
    await signGate?.future;
    if (signError != null) throw IdeWebKeyException(signError!);
    final key = keys[alias];
    if (key == null) throw const IdeWebKeyException('key_missing');
    signed.add(utf8.decode(data));
    final signer = pc.Signer('SHA-256/DET-ECDSA')
      ..init(true, pc.PrivateKeyParameter<pc.ECPrivateKey>(key));
    final s = signer.generateSignature(data) as pc.ECSignature;
    return derSignature(s.r, s.s);
  }

  @override
  Future<bool> isUsable(IdeWebKeyPurpose purpose, String alias) async =>
      keys.containsKey(alias);

  @override
  Future<void> delete(IdeWebKeyPurpose purpose, String alias) async {
    if (deleteFails) throw const IdeWebKeyException('failed');
    deleted.add(alias);
    keys.remove(alias);
  }

  IdeWebBiometricState biometric = const IdeWebBiometricState(
    available: true,
    enrolled: true,
    strong: true,
  );

  @override
  Future<IdeWebBiometricState> biometricState() async => biometric;
}

Uint8List derSignature(BigInt r, BigInt s) {
  List<int> integer(BigInt value) {
    var hex = value.toRadixString(16);
    if (hex.length.isOdd) hex = '0$hex';
    final bytes = [
      for (var i = 0; i < hex.length; i += 2)
        int.parse(hex.substring(i, i + 2), radix: 16),
    ];
    if (bytes.first >= 0x80) bytes.insert(0, 0);
    return [2, bytes.length, ...bytes];
  }

  final body = [...integer(r), ...integer(s)];
  return Uint8List.fromList([0x30, body.length, ...body]);
}

pc.ECSignature parseDer(List<int> der) {
  BigInt read(int offset, int length) => BigInt.parse(
    der
        .sublist(offset, offset + length)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join(),
    radix: 16,
  );
  final rLength = der[3];
  return pc.ECSignature(read(4, rLength), read(6 + rLength, der[5 + rLength]));
}

bool verifyP256(pc.ECPublicKey key, String text, List<int> der) =>
    (pc.Signer('SHA-256/ECDSA')
          ..init(false, pc.PublicKeyParameter<pc.ECPublicKey>(key)))
        .verifySignature(Uint8List.fromList(utf8.encode(text)), parseDer(der));

final class FakePrompter implements IdeWebPrompter {
  FakePrompter({this.answer = true});

  bool answer;
  Completer<bool>? gate;
  final prompts = <IdeWebPrompt>[];
  int dismissed = 0;
  int closed = 0;

  @override
  Future<bool> confirm(IdeWebPrompt prompt) async {
    prompts.add(prompt);
    return gate?.future ?? answer;
  }

  @override
  void dismiss() {
    dismissed++;
    if (gate?.isCompleted == false) gate!.complete(false);
  }

  @override
  void close() => closed++;
}

final class FakeFileSaver implements IdeWebFileSaver {
  IdeWebFileSaveResult result = IdeWebFileSaveResult.saved;
  final saved = <IdeWebFile>[];
  int disposed = 0;

  @override
  Future<IdeWebFileSaveResult> save(
    IdeWebFile file, {
    required Future<bool> Function() confirmOpen,
  }) async {
    saved.add(file);
    return result;
  }

  @override
  Future<void> disposeTemp() async => disposed++;
}

final class FakeDataCleaner implements IdeWebDataCleaner {
  int calls = 0;
  Object? error;

  @override
  Future<void> clearAll() async {
    calls++;
    if (error != null) throw error!;
  }
}

final class FakeMicPermission implements IdeWebMicPermission {
  bool granted = true;
  int asked = 0;

  @override
  Future<bool> request() async {
    asked++;
    return granted;
  }
}

final class FakeBrowser implements IdeWebBrowser {
  IdeWebBrowserResult result = const IdeWebBrowserOpened();
  Completer<IdeWebBrowserResult>? gate;
  final opened = <Uri>[];

  @override
  Future<IdeWebBrowserResult> authenticate(
    Uri url, {
    required String scheme,
  }) async {
    opened.add(url);
    return gate?.future ?? result;
  }
}

final class FakeLauncher implements ExternalUrlLauncher {
  final opened = <String>[];

  @override
  Future<bool> open(String url) async {
    opened.add(url);
    return true;
  }
}

final class FakeIdeWebView implements IdeWebView {
  final controller = StreamController<IdeWebViewEvent>.broadcast(sync: true);
  final log = <String>[];
  final replies = <(String, Map<String, dynamic>)>[];
  final emitted = <String>[];
  bool supported = true;
  bool capture = false;
  bool canGoBack = false;
  Object? openError;
  Completer<void>? disposeGate;
  void Function()? onBlank;

  void add(IdeWebViewEvent event) => controller.add(event);

  @override
  Widget build() =>
      const ColoredBox(color: Color(0xFF223344), child: SizedBox.expand());

  @override
  Stream<IdeWebViewEvent> get events => controller.stream;

  @override
  Future<bool> attach({required bool bridgeEnabled}) async {
    log.add('attach:$bridgeEnabled:${controller.hasListener}');
    return supported;
  }

  @override
  Future<void> open(IdeWebEntry entry) async {
    log.add('open');
    if (openError != null) throw openError!;
  }

  @override
  Future<void> reloadHome() async => log.add('home');

  @override
  Future<void> loadBlank() async {
    log.add('blank');
    onBlank?.call();
  }

  @override
  Future<void> reply(String replyId, String payload) async =>
      replies.add((replyId, jsonDecode(payload) as Map<String, dynamic>));

  @override
  Future<void> emit(String payload) async => emitted.add(
    (jsonDecode(payload) as Map<String, dynamic>)['event'] as String,
  );

  @override
  Future<bool> captureOpen() async => capture;

  @override
  Future<void> stopCapture() async => log.add('stopCapture');

  @override
  Future<void> pauseMedia() async => log.add('pauseMedia');

  @override
  Future<bool> goBack() async {
    log.add('back');
    return canGoBack;
  }

  @override
  Future<void> dispose() async {
    await disposeGate?.future;
    log.add('dispose');
  }
}

/// Chờ các việc bất đồng bộ ngắn chạy xong.
Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 5));
