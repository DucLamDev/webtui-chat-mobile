import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pointycastle/export.dart' as pc;
import 'package:webtui_chat/core/security/secure_key_value_store.dart';
import 'package:webtui_chat/features/ide_web/application/ide_web_device_keys.dart';
import 'package:webtui_chat/features/ide_web/data/ide_web_stores.dart';
import 'package:webtui_chat/features/ide_web/data/method_channel_ide_web_keys.dart';
import 'package:webtui_chat/features/ide_web/domain/ide_web_device_key.dart';
import 'package:webtui_chat/features/ide_web/domain/ide_web_ports.dart';

import 'support/fakes.dart';

/// TC6: khoá thiết bị.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Matcher keyError(String code) =>
      throwsA(isA<IdeWebKeyException>().having((e) => e.code, 'code', code));

  test('véc-tơ thử của hợp đồng', () {
    final v = fixture('sign-vector.json');
    String text(IdeWebSigningAction action, IdeWebKeyPurpose purpose) =>
        ideWebSigningString(
          action: action,
          purpose: purpose,
          origin: v['origin'] as String,
          keyId: v['key_id'] as String,
          challenge: v['challenge'] as String,
        );
    final sign = text(IdeWebSigningAction.sign, IdeWebKeyPurpose.possession);
    expect(sign, v['string_sign']);
    expect('${sha256.convert(utf8.encode(sign))}', v['sha256_sign']);
    final register = text(
      IdeWebSigningAction.register,
      IdeWebKeyPurpose.biometric,
    );
    expect('${sha256.convert(utf8.encode(register))}', v['sha256_register']);
    List<int> decode(String key) =>
        base64Url.decode(base64Url.normalize(v[key] as String));
    final spki = decode('public_key');
    final key = pc.ECPublicKey(
      p256.curve.decodePoint(spki.sublist(spki.length - 65)),
      p256,
    );
    expect(verifyP256(key, sign, decode('signature_example')), isTrue);
    expect(verifyP256(key, '$sign ', decode('signature_example')), isFalse);
  });

  test('challenge: base64url không đệm, 32–64 byte, dạng chuẩn', () {
    String b64(int n) => ideWebBase64Url(List.filled(n, 7));
    expect(isIdeWebChallenge(b64(32)), isTrue);
    expect(isIdeWebChallenge(b64(64)), isTrue);
    for (final bad in [
      b64(31),
      b64(65),
      '${b64(32)}=',
      '${b64(31)}+/',
      '',
      // 43 ký tự nhưng bit thừa khác 0.
      '${'A' * 42}B',
    ]) {
      expect(isIdeWebChallenge(bad), isFalse, reason: bad);
    }
  });

  group('kho khoá', () {
    late FakeKeyChip chip;
    late MemoryKeyStore store;
    late IdeWebDeviceKeys keys;
    setUp(() {
      chip = FakeKeyChip();
      store = MemoryKeyStore();
      keys = IdeWebDeviceKeys(chip: chip, store: store);
    });
    Future<IdeWebRegisteredKey> create([
      IdeWebKeyPurpose purpose = IdeWebKeyPurpose.possession,
      bool Function()? wanted,
    ]) => keys.create(
      owner: testOwner,
      purpose: purpose,
      origin: testOrigin,
      challenge: testChallenge,
      stillWanted: wanted ?? () => true,
    );

    test('tạo, ký, xoá; alias đúng dạng hợp đồng native', () async {
      final key = await create();
      final alias = chip.keys.keys.single;
      expect(
        alias,
        matches(r'^ideweb\.p\.[0-9a-f]{24}\.[A-Za-z0-9_-]{16,128}$'),
      );
      expect(alias, endsWith(key.keyId));
      expect(
        verifyP256(
          chip.public[alias]!,
          'AppChat-IDE-v1:register\npossession\n$testOrigin\n${key.keyId}\n$testChallenge',
          base64Url.decode(base64Url.normalize(key.proof)),
        ),
        isTrue,
      );
      final signature = await keys.sign(
        owner: testOwner,
        keyId: key.keyId,
        origin: testOrigin,
        challenge: testChallenge,
      );
      expect(signature, isNot(contains('=')));
      expect(
        verifyP256(
          chip.public[alias]!,
          'AppChat-IDE-v1:sign\npossession\n$testOrigin\n${key.keyId}\n$testChallenge',
          base64Url.decode(base64Url.normalize(signature)),
        ),
        isTrue,
      );
      expect(
        await keys.hint(testOwner, IdeWebKeyPurpose.possession),
        key.keyId,
      );
      await keys.delete(testOwner, key.keyId);
      expect(chip.keys, isEmpty);
      expect(await keys.status(testOwner), isEmpty);
    });

    test('khoá của người khác không dùng được', () async {
      final key = await create();
      expect(await keys.status(otherOwner), isEmpty);
      await expectLater(
        keys.sign(
          owner: otherOwner,
          keyId: key.keyId,
          origin: testOrigin,
          challenge: testChallenge,
        ),
        keyError('key_missing'),
      );
      await expectLater(
        keys.delete(otherOwner, key.keyId),
        keyError('key_missing'),
      );
    });

    test('cùng người giữ khoá, người khác đăng nhập thì xoá hẳn', () async {
      await create();
      await keys.dropOtherOwner(testOwner);
      expect(chip.keys, hasLength(1));
      await keys.dropOtherOwner(otherOwner);
      expect(chip.keys, isEmpty);
      expect(store.value, isNull);
    });

    test('chip chưa xoá được thì giữ bản ghi để xoá tiếp', () async {
      await create();
      chip.deleteFails = true;
      await expectLater(keys.purge(), keyError('failed'));
      expect(store.value!.keys, hasLength(1));
      chip.deleteFails = false;
      await keys.purge();
      expect(store.value, isNull);
    });

    test(
      'ký đăng ký bị huỷ / trang đã đổi: không để lại khoá mồ côi',
      () async {
        chip.signError = 'cancelled';
        await expectLater(create(), keyError('cancelled'));
        chip.signError = null;
        await expectLater(
          create(IdeWebKeyPurpose.biometric, () => false),
          keyError('cancelled'),
        );
        expect(chip.keys, isEmpty);
        expect(store.value!.keys, isEmpty);
      },
    );

    test(
      'người khác đăng nhập giữa lúc hỏi sinh trắc: huỷ, xoá khoá',
      () async {
        chip.signGate = Completer<void>();
        final expectation = expectLater(
          create(IdeWebKeyPurpose.biometric),
          throwsA(isA<IdeWebKeyException>()),
        );
        await settle();
        await keys.dropOtherOwner(otherOwner);
        chip.signGate!.complete();
        await expectation;
        expect(chip.keys, isEmpty);
        expect(store.value, isNull);
      },
    );

    test('key_invalid được nhớ; xoay khoá: tạo mới rồi xoá cũ', () async {
      final old = await create(IdeWebKeyPurpose.biometric);
      chip.signError = 'key_invalid';
      Future<String> sign() => keys.sign(
        owner: testOwner,
        keyId: old.keyId,
        origin: testOrigin,
        challenge: testChallenge,
      );
      await expectLater(sign(), keyError('key_invalid'));
      chip.signError = null;
      await expectLater(sign(), keyError('key_invalid'));
      expect((await keys.status(testOwner)).single.usable, isFalse);
      expect(await keys.hint(testOwner, IdeWebKeyPurpose.biometric), isNull);
      final fresh = await create(IdeWebKeyPurpose.biometric);
      await keys.delete(testOwner, old.keyId);
      final status = await keys.status(testOwner);
      expect(status.single.key.keyId, fresh.keyId);
      expect(status.single.usable, isTrue);
    });

    test('không vượt số khoá tối đa', () async {
      for (var i = 0; i < IdeWebDeviceKeys.maxKeys; i++) {
        await create();
      }
      await expectLater(create(), keyError('failed'));
      expect(chip.keys, hasLength(IdeWebDeviceKeys.maxKeys));
    });
  });

  test('kho bền: đi về đúng, dữ liệu hỏng coi như chưa có', () async {
    final secure = MemorySecureStore();
    final store = SecureIdeWebKeyMetadataStore(secure);
    final key = IdeWebDeviceKey(
      keyId: '6b1f0e3a-8c57-4c8e-9b39-2f1f5b0d7a11',
      purpose: IdeWebKeyPurpose.biometric,
      createdAt: DateTime.utc(2026),
      ready: true,
    );
    await store.write(
      IdeWebKeyRecord(ownerDigest: testOwner.digest, keys: [key]),
    );
    final read = (await store.read())!;
    expect(read.ownerDigest, testOwner.digest);
    expect(read.keys.single.toJson(), key.toJson());
    // Đăng xuất giữ khoá, xoá lượt chờ.
    secure.values[SecureStoreKey.ideWebPending] = 'x';
    await secure.clearSession();
    expect(await store.read(), isNotNull);
    for (final raw in ['', '{', '[]', '{"v":2}', '{"v":1,"owner":"../x"}']) {
      secure.values[SecureStoreKey.ideWebDevice] = raw;
      expect(await store.read(), isNull, reason: raw);
    }
    expect(await SecureIdeWebPendingStore(secure).read(), isNull);
  });

  group('kênh native', () {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const channel = MethodChannel('webtui/ide_web_keys');
    const biometric = MethodChannel('webtui/biometric');
    const chip = MethodChannelIdeWebKeyChip();
    final calls = <MethodCall>[];
    tearDown(() {
      calls.clear();
      messenger
        ..setMockMethodCallHandler(channel, null)
        ..setMockMethodCallHandler(biometric, null);
    });

    test('possession đúng tên hàm, đối số, kiểu', () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return switch (call.method) {
          'createPossessionKey' => {'publicKey': 'pk', 'hardware': 'strongbox'},
          'signPossession' => Uint8List.fromList([1, 2]),
          'keyState' => {'exists': true, 'usable': true, 'hardware': 'tee'},
          _ => null,
        };
      });
      const p = IdeWebKeyPurpose.possession;
      final created = await chip.create(p, 'a');
      expect(created.hardware, 'strongbox');
      expect(await chip.sign(p, 'a', Uint8List.fromList([9])), [1, 2]);
      expect(await chip.isUsable(p, 'a'), isTrue);
      await chip.delete(p, 'a');
      expect(calls.map((c) => c.method), [
        'createPossessionKey',
        'signPossession',
        'keyState',
        'deleteKey',
      ]);
      final args = calls[1].arguments as Map<Object?, Object?>;
      expect(args['data'], isA<Uint8List>());
      expect(args['alias'], 'a');
    });

    test(
      'biometricState: đọc đúng kênh mới, thiếu / lỗi thì coi như không có',
      () async {
        List<bool> flags(IdeWebBiometricState s) => [
          s.available,
          s.enrolled,
          s.strong,
        ];
        Object? answer;
        messenger
          ..setMockMethodCallHandler(channel, (call) async {
            expect(call.method, 'biometricState');
            return answer;
          })
          // Kênh cũ tính cả sinh trắc yếu: không được hỏi.
          ..setMockMethodCallHandler(biometric, (call) async => true);
        answer = {'available': true, 'enrolled': false, 'strong': true};
        expect(flags(await chip.biometricState()), [true, false, true]);
        answer = null;
        expect(flags(await chip.biometricState()), [false, false, false]);
        messenger.setMockMethodCallHandler(
          channel,
          (_) async => throw PlatformException(code: 'failed'),
        );
        expect(flags(await chip.biometricState()), [false, false, false]);
        messenger.setMockMethodCallHandler(channel, null);
        expect(flags(await chip.biometricState()), [false, false, false]);
      },
    );

    test('biometric dùng kênh sẵn có, đổi base64 sang base64url', () async {
      messenger
        ..setMockMethodCallHandler(biometric, (call) async {
          calls.add(call);
          return base64.encode([251, 255, 254]);
        })
        ..setMockMethodCallHandler(
          channel,
          (call) async => {
            'exists': true,
            'usable': true,
            'hardware': 'strongbox',
          },
        );
      const b = IdeWebKeyPurpose.biometric;
      final created = await chip.create(b, 'a');
      expect(created.publicKey, '-__-');
      expect(created.hardware, 'strongbox');
      expect(await chip.sign(b, 'a', Uint8List.fromList([1])), [251, 255, 254]);
      await chip.delete(b, 'a');
      expect(calls.map((c) => c.method), [
        'createStepKey',
        'signWithStepKey',
        'deleteStepKey',
      ]);
    });

    test('đổi mã lỗi', () async {
      for (final entry in {
        'cancelled': 'cancelled',
        'notEnrolled': 'not_enrolled',
        'biometricRequired': 'not_enrolled',
        'key_invalid': 'key_invalid',
        'la': 'failed',
      }.entries) {
        messenger.setMockMethodCallHandler(
          biometric,
          (_) => throw PlatformException(code: entry.key),
        );
        await expectLater(
          chip.sign(IdeWebKeyPurpose.biometric, 'a', Uint8List(1)),
          keyError(entry.value),
        );
      }
      messenger.setMockMethodCallHandler(
        channel,
        (_) => throw PlatformException(code: 'key_missing'),
      );
      await expectLater(
        chip.sign(IdeWebKeyPurpose.possession, 'a', Uint8List(1)),
        keyError('key_missing'),
      );
      messenger.setMockMethodCallHandler(channel, null);
      await expectLater(
        chip.create(IdeWebKeyPurpose.possession, 'a'),
        keyError('unsupported'),
      );
    });
  });
}
